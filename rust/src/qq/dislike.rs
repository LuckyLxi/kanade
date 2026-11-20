//! “不喜欢”黑名单（music.feedback.FeedbackBlack）。参数来自 Android 客户端黑名单网页。

use anyhow::{bail, Context, Result};
use serde_json::{json, Value};

use super::client::core;
use super::error::ApiError;
use super::client::webkit_comm;
use super::parse::{n, s};
use crate::api::types::{DislikeItem, DislikeKind};

const MODULE: &str = "music.feedback.FeedbackBlack";

pub async fn dislike_song(song_id: i64, name: &str) -> Result<()> {
    write("AddDislike", DislikeKind::Song, &song_id.to_string(), name).await
}

/// 黑名单只认歌手的数字 id，传 mid 也返回成功但不会生效。
pub async fn dislike_singer(mid: &str, name: &str) -> Result<()> {
    let data = core().musicu_with_comm("music.musichallSinger.SingerInfoInter", "GetSingerDetail",
        json!({"singer_mids": [mid], "pic": 0, "group_singer": 0, "wiki_singer": 0, "ex_singer": 0}), webkit_comm()).await?;
    let id = n(&data["singer_list"][0]["basic_info"]["singer_id"]);
    if id == 0 { bail!(ApiError::bad_response(format!("singer id for {mid} is missing"))); }
    write("AddDislike", DislikeKind::Singer, &id.to_string(), name).await
}

/// `id` 用 `dislikes` 返回的值。
pub async fn cancel_dislike(kind: DislikeKind, id: &str) -> Result<()> {
    write("CancelDislike", kind, id, "").await
}

async fn write(method: &str, kind: DislikeKind, id: &str, name: &str) -> Result<()> {
    let c = core();
    if c.session().is_none() { bail!(ApiError::NotLoggedIn); }
    let data = c.desktop_private(MODULE, method, write_param(kind, id, name)).await?;
    check_retcode(&data, method)
}

fn write_param(kind: DislikeKind, id: &str, name: &str) -> Value {
    let item = json!([{"ID": id, "Name": name, "IdType": 0}]);
    let (songs, singers) = match kind {
        DislikeKind::Song => (item, json!([])),
        DislikeKind::Singer => (json!([]), item),
    };
    json!({"Singers": singers, "Songs": songs, "Styles": [], "OnlyAdd": 1})
}

fn check_retcode(data: &Value, method: &str) -> Result<()> {
    let code = data["Retcode"].as_i64().context(ApiError::bad_response(format!("{method} returned no Retcode")))?;
    if code != 0 {
        bail!(ApiError::ServerError { api: format!("{MODULE}.{method}"), code: code.to_string() });
    }
    Ok(())
}

/// 按页取到空页为止；服务端分页的大小没抓到过，遇到重复的页也停下。
pub async fn dislikes(kind: DislikeKind) -> Result<Vec<DislikeItem>> {
    let c = core();
    if c.session().is_none() { bail!(ApiError::NotLoggedIn); }
    let (cmd, field) = match kind {
        DislikeKind::Song => (3, "Songs"),
        DislikeKind::Singer => (2, "Singers"),
    };
    let mut items: Vec<DislikeItem> = Vec::new();
    for page in 1.. {
        let last = items.last().map(|i| i.id.parse::<i64>().unwrap_or(0)).unwrap_or(0);
        let (song_last, singer_last) = if kind == DislikeKind::Song { (last, 0) } else { (0, last) };
        let data = c.desktop_private(MODULE, "GetDislikeList",
            json!({"Cmd": cmd, "Page": page, "SongLastid": song_last, "SingersLastid": singer_last})).await?;
        check_retcode(&data, "GetDislikeList")?;
        let before = items.len();
        for item in data[field].as_array().into_iter().flatten().map(parse_item) {
            if !items.iter().any(|i| i.id == item.id) { items.push(item); }
        }
        if items.len() == before { break; }
    }
    Ok(items)
}

fn parse_item(v: &Value) -> DislikeItem {
    DislikeItem { id: s(&v["ID"]), name: s(&v["Name"]), image_url: s(&v["Img"]) }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn write_param_puts_item_in_its_kind() {
        assert_eq!(write_param(DislikeKind::Song, "106585340", "泪海"), json!({
            "Singers": [], "Songs": [{"ID": "106585340", "Name": "泪海", "IdType": 0}], "Styles": [], "OnlyAdd": 1,
        }));
        assert_eq!(write_param(DislikeKind::Singer, "4558", "周杰伦")["Singers"][0]["ID"], "4558");
    }

    #[test]
    fn parses_list_item() {
        let item = parse_item(&json!({"ID": "4558", "IdType": 0, "Img": "https://y.gtimg.cn/a.jpg", "Name": "周杰伦", "Time": 1}));
        assert_eq!((item.id.as_str(), item.name.as_str(), item.image_url.as_str()), ("4558", "周杰伦", "https://y.gtimg.cn/a.jpg"));
    }
}
