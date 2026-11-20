import 'dart:io';

import 'package:flutter/painting.dart';

import '../src/rust/api/types.dart';

/// 有些图片还是 http 链接，Android 默认不允许明文请求，统一换成 https。
String httpsUrl(String url) => url.replaceFirst('http://', 'https://');

String singerNames(Song s) => s.singers.map((e) => e.name).join(' / ');

/// 播放页、系统媒体卡片用的 500px 大封面。
String bigCoverUrl(Song s) =>
    httpsUrl(s.coverUrl).replaceFirst('300x300', '500x500');

/// 恢复下载时从歌曲文件里取出的封面存在本地，地址是文件路径。
bool isFileCover(String url) => url.isNotEmpty && !url.contains('://');

ImageProvider coverImage(String url) =>
    isFileCover(url) ? FileImage(File(url)) : NetworkImage(httpsUrl(url));

/// 系统媒体卡片用的大封面地址。
Uri coverUri(Song s) =>
    isFileCover(s.coverUrl) ? Uri.file(s.coverUrl) : Uri.parse(bigCoverUrl(s));

/// 恢复下载时导入的本地歌（Rust 侧 download::is_local），没有 QQ 音乐的歌曲 id。
bool isLocalSong(Song s) => s.mid.startsWith('local:');

/// “我喜欢”在每个账号下的目录编号都是 201（Rust 侧见 qq/library.rs 的 LIKED_DIR_ID）。
bool isLikedPlaylist(MyPlaylist p) => p.dirId == 201;

/// 歌手头像，规则和 Rust 侧 parse::singer_cover 一致。
String singerAvatar(String mid) =>
    'https://y.gtimg.cn/music/photo_new/T001R300x300M000$mid.jpg';
