//! 歌词接口 `crypt:1` 时返回的密文：十六进制 → QQ 音乐改过的 3DES（ECB）→ zlib。
//! DES 照 Brad Conte 的公有领域实现写，保留 QQ 的三处不同：S 盒里有两个数不一样，
//! 取位时按小端 32 位字排，密钥每轮移位后只留高 28 位。照标准 DES 解不开。

use std::io::Read;

use anyhow::{bail, Context, Result};

const KEY: &[u8; 24] = b"!@#)(*$%123ZXC!@!@#)(NHL";

#[rustfmt::skip]
const SBOX: [[u8; 64]; 8] = [
    [14, 4, 13, 1, 2, 15, 11, 8, 3, 10, 6, 12, 5, 9, 0, 7,
     0, 15, 7, 4, 14, 2, 13, 1, 10, 6, 12, 11, 9, 5, 3, 8,
     4, 1, 14, 8, 13, 6, 2, 11, 15, 12, 9, 7, 3, 10, 5, 0,
     15, 12, 8, 2, 4, 9, 1, 7, 5, 11, 3, 14, 10, 0, 6, 13],
    [15, 1, 8, 14, 6, 11, 3, 4, 9, 7, 2, 13, 12, 0, 5, 10,
     3, 13, 4, 7, 15, 2, 8, 15, 12, 0, 1, 10, 6, 9, 11, 5,
     0, 14, 7, 11, 10, 4, 13, 1, 5, 8, 12, 6, 9, 3, 2, 15,
     13, 8, 10, 1, 3, 15, 4, 2, 11, 6, 7, 12, 0, 5, 14, 9],
    [10, 0, 9, 14, 6, 3, 15, 5, 1, 13, 12, 7, 11, 4, 2, 8,
     13, 7, 0, 9, 3, 4, 6, 10, 2, 8, 5, 14, 12, 11, 15, 1,
     13, 6, 4, 9, 8, 15, 3, 0, 11, 1, 2, 12, 5, 10, 14, 7,
     1, 10, 13, 0, 6, 9, 8, 7, 4, 15, 14, 3, 11, 5, 2, 12],
    [7, 13, 14, 3, 0, 6, 9, 10, 1, 2, 8, 5, 11, 12, 4, 15,
     13, 8, 11, 5, 6, 15, 0, 3, 4, 7, 2, 12, 1, 10, 14, 9,
     10, 6, 9, 0, 12, 11, 7, 13, 15, 1, 3, 14, 5, 2, 8, 4,
     3, 15, 0, 6, 10, 10, 13, 8, 9, 4, 5, 11, 12, 7, 2, 14],
    [2, 12, 4, 1, 7, 10, 11, 6, 8, 5, 3, 15, 13, 0, 14, 9,
     14, 11, 2, 12, 4, 7, 13, 1, 5, 0, 15, 10, 3, 9, 8, 6,
     4, 2, 1, 11, 10, 13, 7, 8, 15, 9, 12, 5, 6, 3, 0, 14,
     11, 8, 12, 7, 1, 14, 2, 13, 6, 15, 0, 9, 10, 4, 5, 3],
    [12, 1, 10, 15, 9, 2, 6, 8, 0, 13, 3, 4, 14, 7, 5, 11,
     10, 15, 4, 2, 7, 12, 9, 5, 6, 1, 13, 14, 0, 11, 3, 8,
     9, 14, 15, 5, 2, 8, 12, 3, 7, 0, 4, 10, 1, 13, 11, 6,
     4, 3, 2, 12, 9, 5, 15, 10, 11, 14, 1, 7, 6, 0, 8, 13],
    [4, 11, 2, 14, 15, 0, 8, 13, 3, 12, 9, 7, 5, 10, 6, 1,
     13, 0, 11, 7, 4, 9, 1, 10, 14, 3, 5, 12, 2, 15, 8, 6,
     1, 4, 11, 13, 12, 3, 7, 14, 10, 15, 6, 8, 0, 5, 9, 2,
     6, 11, 13, 8, 1, 4, 10, 7, 9, 5, 0, 15, 14, 2, 3, 12],
    [13, 2, 8, 4, 6, 15, 11, 1, 10, 9, 3, 14, 5, 0, 12, 7,
     1, 15, 13, 8, 10, 3, 7, 4, 12, 5, 6, 11, 0, 14, 9, 2,
     7, 11, 4, 1, 9, 12, 14, 2, 0, 6, 10, 13, 15, 3, 5, 8,
     2, 1, 14, 7, 4, 10, 8, 13, 15, 12, 9, 0, 3, 5, 6, 11],
];

/// 标准 DES 的 P 置换（从 0 数）。
const P: [u32; 32] = [
    15, 6, 19, 20, 28, 11, 27, 16, 0, 14, 22, 25, 4, 17, 30, 9, 1, 7, 23, 13, 31, 26, 2, 8, 18, 12,
    29, 5, 21, 10, 3, 24,
];

/// 第 b 位：按 32 位字小端存放来数。
fn bitnum(a: &[u8], b: u32, c: u32) -> u32 {
    (((a[((b / 32) * 4 + 3 - (b % 32) / 8) as usize] >> (7 - b % 8)) & 1) as u32) << c
}

fn bitnum_intr(a: u32, b: u32, c: u32) -> u32 {
    ((a >> (31 - b)) & 1) << c
}

fn bitnum_intl(a: u32, b: u32, c: u32) -> u32 {
    ((a << b) & 0x8000_0000) >> c
}

fn sbox_bit(a: u8) -> usize {
    ((a & 32) | ((a & 31) >> 1) | ((a & 1) << 4)) as usize
}

fn initial_permutation(input: &[u8]) -> (u32, u32) {
    let half = |starts: [u32; 4]| {
        let mut s = 0;
        for (k, start) in starts.into_iter().enumerate() {
            for m in 0..8 {
                s |= bitnum(input, start - 8 * m, 31 - (k as u32 * 8 + m));
            }
        }
        s
    };
    (half([57, 59, 61, 63]), half([56, 58, 60, 62]))
}

fn inverse_permutation(s0: u32, s1: u32) -> [u8; 8] {
    let mut out = [0u8; 8];
    // 写回时也按小端字排
    for (i, at) in [3, 2, 1, 0, 7, 6, 5, 4].into_iter().enumerate() {
        let r = 7 - i as u32;
        out[at] = (bitnum_intr(s1, r, 7)
            | bitnum_intr(s0, r, 6)
            | bitnum_intr(s1, r + 8, 5)
            | bitnum_intr(s0, r + 8, 4)
            | bitnum_intr(s1, r + 16, 3)
            | bitnum_intr(s0, r + 16, 2)
            | bitnum_intr(s1, r + 24, 1)
            | bitnum_intr(s0, r + 24, 0)) as u8;
    }
    out
}

fn f(state: u32, key: &[u8; 6]) -> u32 {
    let t1 = bitnum_intl(state, 31, 0)
        | ((state & 0xf000_0000) >> 1)
        | bitnum_intl(state, 4, 5)
        | bitnum_intl(state, 3, 6)
        | ((state & 0x0f00_0000) >> 3)
        | bitnum_intl(state, 8, 11)
        | bitnum_intl(state, 7, 12)
        | ((state & 0x00f0_0000) >> 5)
        | bitnum_intl(state, 12, 17)
        | bitnum_intl(state, 11, 18)
        | ((state & 0x000f_0000) >> 7)
        | bitnum_intl(state, 16, 23);
    let t2 = bitnum_intl(state, 15, 0)
        | ((state & 0x0000_f000) << 15)
        | bitnum_intl(state, 20, 5)
        | bitnum_intl(state, 19, 6)
        | ((state & 0x0000_0f00) << 13)
        | bitnum_intl(state, 24, 11)
        | bitnum_intl(state, 23, 12)
        | ((state & 0x0000_00f0) << 11)
        | bitnum_intl(state, 28, 17)
        | bitnum_intl(state, 27, 18)
        | ((state & 0x0000_000f) << 9)
        | bitnum_intl(state, 0, 23);
    let mut l = [
        (t1 >> 24) as u8,
        (t1 >> 16) as u8,
        (t1 >> 8) as u8,
        (t2 >> 24) as u8,
        (t2 >> 16) as u8,
        (t2 >> 8) as u8,
    ];
    for (b, k) in l.iter_mut().zip(key) {
        *b ^= k;
    }
    let s = |i: usize, v: u8| SBOX[i][sbox_bit(v)] as u32;
    let state = (s(0, l[0] >> 2) << 28)
        | (s(1, ((l[0] & 0x03) << 4) | (l[1] >> 4)) << 24)
        | (s(2, ((l[1] & 0x0f) << 2) | (l[2] >> 6)) << 20)
        | (s(3, l[2] & 0x3f) << 16)
        | (s(4, l[3] >> 2) << 12)
        | (s(5, ((l[3] & 0x03) << 4) | (l[4] >> 4)) << 8)
        | (s(6, ((l[4] & 0x0f) << 2) | (l[5] >> 6)) << 4)
        | s(7, l[5] & 0x3f);
    P.iter()
        .enumerate()
        .fold(0, |acc, (c, &b)| acc | bitnum_intl(state, b, c as u32))
}

type Schedule = [[u8; 6]; 16];

fn crypt(input: &[u8], key: &Schedule) -> [u8; 8] {
    let (mut s0, mut s1) = initial_permutation(input);
    for k in &key[..15] {
        let prev = s1;
        s1 = f(s1, k) ^ s0;
        s0 = prev;
    }
    s0 ^= f(s1, &key[15]);
    inverse_permutation(s0, s1)
}

fn key_schedule(key: &[u8], decrypt: bool) -> Schedule {
    const SHIFT: [u32; 16] = [1, 1, 2, 2, 2, 2, 2, 2, 1, 2, 2, 2, 2, 2, 2, 1];
    const PERM_C: [u32; 28] = [
        56, 48, 40, 32, 24, 16, 8, 0, 57, 49, 41, 33, 25, 17, 9, 1, 58, 50, 42, 34, 26, 18, 10, 2,
        59, 51, 43, 35,
    ];
    const PERM_D: [u32; 28] = [
        62, 54, 46, 38, 30, 22, 14, 6, 61, 53, 45, 37, 29, 21, 13, 5, 60, 52, 44, 36, 28, 20, 12,
        4, 27, 19, 11, 3,
    ];
    const COMPRESSION: [u32; 48] = [
        13, 16, 10, 23, 0, 4, 2, 27, 14, 5, 20, 9, 22, 18, 11, 3, 25, 7, 15, 6, 26, 19, 12, 1, 40,
        51, 30, 36, 46, 54, 29, 39, 50, 44, 32, 47, 43, 48, 38, 55, 33, 52, 45, 41, 49, 35, 28, 31,
    ];
    let mut c = (0..28).fold(0, |acc, i| acc | bitnum(key, PERM_C[i], 31 - i as u32));
    let mut d = (0..28).fold(0, |acc, i| acc | bitnum(key, PERM_D[i], 31 - i as u32));
    let mut out = [[0u8; 6]; 16];
    for (i, &s) in SHIFT.iter().enumerate() {
        c = ((c << s) | (c >> (28 - s))) & 0xffff_fff0;
        d = ((d << s) | (d >> (28 - s))) & 0xffff_fff0;
        let round = &mut out[if decrypt { 15 - i } else { i }];
        for (j, &bit) in COMPRESSION.iter().enumerate() {
            let (half, bit) = if j < 24 { (c, bit) } else { (d, bit - 27) };
            round[j / 8] |= bitnum_intr(half, bit, 7 - (j % 8) as u32) as u8;
        }
    }
    out
}

/// 解出原文（QRC 的 XML，或者普通 LRC）。空串原样返回。
pub fn decrypt(hex: &str) -> Result<String> {
    let hex = hex.trim();
    if hex.is_empty() {
        return Ok(String::new());
    }
    if !hex.len().is_multiple_of(16) || !hex.bytes().all(|b| b.is_ascii_hexdigit()) {
        bail!("歌词密文格式不对");
    }
    let bytes: Vec<u8> = (0..hex.len())
        .step_by(2)
        .map(|i| u8::from_str_radix(&hex[i..i + 2], 16).unwrap())
        .collect();
    let keys = [
        key_schedule(&KEY[16..], true),
        key_schedule(&KEY[8..], false),
        key_schedule(&KEY[..8], true),
    ];
    let mut plain = Vec::with_capacity(bytes.len());
    for block in bytes.as_chunks::<8>().0 {
        let mut b = *block;
        for k in &keys {
            b = crypt(&b, k);
        }
        plain.extend_from_slice(&b);
    }
    let mut text = String::new();
    flate2::read::ZlibDecoder::new(&plain[..])
        .read_to_string(&mut text)
        .context("歌词解密失败")?;
    Ok(text)
}
