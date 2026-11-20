//! 下载文件夹里的文件认回下载记录（重装后），没有标记的当本地歌导入。

use std::collections::HashMap;

use anyhow::{Context, Result};

use crate::api::types::{Lyric, Quality, Singer, Song};
use crate::qq::client::now_ms;
use crate::qq::{lyric, music, parse, quality};

use super::{
    is_local, load, platform, records, save, song_json, Entry, Record, State, DOWNLOADER, LOCAL,
    MARK, STAGE,
};

pub(super) struct Info {
    pub(super) mark: Option<(i64, String)>,
    pub(super) title: String,
    pub(super) artist: String,
    pub(super) album: String,
    pub(super) secs: u32,
    /// 没有标记时按格式和码率估的音质。
    pub(super) quality: Quality,
    /// 内嵌封面和扩展名。
    pub(super) picture: Option<(Vec<u8>, &'static str)>,
}

pub(super) fn is_audio(name: &str) -> bool {
    let ext = name.rsplit_once('.').map_or("", |(_, e)| e);
    ["flac", "mp3", "m4a", "ogg", "wav"]
        .iter()
        .any(|e| ext.eq_ignore_ascii_case(e))
}

pub(super) fn stem_of(name: &str) -> &str {
    name.rsplit_once('.').map_or(name, |(s, _)| s)
}

/// 下载时存的 MediaStore 地址换成 `media:<id>`，和文件夹授权列出来的文件对得上。
pub(super) fn media_alias(file: &str) -> Option<String> {
    let id = file.strip_prefix("content://media/")?.rsplit('/').next()?;
    id.parse::<u64>().ok().map(|id| format!("media:{id}"))
}

pub(super) fn parse_mark(comment: &str) -> Option<(i64, String)> {
    let (id, q) = comment.trim().strip_prefix(MARK)?.split_once(':')?;
    quality::from_cache_key(q)?;
    Some((id.parse().ok().filter(|&id| id > 0)?, q.to_owned()))
}

pub(super) fn read_tagged(file: &str) -> Option<lofty::file::TaggedFile> {
    lofty::probe::Probe::new(std::io::BufReader::new(platform::open(file).ok()?))
        .guess_file_type()
        .ok()?
        .read()
        .ok()
}

pub(super) fn read_info(entry: &Entry) -> Option<Info> {
    use lofty::file::{AudioFile, TaggedFileExt};
    use lofty::picture::{MimeType, PictureType};
    use lofty::tag::ItemKey;

    let tagged = read_tagged(&entry.file)?;
    let tag = tagged.primary_tag().or_else(|| tagged.first_tag());
    let text = |key: ItemKey| {
        tag.and_then(|t| t.get_string(&key))
            .map_or_else(String::new, |s| s.trim().to_owned())
    };
    let props = tagged.properties();
    let kbps = props.audio_bitrate().unwrap_or(0);
    let ext = entry.name.rsplit_once('.').map_or(String::new(), |(_, e)| e.to_ascii_lowercase());
    let quality = match ext.as_str() {
        "flac" if props.bit_depth().unwrap_or(16) > 16 || props.sample_rate().unwrap_or(0) > 48000 => {
            Quality::Hires
        }
        "flac" | "wav" => Quality::Lossless,
        "mp3" if kbps >= 256 => Quality::High,
        "mp3" => Quality::Standard,
        "ogg" if kbps >= 256 => Quality::Ogg320,
        "ogg" => Quality::Ogg192,
        _ => Quality::Low,
    };
    let picture = tag.and_then(|t| {
        let pics = t.pictures();
        let p = pics
            .iter()
            .find(|p| p.pic_type() == PictureType::CoverFront)
            .or_else(|| pics.first())?;
        let ext = if p.mime_type() == Some(&MimeType::Png) { "png" } else { "jpg" };
        Some((p.data().to_vec(), ext))
    });
    Some(Info {
        mark: tag.and_then(|t| t.get_strings(&ItemKey::Comment).find_map(parse_mark)),
        title: text(ItemKey::TrackTitle),
        artist: text(ItemKey::TrackArtist),
        album: text(ItemKey::AlbumTitle),
        secs: props.duration().as_secs() as u32,
        quality,
        picture,
    })
}

/// 没有标记的文件：歌名、歌手先看标签，没有时按「歌手 - 歌名」拆文件名。
pub(super) fn local_song(entry: &Entry, info: &Info) -> Song {
    let stem = stem_of(&entry.name);
    let (artist, title) = stem.split_once(" - ").unwrap_or(("", stem));
    let pick = |tagged: &str, fallback: &str| {
        (if tagged.is_empty() { fallback.trim() } else { tagged }).to_owned()
    };
    // 文件地址不变，mid 就不变；FNV-1a 在各平台、各版本都算得一样
    let hash = entry
        .file
        .bytes()
        .fold(0xcbf2_9ce4_8422_2325u64, |h, b| (h ^ b as u64).wrapping_mul(0x100_0000_01b3));
    Song {
        id: 0,
        mid: format!("{LOCAL}{hash:016x}"),
        name: pick(&info.title, title),
        singers: pick(&info.artist, artist)
            .split(['/', ','])
            .map(str::trim)
            .filter(|s| !s.is_empty())
            .map(|name| Singer {
                mid: String::new(),
                name: name.into(),
            })
            .collect(),
        album_mid: String::new(),
        album_name: info.album.clone(),
        duration_secs: info.secs,
        media_mid: String::new(),
        cover_url: String::new(),
        vip: false,
        has_hq: false,
        has_flac: false,
        mv_vid: String::new(),
    }
}

/// 本地歌的封面存进数据目录，返回路径。
pub(super) fn save_cover(mid: &str, picture: &Option<(Vec<u8>, &str)>) -> Option<String> {
    let (data, ext) = picture.as_ref()?;
    let dir = STAGE.get()?.join("covers");
    std::fs::create_dir_all(&dir).ok()?;
    let path = dir.join(format!("{}.{ext}", mid.trim_start_matches(LOCAL)));
    std::fs::write(&path, data).ok()?;
    Some(path.to_string_lossy().into_owned())
}

/// 本地歌的记录：按标签重新读一遍信息；[mid] 是已有记录的就沿用，播放队列里的还认得。
pub(super) fn local_record(mid: Option<&str>, entry: &Entry, info: &Info, lrc: Option<String>, created: i64) -> (String, Record) {
    let mut song = local_song(entry, info);
    if let Some(mid) = mid {
        song.mid = mid.into();
    }
    let cover = save_cover(&song.mid, &info.picture);
    let key = quality::cache_key(info.quality);
    let rec = Record {
        song: song_json(&song),
        want: key.clone(),
        quality: Some(key),
        state: State::Done,
        received: entry.size,
        total: entry.size,
        file: Some(entry.file.clone()),
        lrc,
        error: None,
        created,
        cover,
    };
    (song.mid, rec)
}

/// 重装后数据库没了、歌还在下载文件夹里：按文件补回下载记录，返回补回的首数。
/// 有标记的按歌曲 id 取回歌曲信息；没有的当本地歌，信息、封面从标签读。
/// 已有记录的文件换成这次列出来的地址（Android 上文件夹授权的地址读得到也删得掉），本地歌顺便重读一遍。
pub async fn restore() -> Result<u32> {
    let mut known = HashMap::new();
    for (mid, rec) in records() {
        for file in rec.file.iter().chain(rec.lrc.iter()) {
            known.insert(file.clone(), mid.clone());
            if let Some(alias) = media_alias(file) {
                known.insert(alias, mid.clone());
            }
        }
    }
    let entries = tokio::task::spawn_blocking(platform::list).await??;
    let lrcs: HashMap<String, String> = entries
        .iter()
        .filter_map(|e| Some((e.name.strip_suffix(".lrc")?.to_owned(), e.file.clone())))
        .collect();
    let found = tokio::task::spawn_blocking(move || {
        entries
            .into_iter()
            .filter(|e| is_audio(&e.name))
            .filter_map(|e| {
                let mid = known
                    .get(&e.file)
                    .or_else(|| known.get(e.alias.as_ref()?))
                    .cloned();
                // 已有记录、也不是本地歌的不用读标签
                let info = match &mid {
                    Some(mid) if !is_local(mid) => None,
                    _ => Some(read_info(&e)?),
                };
                Some((e, mid, info))
            })
            .collect::<Vec<_>>()
    })
    .await?;

    let ids: Vec<i64> = found
        .iter()
        .filter(|(_, mid, _)| mid.is_none())
        .filter_map(|(_, _, i)| Some(i.as_ref()?.mark.as_ref()?.0))
        .collect();
    let mut tracks = HashMap::new();
    for chunk in ids.chunks(50) {
        for t in music::tracks_by_id(chunk).await?.as_array().into_iter().flatten() {
            tracks.insert(parse::n(&t["id"]), t.clone());
        }
    }

    let now = now_ms() as i64;
    let mut restored = 0;
    for (i, (entry, mid, info)) in found.into_iter().enumerate() {
        let lrc = lrcs.get(stem_of(&entry.name)).cloned();
        let (mid, rec) = match (mid, info) {
            (Some(mid), info) => {
                let Some(mut rec) = load(&mid) else { continue };
                match &info {
                    Some(info) if is_local(&mid) => {
                        rec = local_record(Some(&mid), &entry, info, lrc, rec.created).1;
                        restored += 1;
                    }
                    _ => {
                        if rec.file.as_deref() == Some(entry.file.as_str()) {
                            continue;
                        }
                        rec.file = Some(entry.file);
                        rec.lrc = lrc.or(rec.lrc);
                    }
                }
                (mid, rec)
            }
            (None, Some(info)) => {
                let created = now + i as i64;
                let marked = info.mark.as_ref().and_then(|(id, q)| {
                    let song = tracks.get(id)?.clone();
                    let mid = parse::song(&song)?.mid;
                    Some((mid, song, q.clone()))
                });
                let (mid, rec) = match marked {
                    Some((mid, song, key)) => (
                        mid,
                        Record {
                            song,
                            want: key.clone(),
                            quality: Some(key),
                            state: State::Done,
                            received: entry.size,
                            total: entry.size,
                            file: Some(entry.file),
                            lrc,
                            error: None,
                            created,
                            cover: None,
                        },
                    ),
                    None => local_record(None, &entry, &info, lrc, created),
                };
                // 这首已经有记录（比如重装后又下了一遍）就不动它
                if load(&mid).is_some() {
                    continue;
                }
                restored += 1;
                (mid, rec)
            }
            (None, None) => continue,
        };
        save(&mid, &rec);
        if let Some(d) = DOWNLOADER.get() {
            d.emit_record(&rec);
        }
    }
    Ok(restored)
}

pub(super) fn read_text(file: &str) -> Option<String> {
    use std::io::Read;
    let mut data = Vec::new();
    platform::open(file).ok()?.read_to_end(&mut data).ok()?;
    let text = String::from_utf8_lossy(&data);
    Some(text.trim_start_matches('\u{feff}').to_owned())
}

/// 下载时写的 .lrc 每个时间先一行原文，同一时间再跟一行翻译；拆回两份交给歌词解析。
pub(super) fn split_translation(text: &str) -> (String, String) {
    let (mut orig, mut trans) = (String::new(), String::new());
    let mut last = None;
    for line in text.lines() {
        let stamp = line
            .strip_prefix('[')
            .and_then(|r| r.split_once(']'))
            .map(|(s, _)| s)
            .filter(|s| s.starts_with(|c: char| c.is_ascii_digit()));
        let out = if stamp.is_some() && stamp == last { &mut trans } else { &mut orig };
        out.push_str(line);
        out.push('\n');
        last = stamp;
    }
    (orig, trans)
}

/// 本地歌的歌词：先读同名 .lrc，没有再读标签里的歌词。
pub fn local_lyric(mid: &str) -> Result<Lyric> {
    use lofty::file::TaggedFileExt;
    use lofty::tag::ItemKey;

    let rec = load(mid).context("download record is missing")?;
    let text = rec
        .lrc
        .as_deref()
        .and_then(read_text)
        .or_else(|| {
            let tagged = read_tagged(rec.file.as_deref()?)?;
            let tag = tagged.primary_tag().or_else(|| tagged.first_tag())?;
            tag.get_string(&ItemKey::Lyrics).map(str::to_owned)
        })
        .unwrap_or_default();
    let (orig, trans) = split_translation(&text);
    Ok(lyric::build(&orig, &trans, ""))
}
