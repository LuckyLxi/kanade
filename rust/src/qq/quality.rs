//! 根据 QQ 歌曲文件信息和当前账号的取链接结果生成音质列表。

use anyhow::{bail, Context, Result};
use serde_json::{json, Value};
use tokio::task::JoinSet;

use super::client::core;
use super::error::ApiError;
use super::parse::{n, s};
use crate::api::types::{Quality, QualityOption, QualityUnavailableReason as Reason};

struct Format {
    quality: Quality,
    prefix: &'static str,
    ext: &'static str,
    field: &'static str,
    index: Option<usize>,
}

// size_new 的已知格式映射参考 QQMusicApi，显示哪些档位由歌曲响应决定。
const FORMATS: &[Format] = &[
    Format {
        quality: Quality::Master,
        prefix: "AI00",
        ext: "flac",
        field: "size_new",
        index: Some(0),
    },
    Format {
        quality: Quality::Hires,
        prefix: "RS01",
        ext: "flac",
        field: "size_hires",
        index: None,
    },
    Format {
        quality: Quality::Atmos,
        prefix: "Q000",
        ext: "flac",
        field: "size_new",
        index: Some(1),
    },
    Format {
        quality: Quality::Atmos51,
        prefix: "Q001",
        ext: "flac",
        field: "size_new",
        index: Some(2),
    },
    Format {
        quality: Quality::Atmos71,
        prefix: "Q003",
        ext: "ogg",
        field: "size_new",
        index: Some(6),
    },
    Format {
        quality: Quality::Dolby,
        prefix: "D004",
        ext: "mp4",
        field: "size_dolby",
        index: None,
    },
    Format {
        quality: Quality::Dts,
        prefix: "DT03",
        ext: "mp4",
        field: "size_new",
        index: Some(9),
    },
    Format {
        quality: Quality::Vinyl,
        prefix: "V0M0",
        ext: "mflac",
        field: "size_new",
        index: Some(4),
    },
    Format {
        quality: Quality::Aicodec,
        prefix: "TL01",
        ext: "nac",
        field: "size_new",
        index: Some(7),
    },
    Format {
        quality: Quality::Lossless,
        prefix: "F000",
        ext: "flac",
        field: "size_flac",
        index: None,
    },
    Format {
        quality: Quality::Ogg640,
        prefix: "O801",
        ext: "ogg",
        field: "size_new",
        index: Some(5),
    },
    Format {
        quality: Quality::High,
        prefix: "M800",
        ext: "mp3",
        field: "size_320mp3",
        index: None,
    },
    Format {
        quality: Quality::Ogg320,
        prefix: "O800",
        ext: "ogg",
        field: "size_new",
        index: Some(3),
    },
    Format {
        quality: Quality::Aac192,
        prefix: "C600",
        ext: "m4a",
        field: "size_192aac",
        index: None,
    },
    Format {
        quality: Quality::Ogg192,
        prefix: "O600",
        ext: "ogg",
        field: "size_192ogg",
        index: None,
    },
    Format {
        quality: Quality::Standard,
        prefix: "M500",
        ext: "mp3",
        field: "size_128mp3",
        index: None,
    },
    Format {
        quality: Quality::Low,
        prefix: "C400",
        ext: "m4a",
        field: "size_96aac",
        index: None,
    },
    Format {
        quality: Quality::Ogg96,
        prefix: "O400",
        ext: "ogg",
        field: "size_96ogg",
        index: None,
    },
    Format {
        quality: Quality::Aac48,
        prefix: "C200",
        ext: "m4a",
        field: "size_48aac",
        index: None,
    },
];

fn unsupported_reason(quality: Quality) -> Option<Reason> {
    match quality {
        Quality::Aicodec | Quality::Vinyl => Some(Reason::Unsupported),
        Quality::Dts | Quality::Dolby => Some(Reason::Unverified),
        _ => None,
    }
}

fn ensure_playable(quality: Quality) -> Result<()> {
    match unsupported_reason(quality) {
        Some(Reason::Unverified) => bail!(ApiError::UnverifiedFormat),
        Some(_) => bail!(ApiError::UnsupportedFormat),
        None => Ok(()),
    }
}

pub fn file_name(quality: Quality, media_mid: &str) -> Result<String> {
    ensure_playable(quality)?;
    let format = FORMATS
        .iter()
        .find(|f| f.quality == quality)
        .context(ApiError::UnsupportedFormat)?;
    Ok(format!(
        "{}{media_mid}{media_mid}.{}",
        format.prefix, format.ext
    ))
}

pub fn playback_chain(quality: Quality) -> Result<Vec<Quality>> {
    ensure_playable(quality)?;
    let fallback: &[Quality] = match quality {
        Quality::Aac48 => &[],
        Quality::Low | Quality::Ogg96 => &[Quality::Low],
        Quality::Standard | Quality::Ogg192 | Quality::Aac192 => &[Quality::Standard, Quality::Low],
        Quality::High | Quality::Ogg320 | Quality::Ogg640 => {
            &[Quality::High, Quality::Standard, Quality::Low]
        }
        _ => &[
            Quality::Lossless,
            Quality::High,
            Quality::Standard,
            Quality::Low,
        ],
    };
    let mut chain = vec![quality];
    chain.extend(fallback.iter().copied().filter(|q| *q != quality));
    Ok(chain)
}

/// 比 `quality` 低一档的音质，用于播不了时自动降级；已经是最低档时为 None。
pub fn lower(quality: Quality) -> Option<Quality> {
    playback_chain(quality).ok()?.get(1).copied()
}

/// 歌曲缓存索引里记录的音质标识。
pub fn cache_key(quality: Quality) -> String {
    format!("{quality:?}")
}

pub fn from_cache_key(key: &str) -> Option<Quality> {
    FORMATS.iter().map(|f| f.quality).find(|q| cache_key(*q) == key)
}

pub fn extension(quality: Quality) -> &'static str {
    FORMATS.iter().find(|f| f.quality == quality).map_or("bin", |f| f.ext)
}

fn options_from_file(file: &Value) -> Vec<QualityOption> {
    FORMATS
        .iter()
        // 编码格式不等于用户音质档位；保留格式映射供取链接使用，菜单只列音质档位。
        .filter(|format| {
            !matches!(
                format.quality,
                Quality::Ogg640
                    | Quality::Ogg320
                    | Quality::Ogg192
                    | Quality::Ogg96
                    | Quality::Aac192
                    | Quality::Aac48
            )
        })
        .filter_map(|format| {
            let size = match format.index {
                Some(index) => n(&file[format.field][index]),
                None => n(&file[format.field]),
            };
            (size > 0).then(|| QualityOption {
                quality: format.quality,
                available: false,
                reason: Some(unsupported_reason(format.quality).unwrap_or(Reason::NoLink)),
            })
        })
        .collect()
}

fn grant<'a>(data: &'a Value, filename: &str) -> Result<&'a Value> {
    data["midurlinfo"]
        .as_array()
        .context(ApiError::bad_response("quality response is missing midurlinfo"))?
        .iter()
        .find(|item| item["filename"].as_str() == Some(filename))
        .context(ApiError::bad_response("quality response is missing the requested file"))
}

fn grant_result(item: &Value) -> Result<i64> {
    item["result"]
        .as_i64()
        .context(ApiError::bad_response("quality response is missing grant result"))
}

fn unavailable_reason(item: &Value) -> Result<Reason> {
    Ok(match grant_result(item)? {
        104003 => Reason::NoPermission,
        104013 => Reason::DeviceRestricted,
        _ => Reason::NoLink,
    })
}

pub async fn stream_available(url: &str) -> Result<bool> {
    Ok(core().http.head(url).send().await?.status().is_success())
}

pub async fn song_qualities(mid: &str) -> Result<Vec<QualityOption>> {
    let c = core();
    let desktop = c.session().is_some();
    let track = c
        .cached(&format!("quality-track:{mid}"), 600, || async {
            let param =
                json!({ "ctx": 0, "client": 1, "types": [0], "modify_stamp": [0], "mids": [mid] });
            if desktop {
                c.desktop_musicu("music.trackInfo.UniformRuleCtrl", "CgiGetTrackInfo", param)
                    .await
            } else {
                c.musicu("music.trackInfo.UniformRuleCtrl", "CgiGetTrackInfo", param)
                    .await
            }
        })
        .await?;
    let file = &track["tracks"][0]["file"];
    if !file.is_object() {
        bail!(ApiError::bad_response("track response is missing file info"));
    }
    let mut options = options_from_file(file);
    let media_mid = s(&file["media_mid"]);
    let media_mid = if media_mid.is_empty() {
        mid
    } else {
        &media_mid
    };
    let files: Vec<_> = options
        .iter()
        .enumerate()
        .filter(|(_, option)| unsupported_reason(option.quality).is_none())
        .map(|(index, option)| Ok((index, file_name(option.quality, media_mid)?)))
        .collect::<Result<_>>()?;
    if files.is_empty() {
        return Ok(options);
    }
    let param = json!({
        "guid": if desktop { &c.desktop_guid } else { &c.guid },
        "uin": c.uin(),
        "loginflag": 1,
        "platform": "20",
        "ctx": 0,
        "filename": files.iter().map(|(_, name)| name).collect::<Vec<_>>(),
        "songmid": vec![mid; files.len()],
        "songtype": vec![0; files.len()],
    });
    let apis: &[(&str, &str)] = if desktop {
        &[("music.vkey.GetVkey", "UrlGetVkey")]
    } else {
        &[
            ("music.vkey.GetVkey", "UrlGetVkey"),
            ("vkey.GetVkeyServer", "CgiGetVkey"),
        ]
    };
    let mut urls: Vec<Option<String>> = vec![None; options.len()];
    let mut responded = false;
    let mut last_error = None;
    for &(module, method) in apis {
        let response = if desktop {
            c.desktop_musicu(module, method, param.clone()).await
        } else {
            c.musicu(module, method, param.clone()).await
        };
        let data = match response {
            Ok(data) => data,
            Err(error) => {
                last_error = Some(error);
                continue;
            }
        };
        responded = true;
        for (index, filename) in &files {
            if urls[*index].is_some() {
                continue;
            }
            let item = grant(&data, filename)?;
            let purl = s(&item["purl"]);
            let result = grant_result(item)?;
            if result == 0 && !purl.is_empty() {
                let sip = data["sip"]
                    .as_array()
                    .context(ApiError::bad_response("quality response is missing sip"))?
                    .iter()
                    .filter_map(Value::as_str)
                    .find(|url| url.starts_with("https://"))
                    .or_else(|| data["sip"][0].as_str())
                    .context(ApiError::bad_response("quality response has no CDN address"))?;
                urls[*index] = Some(format!("{sip}{purl}"));
            } else {
                options[*index].reason = Some(unavailable_reason(item)?);
            }
        }
        if files.iter().all(|(index, _)| urls[*index].is_some()) {
            break;
        }
    }
    if !responded {
        return Err(last_error.unwrap_or_else(|| ApiError::bad_response("quality request failed").into()));
    }
    if last_error.is_some() {
        for (index, _) in &files {
            if urls[*index].is_none() {
                options[*index].reason = Some(Reason::VerifyFailed);
            }
        }
    }
    let pending: Vec<_> = urls
        .into_iter()
        .enumerate()
        .filter_map(|(index, url)| url.map(|url| (index, url)))
        .collect();
    // HEAD 不下载音频正文；限制并发，防止切歌时同时建立过多 CDN 连接。
    for chunk in pending.chunks(4) {
        let mut checks = JoinSet::new();
        for (index, url) in chunk {
            let (index, url) = (*index, url.clone());
            checks.spawn(async move { (index, stream_available(&url).await) });
        }
        while let Some(check) = checks.join_next().await {
            let (index, available) = check?;
            options[index].available = available?;
            options[index].reason = (!options[index].available).then_some(Reason::FileUnavailable);
        }
    }
    Ok(options)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn lists_quality_tiers_instead_of_all_codec_variants() {
        // “月声尽，心灯明”：旧列表把 6 个额外编码格式也展示成了音质档位。
        let options = options_from_file(&json!({
            "size_new": [4096, 4096, 4096, 1024, 0, 2048, 4096, 0, 0, 0],
            "size_flac": 4096,
            "size_320mp3": 1024,
            "size_192aac": 768,
            "size_192ogg": 768,
            "size_128mp3": 512,
            "size_96aac": 384,
            "size_96ogg": 384,
            "size_48aac": 192,
        }));
        let qualities: Vec<_> = options.iter().map(|option| option.quality).collect();
        assert_eq!(qualities, vec![
            Quality::Master, Quality::Atmos, Quality::Atmos51, Quality::Atmos71,
            Quality::Lossless, Quality::High, Quality::Standard, Quality::Low,
        ]);
        // 没有 Hi-Res 文件时也不能为了补齐档位而添加它。
        assert!(!qualities.contains(&Quality::Hires));
    }

    #[test]
    fn only_lists_formats_present_in_qq_metadata() {
        let options = options_from_file(&json!({
            "size_128mp3": 1024,
            "size_flac": 0,
            "size_dolby": 128,
            "size_new": [4096, 0, 0, 0, 0, 0, 0, 512, 0, 256],
        }));
        let qualities: Vec<_> = options.iter().map(|option| option.quality).collect();
        assert_eq!(
            qualities,
            vec![
                Quality::Master,
                Quality::Dolby,
                Quality::Dts,
                Quality::Aicodec,
                Quality::Standard
            ]
        );
        assert!(options[1..4].iter().all(|option| !option.available));
        assert_eq!(options[1].reason, Some(Reason::Unverified));
        assert_eq!(options[3].reason, Some(Reason::Unsupported));
        assert!(options_from_file(&json!({})).is_empty());
    }

    #[test]
    fn rejects_missing_grants_and_distinguishes_permission_denials() {
        let data =
            json!({ "midurlinfo": [{ "filename": "M800test.mp3", "result": 104003, "purl": "" }] });
        assert_eq!(
            unavailable_reason(grant(&data, "M800test.mp3").unwrap()).unwrap(),
            Reason::NoPermission
        );
        assert!(grant(&data, "F000test.flac").is_err());
        assert!(unavailable_reason(&json!({})).is_err());
    }

    #[test]
    fn keeps_existing_fallback_order_and_handles_new_formats() {
        assert_eq!(
            playback_chain(Quality::High).unwrap(),
            vec![Quality::High, Quality::Standard, Quality::Low]
        );
        assert_eq!(
            playback_chain(Quality::Master).unwrap(),
            vec![
                Quality::Master,
                Quality::Lossless,
                Quality::High,
                Quality::Standard,
                Quality::Low
            ]
        );
        assert_eq!(
            playback_chain(Quality::Ogg96).unwrap(),
            vec![Quality::Ogg96, Quality::Low]
        );
        assert_eq!(
            playback_chain(Quality::Aac48).unwrap(),
            vec![Quality::Aac48]
        );
        assert_eq!(
            playback_chain(Quality::Ogg640).unwrap(),
            vec![
                Quality::Ogg640,
                Quality::High,
                Quality::Standard,
                Quality::Low
            ]
        );
        assert_eq!(
            file_name(Quality::Master, "test").unwrap(),
            "AI00testtest.flac"
        );
        assert!(file_name(Quality::Vinyl, "test").is_err());
        assert!(playback_chain(Quality::Dts).is_err());
        assert!(playback_chain(Quality::Dolby).is_err());
    }
}
