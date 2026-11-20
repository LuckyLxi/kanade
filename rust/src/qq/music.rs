//! 相似歌曲、播放链接、歌词、副歌、榜单、歌单。

use anyhow::{bail, Context, Result};
use serde_json::{json, Value};

use super::client::core;
use super::error::ApiError;
use super::lyric;
use super::parse::{self, first_s, n, s};
use super::qrc;
use super::quality::{file_name, playback_chain, stream_available};
use crate::api::types::*;


/// 歌曲更多菜单的“查找相似歌曲”，按上游顺序返回。
pub async fn similar_songs(song_id: i64) -> Result<Vec<Song>> {
    let data = core()
        .musicu(
            "music.recommend.TrackRelationServer",
            "GetSimilarSongs",
            json!({"songid": song_id}),
        )
        .await?;
    similar_song_list(&data)
}

fn similar_song_list(data: &Value) -> Result<Vec<Song>> {
    let code = data["retcode"].as_i64().context(ApiError::bad_response(
        "similar songs response has no retcode",
    ))?;
    if code != 0 {
        bail!(ApiError::ServerError {
            api: "music.recommend.TrackRelationServer.GetSimilarSongs".into(),
            code: code.to_string()
        });
    }
    let list = data["vecSong"].as_array().context(ApiError::bad_response(
        "similar songs response has no vecSong",
    ))?;
    Ok(list
        .iter()
        .filter_map(|item| parse::song(&item["track"]))
        .collect())
}

/// 从请求的音质开始逐级降级，直到拿到可用链接。
pub async fn song_url(mid: &str, media_mid: &str, quality: Quality) -> Result<SongUrl> {
    let chain = playback_chain(quality)?;
    let c = core();
    let desktop = c.session().is_some();
    let vkey_apis: &[(&str, &str)] = if desktop {
        &[("music.vkey.GetVkey", "UrlGetVkey")]
    } else {
        &[
            ("music.vkey.GetVkey", "UrlGetVkey"),
            ("vkey.GetVkeyServer", "CgiGetVkey"),
        ]
    };
    let mut last_err = None;
    let mut got_response = false;
    for &q in &chain {
        let plain_apis = if super::quality::uses_plain_source(q) {
            vkey_apis
        } else {
            &[]
        };
        for &(module, method) in plain_apis {
            let mut param = json!({
                "guid": if desktop { &c.desktop_guid } else { &c.guid },
                "songmid": [mid],
                "songtype": [0],
                "uin": c.uin(),
                "loginflag": 1,
                "platform": "20",
                "filename": [file_name(q, media_mid)?],
            });
            let response = if desktop {
                param["ctx"] = json!(0);
                c.desktop_musicu(module, method, param).await
            } else {
                c.musicu(module, method, param).await
            };
            let data = match response {
                Ok(d) => {
                    got_response = true;
                    d
                }
                Err(e) => {
                    last_err = Some(e);
                    continue;
                }
            };
            let item = &data["midurlinfo"][0];
            let purl = s(&item["purl"]);
            if !purl.is_empty() && s(&item["ekey"]).is_empty() {
                let sip = data["sip"]
                    .as_array()
                    .and_then(|a| {
                        a.iter()
                            .map(s)
                            .find(|x| x.starts_with("https"))
                            .or_else(|| a.first().map(s))
                    })
                    .unwrap_or_else(|| "https://isure.stream.qqmusic.qq.com/".into());
                let url = format!("{sip}{purl}");
                if !matches!(
                    q,
                    Quality::Low | Quality::Standard | Quality::High | Quality::Lossless
                ) && !stream_available(&url).await?
                {
                    continue;
                }
                return Ok(SongUrl {
                    url,
                    quality: q,
                    ekey: None,
                });
            }
        }
        if desktop && super::quality::encrypted_format(q).is_some() {
            if let Ok(source) = super::quality::encrypted_source(mid, media_mid, q, None).await {
                return Ok(source);
            }
        }
        if q == Quality::Ra360 {
            if let Ok(source) = super::quality::ra360_source(mid, media_mid).await {
                return Ok(source);
            }
        }
    }
    // 全部请求都失败说明是网络等问题，原样报出；否则就是没有权限
    match last_err {
        Some(e) if !got_response => Err(e),
        _ => bail!(ApiError::NoPlayableUrl),
    }
}

pub async fn lyric(mid: &str, id: i64) -> Result<Lyric> {
    let c = core();
    let data = c
        // 缓存的是解密后的原文；以前存的是不带逐字和罗马音的版本，换个键不再读它
        .cached(&format!("lyric:qrc:{mid}"), 7 * 86400, || async {
            let r = c
                .musicu(
                    "music.musichallSong.PlayLyricInfo",
                    "GetPlayLyricInfo",
                    json!({ "songMID": mid, "songID": id, "trans": 1, "roma": 1, "crypt": 1, "qrc": 1 }),
                )
                .await;
            let decrypted = r.and_then(|d| {
                Ok(json!({
                    "lyric": qrc::decrypt(&s(&d["lyric"]))?,
                    "trans": qrc::decrypt(&s(&d["trans"]))?,
                    "roma": qrc::decrypt(&s(&d["roma"]))?,
                }))
            });
            match decrypted {
                Ok(d) if !s(&d["lyric"]).is_empty() => Ok(d),
                _ => {
                    let d = c
                        .get_json(
                            "https://c.y.qq.com/lyric/fcgi-bin/fcg_query_lyric_new.fcg",
                            &[("songmid", mid.to_string()), ("format", "json".into()), ("nobase64", "1".into()), ("g_tk", "5381".into())],
                        )
                        .await?;
                    Ok(json!({ "lyric": s(&d["lyric"]), "trans": s(&d["trans"]) }))
                }
            }
        })
        .await?;
    Ok(lyric::build(
        &s(&data["lyric"]),
        &s(&data["trans"]),
        &s(&data["roma"]),
    ))
}

/// 歌曲信息里的 `file.try_begin` / `try_end` 就是官方客户端标出的高潮片段，没有时是 0。
pub async fn chorus(id: i64) -> Result<Option<ChorusRange>> {
    let c = core();
    let file = c
        .cached(&format!("chorus:{id}"), 7 * 86400, || async {
            Ok(tracks_by_id(&[id]).await?[0]["file"].clone())
        })
        .await?;
    Ok(chorus_range(&file))
}

fn chorus_range(file: &Value) -> Option<ChorusRange> {
    let (start_ms, end_ms) = (n(&file["try_begin"]) as u32, n(&file["try_end"]) as u32);
    (end_ms > start_ms).then_some(ChorusRange { start_ms, end_ms })
}

pub async fn toplists() -> Result<Vec<TopListGroup>> {
    let c = core();
    let data = c
        .cached("toplists", 3600, || {
            c.musicu("musicToplist.ToplistInfoServer", "GetAll", json!({}))
        })
        .await?;
    let groups = data["group"].as_array().cloned().unwrap_or_default();
    Ok(groups
        .iter()
        .map(|g| TopListGroup {
            name: first_s(g, &["groupName"]),
            lists: g["toplist"]
                .as_array()
                .map(|a| {
                    a.iter()
                        .map(|t| TopList {
                            top_id: n(&t["topId"]),
                            title: s(&t["title"]),
                            cover_url: first_s(t, &["frontPicUrl", "headPicUrl", "mbFrontPicUrl"]),
                            period: s(&t["period"]),
                            preview: t["song"]
                                .as_array()
                                .map(|x| {
                                    x.iter()
                                        .take(3)
                                        .map(|x| {
                                            format!("{} - {}", s(&x["title"]), s(&x["singerName"]))
                                        })
                                        .collect()
                                })
                                .unwrap_or_default(),
                        })
                        .collect()
                })
                .unwrap_or_default(),
        })
        .collect())
}

pub async fn toplist_detail(top_id: i64, period: &str) -> Result<TopListDetail> {
    let c = core();
    let data = c
        .cached(&format!("toplist:{top_id}:{period}"), 1800, || {
            c.musicu(
                "musicToplist.ToplistInfoServer",
                "GetDetail",
                json!({ "topId": top_id, "offset": 0, "num": 100, "period": period }),
            )
        })
        .await?;
    let info = &data["data"];
    Ok(TopListDetail {
        top_id,
        title: s(&info["title"]),
        cover_url: first_s(info, &["frontPicUrl", "headPicUrl"]),
        description: s(&info["intro"]),
        period: s(&info["period"]),
        songs: parse::songs(&data["songInfoList"]),
    })
}

/// 推荐卡片里的歌曲只有 id，没有播放所需的 mid，按 id 批量补全。
pub(super) async fn tracks_by_id(ids: &[i64]) -> Result<Value> {
    if ids.is_empty() {
        return Ok(json!([]));
    }
    let data = core()
        .musicu(
            "music.trackInfo.UniformRuleCtrl",
            "CgiGetTrackInfo",
            json!({ "ids": ids, "types": vec![0; ids.len()] }),
        )
        .await?;
    Ok(data["tracks"].clone())
}

/// 歌单详情的缓存键；改歌单后清缓存也用它。
pub(super) fn playlist_cache_key(id: impl std::fmt::Display) -> String {
    format!("playlist:{}:{id}", core().uin())
}

pub async fn playlist_detail(id: &str) -> Result<PlaylistDetail> {
    let c = core();
    let disstid: i64 = id.parse().unwrap_or(0);
    let data = c
        // “每日30首”这类歌单因人而异，缓存按账号区分
        .cached(&playlist_cache_key(id), 600, || {
            c.musicu(
                "music.srfDissInfo.aiDissInfo",
                "uniform_get_Dissinfo",
                json!({
                    "disstid": disstid,
                    "enc_host_uin": "",
                    "tag": 1,
                    "userinfo": 1,
                    "song_begin": 0,
                    "song_num": 1000,
                    "onlysonglist": 0,
                    "orderlist": 1,
                }),
            )
        })
        .await?;
    let dir = &data["dirinfo"];
    Ok(PlaylistDetail {
        id: id.to_string(),
        title: s(&dir["title"]),
        cover_url: s(&dir["picurl"]),
        description: s(&dir["desc"]),
        creator: first_s(&dir["creator"], &["nick"]),
        songs: parse::songs(&data["songlist"]),
    })
}

/// 当前登录用户创建的歌单（含“我喜欢”）和收藏的歌单。
pub async fn user_playlists() -> Result<Vec<PlaylistBrief>> {
    let c = core();
    let Some(sess) = c.session() else {
        bail!(ApiError::NotLoggedIn)
    };
    let mut out = Vec::new();

    let created = c
        .get_json(
            "https://c.y.qq.com/rsc/fcgi-bin/fcg_user_created_diss",
            &[
                ("hostuin", sess.uin.clone()),
                ("sin", "0".into()),
                ("size", "200".into()),
                ("format", "json".into()),
            ],
        )
        .await?;
    if let Some(list) = created["data"]["disslist"].as_array() {
        out.extend(
            list.iter()
                .filter(|p| n(&p["tid"]) != 0)
                .map(|p| PlaylistBrief {
                    id: s(&p["tid"]),
                    title: s(&p["diss_name"]),
                    cover_url: s(&p["diss_cover"]),
                    song_count: n(&p["song_cnt"]) as u32,
                    play_count: n(&p["listen_num"]) as u64,
                    creator: sess.nickname.clone(),
                }),
        );
    }

    let fav = c
        .get_json(
            "https://c.y.qq.com/fav/fcgi-bin/fcg_get_profile_order_asset.fcg",
            &[
                ("ct", "20".into()),
                ("cid", "205360956".into()),
                ("userid", sess.uin.clone()),
                ("reqtype", "3".into()),
                ("sin", "0".into()),
                ("ein", "200".into()),
                ("format", "json".into()),
            ],
        )
        .await;
    if let Ok(fav) = fav {
        if let Some(list) = fav["data"]["cdlist"].as_array() {
            out.extend(list.iter().map(|p| PlaylistBrief {
                id: s(&p["dissid"]),
                title: s(&p["dissname"]),
                cover_url: s(&p["logo"]),
                song_count: n(&p["songnum"]) as u32,
                play_count: n(&p["listennum"]) as u64,
                creator: first_s(p, &["nickname"]),
            }));
        }
    }
    Ok(out)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn chorus_range_comes_from_try_fields() {
        let r = chorus_range(&json!({"try_begin": 72998, "try_end": 104743})).unwrap();
        assert_eq!((r.start_ms, r.end_ms), (72998, 104743));
        assert!(chorus_range(&json!({"try_begin": 0, "try_end": 0})).is_none());
        assert!(chorus_range(&json!({})).is_none());
    }

    #[test]
    fn similar_songs_use_nested_tracks_and_preserve_order_and_mv() {
        let data = json!({"retcode": 0, "vecSong": [
            {"track": {"id": 11, "mid": "first", "mv": {"id": 0, "vid": "video"}}},
            {"track": {"id": 22, "mid": "second"}},
        ], "vecSongNew": null});
        let songs = similar_song_list(&data).unwrap();
        assert_eq!(songs.iter().map(|s| s.id).collect::<Vec<_>>(), vec![11, 22]);
        assert_eq!(songs[0].mv_vid, "video");
        assert!(similar_song_list(&json!({"retcode": 0, "vecSong": []}))
            .unwrap()
            .is_empty());
    }

    #[test]
    fn similar_songs_reject_failed_or_malformed_results() {
        for data in [
            json!({"retcode": 1000, "vecSong": []}),
            json!({"vecSong": []}),
            json!({"retcode": 0}),
        ] {
            assert!(similar_song_list(&data).is_err());
        }
    }
}
