//! 最近播放：读取与官方客户端同一份云端记录，播放时上报。都走 PC 通道。

use anyhow::{bail, Result};
use serde_json::{json, Value};

use super::client::{core, now_ms};
use super::error::ApiError;
use super::parse;
use crate::api::types::Song;

/// 和官方客户端一样一次取 2500 条。
const REQUEST_COUNT: u32 = 2500;
/// 歌曲；6 是 MV。
const SONG_TYPE: i64 = 2;

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
    if data["code"].as_i64() != Some(0) {
        bail!(ApiError::ServerError { api: "PlayRecentlyRead".into(), code: format!("{:?}", data["code"].as_i64()) });
    }
    let list = data["data"]["songList"].as_array().into_iter().flatten();
    Ok(Value::Array(list.map(|item| item["track"].clone()).collect()))
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
    fn report_param_uses_captured_shape() {
        assert_eq!(report_param(42, 1700000000), json!({ "data": [{ "id": "42", "lastTime": 1700000000, "listenCnt": 1, "type": 2 }] }));
    }
}
