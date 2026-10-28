//! Dart 侧调用的接口。具体实现在 crate::qq。
//! 错误统一转换成 ApiError 错误码，由 Dart 侧翻译。

use crate::api::error::ApiError;
use crate::api::types::*;
use crate::qq::audio_cache::cache;
use crate::qq::{client, detail, library, login, music, quality};

#[flutter_rust_bridge::frb(init)]
pub fn init_app() {
    flutter_rust_bridge::setup_default_user_utils();
}

/// 设置数据目录（SQLite 缓存和登录态存放处）。启动时调用一次。
pub fn init_core(data_dir: String) -> Result<(), ApiError> {
    Ok(client::init(std::path::Path::new(&data_dir))?)
}

pub async fn search_songs(keyword: String, page: u32, page_size: u32) -> Result<SearchResult, ApiError> {
    Ok(music::search_songs(&keyword, page, page_size).await?)
}

pub async fn get_hot_search() -> Result<HotSearch, ApiError> {
    Ok(music::hot_search().await?)
}

pub async fn get_search_suggestions(query: String) -> Result<Vec<SearchSuggestion>, ApiError> {
    Ok(music::search_suggestions(&query).await?)
}

pub async fn get_song_url(mid: String, media_mid: String, quality: Quality) -> Result<SongUrl, ApiError> {
    Ok(music::song_url(&mid, &media_mid, quality).await?)
}

/// 比 `quality` 低一档的音质；已是最低档时为 None。拿到链接却播不了时用来降级重试。
#[flutter_rust_bridge::frb(sync)]
pub fn lower_quality(quality: Quality) -> Option<Quality> {
    quality::lower(quality)
}

/// 本地缓存的这首歌这个音质的文件路径。
#[flutter_rust_bridge::frb(sync)]
pub fn get_cached_audio(mid: String, quality: Quality) -> Option<String> {
    cache().lookup(&mid, quality)
}

/// 这首歌任一音质的缓存（没网时用）。
#[flutter_rust_bridge::frb(sync)]
pub fn get_any_cached_audio(mid: String) -> Option<CachedAudio> {
    cache().lookup_any(&mid).map(|(path, quality)| CachedAudio { path, quality })
}

/// 缓存文件播不了时删掉。
#[flutter_rust_bridge::frb(sync)]
pub fn remove_cached_audio(mid: String, quality: Quality) {
    cache().remove(&mid, quality)
}

/// 把播放链接换成边播边存的本机地址；缓存关闭时原样返回。
#[flutter_rust_bridge::frb(sync)]
pub fn stream_audio(mid: String, quality: Quality, url: String) -> Result<String, ApiError> {
    Ok(cache().stream(&mid, quality, &url)?)
}

/// 歌曲缓存上限（MB），0 表示关闭。
#[flutter_rust_bridge::frb(sync)]
pub fn get_audio_cache_limit_mb() -> i64 {
    cache().limit_mb()
}

#[flutter_rust_bridge::frb(sync)]
pub fn set_audio_cache_limit_mb(mb: i64) -> Result<(), ApiError> {
    Ok(cache().set_limit_mb(mb)?)
}

/// 歌曲缓存占用的字节数。
pub fn get_audio_cache_size() -> i64 {
    cache().size()
}

pub fn clear_audio_cache() {
    cache().clear()
}

/// 接口数据缓存占用的字节数。
pub fn get_api_cache_size() -> i64 {
    client::core().store.cache_size()
}

pub async fn get_song_qualities(mid: String) -> Result<Vec<QualityOption>, ApiError> {
    Ok(quality::song_qualities(&mid).await?)
}

pub async fn get_lyric(mid: String, id: i64) -> Result<Lyric, ApiError> {
    Ok(music::lyric(&mid, id).await?)
}

pub async fn get_toplists() -> Result<Vec<TopListGroup>, ApiError> {
    Ok(music::toplists().await?)
}

pub async fn get_toplist_detail(top_id: i64, period: String) -> Result<TopListDetail, ApiError> {
    Ok(music::toplist_detail(top_id, &period).await?)
}

pub async fn get_recommend_feed() -> Result<RecommendFeed, ApiError> {
    Ok(music::recommend_feed().await?)
}

/// 猜你喜欢电台的下一批歌（需要登录）。
pub async fn get_guess_you_like() -> Result<Vec<Song>, ApiError> {
    Ok(music::guess_you_like().await?)
}

/// 刷歌模式的第 `page` 批歌，`seed` 来自 `RecommendFeed.radar_seed`。
pub async fn get_radar_songs(seed: Vec<i64>, page: u32) -> Result<Vec<Song>, ApiError> {
    Ok(music::radar_songs(&seed, page).await?)
}

pub async fn get_new_songs() -> Result<Vec<Song>, ApiError> {
    Ok(music::new_songs().await?)
}

pub async fn get_playlist_detail(id: String) -> Result<PlaylistDetail, ApiError> {
    Ok(music::playlist_detail(&id).await?)
}

pub async fn get_user_playlists() -> Result<Vec<PlaylistBrief>, ApiError> {
    Ok(music::user_playlists().await?)
}

/// 歌手资料，附带第一页歌曲和专辑。
pub async fn get_singer_detail(mid: String) -> Result<SingerDetail, ApiError> {
    Ok(detail::singer_detail(&mid).await?)
}

/// 歌手歌曲翻页，`begin` 从 0 开始。
pub async fn get_singer_songs(mid: String, begin: u32, num: u32) -> Result<Vec<Song>, ApiError> {
    Ok(detail::singer_songs(&mid, begin, num).await?)
}

pub async fn get_singer_albums(mid: String, begin: u32, num: u32) -> Result<Vec<AlbumBrief>, ApiError> {
    Ok(detail::singer_albums(&mid, begin, num).await?)
}

pub async fn get_album_detail(mid: String) -> Result<AlbumDetail, ApiError> {
    Ok(detail::album_detail(&mid).await?)
}

/// 评论第 `page` 页（从 0 开始），`last_seq_no` 是上一页最后一条的 `seq_no`，第一页传空。
pub async fn get_comments(target: CommentTarget, id: i64, page: u32, last_seq_no: String) -> Result<CommentPage, ApiError> {
    Ok(detail::comments_page(target, id, page, &last_seq_no).await?)
}

pub async fn get_comment_replies(root_id: String, page: u32, last_seq_no: String) -> Result<CommentPage, ApiError> {
    Ok(detail::comment_replies(&root_id, page, &last_seq_no).await?)
}

/// 自己创建的歌单（需要登录），加入歌单时选择用。
pub async fn get_my_playlists() -> Result<Vec<MyPlaylist>, ApiError> {
    Ok(library::my_playlists().await?)
}

/// “我喜欢”里的歌曲 id（需要登录）。
pub async fn get_liked_song_ids() -> Result<Vec<i64>, ApiError> {
    Ok(library::liked_song_ids().await?)
}

/// 红心 / 取消红心（需要登录）。
pub async fn set_song_liked(song_id: i64, liked: bool) -> Result<(), ApiError> {
    Ok(library::set_song_liked(song_id, liked).await?)
}

pub async fn add_song_to_playlist(dir_id: i64, song_id: i64) -> Result<(), ApiError> {
    Ok(library::add_to_playlist(dir_id, song_id).await?)
}

pub async fn remove_song_from_playlist(dir_id: i64, song_id: i64) -> Result<(), ApiError> {
    Ok(library::remove_from_playlist(dir_id, song_id).await?)
}

pub async fn create_login_qr(kind: LoginKind) -> Result<QrCode, ApiError> {
    Ok(match kind {
        LoginKind::Qq => login::create_qr().await?,
        LoginKind::Wechat => login::create_wx_qr().await?,
        LoginKind::QqMusic => login::create_tme_qr().await?,
    })
}

/// 同一台手机跳转 QQ 登录的票据；拿到后用 `poll_login_qr(LoginKind::Qq, ...)` 轮询。
pub async fn create_qq_app_login() -> Result<QrCode, ApiError> {
    Ok(login::create_app_qr().await?)
}

pub async fn poll_login_qr(kind: LoginKind, qrsig: String) -> Result<QrStatus, ApiError> {
    Ok(match kind {
        LoginKind::Qq => login::poll_qr(&qrsig).await?,
        LoginKind::Wechat => login::poll_wx_qr(&qrsig).await?,
        LoginKind::QqMusic => login::poll_tme_qr(&qrsig).await?,
    })
}

pub async fn login_with_cookie(cookie: String) -> Result<UserInfo, ApiError> {
    Ok(login::login_with_cookie(&cookie).await?)
}

#[flutter_rust_bridge::frb(sync)]
pub fn current_user() -> Option<UserInfo> {
    client::core().session().map(|s| login::user_of(&s))
}

pub fn logout() -> Result<(), ApiError> {
    Ok(client::core().set_session(None)?)
}

pub fn clear_cache() -> Result<(), ApiError> {
    Ok(client::core().store.cache_clear()?)
}

/// 读取界面偏好（如语言），存放在 kv 表的 `pref:` 前缀下。
#[flutter_rust_bridge::frb(sync)]
pub fn get_pref(key: String) -> Option<String> {
    client::core().store.kv_get(&format!("pref:{key}"))
}

#[flutter_rust_bridge::frb(sync)]
pub fn set_pref(key: String, value: String) -> Result<(), ApiError> {
    Ok(client::core().store.kv_set(&format!("pref:{key}"), &value)?)
}
