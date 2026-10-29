//! 真实接口冒烟测试：cargo test --test live -- --ignored --nocapture

use rust_lib_kanade::api::types::Quality;
use rust_lib_kanade::qq::{client, login, music};

fn desktop_test_har() -> serde_json::Value {
    let path = std::env::var_os("QQMUSIC_TEST_HAR").expect("请通过 QQMUSIC_TEST_HAR 指定本地登录抓包");
    let text = std::fs::read_to_string(path).expect("无法读取本地 HAR");
    serde_json::from_str(text.trim_start_matches('\u{feff}')).expect("HAR 格式错误")
}

// 只在显式运行 PC 冒烟测试时，将本地 HAR 中的登录态放入测试进程的内存数据库。
fn use_desktop_test_login() {
    let har = desktop_test_har();
    let comm = har["log"]["entries"].as_array().expect("HAR 缺少请求列表").iter().find_map(|entry| {
        let post = &entry["request"]["postData"];
        let raw = post["text"].as_str().or_else(|| post["params"][0]["value"].as_str())?;
        let body: serde_json::Value = serde_json::from_str(raw).ok()?;
        let comm = &body["comm"];
        (!comm["authst"].as_str()?.is_empty()).then(|| comm.clone())
    }).expect("HAR 中没有登录态");
    client::core().set_session(Some(client::Session {
        uin: comm["uin"].as_str().expect("登录态缺少 uin").into(),
        musickey: comm["authst"].as_str().expect("登录态缺少 authst").into(),
        login_type: comm["tmeLoginType"].as_i64().expect("登录态缺少 tmeLoginType") as i32,
        nickname: String::new(),
        avatar_url: String::new(),
    })).unwrap();
}

#[tokio::test]
#[ignore]
async fn desktop_quality_tiers_for_reported_song() {
    use_desktop_test_login();
    let result = music::search_songs("月声尽，心灯明", 1, 10).await.unwrap();
    let song = result.songs.iter().find(|song| song.name.contains("月声尽") && song.name.contains("心灯明"))
        .expect("没有找到报告中的歌曲");
    let options = rust_lib_kanade::qq::quality::song_qualities(&song.mid).await.unwrap();
    let qualities: Vec<_> = options.iter().filter(|option| option.available).map(|option| option.quality).collect();
    assert!(!qualities.is_empty(), "当前测试账号没有可播放档位");
    assert!(options.iter().all(|option| !matches!(option.quality,
        Quality::Ogg640 | Quality::Ogg320 | Quality::Ogg192 | Quality::Ogg96 | Quality::Aac192 | Quality::Aac48
    )), "底层编码格式不应成为独立音质档位");
    println!("{}: playable quality tiers = {qualities:?}", song.name);
}

#[tokio::test]
#[ignore]
async fn desktop_dynamic_qualities() {
    use_desktop_test_login();
    let har = desktop_test_har();
    let mid = har["log"]["entries"].as_array().unwrap().iter().find_map(|entry| {
        let text = entry["response"]["content"]["text"].as_str()?;
        let response: serde_json::Value = serde_json::from_str(text).ok()?;
        response["music.search.SearchCgiService"]["data"]["body"]["song"]["list"][0]["mid"].as_str().map(str::to_string)
    }).expect("HAR 中没有搜索歌曲样本");
    let options = rust_lib_kanade::qq::quality::song_qualities(&mid).await.unwrap();
    assert!(options.len() > 4, "未返回扩展音质");
    assert!(options.iter().any(|option| option.quality == Quality::Master));
    assert!(options.iter().filter(|option| matches!(option.quality, Quality::Aicodec | Quality::Vinyl | Quality::Dts | Quality::Dolby)).all(|option| !option.available));
    let selected = options.iter().find(|option| option.available && matches!(option.quality, Quality::Master | Quality::Hires | Quality::Atmos | Quality::Atmos51 | Quality::Atmos71)).expect("当前样本没有可播放的扩展音质");
    let track = client::core().desktop_musicu("music.trackInfo.UniformRuleCtrl", "CgiGetTrackInfo", serde_json::json!({
        "ctx": 0, "client": 1, "types": [0], "modify_stamp": [0], "mids": [mid],
    })).await.unwrap();
    let media_mid = track["tracks"][0]["file"]["media_mid"].as_str().unwrap();
    let url = music::song_url(&mid, media_mid, selected.quality).await.unwrap();
    assert_eq!(url.quality, selected.quality);
    let response = reqwest::Client::new().get(&url.url).header("Range", "bytes=0-1023").send().await.unwrap();
    assert_eq!(response.status(), reqwest::StatusCode::PARTIAL_CONTENT);
    let bytes = response.bytes().await.unwrap();
    assert!(bytes.starts_with(b"fLaC") || bytes.starts_with(b"OggS"));
}

#[tokio::test]
#[ignore]
async fn desktop_search_pagination() {
    use_desktop_test_login();
    let first = music::search_songs("piano", 1, 5).await.unwrap();
    let second = music::search_songs("piano", 2, 5).await.unwrap();
    assert!(first.total >= 10);
    assert_eq!(first.songs.len(), 5);
    assert_eq!(second.songs.len(), 5);
    assert!(first.songs.iter().all(|song| !song.mid.is_empty() && !song.media_mid.is_empty() && !song.name.is_empty()));
    let first_mids: Vec<_> = first.songs.iter().map(|song| &song.mid).collect();
    let second_mids: Vec<_> = second.songs.iter().map(|song| &song.mid).collect();
    assert_ne!(first_mids, second_mids);
}

#[tokio::test]
#[ignore]
async fn desktop_search_and_stream() {
    use_desktop_test_login();
    let result = music::search_songs("纯音乐 钢琴", 1, 20).await.unwrap();
    let candidates: Vec<_> = result.songs.iter().filter(|song| !song.vip).take(3).collect();
    assert!(!candidates.is_empty(), "没有找到用于验证的普通歌曲");
    let mut playable = None;
    for song in candidates {
        if let Ok(url) = music::song_url(&song.mid, &song.media_mid, Quality::High).await {
            playable = Some(url);
            break;
        }
    }
    let url = playable.expect("普通歌曲均未返回 PC 播放链接");
    let response = reqwest::Client::new()
        .get(&url.url)
        .header("Range", "bytes=0-1023")
        .timeout(std::time::Duration::from_secs(15))
        .send()
        .await
        .unwrap();
    assert_eq!(response.status(), reqwest::StatusCode::PARTIAL_CONTENT);
    let bytes = response.bytes().await.unwrap();
    assert_eq!(bytes.len(), 1024);
    let is_mp3 = bytes.starts_with(b"ID3") || (bytes[0] == 0xff && bytes[1] & 0xe0 == 0xe0);
    let is_m4a = &bytes[4..8] == b"ftyp";
    assert!(is_mp3 || is_m4a, "播放链接返回的内容不是普通 MP3 / M4A 音频");
}

#[tokio::test]
#[ignore]
async fn anonymous_search() {
    assert!(client::core().session().is_none());
    let result = music::search_songs("piano", 1, 5).await.unwrap();
    assert!(result.total > 0);
    assert_eq!(result.songs.len(), 5);
}

#[tokio::test]
#[ignore]
async fn search_and_play() {
    let r = music::search_songs("周杰伦 晴天", 1, 5).await.unwrap();
    println!("total={} first={:?}", r.total, r.songs.first());
    let song = r.songs.iter().find(|s| !s.vip).unwrap_or(&r.songs[0]).clone();
    let url = music::song_url(&song.mid, &song.media_mid, Quality::High).await;
    println!("url for {} ({}): {:?}", song.name, song.mid, url);
    let lyric = music::lyric(&song.mid, song.id).await.unwrap();
    println!("lyric lines={} first={:?}", lyric.lines.len(), lyric.lines.get(5));
}

#[tokio::test]
#[ignore]
async fn free_song_url() {
    // 搜索若干首，找一首非会员歌曲验证播放链接
    let r = music::search_songs("纯音乐 钢琴", 1, 20).await.unwrap();
    for s in r.songs.iter().filter(|s| !s.vip).take(3) {
        println!("{} vip={} -> {:?}", s.name, s.vip, music::song_url(&s.mid, &s.media_mid, Quality::Standard).await.map(|u| (u.quality, u.url.len())));
    }
}

#[tokio::test]
#[ignore]
async fn toplists_and_playlists() {
    let groups = music::toplists().await.unwrap();
    let first = &groups[0].lists[0];
    println!("groups={} first={:?}", groups.len(), first);
    let d = music::toplist_detail(first.top_id, &first.period).await.unwrap();
    println!("toplist {} songs={} first={:?}", d.title, d.songs.len(), d.songs.first().map(|s| &s.name));
    let feed = music::recommend_feed().await.unwrap();
    let rec: Vec<_> = feed.sections.into_iter().flat_map(|s| s.playlists).collect();
    println!("recommend={} first={:?}", rec.len(), rec.first());
    // 未登录时“每日30首”入口的 id 是 "0"，取不到详情
    if let Some(p) = rec.iter().find(|p| p.id != "0") {
        let pd = music::playlist_detail(&p.id).await.unwrap();
        println!("playlist {} songs={}", pd.title, pd.songs.len());
    }
}

#[tokio::test]
#[ignore]
async fn qr_create() {
    let qr = login::create_qr().await.unwrap();
    println!("qr png bytes={} qrsig len={}", qr.image.len(), qr.qrsig.len());
    println!("poll: {:?}", login::poll_qr(&qr.qrsig).await);
}

#[tokio::test]
#[ignore]
async fn print_free_url() {
    let r = music::search_songs("夜的钢琴曲5", 1, 5).await.unwrap();
    let s = r.songs.iter().find(|s| !s.vip).unwrap();
    println!("URL={}", music::song_url(&s.mid, &s.media_mid, Quality::High).await.unwrap().url);
}


#[tokio::test]
#[ignore]
async fn wx_qr_create() {
    let qr = login::create_wx_qr().await.unwrap();
    println!("wx qr bytes={} head={:02x?} uuid={}", qr.image.len(), &qr.image[..4], qr.qrsig);
    println!("poll: {:?}", login::poll_wx_qr(&qr.qrsig).await);
}

/// 只读：自己的歌单里应能找到“我喜欢”（dirid 201）。不会发送写请求。
#[tokio::test]
#[ignore]
async fn desktop_my_playlists_include_liked() {
    use_desktop_test_login();
    let lists = rust_lib_kanade::qq::library::my_playlists().await.unwrap();
    assert!(lists.iter().any(|p| p.dir_id == rust_lib_kanade::qq::library::LIKED_DIR_ID), "没有找到我喜欢");
    let liked = rust_lib_kanade::qq::library::liked_song_ids().await.unwrap();
    println!("playlists={} liked songs={}", lists.len(), liked.len());
}

/// 使用写操作的请求封装调用只读接口，验证网关和请求结构，不改动账号数据。
#[tokio::test]
#[ignore]
async fn desktop_write_transport_with_readonly_call() {
    use_desktop_test_login();
    let data = client::core().desktop_write("music.vipcgi.VipBannerCgi", "QueryVipBanner", serde_json::json!({})).await.unwrap();
    assert!(data.get("banner").is_some(), "PC 请求封装没有返回预期的只读数据");
}

/// 与应用登录上下文相同的写请求封装调用只读接口，不改动账号数据。
#[tokio::test]
#[ignore]
async fn mobile_write_transport_with_readonly_call() {
    use_desktop_test_login();
    let data = client::core().mobile_write("music.vipcgi.VipBannerCgi", "QueryVipBanner", serde_json::json!({})).await.unwrap();
    assert!(data.get("banner").is_some(), "Android 写请求封装没有返回预期的只读数据");
}

/// 仅在用户同意后显式运行：只测试报告中的一首未收藏歌曲，随后恢复原状态。
#[tokio::test]
#[ignore]
async fn desktop_like_iris_and_restore() {
    use rust_lib_kanade::qq::library;
    assert_eq!(std::env::var("QQMUSIC_TEST_ALLOW_LIKE_IRIS").as_deref(), Ok("1"), "需要用户同意真实收藏并恢复");
    let path = std::env::var_os("QQMUSIC_TEST_SESSION_DB").expect("需要明确指定当前登录数据库");
    let db = rusqlite::Connection::open_with_flags(path, rusqlite::OpenFlags::SQLITE_OPEN_READ_ONLY).unwrap();
    let raw: String = db.query_row("SELECT value FROM kv WHERE key='session'", [], |row| row.get(0)).unwrap();
    let session: client::Session = serde_json::from_str(&raw).unwrap();
    drop(db);
    // 测试进程使用独立的内存 Store，不改动应用保存的登录态。
    client::core().set_session(Some(session)).unwrap();
    async fn liked() -> anyhow::Result<bool> {
        let data = client::core().mobile_write("music.musicasset.SongFavRead", "IsSongFanByMid",
            serde_json::json!({"v_songMid": ["004Ytrah01J9gS"]})).await?;
        data["m_fan"]["004Ytrah01J9gS"].as_bool().ok_or_else(|| anyhow::anyhow!("missing favorite status"))
    }
    assert!(!liked().await.unwrap(), "目标歌曲已经收藏，停止测试以保留原状态");
    let add = library::set_song_liked(634598738, true).await;
    let after_add = liked().await;
    // 初始状态已确认未收藏。成功或结果不明确时均恢复，不重试添加。
    let restore = if !matches!(after_add, Ok(false)) || add.is_ok() {
        library::set_song_liked(634598738, false).await
    } else { Ok(()) };
    let after_restore = liked().await;
    assert!(restore.is_ok() && matches!(after_restore, Ok(false)), "未能确认恢复未收藏状态，请在官方客户端核对该曲");
    assert!(add.is_ok(), "收藏请求失败：{add:?}");
    assert!(matches!(after_add, Ok(true)), "写入后未确认已收藏：{after_add:?}");
    println!("reported song: favorite confirmed, original unliked state restored");
}

/// 只读验证 ag-1 请求加密、签名、Cookie 以及响应解码，不提交收藏或取消收藏。
#[tokio::test]
#[ignore]
async fn signed_web_transport_with_readonly_call() {
    use_desktop_test_login();
    let data = client::core().signed_web_musicu("music.vipcgi.VipBannerCgi", "QueryVipBanner", serde_json::json!({})).await.unwrap();
    assert!(data.get("banner").is_some(), "签名加密通道没有返回预期的只读数据");
}
