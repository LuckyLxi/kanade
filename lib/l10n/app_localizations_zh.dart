// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Chinese (`zh`).
class AppLocalizationsZh extends AppLocalizations {
  AppLocalizationsZh([String locale = 'zh']) : super(locale);

  @override
  String get appTitle => 'Kanade';

  @override
  String get tabDiscover => '发现';

  @override
  String get tabSearch => '搜索';

  @override
  String get tabMine => '我的';

  @override
  String get windowMinimize => '最小化';

  @override
  String get windowMaximize => '最大化';

  @override
  String get windowRestore => '向下还原';

  @override
  String get windowClose => '关闭';

  @override
  String get language => '语言';

  @override
  String get languageSystem => '跟随系统';

  @override
  String get retry => '重试';

  @override
  String get cancel => '取消';

  @override
  String loadFailed(String error) {
    return '加载失败：$error';
  }

  @override
  String get recommendedPlaylists => '推荐歌单';

  @override
  String get recommendedSongs => '为你推荐';

  @override
  String get radioGuessYouLike => '猜你喜欢';

  @override
  String get radioRadar => '刷歌模式';

  @override
  String radioFailed(String error) {
    return '电台没取到歌：$error';
  }

  @override
  String get newSongs => '新歌首发';

  @override
  String viewAllSongs(int count) {
    return '查看全部 $count 首';
  }

  @override
  String updatedAt(String period) {
    return '更新于 $period';
  }

  @override
  String playAll(int count) {
    return '播放全部 ($count)';
  }

  @override
  String songCount(int count) {
    return '$count 首';
  }

  @override
  String get searchHint => '搜索歌曲、歌手';

  @override
  String get searchPrompt => '输入关键词后回车搜索';

  @override
  String get searchHot => '热搜榜';

  @override
  String get searchRecommended => '猜你想搜';

  @override
  String get searchNoResults => '没有找到相关歌曲';

  @override
  String searchFailed(String error) {
    return '搜索失败：$error';
  }

  @override
  String searchTotal(int count) {
    return '共 $count 首';
  }

  @override
  String get quality => '音质';

  @override
  String get qualityLoading => '正在获取音质';

  @override
  String qualityFailed(String error) {
    return '音质获取失败：$error';
  }

  @override
  String get qualityFailedRetry => '音质获取失败，点击重试';

  @override
  String get qualityNoneForSong => '歌曲暂无可用音质';

  @override
  String get qualityNone => '暂无可用音质';

  @override
  String qualityWithReason(String quality, String reason) {
    return '$quality（$reason）';
  }

  @override
  String qualityDowngraded(String actual, String requested) {
    return '$actual（无权获取$requested）';
  }

  @override
  String get qualityLow => '流畅 96k';

  @override
  String get qualityStandard => '标准 128k';

  @override
  String get qualityHigh => '高品质 320k';

  @override
  String get qualityLossless => '无损 FLAC';

  @override
  String get qualityMaster => '臻品母带';

  @override
  String get qualityAtmos => '臻品音质';

  @override
  String get qualityAtmos51 => '臻品全景声 5.1';

  @override
  String get qualityAtmos71 => '臻品全景声 7.1';

  @override
  String get qualityDolby => '杜比全景声';

  @override
  String get qualityOgg320 => '高品质 OGG 320k';

  @override
  String get qualityAiCodec => 'AI 音质';

  @override
  String get qualityVinyl => '黑胶';

  @override
  String get reasonUnsupported => '播放器暂不支持此格式';

  @override
  String get reasonUnverified => '暂未通过播放验证';

  @override
  String get reasonNoPermission => '当前账号无权限';

  @override
  String get reasonDeviceRestricted => '播放设备受限';

  @override
  String get reasonNoLink => '暂无可用链接';

  @override
  String get reasonVerifyFailed => '音质验证失败，请稍后重试';

  @override
  String get reasonFileUnavailable => '音频文件暂不可用';

  @override
  String get logout => '退出登录';

  @override
  String get loginPrompt => '登录后可以同步你的歌单，并播放账号有权限的歌曲';

  @override
  String get loginQq => 'QQ 扫码登录';

  @override
  String get loginWechat => '微信扫码登录';

  @override
  String get loginQqMusic => 'QQ 音乐授权登录';

  @override
  String get loginCookie => '使用 Cookie 登录';

  @override
  String get noPlaylists => '还没有歌单';

  @override
  String get qrLoading => '正在获取二维码…';

  @override
  String get qrScanHintQq => '请使用手机 QQ 扫码';

  @override
  String get qrScanHintWechat => '请使用手机微信扫码';

  @override
  String get qrScanHintQqMusic => '请使用 QQ 音乐 App 扫码，将登录 App 当前的账号';

  @override
  String get qrScanned => '已扫码，请在手机上确认';

  @override
  String get qrExpired => '二维码已过期';

  @override
  String get qrRefused => '已在手机上取消登录';

  @override
  String get qrRefresh => '刷新二维码';

  @override
  String get qrOpenQq => '跳转 QQ 登录';

  @override
  String get qrQqNotInstalled => '无法打开 QQ，请确认已安装手机 QQ';

  @override
  String get qrSaveImage => '保存二维码';

  @override
  String get qrSavedQq => '已保存到相册，在 QQ「扫一扫」右上角选择相册图片即可';

  @override
  String get qrOpenQqMusic => '跳转 QQ 音乐授权';

  @override
  String get qrQqMusicNotInstalled => '无法打开 QQ 音乐，请确认已安装 QQ 音乐 App';

  @override
  String get qrWechatSameDeviceTip =>
      '微信不支持本机登录。如果 QQ 音乐 App 登的是微信号，可以改用「QQ 音乐授权登录」';

  @override
  String qrSaveFailed(String error) {
    return '保存失败：$error';
  }

  @override
  String qrFailed(String error) {
    return '获取二维码失败：$error';
  }

  @override
  String get cookieLoginTitle => 'Cookie 登录';

  @override
  String get cookieLoginHint =>
      '在浏览器登录 y.qq.com 后，从开发者工具复制 Cookie 粘贴到这里（需要包含 uin 和 qm_keyst）。';

  @override
  String get login => '登录';

  @override
  String get swipeForLyrics => '← 左滑查看歌词';

  @override
  String get noLyrics => '暂无歌词';

  @override
  String get modeSequence => '列表循环';

  @override
  String get modeRepeatOne => '单曲循环';

  @override
  String get modeShuffle => '随机播放';

  @override
  String get lyrics => '歌词';

  @override
  String get upNext => '接下来播放';

  @override
  String get volume => '音量';

  @override
  String get queue => '播放队列';

  @override
  String playbackError(String error) {
    return '播放出错：$error';
  }

  @override
  String songUnplayable(String song, String error) {
    return '《$song》无法播放：$error';
  }

  @override
  String get errorNotLoggedIn => '尚未登录';

  @override
  String get errorNoPlayableUrl => '没有可用的播放链接（可能需要登录或会员）';

  @override
  String errorLoginFailed(String detail) {
    return '登录失败：$detail';
  }

  @override
  String errorInvalidCookie(String field) {
    return 'Cookie 里没有 $field';
  }

  @override
  String errorServer(String code, String api) {
    return '服务器返回错误码 $code（$api）';
  }

  @override
  String errorBadResponse(String detail) {
    return '服务器响应异常：$detail';
  }

  @override
  String errorNetwork(String detail) {
    return '网络错误：$detail';
  }

  @override
  String errorInternal(String detail) {
    return '内部错误：$detail';
  }

  @override
  String get like => '收藏到我喜欢';

  @override
  String get unlike => '取消喜欢';

  @override
  String get liked => '已添加到我喜欢';

  @override
  String get unliked => '已取消喜欢';

  @override
  String get addToPlaylist => '加入歌单';

  @override
  String addedToPlaylist(String name) {
    return '已加入「$name」';
  }

  @override
  String get removeFromPlaylist => '从歌单中删除';

  @override
  String removedFromPlaylist(String name) {
    return '已从「$name」删除';
  }

  @override
  String actionFailed(String error) {
    return '操作失败：$error';
  }

  @override
  String get loginRequired => '请先在「我的」页登录';

  @override
  String get noMyPlaylists => '没有可加入的歌单';

  @override
  String get more => '更多';

  @override
  String singerNamed(String name) {
    return '歌手：$name';
  }

  @override
  String albumNamed(String name) {
    return '专辑：$name';
  }

  @override
  String get comments => '评论';

  @override
  String get hotComments => '热门评论';

  @override
  String get latestComments => '最新评论';

  @override
  String commentTotal(int count) {
    return '共 $count 条评论';
  }

  @override
  String get noComments => '还没有评论';

  @override
  String get replies => '回复';

  @override
  String viewReplies(int count) {
    return '查看 $count 条回复';
  }

  @override
  String replyTo(String name) {
    return '回复 $name：';
  }

  @override
  String get loadMore => '加载更多';

  @override
  String get tabSongs => '歌曲';

  @override
  String get tabAlbums => '专辑';

  @override
  String publishedOn(String date) {
    return '发行于 $date';
  }

  @override
  String get settings => '设置';

  @override
  String get settingsGeneral => '通用';

  @override
  String get settingsCache => '缓存';

  @override
  String get settingsAccount => '账号';

  @override
  String get defaultQuality => '默认音质';

  @override
  String get defaultQualityHint => '选的音质没有或播不了时会自动降低';

  @override
  String get audioCacheLimit => '歌曲缓存上限';

  @override
  String get audioCacheLimitHint => '边听边存，超出后删除最久没听的歌';

  @override
  String get audioCacheOff => '关闭';

  @override
  String get audioCacheCustom => '自定义';

  @override
  String get audioCacheCustomTitle => '自定义缓存上限';

  @override
  String get audioCacheCustomUnit => 'MB';

  @override
  String get audioCacheSize => '歌曲缓存';

  @override
  String get apiCacheSize => '其他缓存';

  @override
  String get apiCacheSizeHint => '歌单、搜索、歌词等数据';

  @override
  String get clear => '清除';

  @override
  String get clearAudioCacheConfirm => '清除所有已缓存的歌曲？';

  @override
  String get clearApiCacheConfirm => '清除歌单、搜索、歌词等缓存数据？';

  @override
  String get cacheCleared => '已清除';

  @override
  String get logoutConfirm => '确定退出登录？';

  @override
  String get ok => '确定';

  @override
  String get likedSongs => '我喜欢';

  @override
  String get recentPlays => '最近播放';

  @override
  String get myPlaylists => '我的歌单';

  @override
  String get playlistsCreated => '创建的';

  @override
  String get playlistsCollected => '收藏的';

  @override
  String get shufflePlay => '随机播放';

  @override
  String get seeAll => '全部';
}
