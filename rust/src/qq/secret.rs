//! 登录凭证写进数据库前的加密。
//!
//! Windows 用 DPAPI，密文只有同一个 Windows 用户能解开；Android 用 Kotlin 从
//! Keystore 派生、启动时传进来的密钥做 AES-256-GCM（`SessionKey.kt`）。
//! 数据库文件被复制到别的用户或设备上时，凭证解不开，相当于未登录。

use anyhow::Result;
use base64::{engine::general_purpose::STANDARD, Engine};

const PREFIX: &str = "enc1:";

/// 是否已经是加密后的格式；旧版本写的是明文 JSON。
pub fn is_sealed(stored: &str) -> bool {
    stored.starts_with(PREFIX)
}

pub fn seal(plain: &str) -> Result<String> {
    Ok(format!(
        "{PREFIX}{}",
        STANDARD.encode(platform::protect(plain.as_bytes())?)
    ))
}

/// 解出明文；旧版本的明文原样返回。
pub fn open(stored: &str) -> Result<String> {
    let Some(data) = stored.strip_prefix(PREFIX) else {
        return Ok(stored.to_owned());
    };
    Ok(String::from_utf8(platform::unprotect(
        &STANDARD.decode(data)?,
    )?)?)
}

#[cfg(windows)]
mod platform {
    use std::{ptr, slice};

    use anyhow::{bail, Result};
    use windows_sys::Win32::Foundation::LocalFree;
    use windows_sys::Win32::Security::Cryptography::{
        CryptProtectData, CryptUnprotectData, CRYPTPROTECT_UI_FORBIDDEN, CRYPT_INTEGER_BLOB,
    };

    pub fn protect(data: &[u8]) -> Result<Vec<u8>> {
        let (input, mut out) = blobs(data);
        let ok = unsafe {
            CryptProtectData(
                &input,
                ptr::null(),
                ptr::null(),
                ptr::null(),
                ptr::null(),
                CRYPTPROTECT_UI_FORBIDDEN,
                &mut out,
            )
        };
        take(ok, out)
    }

    pub fn unprotect(data: &[u8]) -> Result<Vec<u8>> {
        let (input, mut out) = blobs(data);
        let ok = unsafe {
            CryptUnprotectData(
                &input,
                ptr::null_mut(),
                ptr::null(),
                ptr::null(),
                ptr::null(),
                CRYPTPROTECT_UI_FORBIDDEN,
                &mut out,
            )
        };
        take(ok, out)
    }

    fn blobs(data: &[u8]) -> (CRYPT_INTEGER_BLOB, CRYPT_INTEGER_BLOB) {
        (
            CRYPT_INTEGER_BLOB {
                cbData: data.len() as u32,
                pbData: data.as_ptr() as *mut u8,
            },
            CRYPT_INTEGER_BLOB {
                cbData: 0,
                pbData: ptr::null_mut(),
            },
        )
    }

    fn take(ok: i32, out: CRYPT_INTEGER_BLOB) -> Result<Vec<u8>> {
        if ok == 0 {
            bail!("DPAPI failed: {}", std::io::Error::last_os_error());
        }
        let result = unsafe { slice::from_raw_parts(out.pbData, out.cbData as usize) }.to_vec();
        unsafe { LocalFree(out.pbData.cast()) };
        Ok(result)
    }
}

#[cfg(target_os = "android")]
mod platform {
    use std::sync::OnceLock;

    use anyhow::{bail, Context, Result};
    use jni::objects::{JByteArray, JClass};
    use jni::JNIEnv;
    use ring::aead::{Aad, LessSafeKey, Nonce, UnboundKey, AES_256_GCM, NONCE_LEN};
    use ring::rand::{SecureRandom, SystemRandom};

    static KEY: OnceLock<LessSafeKey> = OnceLock::new();

    /// `SessionKey.install` 在每个进程的 `Application.onCreate` 里调用，早于 Flutter 引擎启动。
    #[no_mangle]
    pub extern "system" fn Java_com_lxi_kanade_SessionKey_nativeSetKey(
        env: JNIEnv,
        _class: JClass,
        key: JByteArray,
    ) {
        let Ok(bytes) = env.convert_byte_array(&key) else {
            return;
        };
        if let Ok(key) = UnboundKey::new(&AES_256_GCM, &bytes) {
            let _ = KEY.set(LessSafeKey::new(key));
        }
    }

    fn key() -> Result<&'static LessSafeKey> {
        KEY.get().context("session key unavailable")
    }

    pub fn protect(data: &[u8]) -> Result<Vec<u8>> {
        let key = key()?;
        let mut nonce = [0u8; NONCE_LEN];
        if SystemRandom::new().fill(&mut nonce).is_err() {
            bail!("random nonce failed");
        }
        let mut sealed = data.to_vec();
        if key
            .seal_in_place_append_tag(
                Nonce::assume_unique_for_key(nonce),
                Aad::empty(),
                &mut sealed,
            )
            .is_err()
        {
            bail!("session encrypt failed");
        }
        Ok([nonce.as_slice(), &sealed].concat())
    }

    pub fn unprotect(data: &[u8]) -> Result<Vec<u8>> {
        let key = key()?;
        if data.len() < NONCE_LEN {
            bail!("session ciphertext too short");
        }
        let (nonce, sealed) = data.split_at(NONCE_LEN);
        let nonce = Nonce::try_assume_unique_for_key(nonce).unwrap();
        let mut sealed = sealed.to_vec();
        let Ok(plain) = key.open_in_place(nonce, Aad::empty(), &mut sealed) else {
            bail!("session decrypt failed");
        };
        Ok(plain.to_vec())
    }
}

/// App 只发布 Windows 和 Android；其他系统上只用于跑测试，不加密。
#[cfg(not(any(windows, target_os = "android")))]
mod platform {
    use anyhow::Result;

    pub fn protect(data: &[u8]) -> Result<Vec<u8>> {
        Ok(data.to_vec())
    }

    pub fn unprotect(data: &[u8]) -> Result<Vec<u8>> {
        Ok(data.to_vec())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn sealed_round_trip_and_legacy_plaintext() {
        let plain = r#"{"uin":"1","musickey":"k","login_type":2}"#;
        let sealed = seal(plain).unwrap();
        assert!(is_sealed(&sealed));
        assert!(!sealed.contains("musickey"));
        assert_eq!(open(&sealed).unwrap(), plain);
        assert!(!is_sealed(plain));
        assert_eq!(open(plain).unwrap(), plain);
    }
}
