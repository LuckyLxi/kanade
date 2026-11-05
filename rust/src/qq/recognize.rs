//! 听歌识曲。接口和录音格式见 docs/qqmusic-song-recognition-capture.md。

use anyhow::{bail, Result};
use base64::Engine;
use serde_json::Value;

use super::client::core;
use super::error::ApiError;
use super::music::tracks_by_id;
use super::parse::{self, n};
use crate::api::types::Song;

const URL: &str = "https://c6.y.qq.com/youtu/humming/search";

/// `pcm` 是从开始录到现在的全部录音（8 kHz、16 位小端、单声道）；同一次识别的多次请求用同一个 `session_id`。
/// 还没认出来时返回 None。
pub async fn recognize(session_id: i64, pcm: &[u8]) -> Result<Option<Song>> {
    let body = base64::engine::general_purpose::STANDARD.encode(pcm);
    let text = core()
        .http
        .post(URL)
        .query(&[("sessionid", session_id.to_string()), ("recognizetype", "1".into()), ("fpType", "5".into())])
        .header("Content-Type", "application/x-www-form-urlencoded")
        .body(body)
        .send()
        .await?
        .error_for_status()?
        .text()
        .await?;
    let Some(id) = matched_song_id(&serde_json::from_str(&text)?)? else {
        return Ok(None);
    };
    // 无签名响应的歌名等字段是 base64，按 id 取完整歌曲信息。
    let tracks = tracks_by_id(&[id]).await?;
    Ok(tracks.as_array().and_then(|t| t.first()).and_then(parse::song))
}

fn matched_song_id(v: &Value) -> Result<Option<i64>> {
    if n(&v["ret"]) != 0 {
        bail!(ApiError::ServerError { api: "youtu.humming.search".into(), code: n(&v["ret"]).to_string() });
    }
    // 录音几乎是底噪时服务端也会返回一串候选，它们的 lcs 都是 0；真正认出来时 lcs 为正。
    if n(&v["results"][0]["lcs"]) <= 0 {
        return Ok(None);
    }
    let id = n(&v["songlist"][0]["songid"]);
    Ok((id > 0).then_some(id))
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    #[test]
    fn not_match_has_no_song() {
        let v = json!({"session_id":"1","fpType":5,"ret":0,"code":0,"subcode":-7,"message":"not_match"});
        assert_eq!(matched_song_id(&v).unwrap(), None);
    }

    #[test]
    fn match_returns_song_id() {
        let v = json!({"req_length":"12.144","results":[{"id":556513371,"inlier":36,"lcs":100,"type":"music"}],"ret":0,"status":1,
            "songlist":[{"songid":556513371,"songmid":"003iAr9X0S6fJp"}]});
        assert_eq!(matched_song_id(&v).unwrap(), Some(556513371));
    }

    #[test]
    fn noise_candidates_without_lcs_are_not_a_match() {
        let v = json!({"ret":0,"status":1,
            "results":[{"id":451888605,"inlier":15,"lcs":0},{"id":297595346,"inlier":15,"lcs":0}],
            "songlist":[{"songid":451888605,"songmid":"004BMSXY1cIiUa"}]});
        assert_eq!(matched_song_id(&v).unwrap(), None);
    }

    #[test]
    fn nonzero_ret_is_error() {
        assert!(matched_song_id(&json!({"ret": -1})).is_err());
    }
}
