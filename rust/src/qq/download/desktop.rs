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

pub fn list() -> Result<Vec<super::Entry>> {
    let Ok(dir) = std::fs::read_dir(super::dir()) else {
        return Ok(Vec::new());
    };
    Ok(dir
        .flatten()
        .filter_map(|e| {
            let meta = e.metadata().ok().filter(|m| m.is_file())?;
            Some(super::Entry {
                file: e.path().to_string_lossy().into_owned(),
                name: e.file_name().to_string_lossy().into_owned(),
                size: meta.len(),
                alias: None,
            })
        })
        .collect())
}

pub fn open(file: &str) -> Result<std::fs::File> {
    Ok(std::fs::File::open(file)?)
}

pub fn notify(_done: u32, _total: u32) {}
