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
        singers.first().map(|x: &Singer| singer_cover(&x.mid)).unwrap_or_default()
    };
    Some(Song {
        id: n(&v["id"]).max(n(&v["songid"])),
        name: first_s(v, &["name", "title", "songname"]),
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
    })
}

pub fn songs(arr: &Value) -> Vec<Song> {
    arr.as_array().map(|a| a.iter().filter_map(song).collect()).unwrap_or_default()
}
