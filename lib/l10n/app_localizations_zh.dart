// ignore_for_file: deprecated_member_use

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
  String get pressBackAgainToExit => '再按一次退出';

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
  String get themeToDark => '切换到深色';

  @override
  String get themeToLight => '切换到浅色';

  @override
  String get retry => '重试';

  @override
  String get loading => '加载中';

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
  String get discoverRecommend => '推荐';

  @override
  String get discoverToplists => '排行榜';

  @override
  String get radioGuessYouLike => '猜你喜欢';

  @override
  String get radioRadar => '刷歌模式';

  @override
  String radioFailed(String error) {
    return '电台没取到歌：$error';
  }

  @override
  String feedColumnTitle(String name) {
    return '「$name」的专属乐流';
  }

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
  String get playAllTitle => '播放全部';

  @override
  String get recentSearchHint => '在最近播放中搜索';

  @override
  String get recentNewestFirst => '从新到旧';

  @override
  String songCount(int count) {
    return '$count 首';
  }

  @override
  String get searchHint => '搜索歌曲、歌手、专辑、视频';

  @override
  String get recognizeSong => '听歌识曲';

  @override
  String get recognizeListening => '正在听…';

  @override
  String get recognizeHint => '让麦克风靠近正在播放的音乐';

  @override
  String recognizeElapsed(int seconds) {
    return '$seconds 秒';
  }

  @override
  String get recognizeNotFound => '没听出来是哪首歌';

  @override
  String get recognizeAgain => '再识别一次';

  @override
  String get recognizeNoMic => '没有麦克风权限';

  @override
  String get recognizeBubble => '开启悬浮按钮';

  @override
  String get recognizeBubbleHint => '切到别的软件也能接着识曲';

  @override
  String get recognizeSourceMic => '麦克风';

  @override
  String get recognizeSourcePhone => '手机内声音';

  @override
  String get recognizeSourceComputer => '电脑内声音';

  @override
  String get recognizeHintPhone => '识别这台手机正在播放的声音';

  @override
  String get recognizeHintComputer => '识别这台电脑正在播放的声音';

  @override
  String get recognizeCaptureDenied => '需要授权才能录手机内声音，已改用麦克风';

  @override
  String get recognizeSilent => '没录到声音，可能没在播放，或者该应用不允许录制';

  @override
  String get recognizePaused => '已暂停';

  @override
  String get recognizeTapResume => '点图标重新开始听';

  @override
  String get searchPrompt => '输入关键词后回车搜索';

  @override
  String get searchKindAll => '综合';

  @override
  String get searchMoreSongs => '更多单曲';

  @override
  String get searchRelated => '相关搜索';

  @override
  String get searchRecommended => '猜你想搜';

  @override
  String get filterSongsHint => '搜索歌名、歌手';

  @override
  String get locateCurrentSong => '定位到正在播放';

  @override
  String get searchNoResults => '没有找到相关结果';

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
  String get notLoggedIn => '未登录';

  @override
  String get loginMethods => '选择登录方式';

  @override
  String get loginQqHint => '用手机 QQ 扫一扫';

  @override
  String get loginWechatHint => '用微信扫一扫';

  @override
  String get loginQqMusicHint => '在 QQ 音乐 App 里确认';

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
  String get lyricOptions => '歌词显示';

  @override
  String get lyricWordByWord => '逐字歌词';

  @override
  String get lyricWordByWordHint => '跟着演唱一个字一个字点亮';

  @override
  String get lyricRomaji => '罗马音';

  @override
  String get lyricRomajiHint => '日语、韩语歌在歌词下面显示读音';

  @override
  String get lyricTranslation => '歌词翻译';

  @override
  String get lyricTranslationHint => '外语歌在歌词下面显示中文翻译';

  @override
  String get lyricKeepScreenOn => '歌词页屏幕常亮';

  @override
  String get lyricKeepScreenOnHint => '停在歌词页时屏幕不会自动熄灭';

  @override
  String get softwareRendering => '禁用硬件加速';

  @override
  String get softwareRenderingHint => '不用显卡绘制界面，可能会变卡，重启 Kanade 后生效';

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
  String get playNext => '下一首播放';

  @override
  String get queuedNext => '已添加到下一首播放';

  @override
  String get alreadyPlaying => '正在播放这首歌';

  @override
  String get volume => '音量';

  @override
  String get queue => '播放队列';

  @override
  String get removeFromQueue => '从队列移除';

  @override
  String get reorderQueue => '拖动调整顺序';

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
  String get previousSong => '上一首';

  @override
  String get nextSong => '下一首';

  @override
  String get play => '播放';

  @override
  String get pause => '暂停';

  @override
  String get like => '收藏到我喜欢';

  @override
  String get unlike => '取消喜欢';

  @override
  String get likeShort => '喜欢';

  @override
  String get likedShort => '已喜欢';

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
  String get singerLabel => '歌手';

  @override
  String get albumLabel => '专辑';

  @override
  String get comments => '评论';

  @override
  String get commentsRecommended => '推荐';

  @override
  String get noComments => '还没有评论';

  @override
  String commentCount(String count) {
    return '$count 条评论';
  }

  @override
  String get timeJustNow => '刚刚';

  @override
  String timeMinutesAgo(int count) {
    return '$count 分钟前';
  }

  @override
  String timeHoursAgo(int count) {
    return '$count 小时前';
  }

  @override
  String timeDaysAgo(int count) {
    return '$count 天前';
  }

  @override
  String get replies => '回复';

  @override
  String replyCount(int count) {
    return '$count 条回复';
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
  String get settingsPlayback => '播放';

  @override
  String get settingsAppearance => '外观';

  @override
  String get settingsStorage => '存储';

  @override
  String get settingsAccount => '账号';

  @override
  String get theme => '主题';

  @override
  String get themeSystem => '跟随系统';

  @override
  String get themeLight => '浅色';

  @override
  String get themeDark => '深色';

  @override
  String audioCacheOfLimit(Object limit) {
    return '/ 上限 $limit';
  }

  @override
  String get audioCacheDisabled => '缓存已关闭';

  @override
  String get foryouSettings => '自定义推荐页';

  @override
  String get foryouSettingsHint => '首页最上面那排卡片显示哪些，和手机版 QQ 音乐同步';

  @override
  String get foryouChoose => '可选择显示/隐藏以下内容';

  @override
  String get save => '保存';

  @override
  String get foryouSaved => '已保存';

  @override
  String foryouSaveFailed(Object error) {
    return '保存失败：$error';
  }

  @override
  String get defaultQuality => '默认音质';

  @override
  String get defaultQualityHint => '选的音质没有或播不了时会自动降低';

  @override
  String get songFade => '播放过渡';

  @override
  String get songFadeHint => '切歌、暂停和继续播放时音量渐变';

  @override
  String get floatOutput => '32 位浮点输出';

  @override
  String get floatOutputHint => '以 32 位浮点格式交给系统，多数歌听不出差别';

  @override
  String get songFadeOff => '关闭';

  @override
  String songFadeSeconds(Object seconds) {
    return '$seconds 秒';
  }

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
  String get sessionEndedTitle => '登录已失效';

  @override
  String get sessionExpired => '登录已超过有效期，已自动退出。重新登录后就能继续同步歌单和播放会员歌曲。';

  @override
  String get sessionRevoked => '登录还没到期就被 QQ 音乐注销了，已自动退出。';

  @override
  String get sessionRejected => 'QQ 音乐不再接受当前的登录，已自动退出。';

  @override
  String get sessionCausesTitle => '可能的原因';

  @override
  String get sessionCauseOtherDevice => '账号在其他设备登录，这里被挤下线';

  @override
  String get sessionCauseDeviceRemoved => '在「登录设备管理」里删除了这台设备';

  @override
  String get sessionCausePassword => '修改了账号密码';

  @override
  String get sessionCauseExpired => '登录超过了有效期';

  @override
  String get loginAgain => '重新登录';

  @override
  String get later => '稍后';

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

  @override
  String get refresh => '刷新';

  @override
  String get renamePlaylist => '重命名';

  @override
  String get deletePlaylist => '删除歌单';

  @override
  String get delete => '删除';

  @override
  String get playlistNameHint => '歌单名';

  @override
  String deletePlaylistConfirm(String name) {
    return '确定删除歌单「$name」吗？删除后无法恢复。';
  }

  @override
  String get playlistRenamed => '已重命名';

  @override
  String get playlistDeleted => '已删除歌单';

  @override
  String get nothingPlaying => '还没有在播放的歌';

  @override
  String get searchKindSong => '歌曲';

  @override
  String get searchKindSinger => '歌手';

  @override
  String get searchKindAlbum => '专辑';

  @override
  String get searchKindPlaylist => '歌单';

  @override
  String get searchKindVideo => '视频';

  @override
  String get recentKindRadar => '音乐雷达';

  @override
  String get recentKindAudiobook => '有声';

  @override
  String get searchKindLyric => '歌词';

  @override
  String searchTotalItems(int count) {
    return '共 $count 个结果';
  }

  @override
  String singerStats(int songs, int albums) {
    return '$songs 首歌 · $albums 张专辑';
  }

  @override
  String get searchKindUser => '用户';

  @override
  String get searchHistory => '最近搜索';

  @override
  String get searchHistoryClear => '清空最近搜索';

  @override
  String get searchHistoryClearConfirm => '清空所有最近搜索？';

  @override
  String get mvUnavailable => '这个视频暂时无法播放';

  @override
  String get watchMv => '观看 MV';

  @override
  String get findSimilarSongs => '查找相似歌曲';

  @override
  String similarSongsTitle(String name) {
    return '与《$name》相似的歌曲';
  }

  @override
  String userFansFollows(String fans, String follows) {
    return '粉丝 $fans · 关注 $follows';
  }

  @override
  String userBriefStats(String fans, int count) {
    return '粉丝 $fans · 歌单 $count';
  }

  @override
  String userPlaylists(int count) {
    return '歌单 $count';
  }

  @override
  String get userNoPlaylists => '没有公开的歌单';

  @override
  String userFans(String fans) {
    return '粉丝 $fans';
  }

  @override
  String get singerFeatured => '精选';

  @override
  String get singerSelectedAlbums => '精选专辑';

  @override
  String get follow => '关注';

  @override
  String get followed => '已关注';

  @override
  String get createPlaylist => '新建歌单';

  @override
  String get create => '创建';

  @override
  String get playlistSyncHint => '会同步到你的 QQ 音乐账号';

  @override
  String get playlistCreated => '已新建歌单';

  @override
  String get savedPlaylists => '收藏歌单';

  @override
  String get savedAlbums => '收藏专辑';

  @override
  String get userPrivate => '内容未公开';

  @override
  String get noItems => '暂无内容';

  @override
  String get newest => '最新';

  @override
  String get hottest => '最热';

  @override
  String get userLikes => '我喜欢';

  @override
  String get singerAbout => '详情';

  @override
  String get singerBio => '简介';

  @override
  String get singerGuard => '守护';

  @override
  String get statFans => '粉丝';

  @override
  String get statFollows => '关注';

  @override
  String get statPlaylists => '歌单';

  @override
  String get showMore => '展开';

  @override
  String get showLess => '收起';

  @override
  String durationHoursMinutes(int hours, int minutes) {
    return '$hours 小时 $minutes 分';
  }

  @override
  String durationMinutes(int minutes) {
    return '$minutes 分钟';
  }

  @override
  String filterFound(int count) {
    return '找到 $count 首';
  }

  @override
  String playFiltered(int count) {
    return '播放这 $count 首';
  }

  @override
  String get featuredVideos => '精选视频';

  @override
  String alsoListening(String name) {
    return '听「$name」的也在听';
  }

  @override
  String get relatedPlaylists => '相关歌单';

  @override
  String get anotherBatch => '换一批';

  @override
  String get sleepTimer => '定时关闭';

  @override
  String sleepTimerUntil(String time) {
    return '$time 停止播放';
  }

  @override
  String get sleepTimerWaiting => '这首放完后停止';

  @override
  String get sleepTimerWaitingShort => '播完停';

  @override
  String get sleepTimerDuration => '时长';

  @override
  String get sleepTimerStart => '开始';

  @override
  String get sleepAfterSong => '播完整首再停止';

  @override
  String get sleepAfterSongHint => '到点时正在放的歌会放完再暂停';

  @override
  String get sleepTimerOff => '关闭定时';

  @override
  String get close => '关闭';

  @override
  String get settingsAbout => '关于';

  @override
  String get checkUpdate => '检查更新';

  @override
  String currentVersion(String version) {
    return '当前版本 $version';
  }

  @override
  String get updateChecking => '正在检查…';

  @override
  String get upToDate => '已是最新';

  @override
  String get updateCheckFailed => '检查更新失败，稍后再试';

  @override
  String get updatePreview => '接收预览版更新';

  @override
  String get updatePreviewHint => '测试版也会提醒，可能不稳定';

  @override
  String get updateMirror => '通过镜像下载更新';

  @override
  String get updateMirrorHint => '打开后不连接 GitHub，全部走镜像';

  @override
  String updateAvailable(String version) {
    return '发现新版本 $version';
  }

  @override
  String get updatePreviewBadge => '预览版';

  @override
  String updateCurrent(String version) {
    return '当前 $version';
  }

  @override
  String updateDate(String date) {
    return '$date 发布';
  }

  @override
  String get updateInstaller => '安装包';

  @override
  String get updateInstallerHint => '运行安装程序覆盖更新';

  @override
  String get updateArchive => '压缩包';

  @override
  String get updateArchiveHint => '退出后自动替换文件';

  @override
  String get updateNow => '立即更新';

  @override
  String get updateSkip => '跳过这个版本';

  @override
  String updateDownloading(String version) {
    return '正在下载 $version';
  }

  @override
  String get updateDownloadingHint => '下载完会自动校验并安装';

  @override
  String get updateConnecting => '正在连接下载源…';

  @override
  String updateSource(String source) {
    return '下载源：$source';
  }

  @override
  String get updateFailed => '更新失败';

  @override
  String get updateNetworkFailed => '没能下载下来。检查网络后重试，或在设置里切换镜像。';

  @override
  String get updateCorrupted => '文件校验没通过，可能是下载源出了问题。没有安装任何东西。';

  @override
  String get updateNotWritable => '没有权限替换程序目录里的文件，请改用安装包。';

  @override
  String get updateInstallFailed => '没能打开安装程序。';

  @override
  String get updateUseInstaller => '改用安装包';

  @override
  String get updateOpenBrowser => '在浏览器中下载';

  @override
  String get download => '下载';

  @override
  String get downloaded => '已下载';

  @override
  String get downloading => '下载中';

  @override
  String get downloadQueued => '等待下载';

  @override
  String get downloadPaused => '已暂停';

  @override
  String get downloadFailed => '下载失败';

  @override
  String get downloadAdded => '已加入下载';

  @override
  String get downloadQuality => '选择下载音质';

  @override
  String get downloadWavHint => '存成 WAV，文件比较大';

  @override
  String get downloadOtherQuality => '换个音质重新下载';

  @override
  String get downloadRetry => '重新下载';

  @override
  String get deleteDownload => '删除下载';

  @override
  String get cancelDownload => '取消下载';

  @override
  String deleteDownloadConfirm(String name) {
    return '删除「$name」下载的歌曲文件和歌词？';
  }

  @override
  String get downloadDeleted => '已删除';

  @override
  String get downloadDir => '下载位置';

  @override
  String get downloadDirAndroid => '系统「音乐/Kanade」文件夹';

  @override
  String get settingsDownloads => '下载';

  @override
  String get downloadPauseAll => '全部暂停';

  @override
  String get downloadResumeAll => '全部开始';

  @override
  String get downloadPause => '暂停';

  @override
  String get downloadResume => '继续';

  @override
  String get downloadWaitingWifi => '等待 Wi-Fi';

  @override
  String get downloadEmpty => '没有正在下载的歌';

  @override
  String get downloadedEmpty => '还没有下载过歌';

  @override
  String get downloadConcurrency => '同时下载';

  @override
  String downloadConcurrencyValue(int count) {
    return '$count 首';
  }

  @override
  String get downloadWifiOnly => '仅 Wi-Fi 下载';

  @override
  String get downloadWifiOnlyHint => '用流量时先排队，连上 Wi-Fi 再下';

  @override
  String get restoreDownloads => '恢复已下载的歌';

  @override
  String get restoreDownloadsHint => '重装后找回下载文件夹里的歌，不是 Kanade 下载的当作本地歌';

  @override
  String restoreDownloadsDone(int count) {
    return '已恢复 $count 首';
  }

  @override
  String get restoreDownloadsNone => '没有找到需要恢复的歌';

  @override
  String get restoreDownloadsDenied => '没有授权下载文件夹，无法恢复';

  @override
  String get localSongUnsupported => '本地歌曲不支持这个操作';

  @override
  String selectedCount(int count) {
    return '已选 $count 首';
  }

  @override
  String get selectAll => '全选';

  @override
  String get selectNone => '取消全选';

  @override
  String get multiSelect => '多选';

  @override
  String get downloadAll => '全部下载';

  @override
  String downloadBatchHint(int count) {
    return '共 $count 首，没有这个音质的自动降一档';
  }

  @override
  String get downloadLyrics => '歌词';

  @override
  String get downloadLyricsLrc => 'LRC 文件';

  @override
  String get downloadLyricsEmbed => '写进歌曲';

  @override
  String get downloadLyricsLrcHint => '另存一个和歌曲同名的 .lrc 文件';

  @override
  String get downloadLyricsEmbedHint => '写进歌曲文件的标签里，不另存文件';

  @override
  String get deleteDownloadedSong => '删除歌曲';

  @override
  String cancelDownloadConfirm(String name) {
    return '取消下载「$name」？已经下了的部分会删掉。';
  }

  @override
  String get keepDownload => '不取消';

  @override
  String get dislike => '不喜欢';

  @override
  String get dislikeChoose => '选择不喜欢的内容';

  @override
  String dislikeSong(String name) {
    return '不喜欢歌曲：$name';
  }

  @override
  String dislikeSinger(String name) {
    return '不喜欢歌手：$name';
  }

  @override
  String get dislikedSong => '以后不再推荐这首歌';

  @override
  String get dislikedSinger => '以后不再推荐这位歌手的歌';

  @override
  String get dislikeList => '不喜欢列表';

  @override
  String get dislikeListHint => '查看或撤销不喜欢的歌曲和歌手';

  @override
  String get dislikeSongsEmpty => '没有不喜欢的歌曲';

  @override
  String get dislikeSingersEmpty => '没有不喜欢的歌手';

  @override
  String get dislikeCancel => '撤销';

  @override
  String get dislikeCancelled => '已撤销';

  @override
  String get settingsDesktop => '桌面';

  @override
  String get closeAction => '关闭窗口时';

  @override
  String get closeActionAsk => '每次询问';

  @override
  String get closeToTray => '最小化到托盘';

  @override
  String get closeExit => '退出 Kanade';

  @override
  String get closeAskTitle => '关闭窗口';

  @override
  String get closeAskMessage => '最小化到托盘后，歌会在后台继续放';

  @override
  String get closeAskRemember => '不再询问';

  @override
  String get trayShowWindow => '显示窗口';

  @override
  String get trayExit => '退出';

  @override
  String get autostart => '开机自动启动';

  @override
  String get autostartHint => '开机后待在托盘里，不弹出窗口';

  @override
  String get hotkeys => '全局快捷键';

  @override
  String get hotkeysHint => '在别的窗口里也能用快捷键控制播放';

  @override
  String get hotkeyToggle => '播放/暂停';

  @override
  String get hotkeyVolumeUp => '音量加';

  @override
  String get hotkeyVolumeDown => '音量减';

  @override
  String get hotkeyLike => '喜欢/取消喜欢当前歌曲';

  @override
  String get hotkeyWindow => '显示/隐藏窗口';

  @override
  String get hotkeyNone => '未设置';

  @override
  String get hotkeyTaken => '已被占用';

  @override
  String get hotkeyRecordTitle => '按下新的组合键';

  @override
  String get hotkeyRecordHint => '至少按住 Ctrl、Alt、Shift 中的两个，按 Esc 取消';

  @override
  String get hotkeyClear => '清除';
}
