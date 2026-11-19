//! 歌曲下载：和播放走同一套取链接（逐档降级），加密音源边下边解密，
//! 存成带标签的普通文件，歌词另存同名 .lrc。记录存在数据库里，界面只看记录和事件。

use std::collections::HashMap;
use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{Arc, Mutex, OnceLock};
use std::time::{Duration, Instant};

use anyhow::{bail, Context, Result};
use serde::{Deserialize, Serialize};
use serde_json::{json, Value};
use tokio::io::AsyncWriteExt;
use tokio::runtime::Handle;

use super::client::{core, UA};
use super::error::ApiError;
use super::qmc::Qmc;
use super::{dts, music, nac, parse, quality, ra360};
use crate::api::types::{
    DownloadEvent, DownloadItem, DownloadState, Lyric, Quality, Song, SongUrl,
};
use crate::frb_generated::StreamSink;

const REFERER: &str = "https://y.qq.com/";
const DIR_PREF: &str = "pref:download_dir";
const CONCURRENCY_PREF: &str = "pref:download_concurrency";
pub const MAX_CONCURRENCY: u32 = 5;
const DEFAULT_CONCURRENCY: u32 = 2;
/// 进度写库和通知界面的最短间隔。
const REPORT_EVERY: Duration = Duration::from_millis(300);

#[derive(Serialize, Deserialize, Clone, Copy, PartialEq, Eq)]
enum State {
    Queued,
    Running,
    Paused,
    Failed,
    Done,
}

#[derive(Serialize, Deserialize, Clone)]
struct Record {
    /// 和接口返回的歌曲同一种结构，用 `parse::song` 读回来。
    song: Value,
    want: String,
    quality: Option<String>,
    state: State,
    received: u64,
    total: u64,
    file: Option<String>,
    lrc: Option<String>,
    error: Option<String>,
    created: i64,
}

impl Record {
    fn song(&self) -> Option<Song> {
        parse::song(&self.song)
    }

    fn item(&self) -> Option<DownloadItem> {
        let quality = self
            .quality
            .as_deref()
            .and_then(quality::from_cache_key)
            .or_else(|| quality::from_cache_key(&self.want))?;
        Some(DownloadItem {
            song: self.song()?,
            quality,
            state: match self.state {
                State::Queued => DownloadState::Queued,
                State::Running => DownloadState::Running,
                State::Paused => DownloadState::Paused,
                State::Failed => DownloadState::Failed,
                State::Done => DownloadState::Done,
            },
            received: self.received,
            total: self.total,
            file: self.file.clone().unwrap_or_default(),
            error: self.error.as_deref().map(decode_error),
        })
    }
}

fn song_json(s: &Song) -> Value {
    json!({
        "id": s.id,
        "mid": s.mid,
        "name": s.name,
        "singer": s.singers.iter().map(|x| json!({ "mid": x.mid, "name": x.name })).collect::<Vec<_>>(),
        "album": { "mid": s.album_mid, "name": s.album_name },
        "interval": s.duration_secs,
        "file": {
            "media_mid": s.media_mid,
            "size_320mp3": s.has_hq as i64,
            "size_flac": s.has_flac as i64,
        },
        "pay": { "pay_play": s.vip as i64 },
        "mv": { "vid": s.mv_vid },
    })
}

/// 错误存成短字符串，读回来还原成界面能翻译的 ApiError。
fn encode_error(e: &anyhow::Error) -> String {
    if e
        .chain()
        .filter_map(|c| c.downcast_ref::<std::io::Error>())
        .any(|io| io.kind() == std::io::ErrorKind::PermissionDenied)
    {
        return format!("storage:{e:#}");
    }
    match e.chain().find_map(|c| c.downcast_ref::<ApiError>()) {
        Some(ApiError::NoPlayableUrl) => "no_url".into(),
        Some(ApiError::UnsupportedFormat) => "unsupported".into(),
        Some(ApiError::UnverifiedFormat) => "unverified".into(),
        Some(ApiError::NotLoggedIn) => "login".into(),
        Some(ApiError::Network { detail }) => format!("network:{detail}"),
        Some(other) => format!("internal:{other}"),
        None if e.chain().any(|c| c.is::<reqwest::Error>()) => format!("network:{e:#}"),
        None => format!("internal:{e:#}"),
    }
}

fn decode_error(code: &str) -> ApiError {
    let (kind, detail) = code.split_once(':').unwrap_or((code, ""));
    match kind {
        "no_url" => ApiError::NoPlayableUrl,
        "unsupported" => ApiError::UnsupportedFormat,
        "unverified" => ApiError::UnverifiedFormat,
        "login" => ApiError::NotLoggedIn,
        "network" => ApiError::Network {
            detail: detail.into(),
        },
        _ => ApiError::Internal {
            detail: detail.into(),
        },
    }
}

struct Cancelled;

impl std::fmt::Debug for Cancelled {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.write_str("download cancelled")
    }
}

impl std::fmt::Display for Cancelled {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.write_str("download cancelled")
    }
}

impl std::error::Error for Cancelled {}

pub struct Downloader {
    stage: PathBuf,
    http: reqwest::Client,
    handle: Handle,
    running: Mutex<HashMap<String, Arc<AtomicBool>>>,
    sinks: Mutex<Vec<StreamSink<DownloadEvent>>>,
}

static STAGE: OnceLock<PathBuf> = OnceLock::new();
static DOWNLOADER: OnceLock<Downloader> = OnceLock::new();

/// 下载中的临时文件放在数据目录里，下完再移到音乐文件夹。
pub fn init(stage: PathBuf) {
    let _ = STAGE.set(stage);
}

pub fn downloader() -> &'static Downloader {
    DOWNLOADER.get_or_init(|| {
        let stage = STAGE
            .get()
            .cloned()
            .unwrap_or_else(|| std::env::temp_dir().join("kanade-download"));
        let _ = std::fs::create_dir_all(&stage);
        let (tx, rx) = std::sync::mpsc::channel();
        std::thread::Builder::new()
            .name("download".into())
            .spawn(move || {
                let rt = tokio::runtime::Builder::new_current_thread()
                    .enable_all()
                    .build()
                    .expect("download runtime");
                let _ = tx.send(rt.handle().clone());
                rt.block_on(std::future::pending::<()>());
            })
            .expect("download thread");
        let d = Downloader {
            stage,
            http: reqwest::Client::builder()
                .user_agent(UA)
                .connect_timeout(Duration::from_secs(15))
                .read_timeout(Duration::from_secs(30))
                .build()
                .expect("download client"),
            handle: rx.recv().expect("download runtime"),
            running: Mutex::new(HashMap::new()),
            sinks: Mutex::new(Vec::new()),
        };
        // 上次没下完的（进程被杀或退出）留着，等手动继续
        for (mid, mut rec) in records() {
            if rec.state == State::Running {
                rec.state = State::Paused;
                save(&mid, &rec);
            }
        }
        d
    })
}

fn load(mid: &str) -> Option<Record> {
    serde_json::from_str(&core().store.download_get(mid)?).ok()
}

fn save(mid: &str, rec: &Record) {
    if let Ok(data) = serde_json::to_string(rec) {
        let _ = core().store.download_put(mid, &data, rec.created);
    }
}

fn records() -> Vec<(String, Record)> {
    core()
        .store
        .download_all()
        .iter()
        .filter_map(|data| serde_json::from_str::<Record>(data).ok())
        .filter_map(|rec| Some((rec.song()?.mid, rec)))
        .collect()
}

pub fn list() -> Vec<DownloadItem> {
    records().iter().filter_map(|(_, r)| r.item()).collect()
}

pub fn get(mid: &str) -> Option<DownloadItem> {
    load(mid)?.item()
}

pub fn concurrency() -> u32 {
    core()
        .store
        .kv_get(CONCURRENCY_PREF)
        .and_then(|v| v.parse().ok())
        .unwrap_or(DEFAULT_CONCURRENCY)
        .clamp(1, MAX_CONCURRENCY)
}

/// 下载好的这首歌；文件被删掉了就把记录也删掉，播放改走网络。
pub fn downloaded(mid: &str) -> Option<(String, Quality)> {
    let rec = load(mid).filter(|r| r.state == State::Done)?;
    let file = rec.file.clone()?;
    if !platform::exists(&file) {
        if let Some(lrc) = &rec.lrc {
            platform::delete(lrc);
        }
        core().store.download_delete(mid);
        if let Some(d) = DOWNLOADER.get() {
            d.emit(DownloadEvent::Removed { mid: mid.into() });
        }
        return None;
    }
    Some((file, quality::from_cache_key(rec.quality.as_deref()?)?))
}

/// 下载文件夹。Android 上固定是系统「音乐/Kanade」，这里返回给界面显示用。
pub fn dir() -> PathBuf {
    core()
        .store
        .kv_get(DIR_PREF)
        .filter(|d| !d.is_empty())
        .map(PathBuf::from)
        .unwrap_or_else(platform::default_dir)
}

pub fn set_dir(dir: &str) -> Result<()> {
    if dir.is_empty() {
        core().store.kv_delete(DIR_PREF)
    } else {
        core().store.kv_set(DIR_PREF, dir)
    }
}

impl Downloader {
    pub fn watch(&self, sink: StreamSink<DownloadEvent>) {
        self.sinks.lock().unwrap().push(sink);
    }

    fn emit(&self, event: DownloadEvent) {
        self.sinks
            .lock()
            .unwrap()
            .retain(|s| s.add(event.clone()).is_ok());
    }

    fn emit_record(&self, rec: &Record) {
        if let Some(item) = rec.item() {
            self.emit(DownloadEvent::Changed(item));
        }
    }

    /// 加入队列。已经在下的跳过；下过的按新音质重下，旧文件等新的下完再换掉。
    pub fn enqueue(&'static self, songs: Vec<Song>, want: Quality) {
        let key = quality::cache_key(want);
        let now = super::client::now_ms() as i64;
        for (i, song) in songs.iter().enumerate() {
            if self.running.lock().unwrap().contains_key(&song.mid) {
                continue;
            }
            let rec = match load(&song.mid) {
                Some(mut rec) => {
                    if rec.want != key || rec.state == State::Done {
                        rec.received = 0;
                        rec.total = 0;
                        rec.quality = None;
                        let _ = std::fs::remove_file(self.part(&song.mid));
                    }
                    rec.want = key.clone();
                    rec.state = State::Queued;
                    rec.error = None;
                    rec
                }
                None => Record {
                    song: song_json(song),
                    want: key.clone(),
                    quality: None,
                    state: State::Queued,
                    received: 0,
                    total: 0,
                    file: None,
                    lrc: None,
                    error: None,
                    created: now + i as i64,
                },
            };
            save(&song.mid, &rec);
            self.emit_record(&rec);
        }
        self.pump();
    }

    /// 删掉下载记录、下好的文件和没下完的临时文件。
    pub fn remove(&self, mid: &str) {
        if let Some(cancel) = self.running.lock().unwrap().remove(mid) {
            cancel.store(true, Ordering::Relaxed);
        }
        let _ = std::fs::remove_file(self.part(mid));
        if let Some(rec) = load(mid) {
            for file in rec.file.iter().chain(rec.lrc.iter()) {
                platform::delete(file);
            }
        }
        core().store.download_delete(mid);
        self.emit(DownloadEvent::Removed { mid: mid.into() });
    }

    fn part(&self, mid: &str) -> PathBuf {
        self.stage.join(format!("{mid}.part"))
    }

    fn pump(&'static self) {
        let limit = concurrency() as usize;
        let mut running = self.running.lock().unwrap();
        for (mid, mut rec) in records() {
            if running.len() >= limit {
                break;
            }
            if rec.state != State::Queued || running.contains_key(&mid) {
                continue;
            }
            let cancel = Arc::new(AtomicBool::new(false));
            running.insert(mid.clone(), cancel.clone());
            rec.state = State::Running;
            save(&mid, &rec);
            self.emit_record(&rec);
            self.handle.spawn(async move {
                let result = self.run(&mid, &cancel).await;
                self.finish(&mid, &cancel, result);
            });
        }
    }

    fn finish(&'static self, mid: &str, cancel: &Arc<AtomicBool>, result: Result<()>) {
        {
            let mut running = self.running.lock().unwrap();
            if running.get(mid).is_some_and(|c| Arc::ptr_eq(c, cancel)) {
                running.remove(mid);
            }
        }
        // 被暂停或删除时由那边改记录
        if !cancel.load(Ordering::Relaxed) {
            if let Err(e) = result {
                if let Some(mut rec) = load(mid) {
                    rec.state = State::Failed;
                    rec.error = Some(encode_error(&e));
                    save(mid, &rec);
                    self.emit_record(&rec);
                }
            }
        }
        self.pump();
    }

    async fn run(&'static self, mid: &str, cancel: &Arc<AtomicBool>) -> Result<()> {
        let mut rec = load(mid).context("download record is missing")?;
        let song = rec.song().context("download record is broken")?;
        let want = quality::from_cache_key(&rec.want).context(ApiError::UnsupportedFormat)?;
        let src = music::song_url(&song.mid, &song.media_mid, want).await?;
        let key = quality::cache_key(src.quality);
        let part = self.part(mid);
        // 拿到的档位和上次不一样时没下完的那部分不能接着用
        if rec.quality.as_deref() != Some(key.as_str()) {
            rec.received = 0;
            rec.total = 0;
            let _ = std::fs::remove_file(&part);
        }
        rec.quality = Some(key);
        save(mid, &rec);
        self.emit_record(&rec);

        let mut last = Instant::now();
        let mut report = |rec: &mut Record, received: u64, total: u64| {
            rec.received = received;
            rec.total = total;
            if last.elapsed() >= REPORT_EVERY {
                last = Instant::now();
                save(mid, rec);
                self.emit_record(rec);
            }
        };
        if quality::requires_pcm(src.quality) {
            self.fetch_pcm(&src, &part, cancel, &mut rec, &mut report)
                .await?;
        } else {
            self.fetch(&src, &part, cancel, &mut rec, &mut report)
                .await?;
        }
        if cancel.load(Ordering::Relaxed) {
            bail!(Cancelled);
        }

        let (ext, mime) = sniff(&part).unwrap_or((quality::extension(src.quality), "audio/*"));
        let cover = self.cover(&song).await;
        {
            let (part, song) = (part.clone(), song.clone());
            // 标签写不进去不影响下载
            let _ = tokio::task::spawn_blocking(move || write_tags(&part, &song, cover)).await;
        }
        let lrc = music::lyric(&song.mid, song.id)
            .await
            .ok()
            .and_then(|l| lrc_text(&l, &song));

        let stem = file_stem(&song);
        // 换音质重下：先删旧文件，新文件才能用回同一个名字
        for old in rec.file.take().iter().chain(rec.lrc.take().iter()) {
            platform::delete(old);
        }
        let file = platform::save(&part, &format!("{stem}.{ext}"), mime, false)?;
        let size = rec.total.max(rec.received);
        if let Some(text) = lrc {
            let lrc_part = self.stage.join(format!("{mid}.lrc"));
            let lrc_name = platform::lrc_name(&file, &stem);
            if std::fs::write(&lrc_part, text).is_ok() {
                rec.lrc = platform::save(&lrc_part, &lrc_name, "application/lrc", true).ok();
            }
            let _ = std::fs::remove_file(&lrc_part);
        }
        rec.file = Some(file);
        rec.state = State::Done;
        rec.received = size;
        rec.total = size;
        rec.error = None;
        save(mid, &rec);
        self.emit_record(&rec);
        Ok(())
    }

    /// 普通和加密音源：临时文件还在时从断点接着下，加密的按偏移解密后再写。
    async fn fetch(
        &self,
        src: &SongUrl,
        part: &Path,
        cancel: &AtomicBool,
        rec: &mut Record,
        report: &mut impl FnMut(&mut Record, u64, u64),
    ) -> Result<()> {
        let cipher = src.ekey.as_deref().map(Qmc::from_ekey).transpose()?;
        let mut offset = match tokio::fs::metadata(part).await {
            Ok(m) if rec.received > 0 => m.len(),
            _ => 0,
        };
        let mut req = self.http.get(&src.url).header("Referer", REFERER);
        if offset > 0 {
            req = req.header("Range", format!("bytes={offset}-"));
        }
        let mut resp = req.send().await?.error_for_status()?;
        if resp.status() != reqwest::StatusCode::PARTIAL_CONTENT {
            offset = 0;
        }
        let total = resp.content_length().map_or(0, |n| n + offset);
        let mut f = if offset > 0 {
            tokio::fs::OpenOptions::new().append(true).open(part).await?
        } else {
            tokio::fs::File::create(part).await?
        };
        report(rec, offset, total);
        while let Some(chunk) = resp.chunk().await? {
            if cancel.load(Ordering::Relaxed) {
                f.flush().await?;
                bail!(Cancelled);
            }
            let mut bytes = chunk.to_vec();
            if let Some(cipher) = &cipher {
                cipher.decrypt(&mut bytes, offset as usize);
            }
            f.write_all(&bytes).await?;
            offset += bytes.len() as u64;
            report(rec, offset, total);
        }
        f.sync_all().await?;
        if offset == 0 || (total > 0 && offset != total) {
            bail!("incomplete download");
        }
        rec.received = offset;
        rec.total = offset;
        Ok(())
    }

    /// DTS:X、360RA、AI 音质：整首下完再解码成 WAV，不支持断点。
    async fn fetch_pcm(
        &self,
        src: &SongUrl,
        part: &Path,
        cancel: &Arc<AtomicBool>,
        rec: &mut Record,
        report: &mut impl FnMut(&mut Record, u64, u64),
    ) -> Result<()> {
        let mut resp = self
            .http
            .get(&src.url)
            .header("Referer", REFERER)
            .send()
            .await?
            .error_for_status()?;
        let total = resp.content_length().unwrap_or(0);
        let mut encoded = Vec::with_capacity(total as usize);
        report(rec, 0, total);
        while let Some(chunk) = resp.chunk().await? {
            if cancel.load(Ordering::Relaxed) {
                bail!(Cancelled);
            }
            encoded.extend_from_slice(&chunk);
            report(rec, encoded.len() as u64, total);
        }
        if let Some(ekey) = &src.ekey {
            Qmc::from_ekey(ekey)?.decrypt(&mut encoded, 0);
        }
        let (q, part, cancel) = (src.quality, part.to_path_buf(), cancel.clone());
        let size = tokio::task::spawn_blocking(move || {
            let progress = |_, _| {};
            match q {
                Quality::Dts => dts::decode(&encoded, &part, &cancel, &progress),
                Quality::Aicodec => nac::decode(&encoded, &part, &cancel, &progress),
                Quality::Ra360 => ra360::decode(&encoded, &part, &cancel, &progress),
                _ => unreachable!("only decoded qualities use this download"),
            }
        })
        .await??;
        rec.received = size;
        rec.total = size;
        Ok(())
    }

    async fn cover(&self, song: &Song) -> Option<Vec<u8>> {
        if song.cover_url.is_empty() {
            return None;
        }
        let url = song.cover_url.replace("R300x300", "R800x800");
        let resp = self.http.get(url).send().await.ok()?.error_for_status().ok()?;
        Some(resp.bytes().await.ok()?.to_vec())
    }
}

/// 按文件头认格式；同一档位有时拿到的是别的封装（比如 320k 降成了 OGG）。
fn sniff(path: &Path) -> Option<(&'static str, &'static str)> {
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

fn write_tags(path: &Path, song: &Song, cover: Option<Vec<u8>>) -> Result<()> {
    use lofty::config::{ParseOptions, WriteOptions};
    use lofty::file::{AudioFile, TaggedFileExt};
    use lofty::picture::{MimeType, Picture, PictureType};
    use lofty::tag::{Accessor, Tag};

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
fn lrc_text(lyric: &Lyric, song: &Song) -> Option<String> {
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
fn file_stem(song: &Song) -> String {
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

#[cfg(not(target_os = "android"))]
mod platform {
    use std::path::{Path, PathBuf};

    use anyhow::Result;

    #[cfg(windows)]
    fn music_dir() -> Option<PathBuf> {
        use windows::Win32::System::Com::CoTaskMemFree;
        use windows::Win32::UI::Shell::{FOLDERID_Music, SHGetKnownFolderPath, KF_FLAG_DEFAULT};
        unsafe {
            let p = SHGetKnownFolderPath(&FOLDERID_Music, KF_FLAG_DEFAULT, None).ok()?;
            let s = p.to_string().ok();
            CoTaskMemFree(Some(p.0 as *const _));
            s.map(PathBuf::from)
        }
    }

    #[cfg(not(windows))]
    fn music_dir() -> Option<PathBuf> {
        std::env::var_os("HOME").map(|h| PathBuf::from(h).join("Music"))
    }

    pub fn default_dir() -> PathBuf {
        music_dir()
            .unwrap_or_else(std::env::temp_dir)
            .join("Kanade")
    }

    /// 把下好的临时文件移进下载文件夹，重名时加序号；[overwrite] 时直接覆盖（歌词跟着歌走）。
    pub fn save(src: &Path, name: &str, _mime: &str, overwrite: bool) -> Result<String> {
        let dir = super::dir();
        std::fs::create_dir_all(&dir)?;
        let mut dest = dir.join(name);
        if !overwrite {
            let (stem, ext) = name.rsplit_once('.').unwrap_or((name, ""));
            let mut n = 2;
            while dest.exists() {
                dest = dir.join(format!("{stem} ({n}).{ext}"));
                n += 1;
            }
        }
        if std::fs::rename(src, &dest).is_err() {
            std::fs::copy(src, &dest)?;
            let _ = std::fs::remove_file(src);
        }
        Ok(dest.to_string_lossy().into_owned())
    }

    /// 歌词和歌同名，歌因为重名加了序号时歌词也跟着。
    pub fn lrc_name(file: &str, _stem: &str) -> String {
        let stem = Path::new(file)
            .file_stem()
            .map_or_else(String::new, |s| s.to_string_lossy().into_owned());
        format!("{stem}.lrc")
    }

    pub fn delete(file: &str) {
        let _ = std::fs::remove_file(file);
    }

    pub fn exists(file: &str) -> bool {
        Path::new(file).is_file()
    }
}

/// Android 上经 MediaStore 存进系统「音乐/Kanade」（MediaStoreBridge.kt），文件记的是 content:// 地址。
#[cfg(target_os = "android")]
mod platform {
    use std::path::{Path, PathBuf};
    use std::sync::OnceLock;

    use anyhow::{bail, Context, Result};
    use jni::objects::{GlobalRef, JClass, JObject, JString, JValue};
    use jni::{JNIEnv, JavaVM};

    static BRIDGE: OnceLock<(JavaVM, GlobalRef)> = OnceLock::new();

    /// `MediaStoreBridge.install` 在每个进程的 `Application.onCreate` 里调用；
    /// 后台线程找不到 App 的类，所以这里先存一份类引用。
    #[no_mangle]
    pub extern "system" fn Java_com_lxi_kanade_MediaStoreBridge_nativeInit(
        env: JNIEnv,
        class: JClass,
    ) {
        if let (Ok(vm), Ok(class)) = (env.get_java_vm(), env.new_global_ref(class)) {
            let _ = BRIDGE.set((vm, class));
        }
    }

    fn call<T>(
        f: impl for<'a> FnOnce(&mut JNIEnv<'a>, &JClass<'a>) -> jni::errors::Result<T>,
    ) -> Result<T> {
        let (vm, class) = BRIDGE.get().context("MediaStore bridge unavailable")?;
        let mut env = vm.attach_current_thread()?;
        let class: &JClass = class.as_obj().into();
        let result = f(&mut env, class);
        if env.exception_check().unwrap_or(false) {
            let ex = env.exception_occurred()?;
            env.exception_clear()?;
            let message = env
                .call_method(&ex, "toString", "()Ljava/lang/String;", &[])
                .and_then(|v| v.l())
                .and_then(|o| env.get_string(&JString::from(o)).map(String::from))
                .unwrap_or_default();
            bail!(std::io::Error::new(
                if message.contains("SecurityException") {
                    std::io::ErrorKind::PermissionDenied
                } else {
                    std::io::ErrorKind::Other
                },
                message,
            ));
        }
        Ok(result?)
    }

    fn string(env: &mut JNIEnv, value: JObject) -> jni::errors::Result<String> {
        Ok(env.get_string(&JString::from(value))?.into())
    }

    pub fn default_dir() -> PathBuf {
        PathBuf::from("Music/Kanade")
    }

    pub fn save(src: &Path, name: &str, mime: &str, _overwrite: bool) -> Result<String> {
        call(|env, class| {
            let src = env.new_string(src.to_string_lossy())?;
            let name = env.new_string(name)?;
            let mime = env.new_string(mime)?;
            let uri = env
                .call_static_method(
                    class,
                    "save",
                    "(Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;)Ljava/lang/String;",
                    &[JValue::Object(&src), JValue::Object(&name), JValue::Object(&mime)],
                )?
                .l()?;
            string(env, uri)
        })
    }

    pub fn lrc_name(_file: &str, stem: &str) -> String {
        format!("{stem}.lrc")
    }

    pub fn delete(file: &str) {
        let _ = call(|env, class| {
            let file = env.new_string(file)?;
            env.call_static_method(
                class,
                "delete",
                "(Ljava/lang/String;)V",
                &[JValue::Object(&file)],
            )?;
            Ok(())
        });
    }

    pub fn exists(file: &str) -> bool {
        call(|env, class| {
            let file = env.new_string(file)?;
            env.call_static_method(
                class,
                "exists",
                "(Ljava/lang/String;)Z",
                &[JValue::Object(&file)],
            )?
            .z()
        })
        .unwrap_or(false)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::api::types::{LyricLine, Singer};

    fn song() -> Song {
        Song {
            id: 7,
            mid: "m1".into(),
            name: "A/B?".into(),
            singers: vec![
                Singer { mid: "s1".into(), name: "X".into() },
                Singer { mid: "s2".into(), name: "Y".into() },
            ],
            album_mid: "al".into(),
            album_name: "Album".into(),
            duration_secs: 200,
            media_mid: "mm".into(),
            cover_url: parse::album_cover("al"),
            vip: true,
            has_hq: true,
            has_flac: false,
            mv_vid: "v".into(),
        }
    }

    #[test]
    fn song_round_trips_through_record_json() {
        let s = song();
        let back = parse::song(&song_json(&s)).unwrap();
        assert_eq!(
            (back.id, back.mid, back.name, back.media_mid, back.cover_url),
            (s.id, s.mid, s.name, s.media_mid, s.cover_url)
        );
        assert_eq!(back.singers.len(), 2);
        assert!(back.vip && back.has_hq && !back.has_flac);
        assert_eq!(back.mv_vid, "v");
    }

    #[test]
    fn stems_and_lrc() {
        assert_eq!(file_stem(&song()), "X, Y - A_B_");
        let lyric = Lyric {
            lines: vec![LyricLine {
                time_ms: 61_230,
                text: "hello".into(),
                trans: "你好".into(),
                roma: String::new(),
                words: vec![],
            }],
            plain: String::new(),
        };
        let text = lrc_text(&lyric, &song()).unwrap();
        assert!(text.ends_with("[01:01.23]hello\n[01:01.23]你好\n"));
    }

    #[test]
    fn errors_round_trip() {
        let e = anyhow::Error::new(ApiError::NoPlayableUrl).context("outer");
        assert!(matches!(decode_error(&encode_error(&e)), ApiError::NoPlayableUrl));
        let io = anyhow::Error::new(std::io::Error::from(std::io::ErrorKind::PermissionDenied));
        assert!(encode_error(&io).starts_with("storage:"));
    }
}
