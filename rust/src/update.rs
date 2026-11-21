//! 软件更新：读发布流程生成的版本清单，下载安装文件并核对 SHA-256。
//! 清单在仓库的 update-manifest 分支，安装文件在 GitHub 发布页。
//! 打开镜像时两样都改从镜像取，不连 GitHub：镜像只转发文件下载，不转发 GitHub API，所以版本信息也做成文件。
//! 清单带发布流程的 Ed25519 签名，验过签校验码才可信，镜像换不了安装文件。

use std::path::Path;
use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::OnceLock;
use std::time::Duration;

use anyhow::{bail, Context, Result};
use base64::Engine;
use ring::{digest, signature};
use serde::Deserialize;
use tokio::io::AsyncWriteExt;

use crate::api::error::ApiError;
use crate::api::types::{UpdateAsset, UpdateEvent, UpdateInfo};

const REPO: &str = "LuckyLxi/kanade";
const MANIFEST_BRANCH: &str = "update-manifest";
/// 按顺序尝试，前一个连不上或出错就换下一个。
const MIRRORS: &[&str] = &["https://ghfast.top/", "https://gh-proxy.com/"];
/// 验清单签名的公钥，私钥在仓库的 UPDATE_SIGNING_KEY secret 里。
const MANIFEST_KEY: &str = "1zs5jl3XtnuSsU/pCMmlUtg4qvVzRuMGA4HKpIXJVhg=";

/// 每次下载加一；正在下载的发现它变了就停下。
static GENERATION: AtomicU64 = AtomicU64::new(0);

#[derive(Deserialize)]
struct Manifest {
    tag: String,
    prerelease: bool,
    date: String,
    notes: String,
    assets: Vec<ManifestAsset>,
}

#[derive(Deserialize)]
struct ManifestAsset {
    name: String,
    size: i64,
    sha256: String,
}

fn http() -> &'static reqwest::Client {
    static HTTP: OnceLock<reqwest::Client> = OnceLock::new();
    HTTP.get_or_init(|| {
        reqwest::Client::builder()
            .user_agent(concat!("kanade-updater/", env!("CARGO_PKG_VERSION")))
            .connect_timeout(Duration::from_secs(10))
            .read_timeout(Duration::from_secs(30))
            .build()
            .expect("reqwest client")
    })
}

/// 要尝试的地址前缀和显示给用户的来源名。
fn sources(mirror: bool) -> Vec<(&'static str, &'static str)> {
    if mirror {
        MIRRORS.iter().map(|m| (*m, m.trim_start_matches("https://").trim_end_matches('/'))).collect()
    } else {
        vec![("", "GitHub")]
    }
}

/// 读最新版本的清单。`preview` 时包含预览版。
pub async fn latest(preview: bool, mirror: bool) -> Result<UpdateInfo> {
    let channel = if preview { "preview" } else { "stable" };
    let url = format!("https://raw.githubusercontent.com/{REPO}/{MANIFEST_BRANCH}/{channel}.json");
    let mut last = None;
    for (prefix, _) in sources(mirror) {
        match fetch_manifest(&format!("{prefix}{url}"), preview).await {
            Ok(m) => return Ok(m),
            Err(e) => last = Some(e),
        }
    }
    Err(last.unwrap())
}

/// 原样的字节：`.text()` 会按响应头的编码转码、去掉 BOM，验签就对不上了。
async fn fetch_bytes(url: &str) -> Result<Vec<u8>> {
    Ok(http()
        .get(url)
        .timeout(Duration::from_secs(15))
        .send()
        .await?
        .error_for_status()?
        .bytes()
        .await?
        .to_vec())
}

async fn fetch_manifest(url: &str, preview: bool) -> Result<UpdateInfo> {
    let text = fetch_bytes(url).await?;
    let sig = fetch_bytes(&format!("{url}.sig")).await?;
    let sig = std::str::from_utf8(&sig).map_err(|_| bad("bad signature encoding"))?;
    verify_manifest(&text, sig.trim())?;
    let m: Manifest = serde_json::from_slice(&text)?;
    // 签名不分渠道，正式版渠道拿到预览版清单就是被换了
    if !preview && m.prerelease {
        bail!(bad("stable manifest is a prerelease"));
    }
    // 文件名会拼进下载地址和本地路径
    if let Some(a) = m.assets.iter().find(|a| !safe_name(&a.name)) {
        bail!(bad(&format!("unsafe asset name {:?}", a.name)));
    }
    Ok(UpdateInfo {
        tag: m.tag,
        prerelease: m.prerelease,
        date: m.date,
        notes: m.notes,
        assets: m
            .assets
            .into_iter()
            .map(|a| UpdateAsset { name: a.name, size: a.size, sha256: a.sha256.to_ascii_lowercase() })
            .collect(),
    })
}

/// 停下正在进行的下载。
pub fn cancel() {
    GENERATION.fetch_add(1, Ordering::SeqCst);
}

/// 把 `tag` 发布里的 `asset` 下载到 `dest`，进度和结果从 `emit` 推出去。
pub async fn download(tag: &str, asset: &UpdateAsset, dest: &Path, mirror: bool, emit: impl Fn(UpdateEvent)) {
    let generation = GENERATION.fetch_add(1, Ordering::SeqCst) + 1;
    let url = format!("https://github.com/{REPO}/releases/download/{tag}/{}", asset.name);
    // 一个来源出错或给的文件不对，就换下一个；都不行时报最后一个的结果
    let mut last = UpdateEvent::Cancelled;
    for (prefix, name) in sources(mirror) {
        last = match fetch_file(&format!("{prefix}{url}"), name, asset, dest, generation, &emit).await {
            Ok(UpdateEvent::Done) => return emit(UpdateEvent::Done),
            Ok(event) => event,
            Err(e) => UpdateEvent::Failed { error: ApiError::from(e) },
        };
        if GENERATION.load(Ordering::SeqCst) != generation {
            last = UpdateEvent::Cancelled;
            break;
        }
    }
    let _ = tokio::fs::remove_file(dest).await;
    emit(last);
}

/// 下载一个来源。连不上、中途断开返回 Err（换下一个来源）；下完了返回结束事件。
async fn fetch_file(
    url: &str,
    source: &str,
    asset: &UpdateAsset,
    dest: &Path,
    generation: u64,
    emit: &impl Fn(UpdateEvent),
) -> Result<UpdateEvent> {
    let mut res = http().get(url).send().await?.error_for_status()?;
    // 镜像出错时有的返回 200 加一段说明文字，按大小先挡掉
    if res.content_length().is_some_and(|len| len != asset.size as u64) {
        bail!("{source} returned {} bytes, expected {}", res.content_length().unwrap(), asset.size);
    }
    emit(UpdateEvent::Connected { source: source.to_string() });
    if let Some(dir) = dest.parent() {
        tokio::fs::create_dir_all(dir).await?;
    }
    let mut file = tokio::fs::File::create(dest).await.context("create update file")?;
    let mut hash = digest::Context::new(&digest::SHA256);
    let mut received = 0u64;
    let mut reported = 0u64;
    while let Some(chunk) = res.chunk().await? {
        if GENERATION.load(Ordering::SeqCst) != generation {
            return Ok(UpdateEvent::Cancelled);
        }
        file.write_all(&chunk).await?;
        hash.update(&chunk);
        received += chunk.len() as u64;
        // 每 256 KB 报一次，免得消息太密
        if received - reported >= 256 * 1024 || received == asset.size as u64 {
            reported = received;
            emit(UpdateEvent::Progress { received: received as i64, total: asset.size });
        }
    }
    file.flush().await?;
    drop(file);
    if received != asset.size as u64 {
        bail!("{source} closed after {received} of {} bytes", asset.size);
    }
    let actual: String = hash.finish().as_ref().iter().map(|b| format!("{b:02x}")).collect();
    Ok(if actual == asset.sha256 { UpdateEvent::Done } else { UpdateEvent::Corrupted })
}

fn bad(detail: &str) -> ApiError {
    ApiError::BadResponse { detail: format!("update manifest: {detail}") }
}

fn verify_manifest(text: &[u8], sig: &str) -> Result<()> {
    let engine = base64::engine::general_purpose::STANDARD;
    let key = engine.decode(MANIFEST_KEY).expect("manifest key");
    let sig = engine.decode(sig).map_err(|_| bad("bad signature encoding"))?;
    signature::UnparsedPublicKey::new(&signature::ED25519, key)
        .verify(text, &sig)
        .map_err(|_| bad("signature mismatch"))?;
    Ok(())
}

fn safe_name(name: &str) -> bool {
    !name.is_empty()
        && !name.starts_with('.')
        && name.bytes().all(|b| b.is_ascii_alphanumeric() || b"._-".contains(&b))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn rejects_unsafe_names() {
        assert!(safe_name("kanade-v1.2.0-windows-x64-setup.exe"));
        assert!(!safe_name(r"..\evil.exe"));
        assert!(!safe_name("../evil.apk"));
        assert!(!safe_name(".."));
        assert!(!safe_name(""));
    }

    #[test]
    fn rejects_bad_signature() {
        let sig = "1dVdKHxLBrWYBXtwAtxBHXqztDmw+cJliYv8HSZ0zFJE65ICFCCO0RX75c9bIrKYuwG2I5/hkeMU2wdJWapFCA==";
        assert!(verify_manifest(b"{\"a\":1}\n", sig).is_ok());
        assert!(verify_manifest(b"{\"a\":2}\n", sig).is_err());
    }
}
