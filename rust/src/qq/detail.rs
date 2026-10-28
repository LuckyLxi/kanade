//! 歌手页、专辑页和评论。都是 Windows 客户端内嵌页（ct=20）的接口。

use anyhow::Result;
use serde_json::{json, Value};

use super::client::core;
use super::music::webkit_comm;
use super::parse::{self, album_cover, first_s, n, s, singer_cover};
use crate::api::types::*;

async fn webkit(module: &str, method: &str, param: Value) -> Result<Value> {
    core().musicu_with_comm(module, method, param, webkit_comm()).await
}

/// 歌手资料、第一页歌曲和专辑一起取。
pub async fn singer_detail(mid: &str) -> Result<SingerDetail> {
    let c = core();
    let data = c
        .cached(&format!("singer:{mid}"), 3600, || async {
            let (info, songs, albums) = tokio::join!(
                webkit(
                    "music.musichallSinger.SingerInfoInter",
                    "GetSingerDetail",
                    json!({ "singer_mids": [mid], "pic": 1, "group_singer": 1, "wiki_singer": 1, "ex_singer": 1 }),
                ),
                singer_songs_raw(mid, 0, 30),
                singer_albums_raw(mid, 0, 30),
            );
            Ok(json!({ "info": info?, "songs": songs?, "albums": albums? }))
        })
        .await?;
    let singer = &data["info"]["singer_list"][0];
    let basic = &singer["basic_info"];
    let avatar = s(&singer["pic"]["pic"]);
    Ok(SingerDetail {
        mid: mid.to_string(),
        name: s(&basic["name"]),
        avatar_url: if avatar.is_empty() { singer_cover(mid) } else { avatar },
        description: s(&singer["ex_info"]["desc"]),
        songs: parse::songs(&data["songs"]["songList"]),
        song_total: n(&data["songs"]["totalNum"]) as u32,
        albums: albums(&data["albums"]["albumList"]),
        album_total: n(&data["albums"]["total"]) as u32,
    })
}

async fn singer_songs_raw(mid: &str, begin: u32, num: u32) -> Result<Value> {
    webkit(
        "music.musichallSong.SongListInter",
        "GetSingerSongList",
        json!({ "singerMid": mid, "begin": begin, "num": num, "order": 1 }),
    )
    .await
}

async fn singer_albums_raw(mid: &str, begin: u32, num: u32) -> Result<Value> {
    // order=1 按时间，抓包里另有 order=0 的请求
    webkit(
        "music.musichallAlbum.AlbumListServer",
        "GetAlbumList",
        json!({ "singerMid": mid, "order": 1, "num": num, "begin": begin }),
    )
    .await
}

/// 歌手歌曲翻页，`begin` 从 0 开始。
pub async fn singer_songs(mid: &str, begin: u32, num: u32) -> Result<Vec<Song>> {
    let c = core();
    let data = c.cached(&format!("singer_songs:{mid}:{begin}:{num}"), 3600, || singer_songs_raw(mid, begin, num)).await?;
    Ok(parse::songs(&data["songList"]))
}

pub async fn singer_albums(mid: &str, begin: u32, num: u32) -> Result<Vec<AlbumBrief>> {
    let c = core();
    let data = c.cached(&format!("singer_albums:{mid}:{begin}:{num}"), 3600, || singer_albums_raw(mid, begin, num)).await?;
    Ok(albums(&data["albumList"]))
}

fn albums(list: &Value) -> Vec<AlbumBrief> {
    list.as_array()
        .into_iter()
        .flatten()
        .filter_map(|a| {
            let mid = s(&a["albumMid"]);
            (!mid.is_empty()).then(|| AlbumBrief {
                cover_url: album_cover(&mid),
                name: s(&a["albumName"]),
                publish_date: s(&a["publishDate"]),
                singer_name: s(&a["singerName"]),
                mid,
            })
        })
        .collect()
}

pub async fn album_detail(mid: &str) -> Result<AlbumDetail> {
    let c = core();
    let data = c
        .cached(&format!("album:{mid}"), 3600, || async {
            let (info, songs) = tokio::join!(
                webkit("music.musichallAlbum.AlbumInfoServer", "GetAlbumDetail", json!({ "albumMid": mid })),
                webkit(
                    "music.musichallAlbum.AlbumSongList",
                    "GetAlbumSongList",
                    json!({ "albumMid": mid, "begin": 0, "num": 1000, "order": 2 }),
                ),
            );
            Ok(json!({ "info": info?, "songs": songs? }))
        })
        .await?;
    let info = &data["info"];
    let basic = &info["basicInfo"];
    Ok(AlbumDetail {
        mid: mid.to_string(),
        id: n(&basic["albumID"]),
        name: s(&basic["albumName"]),
        cover_url: album_cover(mid),
        description: s(&basic["desc"]),
        publish_date: s(&basic["publishDate"]),
        company: s(&info["company"]["name"]),
        singers: info["singer"]["singerList"]
            .as_array()
            .into_iter()
            .flatten()
            .map(|x| Singer { mid: s(&x["mid"]), name: s(&x["name"]) })
            .collect(),
        songs: parse::songs(&data["songs"]["songList"]),
    })
}

fn biz_type(target: CommentTarget) -> i64 {
    match target {
        CommentTarget::Song => 1,
        CommentTarget::Album => 2,
    }
}

/// 评论正文里的表情是 `[em]e400846[/em]` 这样的代码，界面上没法显示，去掉。
fn clean_content(text: &str) -> String {
    let mut out = String::with_capacity(text.len());
    let mut rest = text;
    while let Some(start) = rest.find("[em]") {
        out.push_str(&rest[..start]);
        match rest[start..].find("[/em]") {
            Some(end) => rest = &rest[start + end + 5..],
            None => {
                rest = &rest[start..];
                break;
            }
        }
    }
    out.push_str(rest);
    out.trim().to_string()
}

fn comment(v: &Value) -> Option<Comment> {
    let id = s(&v["CmId"]);
    if id.is_empty() {
        return None;
    }
    Some(Comment {
        id,
        seq_no: s(&v["SeqNo"]),
        nick: s(&v["Nick"]),
        avatar_url: s(&v["Avatar"]),
        content: clean_content(&s(&v["Content"])),
        time_secs: n(&v["PubTime"]),
        praise_count: n(&v["PraiseNum"]) as u32,
        reply_count: n(&v["ReplyCnt"]) as u32,
        reply_to: first_s(&v["RepliedComments"][0], &["Nick"]),
    })
}

fn comments(list: &Value) -> Vec<Comment> {
    list["Comments"].as_array().into_iter().flatten().filter_map(comment).collect()
}

/// 最新评论，第一页顺带热门评论。`page` 从 0 开始，`last_seq_no` 是上一页最后一条的 `seq_no`。
/// 抓包只有第一页；后续页按回复列表的翻页方式传游标，没有在抓包里核对过。
pub async fn comments_page(target: CommentTarget, id: i64, page: u32, last_seq_no: &str) -> Result<CommentPage> {
    let first = page == 0;
    let data = webkit(
        "music.globalComment.CommentRead",
        "GetNewCommentList",
        json!({
            "BizType": biz_type(target),
            "BizId": id.to_string(),
            "LastCommentSeqNo": last_seq_no,
            "PageSize": 25,
            "PageNum": page,
            "FromCommentId": "",
            "WithHot": if first { 1 } else { 0 },
            "PicEnable": 1,
            "LastTotal": 0,
            "LastTotalVer": "0",
        }),
    )
    .await?;
    // WithHot=1 时 CommentList 是最新评论（ListType 3），CommentList2 是热门评论（ListType 1）
    let list = &data["CommentList"];
    Ok(CommentPage {
        hot: if first { comments(&data["CommentList2"]) } else { vec![] },
        latest: comments(list),
        total: n(&list["Total"]) as u32,
        has_more: n(&list["HasMore"]) == 1,
    })
}

/// 某条评论下的回复，`page` 从 0 开始。
pub async fn comment_replies(root_id: &str, page: u32, last_seq_no: &str) -> Result<CommentPage> {
    let data = webkit(
        "music.globalComment.CommentRead",
        "GetReplyCommentList",
        json!({
            "RootCmId": root_id,
            "LastCommentSeqNo": last_seq_no,
            "PageSize": 10,
            "LastRankScore": if page == 0 { "" } else { "0" },
            "RankType": 1,
            "PicEnable": 1,
            "PageNum": page,
        }),
    )
    .await?;
    let list = &data["CommentList"];
    let latest = comments(list);
    let total = n(&list["Total"]) as u32;
    Ok(CommentPage {
        hot: vec![],
        // 抓包里回复的 HasMore 一直是 0，即使还有没取完的，所以同时看条数
        has_more: n(&list["HasMore"]) == 1 || (!latest.is_empty() && (page + 1) * 10 < total),
        latest,
        total,
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn strips_emoji_codes() {
        assert_eq!(clean_content("好听[em]e400846[/em][em]e1[/em]！"), "好听！");
        assert_eq!(clean_content("[em]broken"), "[em]broken");
    }

    #[test]
    fn parses_reply_target() {
        let c = comment(&json!({
            "CmId": "1!abc", "SeqNo": "16", "Nick": "a", "Content": "当然了", "PubTime": 1785267626,
            "PraiseNum": 2, "ReplyCnt": 0, "RepliedComments": [{ "Nick": "b", "Content": "x" }]
        }))
        .unwrap();
        assert_eq!(c.reply_to, "b");
        assert_eq!(c.praise_count, 2);
    }

    #[tokio::test]
    #[ignore = "需要联网"]
    async fn fetches_singer_album_and_comments() {
        let singer = singer_detail("002mYUgi0lXd76").await.unwrap();
        assert!(!singer.name.is_empty() && !singer.songs.is_empty() && !singer.albums.is_empty(), "{singer:?}");
        let album = album_detail("00277xRX464rH4").await.unwrap();
        assert_eq!(album.id, 113947);
        assert!(!album.songs.is_empty());
        let page = comments_page(CommentTarget::Song, 1401475, 0, "").await.unwrap();
        assert!(!page.latest.is_empty(), "{page:?}");
        let last = page.latest.last().unwrap().seq_no.clone();
        let next = comments_page(CommentTarget::Song, 1401475, 1, &last).await.unwrap();
        assert!(next.latest.iter().all(|c| page.latest.iter().all(|p| p.id != c.id)), "第二页与第一页重复");
        println!("singer songs={} albums={}, comments total={} p1={} p2={}", singer.song_total, singer.album_total, page.total, page.latest.len(), next.latest.len());
        let root = page.hot.iter().chain(&page.latest).find(|c| c.reply_count > 10).expect("没有回复较多的评论");
        let r0 = comment_replies(&root.id, 0, "").await.unwrap();
        assert!(!r0.latest.is_empty() && r0.has_more, "{r0:?}");
        let r1 = comment_replies(&root.id, 1, &r0.latest.last().unwrap().seq_no).await.unwrap();
        assert!(r1.latest.iter().all(|c| r0.latest.iter().all(|p| p.id != c.id)), "回复第二页与第一页重复");
        println!("replies: cnt={} total={} p1={} p2={}", root.reply_count, r0.total, r0.latest.len(), r1.latest.len());
    }
}
