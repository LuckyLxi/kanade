//! 搜索、播放链接、歌词、榜单、歌单。

use anyhow::{bail, Result};
use base64::Engine;
use serde_json::{json, Value};

use super::client::core;
use super::error::ApiError;
use super::parse::{self, first_s, n, s};
use super::lyric;
use super::sign::hash33;
use super::quality::{file_name, playback_chain, stream_available};
use crate::api::types::*;

fn search_id() -> String {
    // Windows 客户端抓包中的 searchid 为 37 位大写十六进制字符串。
    format!("{}{:05X}", uuid::Uuid::new_v4().simple(), rand::random::<u32>() & 0xfffff).to_uppercase()
}

pub async fn search_songs(keyword: &str, page: u32, page_size: u32) -> Result<SearchResult> {
    let c = core();
    let cache_prefix = if c.session().is_some() { "search:desktop" } else { "search" };
    let key = format!("{cache_prefix}:{keyword}:{page}:{page_size}");
    let data = c
        .cached(&key, 600, || async {
            if c.session().is_some() {
                let d = c.desktop_musicu(
                    "music.search.SearchCgiService",
                    "DoSearchForQQMusicDesktop",
                    json!({
                        "query": keyword,
                        "search_type": 0,
                        "num_per_page": page_size,
                        "page_num": page,
                        "remoteplace": "txt.newclient.top",
                        "searchid": search_id(),
                        "grp": 1,
                    }),
                ).await?;
                return Ok(json!({ "list": d["body"]["song"]["list"], "total": d["meta"]["sum"] }));
            }
            let d = c.get_json(
                "https://c.y.qq.com/soso/fcgi-bin/client_search_cp",
                &[
                    ("w", keyword.to_string()),
                    ("p", page.to_string()),
                    ("n", page_size.to_string()),
                    ("format", "json".into()),
                ],
            ).await?;
            let song = &d["data"]["song"];
            Ok(json!({ "list": song["list"], "total": song["totalnum"] }))
        })
        .await?;
    Ok(SearchResult { songs: parse::songs(&data["list"]), total: n(&data["total"]) as u32 })
}

fn hot_keywords(list: &Value) -> Vec<HotKeyword> {
    list.as_array()
        .map(|a| {
            a.iter()
                .map(|k| HotKeyword { title: s(&k["title"]), query: s(&k["query"]), description: s(&k["description"]) })
                .filter(|k| !k.query.is_empty())
                .collect()
        })
        .unwrap_or_default()
}

/// Windows 客户端的热搜；登录后额外带个性化的“猜你想搜”。
pub async fn hot_search() -> Result<HotSearch> {
    let c = core();
    let uin: i64 = c.uin().parse().unwrap_or(0);
    let data = c
        .cached(&format!("hotkey:desktop:{uin}"), 600, || {
            c.desktop_musicu(
                "tencent_musicsoso_hotkey.HotkeyService",
                "GetHotkeyForQQMusicPC",
                json!({ "search_id": "", "uin": uin }),
            )
        })
        .await?;
    Ok(HotSearch { hot: hot_keywords(&data["vec_hotkey"]), recommended: hot_keywords(&data["vec_reckey"]) })
}

/// Windows 客户端的搜索联想，支持拼音和首字母。
pub async fn search_suggestions(query: &str) -> Result<Vec<SearchSuggestion>> {
    let c = core();
    let data = c
        .cached(&format!("smartbox:desktop:{query}"), 600, || {
            c.desktop_musicu(
                "music.smartboxCgi.SmartBoxCgi",
                "GetSmartBoxResultForPc",
                json!({ "num_per_page": 4, "query": query, "search_id": search_id() }),
            )
        })
        .await?;
    let data = &data["data"];
    let mut out = Vec::new();
    for (kind, group, list) in [
        (SuggestionKind::Song, "song", "song_list"),
        (SuggestionKind::Singer, "singer", "singer_list"),
        (SuggestionKind::Album, "album", "album_list"),
    ] {
        for item in data[group][list].as_array().into_iter().flatten() {
            let title = s(&item["name"]);
            if title.is_empty() {
                continue;
            }
            let subtitle = if kind == SuggestionKind::Singer { String::new() } else { s(&item["singer"]) };
            out.push(SearchSuggestion { kind, title, subtitle });
        }
    }
    Ok(out)
}

/// 从请求的音质开始逐级降级，直到拿到可用链接。
/// 只请求官方提供的普通音频格式，不涉及加密格式。
pub async fn song_url(mid: &str, media_mid: &str, quality: Quality) -> Result<SongUrl> {
    let chain = playback_chain(quality)?;
    let c = core();
    let desktop = c.session().is_some();
    let vkey_apis: &[(&str, &str)] = if desktop {
        &[("music.vkey.GetVkey", "UrlGetVkey")]
    } else {
        &[("music.vkey.GetVkey", "UrlGetVkey"), ("vkey.GetVkeyServer", "CgiGetVkey")]
    };
    let mut last_err = None;
    let mut got_response = false;
    for &q in &chain {
        for &(module, method) in vkey_apis {
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
            let purl = s(&data["midurlinfo"][0]["purl"]);
            if !purl.is_empty() {
                let sip = data["sip"]
                    .as_array()
                    .and_then(|a| a.iter().map(s).find(|x| x.starts_with("https")).or_else(|| a.first().map(s)))
                    .unwrap_or_else(|| "https://isure.stream.qqmusic.qq.com/".into());
                let url = format!("{sip}{purl}");
                if !matches!(q, Quality::Low | Quality::Standard | Quality::High | Quality::Lossless) && !stream_available(&url).await? {
                    continue;
                }
                return Ok(SongUrl { url, quality: q });
            }
        }
    }
    // 全部请求都失败说明是网络等问题，原样报出；否则就是没有权限
    match last_err {
        Some(e) if !got_response => Err(e),
        _ => bail!(ApiError::NoPlayableUrl),
    }
}

fn b64_text(v: &Value) -> String {
    let raw = s(v);
    if raw.is_empty() {
        return raw;
    }
    base64::engine::general_purpose::STANDARD
        .decode(raw.as_bytes())
        .ok()
        .and_then(|b| String::from_utf8(b).ok())
        .unwrap_or(raw)
}

pub async fn lyric(mid: &str, id: i64) -> Result<Lyric> {
    let c = core();
    let data = c
        .cached(&format!("lyric:{mid}"), 7 * 86400, || async {
            let r = c
                .musicu(
                    "music.musichallSong.PlayLyricInfo",
                    "GetPlayLyricInfo",
                    json!({ "songMID": mid, "songID": id, "trans": 1, "roma": 0, "crypt": 0, "qrc": 0 }),
                )
                .await;
            match r {
                Ok(d) if !s(&d["lyric"]).is_empty() => Ok(json!({ "lyric": b64_text(&d["lyric"]), "trans": b64_text(&d["trans"]) })),
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
    Ok(lyric::build(&s(&data["lyric"]), &s(&data["trans"])))
}

pub async fn toplists() -> Result<Vec<TopListGroup>> {
    let c = core();
    let data = c
        .cached("toplists", 3600, || c.musicu("musicToplist.ToplistInfoServer", "GetAll", json!({})))
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
                                .map(|x| x.iter().take(3).map(|x| format!("{} - {}", s(&x["title"]), s(&x["singerName"]))).collect())
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

/// Windows 客户端内嵌推荐页（QBCore webkit）的公参，与原生搜索的 ct=19 不同。
/// 登录后带上账号和 g_tk，推荐结果才是个性化的。
pub(crate) fn webkit_comm() -> Value {
    let c = core();
    let g_tk = c.session().map(|s| hash33(&s.musickey, 5381)).unwrap_or(5381);
    json!({
        "ct": 20,
        "cv": 2276,
        "platform": "wk_v17",
        "uin": c.uin(),
        "g_tk": g_tk,
        "g_tk_new_20200303": g_tk,
        "needNewCode": 1,
        "notice": 0,
    })
}

/// 推荐卡片里的歌曲只有 id，没有播放所需的 mid，按 id 批量补全。
async fn tracks_by_id(ids: &[i64]) -> Result<Value> {
    if ids.is_empty() {
        return Ok(json!([]));
    }
    let data = core()
        .musicu("music.trackInfo.UniformRuleCtrl", "CgiGetTrackInfo", json!({ "ids": ids, "types": vec![0; ids.len()] }))
        .await?;
    Ok(data["tracks"].clone())
}

/// 首页个性推荐（v_shelf → v_niche → v_card）。保留能直接用的歌曲卡（type 200）
/// 和歌单卡（type 500，含“每日30首”等入口），再记下刷歌模式入口的起始歌曲；节目等跳过。
pub async fn recommend_feed() -> Result<RecommendFeed> {
    let c = core();
    let data = c
        .cached(&format!("feed:{}", c.uin()), 1800, || async {
            let feed = c
                .musicu_with_comm(
                    "music.recommend.RecommendFeed",
                    "get_recommend_feed",
                    json!({ "direction": 0, "page": 1, "v_cache": [], "v_uniq": [], "s_num": 0 }),
                    webkit_comm(),
                )
                .await?;
            let ids: Vec<i64> = cards(&feed).filter(|c| n(&c["type"]) == 200).map(|c| n(&c["id"])).filter(|id| *id > 0).collect();
            Ok(json!({ "feed": feed, "tracks": tracks_by_id(&ids).await? }))
        })
        .await?;
    let tracks: std::collections::HashMap<i64, Song> =
        parse::songs(&data["tracks"]).into_iter().map(|s| (s.id, s)).collect();

    let mut sections = Vec::new();
    for shelf in data["feed"]["v_shelf"].as_array().into_iter().flatten() {
        let title = s(&shelf["title_template"]).replace("{String}", &s(&shelf["title_content"])).trim().to_string();
        let shelf_cards: Vec<&Value> = shelf["v_niche"].as_array().into_iter().flatten().flat_map(|niche| niche["v_card"].as_array().into_iter().flatten()).collect();
        let songs: Vec<Song> = shelf_cards
            .iter()
            .filter(|c| n(&c["type"]) == 200)
            .filter_map(|c| tracks.get(&n(&c["id"])).cloned())
            .collect();
        let playlists: Vec<PlaylistBrief> = shelf_cards
            .iter()
            .filter(|c| n(&c["type"]) == 500 && !s(&c["id"]).is_empty())
            .map(|c| PlaylistBrief {
                id: s(&c["id"]),
                title: s(&c["title"]),
                cover_url: s(&c["cover"]),
                song_count: 0,
                play_count: n(&c["cnt"]) as u64,
                // 入口卡（每日30首等）的副标题是其中一首歌，普通歌单为空
                creator: s(&c["subtitle"]),
            })
            .collect();
        if !songs.is_empty() || !playlists.is_empty() {
            sections.push(RecommendSection { title, songs, playlists });
        }
    }
    Ok(RecommendFeed { sections, radar_seed: radar_seed(&data["feed"]) })
}

/// 刷歌模式入口卡的跳转形如 `qqmusic://qq.com/ui/jumpToRadarMode?p={"EntranceSongs":[id],...}`。
fn radar_seed(feed: &Value) -> Vec<i64> {
    cards(feed)
        .filter_map(|c| {
            let scheme = s(&c["scheme"]);
            if !scheme.contains("jumpToRadarMode") {
                return None;
            }
            let p = url::Url::parse(&scheme).ok()?.query_pairs().find(|(k, _)| k == "p")?.1.into_owned();
            let p: Value = serde_json::from_str(&p).ok()?;
            Some(p["EntranceSongs"].as_array()?.iter().map(n).filter(|id| *id > 0).collect::<Vec<_>>())
        })
        .find(|ids| !ids.is_empty())
        .unwrap_or_default()
}

/// 猜你喜欢电台的下一批歌，需要登录。每次调用都是新的一批，不缓存。
pub async fn guess_you_like() -> Result<Vec<Song>> {
    let data = core()
        .musicu_with_comm(
            "music.radioProxy.MbTrackRadioSvr",
            "get_radio_track",
            json!({ "id": 99, "num": 5, "from": 0, "scene": 0, "song_ids": [] }),
            webkit_comm(),
        )
        .await?;
    Ok(parse::songs(&data["tracks"]))
}

/// 刷歌模式（雷达）：按起始歌曲取第 `page` 批相似歌曲，从 1 开始。
pub async fn radar_songs(seed: &[i64], page: u32) -> Result<Vec<Song>> {
    let data = core()
        .musicu_with_comm(
            "music.recommend.TrackRelationServer",
            "GetRadarSong",
            json!({ "Page": page, "ReqType": 0, "FavSongs": [], "EntranceSongs": seed }),
            webkit_comm(),
        )
        .await?;
    let tracks: Vec<Value> = data["VecSongs"].as_array().into_iter().flatten().map(|x| x["Track"].clone()).collect();
    Ok(parse::songs(&Value::Array(tracks)))
}

fn cards(feed: &Value) -> impl Iterator<Item = &Value> {
    feed["v_shelf"]
        .as_array()
        .into_iter()
        .flatten()
        .flat_map(|shelf| shelf["v_niche"].as_array().into_iter().flatten())
        .flat_map(|niche| niche["v_card"].as_array().into_iter().flatten())
}

/// Windows 客户端推荐页的“新歌首发”。
pub async fn new_songs() -> Result<Vec<Song>> {
    let c = core();
    let data = c
        .cached("newsong:desktop", 3600, || {
            c.musicu_with_comm("newsong.NewSongServer", "get_new_song_info", json!({ "type": 5 }), webkit_comm())
        })
        .await?;
    Ok(parse::songs(&data["songlist"]))
}

pub async fn playlist_detail(id: &str) -> Result<PlaylistDetail> {
    let c = core();
    let disstid: i64 = id.parse().unwrap_or(0);
    let data = c
        // “每日30首”这类歌单因人而异，缓存按账号区分
        .cached(&format!("playlist:{}:{id}", c.uin()), 600, || {
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
    let Some(sess) = c.session() else { bail!(ApiError::NotLoggedIn) };
    let mut out = Vec::new();

    let created = c
        .get_json(
            "https://c.y.qq.com/rsc/fcgi-bin/fcg_user_created_diss",
            &[("hostuin", sess.uin.clone()), ("sin", "0".into()), ("size", "200".into()), ("format", "json".into())],
        )
        .await?;
    if let Some(list) = created["data"]["disslist"].as_array() {
        out.extend(list.iter().filter(|p| n(&p["tid"]) != 0).map(|p| PlaylistBrief {
            id: s(&p["tid"]),
            title: s(&p["diss_name"]),
            cover_url: s(&p["diss_cover"]),
            song_count: n(&p["song_cnt"]) as u32,
            play_count: n(&p["listen_num"]) as u64,
            creator: sess.nickname.clone(),
        }));
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

    #[tokio::test]
    #[ignore = "需要联网"]
    async fn fetches_hot_search() {
        let hot = hot_search().await.unwrap();
        assert!(!hot.hot.is_empty());
    }

    #[tokio::test]
    #[ignore = "需要联网"]
    async fn fetches_radar_songs() {
        // 未登录时推荐页没有刷歌入口，用抓包里入口给过的歌曲 id
        assert!(!radar_songs(&[104420880], 1).await.unwrap().is_empty());
    }

    #[test]
    fn extracts_radar_seed_from_entry_card() {
        let feed = json!({ "v_shelf": [{ "v_niche": [{ "v_card": [
            { "type": 900, "scheme": "qqmusic://qq.com/ui/jumpToRadarMode?p=%7B%22EntranceSongs%22%3A%5B104420880%5D%2C%22Page%22%3A%221%22%7D" }
        ] }] }] });
        assert_eq!(radar_seed(&feed), vec![104420880]);
    }

    #[tokio::test]
    #[ignore = "需要联网"]
    async fn fetches_recommend_feed_with_playable_songs() {
        let sections = recommend_feed().await.unwrap().sections;
        let songs: Vec<_> = sections.iter().flat_map(|x| &x.songs).collect();
        assert!(!songs.is_empty(), "{sections:?}");
        assert!(songs.iter().all(|s| !s.mid.is_empty()));
        assert!(sections.iter().any(|x| !x.playlists.is_empty()));
    }

    #[tokio::test]
    #[ignore = "需要联网"]
    async fn fetches_new_songs() {
        assert!(!new_songs().await.unwrap().is_empty());
    }

    #[tokio::test]
    #[ignore = "需要联网"]
    async fn suggests_from_pinyin_initials() {
        let list = search_suggestions("yhbk").await.unwrap();
        assert!(list.iter().any(|x| x.kind == SuggestionKind::Song && x.title.contains("有何不可")), "{list:?}");
    }
}
