//! 下载好的文件：认格式、写标签、生成 .lrc、起文件名。

use std::path::Path;

use anyhow::{Context, Result};

use crate::api::types::{Lyric, Song};

/// 按文件头认格式；同一档位有时拿到的是别的封装（比如 320k 降成了 OGG）。
pub(super) fn sniff(path: &Path) -> Option<(&'static str, &'static str)> {
    use std::io::Read;
    let mut head = [0u8; 12];
    std::fs::File::open(path).ok()?.read_exact(&mut head).ok()?;
    Some(if head.starts_with(b"fLaC") {
        ("flac", "audio/flac")
    } else if head.starts_with(b"OggS") {
        ("ogg", "audio/ogg")
    } else if head.starts_with(b"RIFF") {
        ("wav", "audio/wav")
    } else if &head[4..8] == b"ftyp" {
        ("m4a", "audio/mp4")
    } else if head.starts_with(b"ID3") || (head[0] == 0xFF && head[1] & 0xE0 == 0xE0) {
        ("mp3", "audio/mpeg")
    } else {
        return None;
    })
}

pub(super) fn write_tags(
    path: &Path,
    song: &Song,
    mark: &str,
    cover: Option<Vec<u8>>,
    lyrics: Option<String>,
) -> Result<()> {
    use lofty::config::{ParseOptions, WriteOptions};
    use lofty::file::{AudioFile, TaggedFileExt};
    use lofty::picture::{MimeType, Picture, PictureType};
    use lofty::tag::{Accessor, ItemKey, Tag};

    let mut file = lofty::probe::Probe::open(path)?
        .options(ParseOptions::new().read_properties(false))
        .guess_file_type()?
        .read()?;
    if file.primary_tag().is_none() {
        file.insert_tag(Tag::new(file.primary_tag_type()));
    }
    let tag = file.primary_tag_mut().context("no tag")?;
    tag.set_title(song.name.clone());
    tag.set_artist(
        song.singers
            .iter()
            .map(|s| s.name.as_str())
            .collect::<Vec<_>>()
            .join("/"),
    );
    if !song.album_name.is_empty() {
        tag.set_album(song.album_name.clone());
    }
    tag.insert_text(ItemKey::Comment, mark.into());
    if let Some(text) = lyrics {
        tag.insert_text(ItemKey::Lyrics, text);
    }
    if let Some(data) = cover {
        let mime = if data.starts_with(&[0x89, b'P', b'N', b'G']) {
            MimeType::Png
        } else {
            MimeType::Jpeg
        };
        tag.push_picture(Picture::new_unchecked(
            PictureType::CoverFront,
            Some(mime),
            None,
            data,
        ));
    }
    file.save_to_path(path, WriteOptions::default())?;
    Ok(())
}

/// 原文一行，有翻译时同一时间再跟一行翻译。
pub(super) fn lrc_text(lyric: &Lyric, song: &Song) -> Option<String> {
    if lyric.lines.is_empty() {
        return (!lyric.plain.trim().is_empty()).then(|| lyric.plain.clone());
    }
    let singers = song
        .singers
        .iter()
        .map(|s| s.name.as_str())
        .collect::<Vec<_>>()
        .join("/");
    let mut out = format!("[ti:{}]\n[ar:{singers}]\n[al:{}]\n", song.name, song.album_name);
    for line in &lyric.lines {
        let ms = line.time_ms;
        let stamp = format!("[{:02}:{:02}.{:02}]", ms / 60000, ms / 1000 % 60, ms % 1000 / 10);
        out.push_str(&format!("{stamp}{}\n", line.text));
        if !line.trans.is_empty() {
            out.push_str(&format!("{stamp}{}\n", line.trans));
        }
    }
    Some(out)
}

/// 「歌手 - 歌名」，去掉文件名里不能用的字符。
pub(super) fn file_stem(song: &Song) -> String {
    let singers = song
        .singers
        .iter()
        .map(|s| s.name.as_str())
        .collect::<Vec<_>>()
        .join(", ");
    let raw = if singers.is_empty() {
        song.name.clone()
    } else {
        format!("{singers} - {}", song.name)
    };
    let clean: String = raw
        .chars()
        .map(|c| match c {
            '\\' | '/' | ':' | '*' | '?' | '"' | '<' | '>' | '|' => '_',
            c if c.is_control() => '_',
            c => c,
        })
        .take(120)
        .collect();
    let clean = clean.trim().trim_end_matches('.').trim().to_owned();
    if clean.is_empty() {
        song.mid.clone()
    } else {
        clean
    }
}
