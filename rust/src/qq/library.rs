//! 红心使用与登录态匹配的 Android 客户端通道，普通歌单保留现有 PC 通道。

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
        c.mobile_write(module, method, param).await?
    } else {
        c.desktop_private(module, method, param).await?
    };
    check_write_result(&data, "PlaylistDetailWrite")?;
    forget(dir);
    Ok(())
}

/// 写入成功后丢掉这个歌单和歌单列表的缓存。
fn forget(dir: &MyPlaylist) {
    let c = core();
    c.uncache(&format!("playlist:{}:{}", c.uin(), dir.tid));
    c.uncache("my_playlists");
}

fn write_param(dir: &MyPlaylist, song_id: i64) -> Value {
    json!({"dirId": dir.dir_id, "bFmtUtf8": true, "dirName": dir.name, "tid": dir.tid,
        "v_songInfo": [{"songId": song_id, "songType": 0}]})
}

fn check_write_result(data: &Value, api: &str) -> Result<()> {
    let code = data["retCode"].as_i64().context(ApiError::bad_response(format!("{api} returned no retCode")))?;
    if code != 0 {
        bail!(ApiError::ServerError { api: api.into(), code: code.to_string() });
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

pub async fn create_playlist(name: &str) -> Result<MyPlaylist> {
    let name = name.trim();
    if name.is_empty() { bail!(ApiError::bad_response("playlist name is empty")); }
    let c = core();
    if c.session().is_none() { bail!(ApiError::NotLoggedIn); }
    let data = c.desktop_private("music.musicasset.PlaylistBaseWrite", "AddPlaylist",
        json!({"bFmtUtf8": true, "dirName": name})).await?;
    let playlist = created_playlist(&data)?;
    c.uncache("my_playlists");
    Ok(playlist)
}

fn created_playlist(data: &Value) -> Result<MyPlaylist> {
    check_write_result(data, "PlaylistBaseWrite.AddPlaylist")?;
    let result = &data["result"];
    let dir_id = result["dirId"].as_i64().filter(|id| *id > 0)
        .context(ApiError::bad_response("new playlist directory is missing"))?;
    let tid = result["tid"].as_i64().filter(|id| *id > 0)
        .context(ApiError::bad_response("new playlist id is missing"))?;
    Ok(MyPlaylist {dir_id, tid, name: s(&result["dirName"]), cover_url: s(&result["dirPicUrl"]), song_count: 0})
}

pub async fn remove_from_playlist(dir_id: i64, song_id: i64) -> Result<()> {
    write(&own_dir(dir_id).await?, song_id, false).await
}

/// 改名或删除整个歌单，“我喜欢”两样都不允许。
async fn base_write(dir_id: i64, method: &str, param: impl FnOnce(&MyPlaylist) -> Value) -> Result<()> {
    if dir_id == LIKED_DIR_ID {
        bail!(ApiError::bad_response("the liked playlist cannot be renamed or deleted"));
    }
    let dir = own_dir(dir_id).await?;
    let data = core().desktop_private("music.musicasset.PlaylistBaseWrite", method, param(&dir)).await?;
    check_write_result(&data, &format!("PlaylistBaseWrite.{method}"))?;
    forget(&dir);
    Ok(())
}

pub async fn rename_playlist(dir_id: i64, new_name: &str) -> Result<()> {
    base_write(dir_id, "EditPlaylist", |dir| rename_param(dir, new_name)).await
}

/// 删除要带歌单当前的名字，所以先从 `my_playlists` 重新取目标。
pub async fn delete_playlist(dir_id: i64) -> Result<()> {
    base_write(dir_id, "DelPlaylist", delete_param).await
}

fn rename_param(dir: &MyPlaylist, new_name: &str) -> Value {
    json!({"bFmtUtf8": true, "dirId": dir.dir_id, "dirNewName": new_name, "dirShow": 1, "mask": 1})
}

fn delete_param(dir: &MyPlaylist) -> Value {
    json!({"bFmtUtf8": true, "dirId": dir.dir_id, "dirName": dir.name})
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn created_playlist_requires_success_and_both_identifiers() {
        let good = json!({"retCode": 0, "result": {"dirId": 12, "tid": 9876543210i64, "dirName": "new"}});
        let p = created_playlist(&good).unwrap();
        assert_eq!((p.dir_id, p.tid, p.name.as_str()), (12, 9876543210, "new"));
        for invalid in [json!({"result": good["result"]}), json!({"retCode": 2000, "result": good["result"]}),
            json!({"retCode": 0, "result": {"dirId": 12}}), json!({"retCode": 0, "result": {"dirId": 0, "tid": 42}})] {
            assert!(created_playlist(&invalid).is_err());
        }
    }

    #[test]
    fn liked_and_normal_params_use_captured_pc_shape() {
        let mut dir = MyPlaylist { dir_id: LIKED_DIR_ID, tid: 123456, name: "test".into(), cover_url: String::new(), song_count: 0 };
        assert_eq!(write_param(&dir, 42), json!({"dirId": 201, "tid": 123456, "dirName": "test", "bFmtUtf8": true,
            "v_songInfo": [{"songId": 42, "songType": 0}]}));
        dir.dir_id = 1;
        assert_eq!(write_param(&dir, 42), json!({"dirId": 1, "tid": 123456, "dirName": "test", "bFmtUtf8": true,
            "v_songInfo": [{"songId": 42, "songType": 0}]}));
    }

    #[test]
    fn write_result_requires_explicit_success() {
        assert!(check_write_result(&json!({"retCode": 0}), "X").is_ok());
        for data in [json!({}), json!({"retCode": null})] {
            assert!(matches!(ApiError::from(check_write_result(&data, "X").unwrap_err()), ApiError::BadResponse { .. }));
        }
        let error = check_write_result(&json!({"retCode": 2000}), "PlaylistBaseWrite.DelPlaylist").unwrap_err();
        assert!(matches!(ApiError::from(error), ApiError::ServerError { api, code } if code == "2000" && api == "PlaylistBaseWrite.DelPlaylist"));
    }

    #[test]
    fn rename_and_delete_params_use_captured_pc_shape() {
        let dir = MyPlaylist { dir_id: 5, tid: 123456, name: "now".into(), cover_url: String::new(), song_count: 0 };
        assert_eq!(rename_param(&dir, "new"), json!({"bFmtUtf8": true, "dirId": 5, "dirNewName": "new", "dirShow": 1, "mask": 1}));
        assert_eq!(delete_param(&dir), json!({"bFmtUtf8": true, "dirId": 5, "dirName": "now"}));
    }
}
