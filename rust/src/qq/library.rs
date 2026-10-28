//! 红心使用签名加密通道，普通歌单使用 PC 通道；只在用户点了按钮后提交。

use anyhow::{bail, Context, Result};
use serde_json::{json, Value};

use super::client::core;
use super::error::ApiError;
use super::music::playlist_detail;
use super::parse::{n, s};
use crate::api::types::MyPlaylist;

/// “我喜欢”在每个账号下的目录编号都是 201，tid 则因人而异。
pub const LIKED_DIR_ID: i64 = 201;

/// 当前账号自己创建的歌单（含“我喜欢”），不含收藏的别人的歌单。
pub async fn my_playlists() -> Result<Vec<MyPlaylist>> {
    let c = core();
    let Some(sess) = c.session() else { bail!(ApiError::NotLoggedIn) };
    let data = c
        .cached("my_playlists", 600, || async {
            c.get_json(
                "https://c.y.qq.com/rsc/fcgi-bin/fcg_user_created_diss",
                &[("hostuin", sess.uin.clone()), ("sin", "0".into()), ("size", "200".into()), ("format", "json".into())],
            )
            .await
        })
        .await?;
    Ok(data["data"]["disslist"]
        .as_array()
        .into_iter()
        .flatten()
        .filter(|p| n(&p["tid"]) != 0 && n(&p["dirid"]) != 0)
        .map(|p| MyPlaylist {
            dir_id: n(&p["dirid"]),
            tid: n(&p["tid"]),
            name: s(&p["diss_name"]),
            cover_url: s(&p["diss_cover"]),
            song_count: n(&p["song_cnt"]) as u32,
        })
        .collect())
}

async fn liked_dir() -> Result<MyPlaylist> {
    match my_playlists().await?.into_iter().find(|p| p.dir_id == LIKED_DIR_ID) {
        Some(p) => Ok(p),
        None => bail!(ApiError::bad_response("liked playlist (dirid 201) not found")),
    }
}

/// “我喜欢”里的歌曲 id，用来显示红心状态。
pub async fn liked_song_ids() -> Result<Vec<i64>> {
    let dir = liked_dir().await?;
    Ok(playlist_detail(&dir.tid.to_string()).await?.songs.into_iter().map(|s| s.id).collect())
}

/// 往自己的歌单里加歌或删歌。AddSonglist / DelSonglist 参数相同。
async fn write(dir: &MyPlaylist, song_id: i64, add: bool) -> Result<()> {
    let c = core();
    let module = "music.musicasset.PlaylistDetailWrite";
    let method = if add { "AddSonglist" } else { "DelSonglist" };
    let param = write_param(dir, song_id);
    let data = if dir.dir_id == LIKED_DIR_ID {
        c.signed_web_musicu(module, method, param).await?
    } else {
        c.desktop_write(module, method, param).await?
    };
    check_write_result(&data)?;
    c.uncache(&format!("playlist:{}:{}", c.uin(), dir.tid));
    c.uncache("my_playlists");
    Ok(())
}

fn write_param(dir: &MyPlaylist, song_id: i64) -> Value {
    let mut param = json!({"dirId": dir.dir_id, "v_songInfo": [{"songId": song_id, "songType": 0}]});
    if dir.dir_id != LIKED_DIR_ID {
        param["bFmtUtf8"] = json!(true);
        param["dirName"] = json!(dir.name);
        param["tid"] = json!(dir.tid);
    }
    param
}

fn check_write_result(data: &Value) -> Result<()> {
    let code = data["retCode"].as_i64().context(ApiError::bad_response("PlaylistDetailWrite returned no retCode"))?;
    if code != 0 {
        bail!(ApiError::ServerError { api: "PlaylistDetailWrite".into(), code: code.to_string() });
    }
    Ok(())
}

pub async fn set_song_liked(song_id: i64, liked: bool) -> Result<()> {
    write(&liked_dir().await?, song_id, liked).await
}

/// `dir_id` 来自 `my_playlists`，不能写死：每个账号的普通歌单编号不同。
async fn own_dir(dir_id: i64) -> Result<MyPlaylist> {
    match my_playlists().await?.into_iter().find(|p| p.dir_id == dir_id) {
        Some(p) => Ok(p),
        None => bail!(ApiError::bad_response(format!("playlist dirid {dir_id} not found"))),
    }
}

pub async fn add_to_playlist(dir_id: i64, song_id: i64) -> Result<()> {
    write(&own_dir(dir_id).await?, song_id, true).await
}

pub async fn remove_from_playlist(dir_id: i64, song_id: i64) -> Result<()> {
    write(&own_dir(dir_id).await?, song_id, false).await
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn liked_params_use_web_shape_while_normal_playlist_keeps_pc_shape() {
        let mut dir = MyPlaylist { dir_id: LIKED_DIR_ID, tid: 123456, name: "test".into(), cover_url: String::new(), song_count: 0 };
        assert_eq!(write_param(&dir, 42), json!({"dirId": 201, "v_songInfo": [{"songId": 42, "songType": 0}]}));
        dir.dir_id = 1;
        assert_eq!(write_param(&dir, 42), json!({"dirId": 1, "tid": 123456, "dirName": "test", "bFmtUtf8": true,
            "v_songInfo": [{"songId": 42, "songType": 0}]}));
    }

    #[test]
    fn write_result_requires_explicit_success() {
        assert!(check_write_result(&json!({"retCode": 0})).is_ok());
        for data in [json!({}), json!({"retCode": null})] {
            assert!(matches!(ApiError::from(check_write_result(&data).unwrap_err()), ApiError::BadResponse { .. }));
        }
        let error = check_write_result(&json!({"retCode": 2000})).unwrap_err();
        assert!(matches!(ApiError::from(error), ApiError::ServerError { code, .. } if code == "2000"));
    }
}
