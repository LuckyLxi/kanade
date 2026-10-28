//! LRC 解析，并把翻译按时间轴合并到原文上。

use std::collections::HashMap;

use crate::api::types::{Lyric, LyricLine};

/// 解析一行开头的所有 `[mm:ss.xx]` 时间标签，返回 (时间列表, 剩余文本)。
fn parse_line(line: &str) -> (Vec<u32>, &str) {
    let mut times = Vec::new();
    let mut rest = line.trim();
    while let Some(stripped) = rest.strip_prefix('[') {
        let Some(end) = stripped.find(']') else { break };
        match parse_time(&stripped[..end]) {
            Some(t) => times.push(t),
            // [ti:xxx] 这类元信息标签：整行丢弃
            None => return (Vec::new(), ""),
        }
        rest = &stripped[end + 1..];
    }
    (times, rest.trim())
}

fn parse_time(tag: &str) -> Option<u32> {
    let (m, rest) = tag.split_once(':')?;
    let m: u32 = m.trim().parse().ok()?;
    let (sec, frac) = rest.split_once(['.', ':']).unwrap_or((rest, "0"));
    let sec: u32 = sec.trim().parse().ok()?;
    let frac = frac.trim();
    let ms: u32 = match frac.len() {
        0 => 0,
        1 => frac.parse::<u32>().ok()? * 100,
        2 => frac.parse::<u32>().ok()? * 10,
        _ => frac[..3].parse().ok()?,
    };
    Some(m * 60_000 + sec * 1000 + ms)
}

fn parse_lrc(lrc: &str) -> Vec<(u32, String)> {
    let mut out: Vec<(u32, String)> = lrc
        .lines()
        .flat_map(|l| {
            let (times, text) = parse_line(l);
            times.into_iter().map(move |t| (t, text.to_string()))
        })
        .collect();
    out.sort_by_key(|(t, _)| *t);
    out
}

pub fn build(lrc: &str, trans: &str) -> Lyric {
    let orig = parse_lrc(lrc);
    let trans: HashMap<u32, String> = parse_lrc(trans)
        .into_iter()
        // QQ 音乐的翻译用 “//” 表示该行无翻译
        .filter(|(_, t)| !t.is_empty() && t != "//")
        .collect();
    let lines: Vec<LyricLine> = orig
        .into_iter()
        .map(|(t, text)| LyricLine {
            time_ms: t,
            trans: trans.get(&t).cloned().unwrap_or_default(),
            text,
        })
        .collect();
    let plain = if lines.is_empty() { lrc.trim().to_string() } else { String::new() };
    Lyric { lines, plain }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parses_and_merges() {
        let lrc = "[ti:Song]\n[00:01.50]Hello\n[00:03.00][00:10.000]World\n";
        let trans = "[00:01.50]你好\n[00:03.00]//\n";
        let l = build(lrc, trans);
        assert_eq!(l.lines.len(), 3);
        assert_eq!(l.lines[0].time_ms, 1500);
        assert_eq!(l.lines[0].trans, "你好");
        assert_eq!(l.lines[1].trans, "");
        assert_eq!(l.lines[2].time_ms, 10_000);
        assert_eq!(l.lines[2].text, "World");
    }
}
