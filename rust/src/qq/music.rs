//! 搜索、播放链接、歌词、榜单、歌单。

use anyhow::{bail, Context, Result};
use serde_json::{json, Value};

use super::client::core;
use super::error::ApiError;
use super::lyric;
use super::parse::{self, first_s, n, s};
use super::qrc;
use super::quality::{file_name, playback_chain, stream_available};
use super::sign::hash33;
use crate::api::types::*;

pub async fn search_songs(keyword: &str, page: u32, page_size: u32) -> Result<SearchResult> {
    search(keyword, SearchKind::Song, page, page_size).await
}

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

/// Android 客户端抓包中的 searchid：18 位数字加逗号。
fn mobile_search_id() -> String {
    format!("{:018},", rand::random::<u64>() % 1_000_000_000_000_000_000)
}

/// 各分类在 Android 客户端抓包中的 search_type，以及结果在 `body` 下的字段名。
fn search_spec(kind: SearchKind) -> (u32, &'static str) {
    match kind {
        SearchKind::All => (100, ""),
        SearchKind::Song => (0, "item_song"),
        SearchKind::Singer => (1, "singer"),
        SearchKind::Album => (2, "item_album"),
        SearchKind::Playlist => (3, "item_songlist"),
        SearchKind::Video => (4, "item_mv"),
        SearchKind::Lyric => (7, "item_song"),
        SearchKind::User => (8, "item_user"),
    }
}

/// 分类搜索，`page` 从 1 开始。走 Android 客户端的接口，未登录也有完整结果。
pub async fn search(
    keyword: &str,
    kind: SearchKind,
    page: u32,
    page_size: u32,
) -> Result<SearchResult> {
    if kind == SearchKind::All {
        return search_all(keyword, page).await;
    }
    let c = core();
    let (search_type, group) = search_spec(kind);
    let key = format!("search:mobile:{search_type}:{keyword}:{page}:{page_size}");
    let data = c
        .cached(&key, 600, || async {
            let d = c
                .mobile_public(
                    "music.search.SearchCgiService",
                    "DoSearchForQQMusicMobile",
                    json!({
                        "query": keyword,
                        "highlight": 0,
                        "searchid": mobile_search_id(),
                        "sub_searchid": 0,
                        "search_type": search_type,
                        "nqc_flag": 0,
                        "sin": (page - 1) * page_size,
                        "ein": page * page_size,
                        "page_num": page,
                        "num_per_page": page_size,
                        "cat": 2,
                        "grp": 1,
                        "remoteplace": if page == 1 { "search.android.smart" } else { "more.android.smart" },
                        "from": "8,",
                        "multi_zhida": 1,
                        "sem": 0,
                    }),
                )
                .await?;
            let meta = &d["meta"];
            Ok(json!({ "list": d["body"][group], "total": meta["sum"], "nextpage": meta["nextpage"] }))
        })
        .await?;
    Ok(search_result(kind, keyword, &data))
}

/// 综合搜索。上游第 1 页只有直达卡片和单曲，第 2 页是其余各段，之后每页都是“更多单曲”，
/// 所以这里的第 1 页合并上游前两页，第 n 页对应上游第 n+1 页。
/// 上游翻页要带上一页的 `nextpage_start`，只能从第 1 页依次请求，前面的页走缓存。
async fn search_all(keyword: &str, page: u32) -> Result<SearchResult> {
    let c = core();
    let last = page + 1;
    let mut start = Value::Null;
    let mut r = empty_result();
    for p in 1..=last {
        let mut param = json!({
            "ver": 0,
            "searchid": mobile_search_id(),
            "sub_searchid": 0,
            "search_type": 100,
            "query": keyword,
            "page_id": p,
            "page_num": 15,
            "remoteplace": if p == 1 { "search.android.smart" } else { "more.android.smart" },
            "highlight": 1,
            "nqc_flag": 0,
            "grp": 1,
            "multi_zhida": 1,
            "auto_page": 1,
            "related_data": "",
            "ambi_data": "",
            "from": "8,",
            "seqno": 1,
        });
        if !start.is_null() {
            param["page_start"] = start;
        }
        let d = c
            .cached(&format!("search:mobile:100:{keyword}:{p}"), 600, || {
                c.mobile_public("music.adaptor.SearchAdaptor", "do_search_v2", param)
            })
            .await?;
        start = d["meta"]["nextpage_start"].clone();
        if p == last || page == 1 {
            fill_all(&mut r, keyword, &d["body"]);
            r.has_more = n(&d["meta"]["nextpage"]) > 0;
        }
    }
    Ok(r)
}

fn fill_all(r: &mut SearchResult, keyword: &str, body: &Value) {
    for kind in [
        SearchKind::Song,
        SearchKind::Singer,
        SearchKind::Playlist,
        SearchKind::Album,
        SearchKind::Video,
    ] {
        fill(r, kind, keyword, &body[search_spec(kind).1]["items"]);
    }
    for group in body["direct_result"]["direct_group"]
        .as_array()
        .into_iter()
        .flatten()
    {
        r.direct.extend(
            group["direct_list"]
                .as_array()
                .into_iter()
                .flatten()
                .filter_map(direct),
        );
    }
    r.related.extend(
        body["item_related"]["items"]
            .as_array()
            .into_iter()
            .flatten()
            .map(|x| s(&x["search_word"]))
            .filter(|x| !x.is_empty()),
    );
}

fn direct(x: &Value) -> Option<SearchDirect> {
    let info = &x["custom_info"];
    let (kind, id) = match s(&x["restype"]).as_str() {
        "singer" => (SearchDirectKind::Singer, s(&info["mid"])),
        "songlist" => (SearchDirectKind::Playlist, s(&x["id"])),
        "album" => (SearchDirectKind::Album, first_s(info, &["albummid", "mid"])),
        "mv" => (SearchDirectKind::Video, s(&x["vid"])),
        _ => return None,
    };
    if id.is_empty() {
        return None;
    }
    Some(SearchDirect {
        kind,
        id,
        title: plain(&x["title"]),
        // 上游字段名就是 desciption
        subtitle: plain(&x["desciption"]),
        cover_url: s(&x["pic"]),
        tag: s(&info["subscript_text"]),
    })
}

/// 关了 highlight 仍有部分名字带 `<em>` 高亮标签。
fn plain(v: &Value) -> String {
    s(v).replace("<em>", "").replace("</em>", "")
}

fn empty_result() -> SearchResult {
    SearchResult {
        songs: vec![],
        song_tags: vec![],
        lyric_snippets: vec![],
        singers: vec![],
        albums: vec![],
        playlists: vec![],
        videos: vec![],
        users: vec![],
        direct: vec![],
        related: vec![],
        total: 0,
        has_more: false,
    }
}

fn search_result(kind: SearchKind, keyword: &str, data: &Value) -> SearchResult {
    let list = &data["list"];
    let mut r = empty_result();
    r.total = n(&data["total"]) as u32;
    // 最后一页 nextpage 为 -1
    r.has_more = list.as_array().is_some_and(|a| !a.is_empty()) && n(&data["nextpage"]) > 0;
    fill(&mut r, kind, keyword, list);
    r
}

fn fill(r: &mut SearchResult, kind: SearchKind, keyword: &str, list: &Value) {
    let items = list.as_array().map(Vec::as_slice).unwrap_or_default();
    match kind {
        SearchKind::All => {}
        SearchKind::Song | SearchKind::Lyric => {
            for item in items {
                if let Some(song) = parse::song(item) {
                    if kind == SearchKind::Lyric {
                        r.lyric_snippets.push(lyric_snippet(item, keyword));
                    }
                    r.song_tags.push(
                        item["vec_hotness"]
                            .as_array()
                            .into_iter()
                            .flatten()
                            .map(|h| plain(&h["desc"]))
                            .filter(|x| !x.is_empty())
                            .collect(),
                    );
                    r.songs.push(song);
                }
            }
        }
        SearchKind::Singer => r.singers.extend(
            items
                .iter()
                .map(|x| SingerBrief {
                    mid: s(&x["singerMID"]),
                    name: plain(&x["singerName"]),
                    avatar_url: parse::singer_cover(&s(&x["singerMID"])),
                    song_count: n(&x["songNum"]) as u32,
                    album_count: n(&x["albumNum"]) as u32,
                })
                .filter(|x| !x.mid.is_empty()),
        ),
        SearchKind::Album => r.albums.extend(
            items
                .iter()
                .map(|x| {
                    let singers: Vec<String> = x["singer_list"]
                        .as_array()
                        .into_iter()
                        .flatten()
                        .map(|x| plain(&x["name"]))
                        .filter(|x| !x.is_empty())
                        .collect();
                    AlbumBrief {
                        mid: s(&x["albummid"]),
                        name: plain(&x["name"]),
                        cover_url: parse::album_cover(&s(&x["albummid"])),
                        publish_date: s(&x["publish_date"]),
                        singer_name: if singers.is_empty() {
                            plain(&x["singer"])
                        } else {
                            singers.join(" / ")
                        },
                    }
                })
                .filter(|x| !x.mid.is_empty()),
        ),
        SearchKind::Playlist => r.playlists.extend(
            items
                .iter()
                .map(|x| PlaylistBrief {
                    id: s(&x["dissid"]),
                    title: plain(&x["dissname"]),
                    cover_url: s(&x["logo"]),
                    song_count: n(&x["songnum"]) as u32,
                    play_count: n(&x["listennum"]) as u64,
                    creator: plain(&x["nickname"]),
                })
                .filter(|x| !x.id.is_empty() && x.id != "0"),
        ),
        SearchKind::Video => r.videos.extend(
            items
                .iter()
                .map(|x| {
                    let uploader = plain(&x["uploader_nick"]);
                    let singer = plain(&x["singername"]);
                    VideoBrief {
                        vid: s(&x["vid"]),
                        name: plain(&x["mvname"]),
                        cover_url: s(&x["pic"]),
                        duration_secs: n(&x["duration"]) as u32,
                        play_count: n(&x["play_count"]) as u64,
                        uploaded: singer.is_empty() && !uploader.is_empty(),
                        creator: if singer.is_empty() { uploader } else { singer },
                    }
                })
                .filter(|x| !x.vid.is_empty()),
        ),
        SearchKind::User => {
            r.users.extend(
                items
                    .iter()
                    .map(|x| UserBrief {
                        euin: s(&x["encrypt_uin"]),
                        name: plain(&x["title"]),
                        // iconurl 是认证角标，不是头像
                        avatar_url: s(&x["pic"]),
                        // Android 接口没有单独的粉丝数和歌单数，subtitle 是“2.2万人关注  歌单达人”这种整句
                        fans_count: 0,
                        playlist_count: 0,
                        description: plain(&x["subtitle"]),
                    })
                    .filter(|x| !x.euin.is_empty()),
            )
        }
    }
}

/// 歌词搜索的 `lyric` / `lyric_hilight` 实测常为空，歌词文本在 `content` 里，
/// 第一行是“歌名 - 歌手”。取包含关键词的前两行；没有就用高亮字段去掉标签。
fn lyric_snippet(item: &Value, keyword: &str) -> String {
    let needle = keyword.trim().to_lowercase();
    // Android 接口的换行是字面的 `\n` 两个字符
    let content = s(&item["content"]).replace("\\n", "\n");
    let matched: Vec<&str> = content
        .lines()
        .skip(1)
        .map(str::trim)
        .filter(|line| !needle.is_empty() && line.to_lowercase().contains(&needle))
        .collect();
    // 搜人名时命中的多是“曲：周杰伦”这类署名行，有真正的歌词行就优先用
    let is_credit = |line: &&str| line.chars().take(16).any(|c| c == '：' || c == ':');
    let lyrics: Vec<&str> = matched.iter().copied().filter(|l| !is_credit(l)).collect();
    let hits: Vec<&str> = if lyrics.is_empty() { matched } else { lyrics }
        .into_iter()
        .take(2)
        .collect();
    if !hits.is_empty() {
        return hits.join(" / ");
    }
    first_s(item, &["lyric_hilight", "lyric"])
        .replace("<em>", "")
        .replace("</em>", "")
        .lines()
        .map(str::trim)
        .filter(|x| !x.is_empty())
        .take(2)
        .collect::<Vec<_>>()
        .join(" / ")
}

fn hot_keywords(list: &Value) -> Vec<HotKeyword> {
    list.as_array()
        .map(|a| {
            a.iter()
                .map(|k| {
                    let description = s(&k["description"]);
                    HotKeyword {
                        title: s(&k["title"]),
                        query: s(&k["query"]),
                        // “搜索发现”的“昨日热播”这类标签在 description_param 里
                        description: if description.is_empty() {
                            s(&k["description_param"]["description"])
                        } else {
                            description
                        },
                    }
                })
                .filter(|k| !k.query.is_empty())
                .collect()
        })
        .unwrap_or_default()
}

/// Android 客户端的搜索页：热门搜索、微博热搜等榜单，以及“搜索发现”（未登录也有）。
pub async fn hot_search() -> Result<HotSearch> {
    let c = core();
    let data = c
        .cached("hotkey:mobile", 600, || {
            c.mobile_public(
                "music.musicsearch.HotkeyService",
                "GetHotkeyAllBusinessForQQMusicMobile",
                json!({
                    "searchid": mobile_search_id(),
                    "remote_place": "",
                    "from": "8,",
                    "start": "0",
                    "need_reckey": 1,
                    "need_allhotkey": 1,
                    "need_track_info": 1,
                }),
            )
        })
        .await?;
    let boards = data["business_en_cn"]
        .as_array()
        .into_iter()
        .flatten()
        .map(|b| HotBoard {
            name: s(&b["tabname_cn"]),
            keywords: hot_keywords(&data["map_business_hotkey"][s(&b["tabname_en"])]["vec_hotkey"]),
        })
        .filter(|b| !b.name.is_empty() && !b.keywords.is_empty())
        .collect();
    Ok(HotSearch {
        boards,
        recommended: hot_keywords(&data["vec_reckey"]),
    })
}

/// Android 客户端的搜索联想，支持拼音和首字母，一次十几到二十条。
/// 有对应歌手时在最前面放歌手卡片；夹在中间的 AI 助手条目丢掉。
pub async fn search_suggestions(query: &str) -> Result<Vec<SearchSuggestion>> {
    let c = core();
    let data = c
        .cached(&format!("smartbox:mobile:{query}"), 600, || {
            c.mobile_public(
                "music.smartboxCgi.SmartBoxCgi",
                "GetSmartBoxResult",
                json!({ "query": query, "search_id": mobile_search_id(), "num_per_page": 20 }),
            )
        })
        .await?;
    let singers = data["vec_direct_items"]
        .as_array()
        .into_iter()
        .flatten()
        .filter(|x| s(&x["restype"]) == "singer")
        .map(|x| SearchSuggestion {
            kind: SuggestionKind::Singer,
            // 标题是“歌手: 周杰伦”
            title: s(&x["title"])
                .split_once(':')
                .map(|(_, name)| name.trim().to_string())
                .unwrap_or_else(|| s(&x["title"])),
            mid: s(&x["custom_info"]["mid"]),
            cover_url: s(&x["cover_url"]),
        })
        .filter(|x| !x.mid.is_empty());
    let keywords = data["items"]
        .as_array()
        .into_iter()
        .flatten()
        .filter(|x| s(&x["res_type"]) == "search")
        .map(|x| SearchSuggestion {
            kind: SuggestionKind::Keyword,
            title: plain(&x["hint"]),
            mid: String::new(),
            cover_url: String::new(),
        })
        .filter(|x| !x.title.is_empty());
    Ok(singers.chain(keywords).collect())
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

/// Windows 客户端内嵌推荐页（QBCore webkit）的公参，与原生搜索的 ct=19 不同。
/// 登录后带上账号和 g_tk，推荐结果才是个性化的。
pub(crate) fn webkit_comm() -> Value {
    let c = core();
    let g_tk = c
        .session()
        .map(|s| hash33(&s.musickey, 5381))
        .unwrap_or(5381);
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

/// 首页推荐和专属乐流用新版 Android 客户端（20.09）的公参：栏目才带能单独刷新的 `refresh_param`，
/// 第 1 页之后也才有专属乐流。见 docs/qqmusic-api.md「首页推荐」。
fn android_feed_comm() -> Value {
    json!({"cv": "20090808", "v": "20090808", "chid": "73387"})
}

/// 请求首页推荐的一页，`param` 给出页码等，`ext` 这里补上。官方每次进首页、下拉都重新取，这里也不缓存。
async fn recommend_page(mut param: Value) -> Result<Value> {
    let c = core();
    // 不带 is_20_style 时栏目没有 refresh_param
    param["v_uniq"] = json!([]);
    param["ext"] =
        json!({"is_20_style": "1", "has_login": if c.session().is_some() { "1" } else { "0" }});
    c.musicu_with_comm(
        "music.recommend.RecommendFeed",
        "get_recommend_feed",
        param,
        android_feed_comm(),
    )
    .await
}

/// 把栏目转成区块，歌曲卡只有 id，统一补全一次。
async fn recommend_sections(shelves: &[&Value]) -> Result<Vec<RecommendSection>> {
    let ids: Vec<i64> = shelves
        .iter()
        .flat_map(|shelf| shelf_cards(shelf))
        .filter(|c| n(&c["type"]) == 200)
        .map(|c| n(&c["id"]))
        .filter(|id| *id > 0)
        .collect();
    let tracks = parse::songs(&tracks_by_id(&ids).await?)
        .into_iter()
        .map(|s| (s.id, s))
        .collect();
    Ok(shelves
        .iter()
        .filter_map(|shelf| recommend_section(shelf, &tracks))
        .collect())
}

/// 首页个性推荐（v_shelf → v_niche → v_card）。保留能直接用的歌曲卡（type 200）
/// 和歌单卡（type 500，含“每日30首”等入口），再记下刷歌模式入口的起始歌曲；节目等跳过。
/// 官方首页的歌曲栏目分在两页：第 1 页一个，第 2 页还有两个（第 2 页另带专属乐流的第一批，专属乐流另外取）。
/// 第 2 页的 `v_cache` 是第 1 页的栏目 id，`s_num` 是栏目数，和官方一样。
pub async fn recommend_feed() -> Result<RecommendFeed> {
    let first =
        recommend_page(json!({ "direction": 0, "page": 1, "s_num": 0, "v_cache": [] })).await?;
    let shown: Vec<String> = shelves(&first).map(|shelf| s(&shelf["id"])).collect();
    let second = recommend_page(
        json!({ "direction": 1, "page": 2, "s_num": shown.len(), "v_cache": shown }),
    )
    .await?;
    let all: Vec<&Value> = shelves(&first)
        .chain(shelves(&second).filter(|shelf| s(&shelf["id"]) != FEED_COLUMN_SHELF))
        .collect();
    let mut sections = recommend_sections(&all).await?;
    // 「你的歌单补给站」只发给未登录和 QQ 登录，微信登录没有；这时从歌单广场补一栏放在最后。
    // 补的这栏取不到不影响首页其余内容。见 docs/qqmusic-api.md「歌单补位」。
    if !all.iter().any(|shelf| s(&shelf["id"]) == PLAYLIST_SHELF) {
        if let Ok(playlists) = square_playlists().await {
            if !playlists.is_empty() {
                sections.push(RecommendSection {
                    title: String::new(),
                    songs: vec![],
                    playlists,
                    refresh: String::new(),
                });
            }
        }
    }
    let (radar_seed, radar_cover) = radar_entry(&first).unwrap_or_default();
    Ok(RecommendFeed {
        sections,
        radar_seed,
        radar_cover,
    })
}

/// 首页推荐里「你的歌单补给站」栏目的 id。
const PLAYLIST_SHELF: &str = "271";

/// 歌单广场「推荐」标签的第一批（官方分类歌单页一批 21 个），不需要登录。
async fn square_playlists() -> Result<Vec<PlaylistBrief>> {
    let data = core()
        .musicu(
            "music.playlist.PlaylistSquare",
            "GetRecommendWhole",
            json!({ "IsReqHead": false, "IsReqFeed": true, "FeedReq": { "From": 0, "Size": 21 } }),
        )
        .await?;
    Ok(parse_square_playlists(&data))
}

fn parse_square_playlists(data: &Value) -> Vec<PlaylistBrief> {
    data["FeedRsp"]["List"]
        .as_array()
        .into_iter()
        .flatten()
        .map(|x| &x["Playlist"]["basic"])
        .filter(|b| n(&b["tid"]) > 0)
        .map(|b| PlaylistBrief {
            id: n(&b["tid"]).to_string(),
            title: s(&b["title"]),
            cover_url: s(&b["cover"]["medium_url"]),
            song_count: n(&b["song_cnt"]) as u32,
            play_count: n(&b["play_cnt"]) as u64,
            creator: s(&b["creator"]["nick"]),
        })
        .collect()
}

/// 单独刷新首页的一个栏目，`refresh` 是该栏目的 [`RecommendSection::refresh`]，原样带回；
/// 服务端只返回这一栏的新内容，标题也可能换了。第 2 页的栏目也是这样刷新。
pub async fn refresh_recommend_section(refresh: &str) -> Result<RecommendSection> {
    let info: Value = serde_json::from_str(refresh)
        .context(ApiError::bad_response("invalid recommend refresh_param"))?;
    let feed = recommend_page(
        json!({ "direction": 0, "page": 1, "s_num": 0, "v_cache": [], "refresh_info": info }),
    )
    .await?;
    let shelves: Vec<&Value> = shelves(&feed).collect();
    recommend_sections(&shelves)
        .await?
        .into_iter()
        .next()
        .context(ApiError::bad_response(
            "refreshed recommend shelf has no songs or playlists",
        ))
}

/// 一个栏目里没有能显示的歌曲或歌单时为 None。
fn recommend_section(
    shelf: &Value,
    tracks: &std::collections::HashMap<i64, Song>,
) -> Option<RecommendSection> {
    let title = s(&shelf["title_template"])
        .replace("{String}", &s(&shelf["title_content"]))
        .trim()
        .to_string();
    let shelf_cards: Vec<&Value> = shelf_cards(shelf).collect();
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
    // 顶上那排（301）和未登录时的栏目 ModuleID 为空，不能单独刷新
    let refresh = &shelf["refresh_param"];
    let refresh = if s(&refresh["ModuleID"]).is_empty() {
        String::new()
    } else {
        refresh.to_string()
    };
    (!songs.is_empty() || !playlists.is_empty()).then_some(RecommendSection {
        title,
        songs,
        playlists,
        refresh,
    })
}

const FORYOU_MODULE: &str = "music.recommend.RecommendWidget";

/// 「自定义推荐页」的原始列表。`ChoseStatus`：-1 固定显示，1 已勾选，2 未勾选。
async fn foryou_selections() -> Result<Vec<Value>> {
    let c = core();
    c.session().context(ApiError::NotLoggedIn)?;
    let data = c
        .musicu_with_comm(
            FORYOU_MODULE,
            "GetForyouConfigItems",
            json!({ "Cmd": "0" }),
            android_feed_comm(),
        )
        .await?;
    Ok(data["Selections"].as_array().cloned().unwrap_or_default())
}

/// 固定项和歌单卡（type 500）Kanade 首页能显示；其余是官方 App 里的小游戏、网页和专属功能，不列出。
fn foryou_listed(x: &Value) -> bool {
    n(&x["ChoseStatus"]) == -1 || n(&x["ItemType"]) == 500
}

/// 首页最上面那排卡片的可选项（只含 Kanade 能显示的），需要登录。见 docs/qqmusic-api.md「自定义推荐页」。
pub async fn foryou_config() -> Result<Vec<ForyouItem>> {
    Ok(foryou_selections()
        .await?
        .iter()
        .filter(|x| foryou_listed(x))
        .map(|x| ForyouItem {
            id: s(&x["Id"]),
            title: s(&x["Title"]),
            fixed: n(&x["ChoseStatus"]) == -1,
            chosen: n(&x["ChoseStatus"]) == 1,
        })
        .collect())
}

/// 保存勾选：官方把整张列表连同每项的 ChoseStatus 原样发回，这里先取一次最新列表再改状态。
/// 没列出的项保持原状，不动手机版的选择。
pub async fn save_foryou_config(chosen: &[String]) -> Result<()> {
    let mut items = foryou_selections().await?;
    for x in items
        .iter_mut()
        .filter(|x| n(&x["ChoseStatus"]) != -1 && foryou_listed(x))
    {
        x["ChoseStatus"] = json!(if chosen.contains(&s(&x["Id"])) { 1 } else { 2 });
    }
    let data = core()
        .musicu_write_with_comm(
            FORYOU_MODULE,
            "SaveForyouConfigItems",
            json!({ "Selections": items }),
            android_feed_comm(),
        )
        .await?;
    if n(&data["Code"]) != 0 {
        bail!(ApiError::ServerError {
            api: format!("{FORYOU_MODULE}.SaveForyouConfigItems"),
            code: s(&data["Code"])
        });
    }
    Ok(())
}

/// 专属乐流（栏目 315）只有新版 Android 客户端（20.09）的版本号才返回，旧版本号给的是另一套栏目。
const FEED_COLUMN_SHELF: &str = "315";

/// 专属乐流第 `page` 页（从 1 开始），`seen` 是之前各页返回的 `seen` 合在一起。需要登录。
/// 首页推荐的第 1 页里没有这个栏目，从推荐的第 2 页开始才是，所以服务端页码要加 1。
pub async fn feed_column(page: u32, seen: &[String]) -> Result<FeedColumnPage> {
    let c = core();
    c.session().context(ApiError::NotLoggedIn)?;
    let data = c
        .musicu_with_comm(
            "music.recommend.RecommendFeed",
            "get_recommend_feed",
            json!({
                "direction": 1,
                "page": page + 1,
                "s_num": page + 1,
                "v_cache": [],
                "v_uniq": seen,
                "ext": {"is_20_style": "1", "has_login": "1", "TwoColPages_proxy": "1", "IsTwoColumnFlow_proxy": "1", "two_col_page_proxy": "1"},
            }),
            android_feed_comm(),
        )
        .await?;
    let cards: Vec<&Value> = data["v_shelf"]
        .as_array()
        .into_iter()
        .flatten()
        .filter(|shelf| s(&shelf["id"]) == FEED_COLUMN_SHELF)
        .flat_map(|shelf| shelf["v_niche"].as_array().into_iter().flatten())
        .flat_map(|niche| niche["v_card"].as_array().into_iter().flatten())
        .collect();
    // 组卡只带第一首的完整信息，整页的组卡歌曲一次补全
    let group_ids: Vec<i64> = cards
        .iter()
        .filter(|c| n(&c["subtype"]) == 206)
        .flat_map(|c| {
            c["card_extra_info"]["SongList"]
                .as_array()
                .into_iter()
                .flatten()
                .map(|x| n(&x["ID"]))
        })
        .filter(|id| *id > 0)
        .collect();
    let tracks: std::collections::HashMap<i64, Song> =
        parse::songs(&tracks_by_id(&group_ids).await?)
            .into_iter()
            .map(|s| (s.id, s))
            .collect();
    Ok(feed_column_page(&cards, &tracks))
}

fn feed_column_page(
    cards: &[&Value],
    tracks: &std::collections::HashMap<i64, Song>,
) -> FeedColumnPage {
    let seen = cards
        .iter()
        .map(|c| format!("{}_{}_{}", n(&c["type"]), n(&c["subtype"]), s(&c["id"])))
        .collect();
    let cards = cards
        .iter()
        .filter_map(|c| match (n(&c["type"]), n(&c["subtype"])) {
            (200, 0) => Some(FeedCard {
                kind: FeedCardKind::Song,
                title: String::new(),
                tag: s(&c["tags"][0]["Tag"]),
                songs: vec![parse::song(&c["card_extra_info"]["Tracks"][0])?],
                playlist: None,
            }),
            (200, 206) => {
                let songs: Vec<Song> = c["card_extra_info"]["SongList"]
                    .as_array()?
                    .iter()
                    .filter_map(|x| tracks.get(&n(&x["ID"])).cloned())
                    .collect();
                (!songs.is_empty()).then(|| FeedCard {
                    kind: FeedCardKind::Group,
                    title: s(&c["title"]),
                    tag: String::new(),
                    songs,
                    playlist: None,
                })
            }
            (500, _) if !s(&c["id"]).is_empty() => Some(FeedCard {
                kind: FeedCardKind::Playlist,
                title: s(&c["title"]),
                tag: String::new(),
                songs: vec![],
                playlist: Some(PlaylistBrief {
                    id: s(&c["id"]),
                    title: s(&c["title"]),
                    cover_url: s(&c["cover"]),
                    song_count: 0,
                    play_count: n(&c["cnt"]) as u64,
                    creator: String::new(),
                }),
            }),
            _ => None,
        })
        .collect();
    FeedColumnPage { cards, seen }
}

/// 刷歌模式入口卡的跳转形如 `qqmusic://qq.com/ui/jumpToRadarMode?p={"EntranceSongs":[id],...}`。
/// 返回起始歌曲和卡片封面（动态的专辑图，可能为空）。
fn radar_entry(feed: &Value) -> Option<(Vec<i64>, String)> {
    cards(feed)
        .filter_map(|c| {
            let scheme = s(&c["scheme"]);
            if !scheme.contains("jumpToRadarMode") {
                return None;
            }
            let p = url::Url::parse(&scheme)
                .ok()?
                .query_pairs()
                .find(|(k, _)| k == "p")?
                .1
                .into_owned();
            let p: Value = serde_json::from_str(&p).ok()?;
            let ids: Vec<i64> = p["EntranceSongs"]
                .as_array()?
                .iter()
                .map(n)
                .filter(|id| *id > 0)
                .collect();
            Some((ids, s(&c["cover"])))
        })
        .find(|(ids, _)| !ids.is_empty())
}

/// 猜你喜欢电台的下一批歌，需要登录。每次调用都是新的一批，不缓存。
pub async fn guess_you_like() -> Result<Vec<Song>> {
    radio_songs(GUESS_YOU_LIKE_RADIO).await
}

/// 「猜你喜欢」个性电台的 id，最近播放的音乐雷达里也是它。
pub const GUESS_YOU_LIKE_RADIO: i64 = 99;

/// 个性电台的下一批歌。
pub async fn radio_songs(id: i64) -> Result<Vec<Song>> {
    let data = core()
        .musicu_with_comm(
            "music.radioProxy.MbTrackRadioSvr",
            "get_radio_track",
            json!({ "id": id, "num": 5, "from": 0, "scene": 0, "song_ids": [] }),
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
    let tracks: Vec<Value> = data["VecSongs"]
        .as_array()
        .into_iter()
        .flatten()
        .map(|x| x["Track"].clone())
        .collect();
    Ok(parse::songs(&Value::Array(tracks)))
}

fn shelves(feed: &Value) -> impl Iterator<Item = &Value> {
    feed["v_shelf"].as_array().into_iter().flatten()
}

fn shelf_cards(shelf: &Value) -> impl Iterator<Item = &Value> {
    shelf["v_niche"]
        .as_array()
        .into_iter()
        .flatten()
        .flat_map(|niche| niche["v_card"].as_array().into_iter().flatten())
}

fn cards(feed: &Value) -> impl Iterator<Item = &Value> {
    shelves(feed).flat_map(shelf_cards)
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
    fn parses_square_playlists() {
        let data = json!({"FeedRsp": {"HasMore": true, "List": [
            {"Playlist": {"basic": {"tid": 8584177317u64, "title": "抖音超火", "cover": {"medium_url": "http://m"},
             "song_cnt": 229, "play_cnt": 81002785, "creator": {"nick": "轨迹"}}}, "WhereFrom": "干预"},
            {"Playlist": {"basic": {"tid": 0}}},
        ]}});
        let p = parse_square_playlists(&data);
        assert_eq!(p.len(), 1);
        assert_eq!(
            (p[0].id.as_str(), p[0].cover_url.as_str(), p[0].song_count),
            ("8584177317", "http://m", 229)
        );
        assert_eq!((p[0].play_count, p[0].creator.as_str()), (81002785, "轨迹"));
    }

    #[test]
    fn lists_only_foryou_items_kanade_can_show() {
        let listed = |v: Value| foryou_listed(&v);
        assert!(listed(json!({ "ChoseStatus": -1, "ItemType": 700 })));
        assert!(listed(json!({ "ChoseStatus": 2, "ItemType": 500 })));
        assert!(!listed(json!({ "ChoseStatus": 1, "ItemType": 900 })));
    }

    #[test]
    fn parses_feed_column_cards() {
        let feed = json!([
            {"id": "376471754", "type": 200, "subtype": 0, "tags": [{"Tag": "“男女对唱”"}],
             "card_extra_info": {"Tracks": [{"id": 376471754, "mid": "0026MOow3oTkqr", "name": "Midnight Crisis"}]}},
            {"id": "1052115", "type": 200, "subtype": 206, "title": "重温曾经你最爱听的歌",
             "card_extra_info": {"SongList": [{"ID": 1052115}, {"ID": 512682454}, {"ID": 999}]}},
            {"id": "9525416362", "type": 500, "subtype": 0, "title": "歌单", "cover": "https://c", "cnt": 53012},
            {"id": "1", "type": 1100, "subtype": 1100},
        ]);
        let cards: Vec<&Value> = feed.as_array().unwrap().iter().collect();
        let tracks = parse::songs(&json!([{"id": 1052115, "mid": "00384U752Rv92T"}, {"id": 512682454, "mid": "000EH0I44RZINq"}]))
            .into_iter()
            .map(|s| (s.id, s))
            .collect();
        let page = feed_column_page(&cards, &tracks);
        assert_eq!(
            page.seen,
            [
                "200_0_376471754",
                "200_206_1052115",
                "500_0_9525416362",
                "1100_1100_1"
            ]
        );
        assert_eq!(page.cards.len(), 3);
        assert_eq!(
            (
                page.cards[0].kind,
                page.cards[0].tag.as_str(),
                page.cards[0].songs[0].mid.as_str()
            ),
            (FeedCardKind::Song, "“男女对唱”", "0026MOow3oTkqr")
        );
        // 补全不到的歌跳过，组里剩下两首
        assert_eq!(
            (page.cards[1].kind, page.cards[1].songs.len()),
            (FeedCardKind::Group, 2)
        );
        let playlist = page.cards[2].playlist.as_ref().unwrap();
        assert_eq!(
            (
                page.cards[2].kind,
                playlist.id.as_str(),
                playlist.play_count
            ),
            (FeedCardKind::Playlist, "9525416362", 53012)
        );
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

    #[tokio::test]
    #[ignore = "需要联网"]
    async fn fetches_hot_search() {
        let hot = hot_search().await.unwrap();
        assert!(hot.boards.len() > 1, "{hot:?}");
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
            { "type": 900, "cover": "https://y.gtimg.cn/c.jpg", "scheme": "qqmusic://qq.com/ui/jumpToRadarMode?p=%7B%22EntranceSongs%22%3A%5B104420880%5D%2C%22Page%22%3A%221%22%7D" }
        ] }] }] });
        assert_eq!(
            radar_entry(&feed),
            Some((vec![104420880], "https://y.gtimg.cn/c.jpg".into()))
        );
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

    #[test]
    fn parses_category_search_results() {
        let singers = json!({ "list": [{ "singerMID": "003xSwHe0xtkZI", "singerName": "jixwang", "songNum": 168, "albumNum": 34 }], "total": 19, "nextpage": -1 });
        let r = search_result(SearchKind::Singer, "鸣潮", &singers);
        assert_eq!(
            (
                r.singers[0].name.as_str(),
                r.singers[0].song_count,
                r.has_more
            ),
            ("jixwang", 168, false)
        );

        let albums = json!({ "list": [{ "albummid": "0041WVfh2vtlJE", "name": "太阳之子", "publish_date": "2026-03-25",
            "singer": "<em>周杰伦</em>", "singer_list": [{ "name": "周杰伦" }] }], "total": 525, "nextpage": 2 });
        let r = search_result(SearchKind::Album, "周杰伦", &albums);
        assert_eq!(
            (
                r.albums[0].mid.as_str(),
                r.albums[0].singer_name.as_str(),
                r.albums[0].publish_date.as_str()
            ),
            ("0041WVfh2vtlJE", "周杰伦", "2026-03-25")
        );
        assert!(r.has_more);

        let playlists = json!({ "list": [{ "dissid": "7039749142", "dissname": "百听不厌的<em>周杰伦</em>",
            "logo": "http://qpic.y.qq.com/x/300", "songnum": 99, "listennum": 418605378, "nickname": "今晚月色很美" }],
            "total": 299, "nextpage": 2 });
        let r = search_result(SearchKind::Playlist, "周杰伦", &playlists);
        let p = &r.playlists[0];
        assert_eq!(
            (
                p.id.as_str(),
                p.title.as_str(),
                p.creator.as_str(),
                p.song_count
            ),
            ("7039749142", "百听不厌的周杰伦", "今晚月色很美", 99)
        );

        let videos = json!({ "list": [
            { "vid": "w0026q7f01a", "mvname": "晴天", "pic": "http://y.gtimg.cn/x.jpg",
              "duration": 317, "play_count": 120565509, "singername": "<em>周杰伦</em>", "uploader_nick": "" },
            { "vid": "011MCPJI0R8LSV", "mvname": "过场动画", "singername": "", "uploader_nick": "漂子" },
        ], "total": 597, "nextpage": 2 });
        let r = search_result(SearchKind::Video, "周杰伦", &videos);
        assert_eq!(
            (r.videos[0].vid.as_str(), r.videos[0].creator.as_str()),
            ("w0026q7f01a", "周杰伦")
        );
        assert!(!r.videos[0].uploaded && r.videos[1].uploaded);
        assert_eq!(r.videos[1].creator, "漂子");

        let users = json!({ "list": [{ "encrypt_uin": "oKEA7i4kowv57n**", "title": "<em>周杰伦</em>",
            "pic": "http://y.gtimg.cn/u.jpg", "subtitle": "2.2万人关注  歌单达人" }], "total": 175, "nextpage": -1 });
        let r = search_result(SearchKind::User, "周杰伦", &users);
        assert_eq!(
            (
                r.users[0].name.as_str(),
                r.users[0].description.as_str(),
                r.has_more
            ),
            ("周杰伦", "2.2万人关注  歌单达人", false)
        );
    }

    #[test]
    fn lyric_snippet_skips_title_line() {
        let item = json!({ "mid": "000bjZqH448qnK", "name": "远航星的告别", "lyric": "", "lyric_hilight": "",
            "content": "远航星的告别 - 鸣潮先约电台\\n词：Xulai\\n出品：鸣潮先约电台\\nThat snowflake once fell on my nose" });
        let r = search_result(
            SearchKind::Lyric,
            "snowflake",
            &json!({ "list": [item], "total": 1000, "nextpage": 2 }),
        );
        assert_eq!(
            r.lyric_snippets,
            vec!["That snowflake once fell on my nose".to_string()]
        );
        assert_eq!(r.songs.len(), 1);
        assert_eq!(
            lyric_snippet(
                &json!({ "content": "a - b", "lyric_hilight": "<em>你</em>好\n世界" }),
                "你"
            ),
            "你好 / 世界"
        );
        let credits = json!({ "content": "晴天 - 周杰伦\n词：周杰伦\n曲：周杰伦\n周杰伦说过的话" });
        assert_eq!(lyric_snippet(&credits, "周杰伦"), "周杰伦说过的话");
        assert_eq!(
            lyric_snippet(&json!({ "content": "晴天 - 周杰伦\n词：周杰伦" }), "周杰伦"),
            "词：周杰伦"
        );
    }

    #[test]
    fn parses_combined_search_page() {
        let body = json!({
            "direct_result": { "direct_group": [{ "direct_list": [
                { "restype": "singer", "id": "4558", "title": "歌手: 周杰伦", "desciption": "歌曲:1013",
                  "pic": "p", "custom_info": { "mid": "0025NhlN2yWrP4" } },
                { "restype": "fenlei", "id": "26192", "title": "活动" },
                { "restype": "mv", "id": "2444488", "vid": "002TOGAF0XYfjY", "title": "西西里 周杰伦",
                  "custom_info": { "subscript_text": "新MV" } },
            ] }] },
            "item_song": { "items": [
                { "mid": "a", "id": 1, "name": "晴天", "title": "晴天", "singer": [],
                  "vec_hotness": [{ "desc": "昨日热播" }, { "desc": "\"前奏一出来\"" }] },
                { "mid": "b", "id": 2, "name": "搁浅", "title": "搁浅", "singer": [] },
            ] },
            "item_related": { "items": [{ "display_word": "林俊杰", "search_word": "林俊杰" }] },
        });
        let mut r = empty_result();
        fill_all(&mut r, "周杰伦", &body);
        assert_eq!(r.direct.len(), 2);
        assert_eq!(r.direct[0].id, "0025NhlN2yWrP4");
        assert_eq!(
            (r.direct[1].kind, r.direct[1].tag.as_str()),
            (SearchDirectKind::Video, "新MV")
        );
        assert_eq!(r.songs.len(), r.song_tags.len());
        assert_eq!(r.song_tags[0], ["昨日热播", "\"前奏一出来\""]);
        assert!(r.song_tags[1].is_empty());
        assert_eq!(r.related, ["林俊杰"]);
    }

    #[test]
    fn hot_keywords_fall_back_to_description_param() {
        let list = json!([
            { "title": "发如雪", "query": "发如雪", "description": "国风经典" },
            { "title": "月声尽", "query": "月声尽", "description": "", "description_param": { "description": "昨日热播" } },
            { "title": "空", "query": "" },
        ]);
        let k = hot_keywords(&list);
        assert_eq!(k.len(), 2);
        assert_eq!(
            (k[0].description.as_str(), k[1].description.as_str()),
            ("国风经典", "昨日热播")
        );
    }

    #[tokio::test]
    #[ignore = "需要联网"]
    async fn searches_every_kind_without_login() {
        for kind in [
            SearchKind::Song,
            SearchKind::Singer,
            SearchKind::Album,
            SearchKind::Playlist,
            SearchKind::Video,
            SearchKind::Lyric,
            SearchKind::User,
        ] {
            let r = search("周杰伦", kind, 1, 30).await.unwrap();
            let count = r.songs.len()
                + r.singers.len()
                + r.albums.len()
                + r.playlists.len()
                + r.videos.len()
                + r.users.len();
            assert!(count > 0, "{kind:?} {r:?}");
        }
        let all = search("周杰伦", SearchKind::All, 1, 30).await.unwrap();
        assert!(
            all.direct
                .iter()
                .any(|d| d.kind == SearchDirectKind::Singer && !d.id.is_empty())
                && all.song_tags.iter().any(|t| !t.is_empty())
                && !all.singers.is_empty()
                && !all.related.is_empty()
                && all.has_more,
            "{all:?}"
        );
        // 第 2 页要带上一页的 nextpage_start，接得上才有歌
        assert!(!search("周杰伦", SearchKind::All, 2, 30)
            .await
            .unwrap()
            .songs
            .is_empty());
        let hot = hot_search().await.unwrap();
        assert!(
            hot.boards.len() > 1 && !hot.recommended.is_empty(),
            "{hot:?}"
        );
        let suggestions = search_suggestions("周杰伦").await.unwrap();
        assert!(
            suggestions
                .iter()
                .any(|x| x.kind == SuggestionKind::Singer && !x.mid.is_empty()),
            "{suggestions:?}"
        );
    }

    #[tokio::test]
    #[ignore = "需要联网"]
    async fn suggests_from_pinyin_initials() {
        let list = search_suggestions("yhbk").await.unwrap();
        assert!(
            list.iter()
                .any(|x| x.kind == SuggestionKind::Keyword && x.title.contains("有何不可")),
            "{list:?}"
        );
    }
}
