//! 其他用户的主页：资料和公开歌单。

use anyhow::Result;
use serde_json::{json, Value};

use super::client::core;
use super::parse::{n, s};
use crate::api::types::*;

const HOMEPAGE: &str = "music.UnifiedHomepage.UnifiedHomepageSrv";
/// 主页的歌单标签；歌手账号和只有动态的账号没有这个标签。
const PLAYLIST_TAB: &str = "disc";

/// 主页接口只接受加密账号（搜索结果的 encrypt_uin）。PC 通道返回 10000，走通用 musicu。
pub async fn user_profile(euin: &str) -> Result<UserProfile> {
    let c = core();
    let data = c
        .cached(&format!("user:{euin}"), 3600, || {
            c.musicu(HOMEPAGE, "GetHomepageHeader", json!({ "uin": euin, "IsQueryTabDetail": 1 }))
        })
        .await?;
    let info = &data["Info"];
    let base = &info["BaseInfo"];
    let playlist_count = data["TabDetail"]["TabList"]
        .as_array()
        .into_iter()
        .flatten()
        .find(|t| s(&t["TabID"]) == PLAYLIST_TAB)
        .map(|t| n(&t["Count"]) as u32)
        .unwrap_or(0);
    Ok(UserProfile {
        euin: euin.to_string(),
        name: s(&base["Name"]),
        avatar_url: { let big = s(&base["BigAvatar"]); if big.is_empty() { s(&base["Avatar"]) } else { big } },
        fans_count: n(&info["FansNum"]["Num"]) as u64,
        follow_count: n(&info["FollowNum"]["Num"]) as u64,
        playlist_count,
    })
}

/// 公开歌单第 `page` 页，从 0 开始（实测 0 和 1 是不同的两页）。
pub async fn user_playlists(euin: &str, creator: &str, page: u32, page_size: u32) -> Result<UserPlaylistPage> {
    let c = core();
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
    Ok(UserPlaylistPage { has_more: !playlists.is_empty() && n(&data["HasMore"]) == 1, playlists })
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
