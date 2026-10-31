//! 其他用户的主页：资料和公开歌单。

use anyhow::{bail, Context, Result};
use serde_json::{json, Value};

use super::client::core;
use super::error::ApiError;
use super::music::webkit_comm;
use super::parse::{self, n, s};
use crate::api::types::*;

const HOMEPAGE: &str = "music.UnifiedHomepage.UnifiedHomepageSrv";
/// 主页的歌单标签；歌手账号和只有动态的账号没有这个标签。
const PLAYLIST_TAB: &str = "disc";

/// 官方 PC 主页 CGI 接受搜索结果的 encrypt_uin；公开歌单分页仍用已验证的统一主页接口。
pub async fn user_profile(euin: &str) -> Result<UserProfile> {
    profile(&profile_data(euin).await?)
}

async fn profile_data(euin: &str) -> Result<Value> {
    let c = core();
    c.session().context(ApiError::NotLoggedIn)?;
    let data = c
        .cached(&format!("user:profile:{euin}"), 600, || async {
            let comm = webkit_comm();
            let data = c.get_json("https://c6.y.qq.com/rsc/fcgi-bin/fcg_get_profile_homepage.fcg", &[
                ("userid", euin.into()), ("cid", "205360838".into()), ("ct", "20".into()), ("cv", "2276".into()),
                ("reqfrom", "1".into()), ("reqtype", "0".into()), ("format", "json".into()),
                ("uin", c.uin()), ("platform", "wk_v17".into()),
                ("g_tk", s(&comm["g_tk"])), ("g_tk_new_20200303", s(&comm["g_tk_new_20200303"])),
            ]).await?;
            for field in ["code", "subcode"] {
                let code = data[field].as_i64().context(ApiError::bad_response("user profile result code is missing"))?;
                if code != 0 { bail!(ApiError::ServerError {api: "fcg_get_profile_homepage".into(), code: code.to_string()}); }
            }
            Ok(data["data"].clone())
        })
        .await?;
    Ok(data)
}

fn profile(data: &Value) -> Result<UserProfile> {
    let creator = &data["creator"];
    let euin = creator["encrypt_uin"].as_str().filter(|v| !v.is_empty())
        .context(ApiError::bad_response("user profile has no encrypted account"))?;
    Ok(UserProfile {
        euin: euin.into(), name: s(&creator["nick"]), avatar_url: s(&creator["headpic"]),
        fans_count: n(&creator["nums"]["fansnum"]) as u64,
        follow_count: n(&creator["nums"]["follownum"]) as u64,
        playlist_count: n(&data["mydiss"]["num"]) as u32,
        followed: n(&creator["isfollow"]) == 1,
        is_self: n(&creator["ishost"]) == 1,
        playlists_hidden: n(&creator["diss_lock"]) == 1 && n(&creator["ishost"]) != 1,
    })
}

/// 主页“我喜欢”的四类资产，分页从 0 开始，尊重目标用户的收藏隐私。
pub async fn user_assets(euin: &str, kind: UserAssetKind, page: u32, page_size: u32) -> Result<UserAssetPage> {
    let profile = profile_data(euin).await?;
    if favorites_hidden(&profile) { return Ok(UserAssetPage {hidden: true, ..Default::default()}); }
    let (module, method, param) = match kind {
        UserAssetKind::Song => {
            let Some(id) = liked_playlist_id(&profile)? else { return Ok(UserAssetPage::default()); };
            ("music.srfDissInfo.DissInfo", "CgiGetDiss",
                json!({"optype": 0, "disstid": id, "onlysonglist": 1, "song_begin": page * page_size, "song_num": page_size}))
        }
        UserAssetKind::Playlist => ("music.musicasset.PlaylistFavRead", "GetPlaylistFavInfo_v2",
            json!({"uin": euin, "offset": page * page_size, "size": page_size})),
        UserAssetKind::Album => ("music.musicasset.AlbumFavRead", "GetAlbumFavInfo_v2",
            json!({"euin": euin, "offset": page * page_size, "size": page_size})),
        UserAssetKind::Video => ("music.musicasset.MVFavRead", "getMyFavMV_v2",
            json!({"cid": 205361447, "encuin": euin, "support": 1, "num": page * page_size, "pagesize": page_size})),
    };
    let data = core().musicu_with_comm(module, method, param, webkit_comm()).await?;
    if matches!(kind, UserAssetKind::Song | UserAssetKind::Video) { check_asset_codes(&data, method)?; }
    Ok(assets(&data, kind))
}

fn favorites_hidden(data: &Value) -> bool {
    let creator = &data["creator"];
    n(&creator["ishost"]) != 1 && (n(&creator["fav_lock"]) == 1 || n(&creator["islock"]) == 1)
}

fn liked_playlist_id(data: &Value) -> Result<Option<i64>> {
    let Some(card) = data["mymusic"].as_array().into_iter().flatten().find(|x| n(&x["type"]) == 1) else { return Ok(None); };
    if n(&card["num0"]) == 0 { return Ok(None); }
    let id = s(&card["id"]).parse::<i64>().ok().filter(|id| *id > 0)
        .context(ApiError::bad_response("liked songs have no playlist id"))?;
    Ok(Some(id))
}

fn check_asset_codes(data: &Value, api: &str) -> Result<()> {
    for field in ["code", "subcode"] {
        let code = data[field].as_i64().context(ApiError::bad_response(format!("{api} has no {field}")))?;
        if code != 0 { bail!(ApiError::ServerError {api: api.into(), code: code.to_string()}); }
    }
    Ok(())
}

fn assets(data: &Value, kind: UserAssetKind) -> UserAssetPage {
    let hidden = data["hide"].as_bool().unwrap_or(false);
    let mut result = UserAssetPage {has_more: n(&data["hasmore"]) == 1, hidden, ..Default::default()};
    if hidden { result.has_more = false; return result; }
    let items = data["v_list"].as_array().into_iter().flatten();
    match kind {
        UserAssetKind::Playlist => result.playlists = items.filter(|x| n(&x["tid"]) > 0).map(|x| PlaylistBrief {
            id: s(&x["tid"]), title: s(&x["name"]), cover_url: s(&x["logo"]),
            song_count: n(&x["songnum"]) as u32, play_count: 0, creator: s(&x["nickname"]),
        }).collect(),
        UserAssetKind::Album => result.albums = items.filter(|x| !s(&x["mid"]).is_empty()).map(|x| AlbumBrief {
            mid: s(&x["mid"]), name: s(&x["name"]), cover_url: s(&x["logo"]),
            publish_date: super::mv::beijing_date(n(&x["pubtime"])),
            singer_name: x["v_singer"].as_array().into_iter().flatten().map(|singer| s(&singer["name"])).collect::<Vec<_>>().join(" / "),
        }).collect(),
        UserAssetKind::Video => result.videos = data["mvlist"].as_array().into_iter().flatten()
            .filter(|x| !s(&x["vid"]).is_empty()).map(|x| {
                let singer = s(&x["singer_name"]);
                let uploader = s(&x["uploader_nick"]);
                VideoBrief {
                    vid: s(&x["vid"]), name: s(&x["mv_name"]), cover_url: s(&x["mv_picurl"]),
                    duration_secs: n(&x["duration"]) as u32, play_count: n(&x["playcount"]) as u64,
                    uploaded: singer.is_empty() && !uploader.is_empty(), creator: if singer.is_empty() {uploader} else {singer},
                }
            }).collect(),
        UserAssetKind::Song => result.songs = parse::songs(&data["songlist"]),
    }
    result
}

/// 公开歌单第 `page` 页，从 0 开始（实测 0 和 1 是不同的两页）。
pub async fn user_playlists(euin: &str, creator: &str, page: u32, page_size: u32) -> Result<UserPlaylistPage> {
    let c = core();
    let data = profile_data(euin).await?;
    if profile(&data)?.playlists_hidden { return Ok(UserPlaylistPage {playlists: vec![], has_more: false}); }
    // 部分旧账号在统一主页仅有 about 标签，但 CGI 已返回完整公开列表。
    if let Some(result) = legacy_page(&data, creator, page, page_size) { return Ok(result); }
    let total = n(&data["mydiss"]["num"]);
    let data = c
        .cached(&format!("user:{euin}:disc:{page}:{page_size}"), 600, || {
            c.musicu(
                HOMEPAGE,
                "GetHomepageTabDetail",
                json!({ "uin": euin, "IsQueryTabDetail": 1, "TabID": PLAYLIST_TAB, "PageNum": page, "PageSize": page_size, "Order": 0 }),
            )
        })
        .await?;
    let playlists = playlists(&data["DiscTab"]["List"], creator);
    if page == 0 && total > 0 && playlists.is_empty() {
        bail!(ApiError::bad_response("public playlist list is incomplete"));
    }
    Ok(UserPlaylistPage { has_more: !playlists.is_empty() && n(&data["HasMore"]) == 1, playlists })
}

fn legacy_page(data: &Value, creator: &str, page: u32, page_size: u32) -> Option<UserPlaylistPage> {
    let list = data["mydiss"]["list"].as_array()?;
    let total = data["mydiss"]["num"].as_u64()? as usize;
    if list.len() != total { return None; }
    let start = page as usize * page_size as usize;
    let playlists = list.iter().skip(start).take(page_size as usize).map(|x| PlaylistBrief {
        id: s(&x["dissid"]), title: s(&x["title"]), cover_url: s(&x["picurl"]),
        song_count: song_count(&s(&x["subtitle"])), play_count: 0, creator: creator.into(),
    }).collect();
    Some(UserPlaylistPage {playlists, has_more: start + (page_size as usize) < total})
}

fn playlists(list: &Value, creator: &str) -> Vec<PlaylistBrief> {
    list.as_array()
        .into_iter()
        .flatten()
        .map(|x| PlaylistBrief {
            id: s(&x["Dissid"]),
            title: s(&x["Title"]),
            cover_url: s(&x["Picurl"]),
            song_count: song_count(&s(&x["Subtitle"])),
            play_count: 0,
            creator: creator.to_string(),
        })
        .filter(|x| !x.id.is_empty() && x.id != "0")
        .collect()
}

/// 副标题形如“62首    1260.8万次播放    校园 国语”，只取开头的歌曲数。
fn song_count(subtitle: &str) -> u32 {
    subtitle.trim().split('首').next().and_then(|x| x.trim().parse().ok()).unwrap_or(0)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn liked_songs_use_target_profile_playlist_and_respect_privacy() {
        let data = json!({"creator": {"ishost": 0, "fav_lock": 0}, "mymusic": [
            {"type": 5, "id": "999"}, {"type": 1, "id": "9876543210", "num0": 1400}
        ]});
        assert_eq!(liked_playlist_id(&data).unwrap(), Some(9876543210));
        let mut private = data; private["creator"]["fav_lock"] = json!(1);
        assert!(favorites_hidden(&private));
        private["creator"]["ishost"] = json!(1);
        assert!(!favorites_hidden(&private));
        assert!(liked_playlist_id(&json!({"mymusic": [{"type": 1, "num0": 2}]})).is_err());
        assert_eq!(liked_playlist_id(&json!({"mymusic": [{"type": 1, "num0": 0}]})).unwrap(), None);
    }

    #[test]
    fn liked_videos_use_favorite_fields_and_reject_failed_inner_codes() {
        let data = json!({"code": 0, "subcode": 0, "hasmore": 1, "mvlist": [
            {"vid": "video", "mv_name": "favorite", "mv_picurl": "https://example.test/cover",
                "playcount": 123, "duration": 169, "singer_name": "singer"},
            {"vid": "upload", "mv_name": "upload", "uploader_nick": "uploader"},
            {"id": 123, "mv_name": "no vid"}
        ]});
        check_asset_codes(&data, "MVFavRead").unwrap();
        let page = assets(&data, UserAssetKind::Video);
        assert_eq!(page.videos.len(), 2);
        assert!(page.has_more && page.videos[1].uploaded);
        assert!(page.videos[1].cover_url.is_empty(), "缺封面的收藏仍应保留，由界面显示占位图");
        assert_eq!((page.videos[0].vid.as_str(), page.videos[0].name.as_str(), page.videos[0].play_count), ("video", "favorite", 123));
        for bad in [json!({}), json!({"code": 0}), json!({"code": 0, "subcode": 405})] {
            assert!(check_asset_codes(&bad, "MVFavRead").is_err());
        }
    }

    #[test]
    fn profile_preserves_encrypted_target_and_privacy() {
        let data = json!({"creator": {"uin": 1152921504606846976u64, "encrypt_uin": "encrypted",
            "nick": "user", "isfollow": 1, "ishost": 0, "diss_lock": 1,
            "nums": {"fansnum": 42, "follownum": 7}}, "mydiss": {"num": 0}});
        let p = profile(&data).unwrap();
        assert_eq!(p.euin, "encrypted");
        assert!(p.followed && p.playlists_hidden && !p.is_self);
        let mut own = data.clone(); own["creator"]["ishost"] = json!(1);
        assert!(!profile(&own).unwrap().playlists_hidden);
        assert!(profile(&json!({"creator": {"uin": 42}})).is_err());
    }

    #[test]
    fn complete_legacy_snapshot_pages_without_relying_on_unified_disc_tab() {
        let data = json!({"mydiss": {"num": 2, "list": [
            {"dissid": 9876543210i64, "title": "first", "subtitle": "62首"},
            {"dissid": 9876543211i64, "title": "second", "subtitle": "3首"},
        ]}});
        let first = legacy_page(&data, "user", 0, 1).unwrap();
        let next = legacy_page(&data, "user", 1, 1).unwrap();
        assert_eq!(first.playlists[0].id, "9876543210");
        assert_eq!(next.playlists[0].id, "9876543211");
        assert!(first.has_more && !next.has_more);
        assert_eq!(first.playlists[0].song_count, 62);
        assert!(legacy_page(&json!({"mydiss": {"num": 20, "list": []}}), "user", 0, 10).is_none());
    }

    #[test]
    fn saved_assets_keep_pagination_and_private_content_separate() {
        let data = json!({"hide": false, "hasmore": 1, "v_list": [
            {"tid": 9876543210i64, "name": "saved", "songnum": 62, "logo": "https://example.test/c", "nickname": "creator"}
        ]});
        let page = assets(&data, UserAssetKind::Playlist);
        assert_eq!(page.playlists[0].id, "9876543210");
        assert!(page.has_more && !page.hidden);
        let mut private = data; private["hide"] = json!(true);
        let page = assets(&private, UserAssetKind::Playlist);
        assert!(page.hidden && !page.has_more && page.playlists.is_empty());
        let page = assets(&json!({"v_list": [{"mid": "album", "name": "saved album", "pubtime": 1700000000,
            "v_singer": [{"name": "a"}, {"name": "b"}]}]}), UserAssetKind::Album);
        assert_eq!(page.albums[0].singer_name, "a / b");
        assert_eq!(page.albums[0].publish_date, "2023-11-15");
    }

    #[test]
    fn parses_playlist_tab() {
        let list = json!([
            { "Dissid": 7022753020u64, "Title": "毕业季", "Picurl": "http://qpic.y.qq.com/c.jpg", "Subtitle": "62首    1260.8万次播放    校园 国语" },
            { "Dissid": 0, "Title": "空" },
        ]);
        let p = playlists(&list, "周杰伦");
        assert_eq!(p.len(), 1);
        assert_eq!((p[0].id.as_str(), p[0].song_count, p[0].creator.as_str()), ("7022753020", 62, "周杰伦"));
        assert_eq!(song_count(""), 0);
    }
}
