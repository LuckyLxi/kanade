//! 首页推荐、为你推荐、专属乐流、雷达/电台。

use anyhow::{bail, Context, Result};
use serde_json::{json, Value};

use super::client::{core, webkit_comm};
use super::error::ApiError;
use super::music::tracks_by_id;
use super::parse::{self, n, s};
use crate::api::types::*;

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

#[cfg(test)]
mod tests {
    use super::*;

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
}
