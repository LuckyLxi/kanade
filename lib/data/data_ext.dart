import '../src/rust/api/types.dart';

/// 有些图片还是 http 链接，Android 默认不允许明文请求，统一换成 https。
String httpsUrl(String url) => url.replaceFirst('http://', 'https://');

String singerNames(Song s) => s.singers.map((e) => e.name).join(' / ');

/// 播放页、系统媒体卡片用的 500px 大封面。
String bigCoverUrl(Song s) => httpsUrl(s.coverUrl).replaceFirst('300x300', '500x500');

/// “我喜欢”在每个账号下的目录编号都是 201（Rust 侧见 qq/library.rs 的 LIKED_DIR_ID）。
bool isLikedPlaylist(MyPlaylist p) => p.dirId == 201;
