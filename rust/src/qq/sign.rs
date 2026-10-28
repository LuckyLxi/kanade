//! musics.fcg 请求签名与 ag-1 编码。
//! 协议来源：jixunmoe/qmweb-sign（MIT），参见 rust/THIRD_PARTY_NOTICES.md。

use anyhow::{Context, Result};
use base64::Engine;
use rand::RngCore;
use ring::aead::{Aad, LessSafeKey, Nonce, UnboundKey, AES_128_GCM};
use serde_json::Value;
use sha1::{Digest, Sha1};

use super::error::ApiError;

const REQUEST_KEY: [u8; 16] = [189, 48, 95, 16, 208, 255, 116, 182, 239, 84, 218, 184, 53, 181, 225, 207];
const RESPONSE_KEY: [u8; 21] = [122, 63, 140, 29, 94, 155, 47, 10, 108, 77, 126, 139, 31, 58, 92, 157, 14, 43, 111, 74, 129];

pub fn encrypt_ag1(body: &str) -> Result<String> {
    let mut nonce = [0; 12];
    rand::rngs::OsRng.try_fill_bytes(&mut nonce).context("failed to generate ag-1 nonce")?;
    encrypt_ag1_with_nonce(body, nonce)
}

fn encrypt_ag1_with_nonce(body: &str, nonce: [u8; 12]) -> Result<String> {
    let key = UnboundKey::new(&AES_128_GCM, &REQUEST_KEY)
        .map_err(|_| ApiError::bad_response("failed to initialize ag-1 encryption"))?;
    let mut ciphertext = body.as_bytes().to_vec();
    LessSafeKey::new(key).seal_in_place_append_tag(Nonce::assume_unique_for_key(nonce), Aad::empty(), &mut ciphertext)
        .map_err(|_| ApiError::bad_response("failed to encrypt ag-1 request"))?;
    let mut packet = nonce.to_vec();
    packet.extend(ciphertext);
    Ok(base64::engine::general_purpose::STANDARD.encode(packet))
}

pub fn decode_ag1(bytes: &[u8]) -> Result<Value> {
    let decoded: Vec<_> = bytes.iter().enumerate().map(|(index, byte)| byte ^ RESPONSE_KEY[index % RESPONSE_KEY.len()]).collect();
    // 官网 TextDecoder 使用替换字符处理文本字段中的非法 UTF-8；JSON 结构及业务码仍严格检查。
    serde_json::from_str(&String::from_utf8_lossy(&decoded)).context(ApiError::bad_response("failed to parse ag-1 response"))
}

const PART_1_INDEXES: [usize; 8] = [23, 14, 6, 36, 16, 40, 7, 19];
const PART_2_INDEXES: [usize; 8] = [16, 1, 32, 12, 19, 27, 8, 5];
const SCRAMBLE_VALUES: [u8; 20] = [
    89, 39, 179, 150, 218, 82, 58, 252, 177, 52, 186, 123, 120, 64, 242, 133, 143, 161, 121, 179,
];

pub fn sign(body: &str) -> String {
    let hash: Vec<u8> = Sha1::digest(body.as_bytes())
        .iter()
        .flat_map(|b| format!("{b:02X}").into_bytes())
        .collect();

    // 下标 40 越界，网页端的实现会跳过它
    let part1: String = PART_1_INDEXES
        .iter()
        .filter(|&&i| i < hash.len())
        .map(|&i| hash[i] as char)
        .collect();
    let part2: String = PART_2_INDEXES.iter().map(|&i| hash[i] as char).collect();

    let part3: Vec<u8> = SCRAMBLE_VALUES
        .iter()
        .enumerate()
        .map(|(i, v)| {
            let hex = std::str::from_utf8(&hash[i * 2..i * 2 + 2]).unwrap();
            v ^ u8::from_str_radix(hex, 16).unwrap()
        })
        .collect();
    let b64: String = base64::engine::general_purpose::STANDARD
        .encode(part3)
        .chars()
        .filter(|c| !matches!(c, '/' | '\\' | '+' | '='))
        .collect();

    format!("zzc{part1}{b64}{part2}").to_lowercase()
}

/// ptlogin 的 hash33，用于 ptqrtoken（init = 0）和 g_tk（init = 5381）。
pub fn hash33(s: &str, init: i64) -> i64 {
    let mut h = init;
    for c in s.chars() {
        h = h.wrapping_add((h << 5).wrapping_add(c as i64));
    }
    h & 0x7fff_ffff
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn sign_shape() {
        let s = sign(r#"{"comm":{"ct":11}}"#);
        assert!(s.starts_with("zzc"));
        assert!(s.len() > 30);
    }

    #[test]
    fn ag1_matches_node_aes_gcm_vector() {
        let body = r#"{"comm":{"ct":24},"req_0":{"module":"m","method":"x","param":{}}}"#;
        let nonce = std::array::from_fn(|index| index as u8);
        assert_eq!(encrypt_ag1_with_nonce(body, nonce).unwrap(),
            "AAECAwQFBgcICQoLKpKtOA1Q5TspuJH/gb3nZVwXzQga/hCR0PTb/ET7i0zcAotpHJA3J0D+qQpzu6rgdY5FKSJwcv1flCU4BSlFhJIAZ6YWlh2qvwcoTSQTJRKU");
    }

    #[test]
    fn ag1_decodes_codes_even_with_invalid_utf8_in_text() {
        let source = b"{\"code\":0,\"req_0\":{\"code\":80105,\"data\":{\"retCode\":0,\"msg\":\"\xff\"}}}";
        let encoded: Vec<_> = source.iter().enumerate().map(|(i, byte)| byte ^ RESPONSE_KEY[i % RESPONSE_KEY.len()]).collect();
        let decoded = decode_ag1(&encoded).unwrap();
        assert_eq!(decoded["req_0"]["code"], 80105);
        assert_eq!(decoded["req_0"]["data"]["msg"], "\u{fffd}");
        assert!(decode_ag1(b"invalid response").is_err());
    }
}
