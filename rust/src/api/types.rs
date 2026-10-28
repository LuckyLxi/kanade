//! 暴露给 Dart 的数据结构。

#[derive(Debug, Clone)]
pub struct Singer {
    pub mid: String,
    pub name: String,
}

#[derive(Debug, Clone)]
pub struct Song {
    pub id: i64,
    pub mid: String,
    pub name: String,
    pub singers: Vec<Singer>,
    pub album_mid: String,
    pub album_name: String,
    pub duration_secs: u32,
    /// 拼接播放文件名用的 media_mid，大多数情况下和 mid 一样。
    pub media_mid: String,
    pub cover_url: String,
    /// 需要会员才能播放。
    pub vip: bool,
    pub has_hq: bool,
    pub has_flac: bool,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Quality {
    /// AAC 96kbps（C400 .m4a），非会员最容易拿到
    Low,
    /// MP3 128kbps（M500）
    Standard,
    /// MP3 320kbps（M800）
    High,
    /// FLAC（F000）
    Lossless,
    Master,
    Hires,
    Atmos,
    Atmos51,
    Atmos71,
    Dolby,
    Dts,
    Ogg640,
    Ogg320,
    Ogg192,
    Ogg96,
    Aac192,
    Aac48,
    Aicodec,
    Vinyl,
}

/// 音质不可用的原因，文案由 Dart 侧翻译。
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum QualityUnavailableReason {
    /// 播放器暂不支持此格式
    Unsupported,
    /// 暂未通过播放验证
    Unverified,
    /// 当前账号无权限
    NoPermission,
    /// 播放设备受限
    DeviceRestricted,
    /// 暂无可用链接
    NoLink,
    /// 音质验证失败，请稍后重试
    VerifyFailed,
    /// 音频文件暂不可用
    FileUnavailable,
}

#[derive(Debug, Clone)]
pub struct QualityOption {
    pub quality: Quality,
    pub available: bool,
    /// 无权限、文件不可用或播放器尚未支持的原因；可用时为 None。
    pub reason: Option<QualityUnavailableReason>,
}

#[derive(Debug, Clone)]
pub struct SongUrl {
    pub url: String,
    /// 实际拿到的音质（请求的音质不可用时会自动降级）。
    pub quality: Quality,
}

/// 本地缓存的歌曲文件。
#[derive(Debug, Clone)]
pub struct CachedAudio {
    pub path: String,
    pub quality: Quality,
}

#[derive(Debug, Clone)]
pub struct LyricLine {
    pub time_ms: u32,
    pub text: String,
    /// 翻译，没有就是空字符串。
    pub trans: String,
}

#[derive(Debug, Clone)]
pub struct Lyric {
    pub lines: Vec<LyricLine>,
    /// 纯文本歌词（没有时间轴），lines 为空时用它。
    pub plain: String,
}

#[derive(Debug, Clone)]
pub struct PlaylistBrief {
    pub id: String,
    pub title: String,
    pub cover_url: String,
    pub song_count: u32,
    pub play_count: u64,
    pub creator: String,
}

#[derive(Debug, Clone)]
pub struct PlaylistDetail {
    pub id: String,
    pub title: String,
    pub cover_url: String,
    pub description: String,
    pub creator: String,
    pub songs: Vec<Song>,
}

#[derive(Debug, Clone)]
pub struct TopList {
    pub top_id: i64,
    pub title: String,
    pub cover_url: String,
    pub period: String,
    /// 榜单前几名的预览，形如“歌名 - 歌手”。
    pub preview: Vec<String>,
}

#[derive(Debug, Clone)]
pub struct TopListGroup {
    pub name: String,
    pub lists: Vec<TopList>,
}

#[derive(Debug, Clone)]
pub struct TopListDetail {
    pub top_id: i64,
    pub title: String,
    pub cover_url: String,
    pub description: String,
    pub period: String,
    pub songs: Vec<Song>,
}

#[derive(Debug, Clone)]
pub struct SearchResult {
    pub songs: Vec<Song>,
    pub total: u32,
}

/// 推荐页的一个区块；一个区块要么是歌曲，要么是歌单。
#[derive(Debug, Clone)]
pub struct RecommendSection {
    pub title: String,
    pub songs: Vec<Song>,
    pub playlists: Vec<PlaylistBrief>,
}

#[derive(Debug, Clone)]
pub struct RecommendFeed {
    pub sections: Vec<RecommendSection>,
    /// “刷歌模式”入口给的起始歌曲 id，传给 `get_radar_songs`；没有入口时为空。
    pub radar_seed: Vec<i64>,
}

#[derive(Debug, Clone)]
pub struct HotKeyword {
    pub title: String,
    /// 实际拿去搜索的词，通常和 title 一样。
    pub query: String,
    /// 比如“正在热搜”，可能为空。
    pub description: String,
}

#[derive(Debug, Clone)]
pub struct HotSearch {
    pub hot: Vec<HotKeyword>,
    /// 个性化的“猜你想搜”，只有登录后才有。
    pub recommended: Vec<HotKeyword>,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum SuggestionKind {
    Song,
    Singer,
    Album,
}

#[derive(Debug, Clone)]
pub struct SearchSuggestion {
    pub kind: SuggestionKind,
    pub title: String,
    /// 歌手名；歌手条目为空。
    pub subtitle: String,
}

#[derive(Debug, Clone)]
pub struct UserInfo {
    pub uin: String,
    pub nickname: String,
    pub avatar_url: String,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum LoginKind {
    Qq,
    Wechat,
    /// 用 QQ 音乐 App 授权，沿用 App 当前登录的账号（QQ 或微信）。
    QqMusic,
}

#[derive(Debug, Clone)]
pub struct QrCode {
    /// 二维码图片字节（QQ 是 PNG，微信是 JPEG）。
    pub image: Vec<u8>,
    /// 轮询时原样传回（QQ 是 qrsig，微信是 uuid）。
    pub qrsig: String,
    /// 同一台手机跳转登录用的链接：`create_qq_app_login` 的票据是 txz.qq.com 链接，
    /// QQ 音乐登录是授权页地址；其余为空。
    pub url: String,
}

#[derive(Debug, Clone)]
pub enum QrStatus {
    Waiting,
    Scanned,
    Expired,
    Refused,
    Success { user: UserInfo },
}

#[derive(Debug, Clone)]
pub struct AlbumBrief {
    pub mid: String,
    pub name: String,
    pub cover_url: String,
    /// 形如 2005-08-12，可能为空。
    pub publish_date: String,
    pub singer_name: String,
}

#[derive(Debug, Clone)]
pub struct SingerDetail {
    pub mid: String,
    pub name: String,
    pub avatar_url: String,
    pub description: String,
    /// 第一页热门歌曲，更多用 `get_singer_songs` 翻页。
    pub songs: Vec<Song>,
    pub song_total: u32,
    pub albums: Vec<AlbumBrief>,
    pub album_total: u32,
}

#[derive(Debug, Clone)]
pub struct AlbumDetail {
    pub mid: String,
    /// 数字 id，取评论用。
    pub id: i64,
    pub name: String,
    pub cover_url: String,
    pub description: String,
    pub publish_date: String,
    pub company: String,
    pub singers: Vec<Singer>,
    pub songs: Vec<Song>,
}

/// 评论挂在哪类对象下面。
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum CommentTarget {
    /// id 是歌曲的数字 id
    Song,
    /// id 是专辑的数字 id
    Album,
}

#[derive(Debug, Clone)]
pub struct Comment {
    pub id: String,
    /// 翻页时传回的游标。
    pub seq_no: String,
    pub nick: String,
    pub avatar_url: String,
    pub content: String,
    /// Unix 秒。
    pub time_secs: i64,
    pub praise_count: u32,
    pub reply_count: u32,
    /// 回复列表里被回复的人，没有就是空字符串。
    pub reply_to: String,
}

#[derive(Debug, Clone)]
pub struct CommentPage {
    /// 只有第一页有。
    pub hot: Vec<Comment>,
    pub latest: Vec<Comment>,
    pub total: u32,
    pub has_more: bool,
}

/// 当前账号自己创建的歌单，加歌和红心用。
#[derive(Debug, Clone)]
pub struct MyPlaylist {
    /// 201 是“我喜欢”。
    pub dir_id: i64,
    pub tid: i64,
    pub name: String,
    pub cover_url: String,
    pub song_count: u32,
}
