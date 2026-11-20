//! 搜索、热搜、搜索联想。

use anyhow::Result;
use serde_json::{json, Value};

use super::client::core;
use super::parse::{self, first_s, n, s};
use crate::api::types::*;

pub async fn search_songs(keyword: &str, page: u32, page_size: u32) -> Result<SearchResult> {
    search(keyword, SearchKind::Song, page, page_size).await
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

#[cfg(test)]
mod tests {
    use super::*;

    #[tokio::test]
    #[ignore = "需要联网"]
    async fn fetches_hot_search() {
        let hot = hot_search().await.unwrap();
        assert!(hot.boards.len() > 1, "{hot:?}");
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
