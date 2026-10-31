//! 歌手和用户的关注关系。写操作只在用户触发后提交，不自动重试。

use anyhow::{bail, Context, Result};
use serde_json::{json, Value};

use super::{client::core, error::ApiError, music::webkit_comm};

const MODULE: &str = "Concern.ConcernSystemServer";

pub async fn singer_followed(mid: &str) -> Result<bool> {
    if core().session().is_none() {
        return Ok(false);
    }
    let data = core().musicu_with_comm(MODULE, "cgi_qry_concern_status", json!({
        "vec_userinfo": [{"usertype": 1, "userid": mid}], "opertype": 5, "encrypt_singerid": 1,
    }), webkit_comm()).await?;
    let status = data["map_singer_status"][mid].as_i64()
        .context(ApiError::bad_response("singer follow status is missing"))?;
    Ok(status == 1)
}

pub async fn set_followed(target: &str, singer: bool, followed: bool) -> Result<()> {
    let data = core().musicu_write_with_comm(MODULE, "cgi_concern_user_v2", follow_param(target, singer, followed), webkit_comm()).await?;
    check_follow_result(&data)?;
    core().uncache(&format!("user:profile:{target}"));
    Ok(())
}

fn follow_param(target: &str, singer: bool, followed: bool) -> Value {
    let mut param = json!({"opertype": if followed { 0 } else { 1 },
        "userinfo": {"usertype": if singer { 1 } else { 0 }, "userid": target}});
    if singer {
        param["source"] = json!(0);
        param["encrypt_singerid"] = json!(1);
    }
    param
}

fn check_follow_result(data: &Value) -> Result<()> {
    let code = data["code"].as_i64().context(ApiError::bad_response("follow response has no code"))?;
    if code != 0 {
        bail!(ApiError::ServerError { api: format!("{MODULE}.cgi_concern_user_v2"), code: code.to_string() });
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn follow_does_not_accept_missing_or_failed_business_result() {
        assert!(check_follow_result(&json!({"code": 0})).is_ok());
        for response in [json!({}), json!({"code": null}), json!({"code": 405}), json!({"code": "0"})] {
            assert!(check_follow_result(&response).is_err());
        }
        let singer = follow_param("singer-mid", true, true);
        assert_eq!(singer["userinfo"]["usertype"], 1);
        assert_eq!(singer["encrypt_singerid"], 1);
        let user = follow_param("encrypted-user", false, false);
        assert_eq!(user["userinfo"]["userid"], "encrypted-user");
        assert_eq!(user["userinfo"]["usertype"], 0);
        assert_eq!(user["opertype"], 1);
        assert!(user.get("encrypt_singerid").is_none());
    }
}
