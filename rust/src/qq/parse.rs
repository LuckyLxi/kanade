//! 把 QQ 音乐各接口里结构不太统一的 JSON 转成 api::types。

use serde_json::Value;

use crate::api::types::{Singer, Song};

pub fn s(v: &Value) -> String {
    match v {
        Value::String(s) => s.clone(),
        Value::Number(n) => n.to_string(),
        _ => String::new(),
    }
}

pub fn f(v: &Value) -> f64 {
    match v {
        Value::Number(n) => n.as_f64().unwrap_or(0.0),
        Value::String(s) => s.parse().unwrap_or(0.0),
        _ => 0.0,
    }
}

pub fn n(v: &Value) -> i64 {
    match v {
        Value::Number(n) => n.as_i64().unwrap_or(0),
        Value::String(s) => s.parse().unwrap_or(0),
        _ => 0,
    }
}

/// 返回第一个非空字符串字段。
pub fn first_s(v: &Value, keys: &[&str]) -> String {
    keys.iter().map(|k| s(&v[*k])).find(|x| !x.is_empty()).unwrap_or_default()
}

pub fn album_cover(album_mid: &str) -> String {
    format!("https://y.gtimg.cn/music/photo_new/T002R300x300M000{album_mid}.jpg")
}

pub fn singer_cover(singer_mid: &str) -> String {
    format!("https://y.gtimg.cn/music/photo_new/T001R300x300M000{singer_mid}.jpg")
}

pub fn singer_photo(singer_mid: &str) -> String {
    format!("https://y.gtimg.cn/music/photo_new/T001R800x800M000{singer_mid}.jpg")
}

/// 统一的歌曲解析。搜索、榜单、歌单返回的结构基本一致；
/// 部分旧接口会把歌曲包在 `songInfo` / `data` 里，这里一并处理。
pub fn song(v: &Value) -> Option<Song> {
    let v = if v["songInfo"].is_object() {
        &v["songInfo"]
    } else if v["data"].is_object() && v["mid"].is_null() {
        &v["data"]
    } else {
        v
    };
    let mid = first_s(v, &["mid", "songmid"]);
    if mid.is_empty() {
        return None;
    }
    let singers: Vec<Singer> = v["singer"]
        .as_array()
        .map(|a| a.iter().map(|x| Singer { mid: s(&x["mid"]), name: s(&x["name"]) }).collect())
        .unwrap_or_default();
    let album_mid = first_s(&v["album"], &["mid"]);
    let album_mid = if album_mid.is_empty() { s(&v["albummid"]) } else { album_mid };
    let file = &v["file"];
    let media_mid = first_s(file, &["media_mid"]);
    let media_mid = if media_mid.is_empty() { first_s(v, &["media_mid", "strMediaMid"]) } else { media_mid };
    let cover_url = if !album_mid.is_empty() {
        album_cover(&album_mid)
    } else {
        singers.first().filter(|x| !x.mid.is_empty()).map(|x: &Singer| singer_cover(&x.mid)).unwrap_or_default()
    };
    Some(Song {
        id: n(&v["id"]).max(n(&v["songid"])),
        // title 带版本后缀，比如 name 是 “My Color”，title 是 “My Color (Acoustic ver.)”
        name: first_s(v, &["title", "name", "songname"]),
        media_mid: if media_mid.is_empty() { mid.clone() } else { media_mid },
        mid,
        singers,
        album_name: { let a = first_s(&v["album"], &["name", "title"]); if a.is_empty() { s(&v["albumname"]) } else { a } },
        album_mid,
        duration_secs: n(&v["interval"]) as u32,
        cover_url,
        // 旧版搜索接口（client_search_cp）的字段名不带下划线
        vip: n(&v["pay"]["pay_play"]) == 1 || n(&v["pay"]["payplay"]) == 1,
        has_hq: n(&file["size_320mp3"]) > 0 || n(&v["size320"]) > 0,
        has_flac: n(&file["size_flac"]) > 0 || n(&v["sizeflac"]) > 0,
        mv_vid: s(&v["mv"]["vid"]),
        gain_db: gain_db(&v["volume"]),
    })
}

/// 调大时不让峰值超过满幅；没给峰值就只调小。
fn gain_db(volume: &Value) -> f64 {
    let (gain, peak) = (f(&volume["gain"]), f(&volume["peak"]));
    if peak > 0.0 { gain.min(-20.0 * peak.log10()) } else { gain.min(0.0) }
}

pub fn songs(arr: &Value) -> Vec<Song> {
    arr.as_array().map(|a| a.iter().filter_map(song).collect()).unwrap_or_default()
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    #[test]
    fn song_keeps_video_vid_even_when_numeric_mv_id_is_zero() {
        let track = json!({"mid": "song-mid", "mv": {"id": 0, "vid": "video-vid", "vt": 1}});
        assert_eq!(song(&track).unwrap().mv_vid, "video-vid");
        assert_eq!(song(&json!({"songInfo": track})).unwrap().mv_vid, "video-vid");
        assert_eq!(song(&json!({"mid": "no-video"})).unwrap().mv_vid, "");
        assert_eq!(song(&json!({"mid": "empty-video", "mv": {"id": 0, "vid": ""}})).unwrap().mv_vid, "");
    }

    #[test]
    fn gain_is_capped_by_peak() {
        let gain = |gain: f64, peak: f64| song(&json!({"mid": "m", "volume": {"gain": gain, "peak": peak}})).unwrap().gain_db;
        assert_eq!(gain(-10.5, 1.0), -10.5);
        assert_eq!(gain(3.0, 1.0), 0.0);
        assert!((gain(6.0, 0.648) - 3.769).abs() < 0.01);
        assert_eq!(gain(0.0, 0.0), 0.0);
        assert_eq!(gain(3.0, 0.0), 0.0);
        assert_eq!(gain(-4.0, 0.0), -4.0);
        assert_eq!(song(&json!({"mid": "m"})).unwrap().gain_db, 0.0);
    }
}
