//! 最近播放：读取与官方客户端同一份云端记录，播放时上报。都走 PC 通道。

use anyhow::{bail, Result};
use serde_json::{json, Value};

use super::client::{core, now_ms};
use super::error::ApiError;
use super::parse::{self, first_s, n, s};
use crate::api::types::{AlbumBrief, PlaylistBrief, RecentBook, RecentCollections, RecentRadio, Song, VideoBrief};

/// 和官方客户端一样一次取 2500 条。
const REQUEST_COUNT: u32 = 2500;
/// 歌曲。
const SONG_TYPE: i64 = 2;
/// 「全部」：带专辑、歌单、有声，不带歌曲和视频。
const ALL_TYPE: i64 = 1;
const VIDEO_TYPE: i64 = 6;
/// 个性电台；官方「音乐雷达」只显示其中 radioType=2 的。
const RADIO_TYPE: i64 = 5;
const SHOWN_RADIO: i64 = 2;

/// 最近播放的歌曲，按最后播放时间从新到旧。
pub async fn recent_plays() -> Result<Vec<Song>> {
    let c = core();
    if c.session().is_none() {
        bail!(ApiError::NotLoggedIn);
    }
    let tracks = c
        .cached("recent_plays", 300, || async {
            let data = c
                .desktop_private(
                    "music.musicasset.PlayRecentlyRead",
                    "GetPlayRecentlyInfo",
                    json!({ "requestCnt": REQUEST_COUNT, "type": SONG_TYPE, "updateTime": 0 }),
                )
                .await?;
            recent_tracks(&data)
        })
        .await?;
    Ok(parse::songs(&tracks))
}

/// 响应里还有一层 `data`；每条记录的歌曲在 `track`，播放时间、次数在外面。
fn recent_tracks(data: &Value) -> Result<Value> {
    check(data)?;
    let list = data["data"]["songList"].as_array().into_iter().flatten();
    Ok(Value::Array(list.map(|item| item["track"].clone()).collect()))
}

fn check(data: &Value) -> Result<()> {
    if data["code"].as_i64() != Some(0) {
        bail!(ApiError::ServerError { api: "PlayRecentlyRead".into(), code: format!("{:?}", data["code"].as_i64()) });
    }
    Ok(())
}

/// 专辑、歌单、有声来自「全部」（type 1），视频（type 6）和电台（type 5）单独取。
pub async fn recent_collections() -> Result<RecentCollections> {
    let c = core();
    if c.session().is_none() {
        bail!(ApiError::NotLoggedIn);
    }
    let read = |kind: i64| async move {
        let data = c
            .desktop_private(
                "music.musicasset.PlayRecentlyRead",
                "GetPlayRecentlyInfo",
                json!({ "requestCnt": REQUEST_COUNT, "type": kind, "updateTime": 0 }),
            )
            .await?;
        check(&data)?;
        Ok::<_, anyhow::Error>(data)
    };
    let data = c
        .cached("recent_collections", 300, || async {
            let (all, videos, radios) = tokio::try_join!(read(ALL_TYPE), read(VIDEO_TYPE), read(RADIO_TYPE))?;
            Ok(json!({ "all": all["data"]["allItems"], "videos": videos["data"]["mvList"], "radios": radios["data"]["radioList"] }))
        })
        .await?;
    Ok(collections(&data))
}

fn collections(data: &Value) -> RecentCollections {
    let list = |v: &Value| v.as_array().cloned().unwrap_or_default();
    let all = &data["all"];
    RecentCollections {
        albums: list(&all["albumList"])
            .iter()
            .filter(|x| !s(&x["mid"]).is_empty())
            .map(|x| AlbumBrief {
                mid: s(&x["mid"]),
                name: s(&x["name"]),
                cover_url: parse::album_cover(&first_s(x, &["pmid", "mid"])),
                publish_date: String::new(),
                singer_name: s(&x["singerName"]),
            })
            .collect(),
        playlists: list(&all["geDanList"])
            .iter()
            .filter(|x| n(&x["id"]) > 0)
            .map(|x| PlaylistBrief {
                id: s(&x["id"]),
                title: s(&x["name"]),
                cover_url: s(&x["pic"]),
                song_count: n(&x["num"]) as u32,
                play_count: 0,
                creator: s(&x["creater"]),
            })
            .collect(),
        books: list(&all["listenBookList"])
            .iter()
            .map(|x| RecentBook {
                name: s(&x["name"]),
                cover_url: parse::album_cover(&s(&x["pmid"])),
                episode: parse::song(&x["track"]),
            })
            .collect(),
        radios: list(&data["radios"])
            .iter()
            .filter(|x| n(&x["radioType"]) == SHOWN_RADIO && n(&x["id"]) > 0)
            .map(|x| RecentRadio { id: n(&x["id"]), name: s(&x["name"]), cover_url: s(&x["pic"]) })
            .collect(),
        videos: list(&data["videos"])
            .iter()
            .map(|x| &x["mvInfo"])
            .filter(|v| !s(&v["vid"]).is_empty())
            .map(|v| {
                let singers = v["singers"].as_array().into_iter().flatten().map(|x| s(&x["name"])).collect::<Vec<_>>().join(" / ");
                let uploader = s(&v["uploader_nick"]);
                VideoBrief {
                    vid: s(&v["vid"]),
                    name: s(&v["name"]),
                    cover_url: s(&v["cover_pic"]),
                    duration_secs: 0,
                    play_count: 0,
                    uploaded: singers.is_empty() && !uploader.is_empty(),
                    creator: if singers.is_empty() { uploader } else { singers },
                }
            })
            .collect(),
    }
}

/// 记一次播放。写入，只在真正开始播放某首歌时调用。
pub async fn report_play(song_id: i64) -> Result<()> {
    let c = core();
    if c.session().is_none() {
        bail!(ApiError::NotLoggedIn);
    }
    let data = c
        .desktop_private("music.musicasset.PlayRecentlyWrite", "ReportPlayRecentlyInfo", report_param(song_id, (now_ms() / 1000) as i64))
        .await?;
    if data["ret"].as_i64() != Some(0) {
        bail!(ApiError::ServerError { api: "PlayRecentlyWrite".into(), code: format!("{:?}", data["ret"].as_i64()) });
    }
    c.uncache("recent_plays");
    Ok(())
}

fn report_param(song_id: i64, now_secs: i64) -> Value {
    json!({ "data": [{ "id": song_id.to_string(), "lastTime": now_secs, "listenCnt": 1, "type": SONG_TYPE }] })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn recent_plays_take_the_nested_track() {
        let data = json!({ "code": 0, "type": 2, "updateTime": 1700000000, "data": { "songList": [
            { "track": { "id": 1, "mid": "a", "name": "x", "singer": [], "album": { "mid": "m" } },
              "lastTime": 1700000000, "listenCnt": 3, "lastPlayDevice": 0 },
        ] } });
        let songs = parse::songs(&recent_tracks(&data).unwrap());
        assert_eq!(songs.len(), 1);
        assert_eq!(songs[0].mid, "a");
        assert!(recent_tracks(&json!({ "code": 1000 })).is_err());
    }

    #[test]
    fn collections_follow_android_capture_shape() {
        let data = json!({
            "all": {
                "albumList": [{ "mid": "am", "pmid": "am_1", "name": "A", "singerName": "S1/S2", "num": 6, "track": { "id": 0 } }],
                "geDanList": [{ "id": 42, "name": "P", "pic": "http://p", "num": 164, "creater": "C" }],
                "listenBookList": [{ "name": "B", "pmid": "bm_1", "id": 7,
                    "track": { "id": 9, "mid": "em", "name": "E", "singer": [], "album": { "mid": "bm" } } }],
            },
            "videos": [{ "mvInfo": { "vid": "v1", "name": "V", "cover_pic": "http://v",
                "singers": [{ "name": "X" }, { "name": "Y" }], "uploader_nick": "" } }],
            "radios": [
                { "id": 99, "name": "G", "pic": "http://g", "radioType": 2 },
                { "id": 736, "name": "R", "pic": "http://r", "radioType": 3 },
            ],
        });
        let c = collections(&data);
        assert_eq!(c.albums[0].mid, "am");
        assert!(c.albums[0].cover_url.ends_with("M000am_1.jpg"));
        assert_eq!((c.playlists[0].id.as_str(), c.playlists[0].song_count, c.playlists[0].creator.as_str()), ("42", 164, "C"));
        assert_eq!(c.books[0].episode.as_ref().unwrap().mid, "em");
        assert_eq!((c.videos[0].vid.as_str(), c.videos[0].creator.as_str(), c.videos[0].uploaded), ("v1", "X / Y", false));
        // 和官方一样只留 radioType=2
        assert_eq!(c.radios.iter().map(|r| r.id).collect::<Vec<_>>(), [99]);
    }

    #[test]
    fn report_param_uses_captured_shape() {
        assert_eq!(report_param(42, 1700000000), json!({ "data": [{ "id": "42", "lastTime": 1700000000, "listenCnt": 1, "type": 2 }] }));
    }
}
