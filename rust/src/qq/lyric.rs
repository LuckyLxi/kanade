//! 解析 LRC 和 QRC（逐字歌词），再把翻译和罗马音按时间对到原文的行上。

use crate::api::types::{Lyric, LyricLine, LyricWord};

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

/// QRC 是一段 XML，歌词在 `LyricContent` 属性里；不是 QRC 时返回 None。
/// 属性里的引号不一定转义（比如 `[al:… "ラッキーシアン"]`），所以找到 `"/>` 才算结束。
fn qrc_content(text: &str) -> Option<String> {
    let start = text.find("LyricContent=\"")? + "LyricContent=\"".len();
    let len = text[start..].find("\"/>")?;
    Some(unescape(&text[start..start + len]))
}

fn unescape(s: &str) -> String {
    let mut out = String::with_capacity(s.len());
    let mut rest = s;
    while let Some(i) = rest.find('&') {
        out.push_str(&rest[..i]);
        rest = &rest[i..];
        let entity = rest.find(';').map(|end| (&rest[1..end], end + 1));
        let ch = entity.and_then(|(name, _)| match name {
            "amp" => Some('&'),
            "lt" => Some('<'),
            "gt" => Some('>'),
            "quot" => Some('"'),
            "apos" => Some('\''),
            _ => match name.strip_prefix("#x").or_else(|| name.strip_prefix("#X")) {
                Some(hex) => u32::from_str_radix(hex, 16).ok(),
                None => name.strip_prefix('#').and_then(|d| d.parse().ok()),
            }
            .and_then(char::from_u32),
        });
        match (ch, entity) {
            (Some(c), Some((_, len))) => {
                out.push(c);
                rest = &rest[len..];
            }
            _ => {
                out.push('&');
                rest = &rest[1..];
            }
        }
    }
    out.push_str(rest);
    out
}

/// 字后面的 `(开始,时长)`，返回 (开始, 时长, 这段的长度)。
fn word_time(s: &str) -> Option<(u32, u32, usize)> {
    let close = s.find(')')?;
    let (start, duration) = s[1..close].split_once(',')?;
    let digits = |v: &str| !v.is_empty() && v.bytes().all(|b| b.is_ascii_digit());
    if !digits(start) || !digits(duration) {
        return None;
    }
    Some((start.parse().ok()?, duration.parse().ok()?, close + 1))
}

/// 一行 QRC：`[开始,时长]字(开始,时长)字(开始,时长)…`。字本身也可能带括号，比如 `Around (`。
fn qrc_line(line: &str) -> Option<LyricLine> {
    let (head, body) = line.trim().strip_prefix('[')?.split_once(']')?;
    let time_ms = head.split_once(',')?.0.trim().parse().ok()?;
    let mut words = Vec::new();
    let mut word = String::new();
    let mut rest = body;
    while let Some(open) = rest.find('(') {
        word.push_str(&rest[..open]);
        let tail = &rest[open..];
        match word_time(tail) {
            Some((start_ms, duration_ms, len)) => {
                words.push(LyricWord {
                    start_ms,
                    duration_ms,
                    text: std::mem::take(&mut word),
                });
                rest = &tail[len..];
            }
            None => {
                word.push('(');
                rest = &tail[1..];
            }
        }
    }
    word.push_str(rest);
    let mut text: String = words.iter().map(|w| w.text.as_str()).collect();
    text.push_str(&word);
    Some(LyricLine {
        time_ms,
        text,
        trans: String::new(),
        roma: String::new(),
        words,
    })
}

fn parse_qrc(content: &str) -> Vec<LyricLine> {
    let mut lines: Vec<LyricLine> = content.lines().filter_map(qrc_line).collect();
    lines.sort_by_key(|l| l.time_ms);
    lines
}

/// 时间最近的一行，差太多就不算。翻译的 LRC 只精确到 10 毫秒，QRC 精确到毫秒，对不齐。
fn nearest(lines: &[LyricLine], t: u32) -> Option<usize> {
    let i = lines.partition_point(|l| l.time_ms < t);
    [i.checked_sub(1), (i < lines.len()).then_some(i)]
        .into_iter()
        .flatten()
        .min_by_key(|&j| lines[j].time_ms.abs_diff(t))
        .filter(|&j| lines[j].time_ms.abs_diff(t) <= 1000)
}

fn attach(lines: &mut [LyricLine], extra: Vec<(u32, String)>, set: fn(&mut LyricLine, String)) {
    for (t, text) in extra {
        // QQ 音乐的翻译用 “//” 表示该行无翻译
        if text.is_empty() || text == "//" {
            continue;
        }
        if let Some(i) = nearest(lines, t) {
            set(&mut lines[i], text);
        }
    }
}

/// [lyric] 是 QRC 或 LRC，[trans] 是 LRC，[roma] 是 QRC。
pub fn build(lyric: &str, trans: &str, roma: &str) -> Lyric {
    let qrc = qrc_content(lyric);
    let mut lines = match &qrc {
        Some(content) => parse_qrc(content),
        None => parse_lrc(lyric)
            .into_iter()
            .map(|(time_ms, text)| LyricLine {
                time_ms,
                text,
                trans: String::new(),
                roma: String::new(),
                words: Vec::new(),
            })
            .collect(),
    };
    attach(&mut lines, parse_lrc(trans), |l, t| l.trans = t);
    let roma = match qrc_content(roma) {
        Some(content) => parse_qrc(&content)
            .into_iter()
            .map(|l| (l.time_ms, l.text.trim().to_string()))
            .collect(),
        None => parse_lrc(roma),
    };
    attach(&mut lines, roma, |l, t| l.roma = t);
    let plain = if lines.is_empty() && qrc.is_none() {
        lyric.trim().to_string()
    } else {
        String::new()
    };
    Lyric { lines, plain }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parses_and_merges() {
        let lrc = "[ti:Song]\n[00:01.50]Hello\n[00:03.00][00:10.000]World\n";
        let trans = "[00:01.50]你好\n[00:03.00]//\n";
        let l = build(lrc, trans, "");
        assert_eq!(l.lines.len(), 3);
        assert_eq!(l.lines[0].time_ms, 1500);
        assert_eq!(l.lines[0].trans, "你好");
        assert_eq!(l.lines[1].trans, "");
        assert_eq!(l.lines[2].time_ms, 10_000);
        assert_eq!(l.lines[2].text, "World");
    }

    #[test]
    fn parses_qrc_with_trans_and_roma() {
        let qrc = "<Lyric_1 LyricType=\"1\" LyricContent=\"[ti:Song]\n[al:Album \"Quoted\"]\n\
            [514,500]Turning (514,152)Around ((666,158)&amp;(824,160))(984,10)\n\
            [2801,300]君(2801,150)の(2951,150)\n\"/>";
        let trans = "[00:00.51]转身\n[00:02.80]//\n";
        let roma = "<Lyric_1 LyricContent=\"[2801,300]kimi (2801,150)no(2951,150)\n\"/>";
        let l = build(qrc, trans, roma);
        assert_eq!(l.lines.len(), 2);
        let first = &l.lines[0];
        assert_eq!(first.time_ms, 514);
        assert_eq!(first.text, "Turning Around (&)");
        let words: Vec<_> = first
            .words
            .iter()
            .map(|w| (w.text.as_str(), w.start_ms, w.duration_ms))
            .collect();
        assert_eq!(
            words,
            [
                ("Turning ", 514, 152),
                ("Around (", 666, 158),
                ("&", 824, 160),
                (")", 984, 10)
            ]
        );
        assert_eq!(first.trans, "转身");
        assert_eq!(first.roma, "");
        assert_eq!(l.lines[1].trans, "");
        assert_eq!(l.lines[1].roma, "kimi no");
        assert!(l.plain.is_empty());
    }
}
