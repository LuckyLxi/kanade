//! MV 详情和播放地址。

use anyhow::Result;
use serde_json::{json, Value};

use super::client::core;
use super::parse::{n, s};
use crate::api::types::*;

/// 官方客户端请求的字段（Windows 22.76 抓包）。
const INFO_FIELDS: &[&str] = &[
    "play_forbid_reason", "cover_pic", "name", "singers", "vid", "type", "playcnt", "pubdate", "duration",
    "uploader_nick", "desc", "code",
];

/// 取流返回的 filetype 对应的画面高度，按下载到的 MP4 文件头（tkhd）核对过。
fn height_of(filetype: i64) -> Option<u32> {
    match filetype {
        10 => Some(360),
        20 => Some(480),
        30 => Some(720),
        40 => Some(1080),
        _ => None,
    }
}

/// 播放地址有时效（expire=86400），每次打开都重新取，不缓存。
pub async fn mv_detail(vid: &str) -> Result<MvDetail> {
    let c = core();
    let key = format!("mv:{vid}");
    let (info, urls) = tokio::join!(
        c.cached(&key, 3600, || {
            c.musicu("music.video.VideoData", "get_video_info_batch", json!({ "vidlist": [vid], "required": INFO_FIELDS }))
        }),
        // 官方客户端用 request_type=10003 只拿到相对路径（urlPath），缺 CDN 基址；
        // 10001 + H.264 直接返回完整的 https 地址
        c.musicu("music.stream.MvUrlProxy", "GetMvUrls", json!({ "vids": [vid], "request_type": 10001, "addrtype": 3, "format": 264 })),
    );
    let info = info?;
    Ok(build(vid, &info[vid], &urls?[vid]))
}

fn build(vid: &str, info: &Value, urls: &Value) -> MvDetail {
    let pubdate = n(&info["pubdate"]);
    let mut streams: Vec<MvStream> = urls["mp4"]
        .as_array()
        .into_iter()
        .flatten()
        .filter(|x| n(&x["code"]) == 0)
        .filter_map(|x| {
            let height = height_of(n(&x["filetype"]))?;
            let url = ["freeflow_url", "url"]
                .iter()
                .flat_map(|k| x[*k].as_array().into_iter().flatten())
                .map(s)
                .find(|u| u.starts_with("https://"))?;
            Some(MvStream { height, url, size: n(&x["fileSize"]) as u64 })
        })
        .collect();
    streams.sort_by_key(|x| x.height);
    streams.dedup_by_key(|x| x.height);
    MvDetail {
        vid: vid.to_string(),
        name: s(&info["name"]),
        cover_url: s(&info["cover_pic"]),
        singers: info["singers"]
            .as_array()
            .into_iter()
            .flatten()
            .map(|x| Singer { mid: s(&x["mid"]), name: s(&x["name"]) })
            .filter(|x| !x.name.is_empty())
            .collect(),
        uploader: s(&info["uploader_nick"]),
        duration_secs: n(&info["duration"]).max(n(&urls["duration"])) as u32,
        play_count: n(&info["playcnt"]) as u64,
        publish_date: beijing_date(pubdate),
        description: s(&info["desc"]),
        streams,
    }
}

/// Unix 秒 → 北京时间的 yyyy-mm-dd；0 为空。
fn beijing_date(secs: i64) -> String {
    if secs <= 0 {
        return String::new();
    }
    // 不为一个日期引入时间库：按天数换算公历日期（Howard Hinnant 的 civil_from_days）
    let days = (secs + 8 * 3600).div_euclid(86400);
    let z = days + 719468;
    let era = z.div_euclid(146097);
    let doe = z - era * 146097;
    let yoe = (doe - doe / 1460 + doe / 36524 - doe / 146096) / 365;
    let doy = doe - (365 * yoe + yoe / 4 - yoe / 100);
    let mp = (5 * doy + 2) / 153;
    let d = doy - (153 * mp + 2) / 5 + 1;
    let m = if mp < 10 { mp + 3 } else { mp - 9 };
    let y = yoe + era * 400 + i64::from(m <= 2);
    format!("{y:04}-{m:02}-{d:02}")
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn picks_https_streams_by_height() {
        let info = json!({ "name": "心月辞·何所往", "pubdate": 1789574400, "duration": 169, "playcnt": 4906,
            "singers": [{ "mid": "002wbPaC0L9C3A", "name": "鸣潮先约电台" }] });
        let urls = json!({ "duration": 169, "mp4": [
            { "code": 2000, "filetype": 0, "url": [], "freeflow_url": [] },
            { "code": 0, "filetype": 30, "fileSize": 17583436, "url": ["http://a/720"], "freeflow_url": ["https://a/720"] },
            { "code": 0, "filetype": 10, "fileSize": 6469853, "url": ["https://a/360"], "freeflow_url": [] },
            { "code": 0, "filetype": 40, "fileSize": 1, "url": [], "freeflow_url": [] },
        ] });
        let d = build("004cp3hL2EXB5u", &info, &urls);
        assert_eq!(d.streams.iter().map(|x| (x.height, x.url.as_str())).collect::<Vec<_>>(), vec![(360, "https://a/360"), (720, "https://a/720")]);
        assert_eq!(d.publish_date, "2026-09-17");
        assert_eq!(d.singers[0].name, "鸣潮先约电台");
    }

    #[test]
    fn formats_beijing_date() {
        assert_eq!(beijing_date(0), "");
        assert_eq!(beijing_date(1_700_000_000), "2023-11-15");
        // UTC 16:00 已经是北京时间第二天
        assert_eq!(beijing_date(1_704_124_800), "2024-01-02");
    }
}
