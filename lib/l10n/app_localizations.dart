import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_zh.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('zh'),
  ];

  /// No description provided for @appTitle.
  ///
  /// In zh, this message translates to:
  /// **'Kanade'**
  String get appTitle;

  /// No description provided for @tabDiscover.
  ///
  /// In zh, this message translates to:
  /// **'发现'**
  String get tabDiscover;

  /// No description provided for @tabSearch.
  ///
  /// In zh, this message translates to:
  /// **'搜索'**
  String get tabSearch;

  /// No description provided for @tabMine.
  ///
  /// In zh, this message translates to:
  /// **'我的'**
  String get tabMine;

  /// No description provided for @windowMinimize.
  ///
  /// In zh, this message translates to:
  /// **'最小化'**
  String get windowMinimize;

  /// No description provided for @windowMaximize.
  ///
  /// In zh, this message translates to:
  /// **'最大化'**
  String get windowMaximize;

  /// No description provided for @windowRestore.
  ///
  /// In zh, this message translates to:
  /// **'向下还原'**
  String get windowRestore;

  /// No description provided for @windowClose.
  ///
  /// In zh, this message translates to:
  /// **'关闭'**
  String get windowClose;

  /// No description provided for @language.
  ///
  /// In zh, this message translates to:
  /// **'语言'**
  String get language;

  /// No description provided for @languageSystem.
  ///
  /// In zh, this message translates to:
  /// **'跟随系统'**
  String get languageSystem;

  /// No description provided for @retry.
  ///
  /// In zh, this message translates to:
  /// **'重试'**
  String get retry;

  /// No description provided for @cancel.
  ///
  /// In zh, this message translates to:
  /// **'取消'**
  String get cancel;

  /// No description provided for @loadFailed.
  ///
  /// In zh, this message translates to:
  /// **'加载失败：{error}'**
  String loadFailed(String error);

  /// No description provided for @recommendedPlaylists.
  ///
  /// In zh, this message translates to:
  /// **'推荐歌单'**
  String get recommendedPlaylists;

  /// No description provided for @recommendedSongs.
  ///
  /// In zh, this message translates to:
  /// **'为你推荐'**
  String get recommendedSongs;

  /// No description provided for @discoverRecommend.
  ///
  /// In zh, this message translates to:
  /// **'推荐'**
  String get discoverRecommend;

  /// No description provided for @discoverToplists.
  ///
  /// In zh, this message translates to:
  /// **'排行榜'**
  String get discoverToplists;

  /// No description provided for @radioGuessYouLike.
  ///
  /// In zh, this message translates to:
  /// **'猜你喜欢'**
  String get radioGuessYouLike;

  /// No description provided for @radioRadar.
  ///
  /// In zh, this message translates to:
  /// **'刷歌模式'**
  String get radioRadar;

  /// No description provided for @radioFailed.
  ///
  /// In zh, this message translates to:
  /// **'电台没取到歌：{error}'**
  String radioFailed(String error);

  /// No description provided for @newSongs.
  ///
  /// In zh, this message translates to:
  /// **'新歌首发'**
  String get newSongs;

  /// No description provided for @viewAllSongs.
  ///
  /// In zh, this message translates to:
  /// **'查看全部 {count} 首'**
  String viewAllSongs(int count);

  /// 榜单期数
  ///
  /// In zh, this message translates to:
  /// **'更新于 {period}'**
  String updatedAt(String period);

  /// No description provided for @playAll.
  ///
  /// In zh, this message translates to:
  /// **'播放全部 ({count})'**
  String playAll(int count);

  /// No description provided for @songCount.
  ///
  /// In zh, this message translates to:
  /// **'{count} 首'**
  String songCount(int count);

  /// No description provided for @searchHint.
  ///
  /// In zh, this message translates to:
  /// **'搜索歌曲、歌手'**
  String get searchHint;

  /// No description provided for @searchPrompt.
  ///
  /// In zh, this message translates to:
  /// **'输入关键词后回车搜索'**
  String get searchPrompt;

  /// No description provided for @searchHot.
  ///
  /// In zh, this message translates to:
  /// **'热搜榜'**
  String get searchHot;

  /// No description provided for @searchRecommended.
  ///
  /// In zh, this message translates to:
  /// **'猜你想搜'**
  String get searchRecommended;

  /// No description provided for @searchNoResults.
  ///
  /// In zh, this message translates to:
  /// **'没有找到相关歌曲'**
  String get searchNoResults;

  /// No description provided for @searchFailed.
  ///
  /// In zh, this message translates to:
  /// **'搜索失败：{error}'**
  String searchFailed(String error);

  /// No description provided for @searchTotal.
  ///
  /// In zh, this message translates to:
  /// **'共 {count} 首'**
  String searchTotal(int count);

  /// No description provided for @quality.
  ///
  /// In zh, this message translates to:
  /// **'音质'**
  String get quality;

  /// No description provided for @qualityLoading.
  ///
  /// In zh, this message translates to:
  /// **'正在获取音质'**
  String get qualityLoading;

  /// No description provided for @qualityFailed.
  ///
  /// In zh, this message translates to:
  /// **'音质获取失败：{error}'**
  String qualityFailed(String error);

  /// No description provided for @qualityFailedRetry.
  ///
  /// In zh, this message translates to:
  /// **'音质获取失败，点击重试'**
  String get qualityFailedRetry;

  /// No description provided for @qualityNoneForSong.
  ///
  /// In zh, this message translates to:
  /// **'歌曲暂无可用音质'**
  String get qualityNoneForSong;

  /// No description provided for @qualityNone.
  ///
  /// In zh, this message translates to:
  /// **'暂无可用音质'**
  String get qualityNone;

  /// No description provided for @qualityWithReason.
  ///
  /// In zh, this message translates to:
  /// **'{quality}（{reason}）'**
  String qualityWithReason(String quality, String reason);

  /// 请求的音质没有权限，自动降级
  ///
  /// In zh, this message translates to:
  /// **'{actual}（无权获取{requested}）'**
  String qualityDowngraded(String actual, String requested);

  /// No description provided for @qualityLow.
  ///
  /// In zh, this message translates to:
  /// **'流畅 96k'**
  String get qualityLow;

  /// No description provided for @qualityStandard.
  ///
  /// In zh, this message translates to:
  /// **'标准 128k'**
  String get qualityStandard;

  /// No description provided for @qualityHigh.
  ///
  /// In zh, this message translates to:
  /// **'高品质 320k'**
  String get qualityHigh;

  /// No description provided for @qualityLossless.
  ///
  /// In zh, this message translates to:
  /// **'无损 FLAC'**
  String get qualityLossless;

  /// No description provided for @qualityMaster.
  ///
  /// In zh, this message translates to:
  /// **'臻品母带'**
  String get qualityMaster;

  /// No description provided for @qualityAtmos.
  ///
  /// In zh, this message translates to:
  /// **'臻品音质'**
  String get qualityAtmos;

  /// No description provided for @qualityAtmos51.
  ///
  /// In zh, this message translates to:
  /// **'臻品全景声 5.1'**
  String get qualityAtmos51;

  /// No description provided for @qualityAtmos71.
  ///
  /// In zh, this message translates to:
  /// **'臻品全景声 7.1'**
  String get qualityAtmos71;

  /// No description provided for @qualityDolby.
  ///
  /// In zh, this message translates to:
  /// **'杜比全景声'**
  String get qualityDolby;

  /// No description provided for @qualityOgg320.
  ///
  /// In zh, this message translates to:
  /// **'高品质 OGG 320k'**
  String get qualityOgg320;

  /// No description provided for @qualityAiCodec.
  ///
  /// In zh, this message translates to:
  /// **'AI 音质'**
  String get qualityAiCodec;

  /// No description provided for @qualityVinyl.
  ///
  /// In zh, this message translates to:
  /// **'黑胶'**
  String get qualityVinyl;

  /// No description provided for @reasonUnsupported.
  ///
  /// In zh, this message translates to:
  /// **'播放器暂不支持此格式'**
  String get reasonUnsupported;

  /// No description provided for @reasonUnverified.
  ///
  /// In zh, this message translates to:
  /// **'暂未通过播放验证'**
  String get reasonUnverified;

  /// No description provided for @reasonNoPermission.
  ///
  /// In zh, this message translates to:
  /// **'当前账号无权限'**
  String get reasonNoPermission;

  /// No description provided for @reasonDeviceRestricted.
  ///
  /// In zh, this message translates to:
  /// **'播放设备受限'**
  String get reasonDeviceRestricted;

  /// No description provided for @reasonNoLink.
  ///
  /// In zh, this message translates to:
  /// **'暂无可用链接'**
  String get reasonNoLink;

  /// No description provided for @reasonVerifyFailed.
  ///
  /// In zh, this message translates to:
  /// **'音质验证失败，请稍后重试'**
  String get reasonVerifyFailed;

  /// No description provided for @reasonFileUnavailable.
  ///
  /// In zh, this message translates to:
  /// **'音频文件暂不可用'**
  String get reasonFileUnavailable;

  /// No description provided for @logout.
  ///
  /// In zh, this message translates to:
  /// **'退出登录'**
  String get logout;

  /// No description provided for @loginPrompt.
  ///
  /// In zh, this message translates to:
  /// **'登录后可以同步你的歌单，并播放账号有权限的歌曲'**
  String get loginPrompt;

  /// No description provided for @loginQq.
  ///
  /// In zh, this message translates to:
  /// **'QQ 扫码登录'**
  String get loginQq;

  /// No description provided for @loginWechat.
  ///
  /// In zh, this message translates to:
  /// **'微信扫码登录'**
  String get loginWechat;

  /// No description provided for @loginQqMusic.
  ///
  /// In zh, this message translates to:
  /// **'QQ 音乐授权登录'**
  String get loginQqMusic;

  /// No description provided for @loginCookie.
  ///
  /// In zh, this message translates to:
  /// **'使用 Cookie 登录'**
  String get loginCookie;

  /// No description provided for @noPlaylists.
  ///
  /// In zh, this message translates to:
  /// **'还没有歌单'**
  String get noPlaylists;

  /// No description provided for @qrLoading.
  ///
  /// In zh, this message translates to:
  /// **'正在获取二维码…'**
  String get qrLoading;

  /// No description provided for @qrScanHintQq.
  ///
  /// In zh, this message translates to:
  /// **'请使用手机 QQ 扫码'**
  String get qrScanHintQq;

  /// No description provided for @qrScanHintWechat.
  ///
  /// In zh, this message translates to:
  /// **'请使用手机微信扫码'**
  String get qrScanHintWechat;

  /// No description provided for @qrScanHintQqMusic.
  ///
  /// In zh, this message translates to:
  /// **'请使用 QQ 音乐 App 扫码，将登录 App 当前的账号'**
  String get qrScanHintQqMusic;

  /// No description provided for @qrScanned.
  ///
  /// In zh, this message translates to:
  /// **'已扫码，请在手机上确认'**
  String get qrScanned;

  /// No description provided for @qrExpired.
  ///
  /// In zh, this message translates to:
  /// **'二维码已过期'**
  String get qrExpired;

  /// No description provided for @qrRefused.
  ///
  /// In zh, this message translates to:
  /// **'已在手机上取消登录'**
  String get qrRefused;

  /// No description provided for @qrRefresh.
  ///
  /// In zh, this message translates to:
  /// **'刷新二维码'**
  String get qrRefresh;

  /// No description provided for @qrOpenQq.
  ///
  /// In zh, this message translates to:
  /// **'跳转 QQ 登录'**
  String get qrOpenQq;

  /// No description provided for @qrQqNotInstalled.
  ///
  /// In zh, this message translates to:
  /// **'无法打开 QQ，请确认已安装手机 QQ'**
  String get qrQqNotInstalled;

  /// No description provided for @qrSaveImage.
  ///
  /// In zh, this message translates to:
  /// **'保存二维码'**
  String get qrSaveImage;

  /// No description provided for @qrSavedQq.
  ///
  /// In zh, this message translates to:
  /// **'已保存到相册，在 QQ「扫一扫」右上角选择相册图片即可'**
  String get qrSavedQq;

  /// No description provided for @qrOpenQqMusic.
  ///
  /// In zh, this message translates to:
  /// **'跳转 QQ 音乐授权'**
  String get qrOpenQqMusic;

  /// No description provided for @qrQqMusicNotInstalled.
  ///
  /// In zh, this message translates to:
  /// **'无法打开 QQ 音乐，请确认已安装 QQ 音乐 App'**
  String get qrQqMusicNotInstalled;

  /// No description provided for @qrWechatSameDeviceTip.
  ///
  /// In zh, this message translates to:
  /// **'微信不支持本机登录。如果 QQ 音乐 App 登的是微信号，可以改用「QQ 音乐授权登录」'**
  String get qrWechatSameDeviceTip;

  /// No description provided for @qrSaveFailed.
  ///
  /// In zh, this message translates to:
  /// **'保存失败：{error}'**
  String qrSaveFailed(String error);

  /// No description provided for @qrFailed.
  ///
  /// In zh, this message translates to:
  /// **'获取二维码失败：{error}'**
  String qrFailed(String error);

  /// No description provided for @cookieLoginTitle.
  ///
  /// In zh, this message translates to:
  /// **'Cookie 登录'**
  String get cookieLoginTitle;

  /// No description provided for @cookieLoginHint.
  ///
  /// In zh, this message translates to:
  /// **'在浏览器登录 y.qq.com 后，从开发者工具复制 Cookie 粘贴到这里（需要包含 uin 和 qm_keyst）。'**
  String get cookieLoginHint;

  /// No description provided for @login.
  ///
  /// In zh, this message translates to:
  /// **'登录'**
  String get login;

  /// No description provided for @swipeForLyrics.
  ///
  /// In zh, this message translates to:
  /// **'← 左滑查看歌词'**
  String get swipeForLyrics;

  /// No description provided for @noLyrics.
  ///
  /// In zh, this message translates to:
  /// **'暂无歌词'**
  String get noLyrics;

  /// No description provided for @modeSequence.
  ///
  /// In zh, this message translates to:
  /// **'列表循环'**
  String get modeSequence;

  /// No description provided for @modeRepeatOne.
  ///
  /// In zh, this message translates to:
  /// **'单曲循环'**
  String get modeRepeatOne;

  /// No description provided for @modeShuffle.
  ///
  /// In zh, this message translates to:
  /// **'随机播放'**
  String get modeShuffle;

  /// No description provided for @lyrics.
  ///
  /// In zh, this message translates to:
  /// **'歌词'**
  String get lyrics;

  /// No description provided for @upNext.
  ///
  /// In zh, this message translates to:
  /// **'接下来播放'**
  String get upNext;

  /// No description provided for @volume.
  ///
  /// In zh, this message translates to:
  /// **'音量'**
  String get volume;

  /// No description provided for @queue.
  ///
  /// In zh, this message translates to:
  /// **'播放队列'**
  String get queue;

  /// No description provided for @playbackError.
  ///
  /// In zh, this message translates to:
  /// **'播放出错：{error}'**
  String playbackError(String error);

  /// No description provided for @songUnplayable.
  ///
  /// In zh, this message translates to:
  /// **'《{song}》无法播放：{error}'**
  String songUnplayable(String song, String error);

  /// No description provided for @errorNotLoggedIn.
  ///
  /// In zh, this message translates to:
  /// **'尚未登录'**
  String get errorNotLoggedIn;

  /// No description provided for @errorNoPlayableUrl.
  ///
  /// In zh, this message translates to:
  /// **'没有可用的播放链接（可能需要登录或会员）'**
  String get errorNoPlayableUrl;

  /// No description provided for @errorLoginFailed.
  ///
  /// In zh, this message translates to:
  /// **'登录失败：{detail}'**
  String errorLoginFailed(String detail);

  /// No description provided for @errorInvalidCookie.
  ///
  /// In zh, this message translates to:
  /// **'Cookie 里没有 {field}'**
  String errorInvalidCookie(String field);

  /// No description provided for @errorServer.
  ///
  /// In zh, this message translates to:
  /// **'服务器返回错误码 {code}（{api}）'**
  String errorServer(String code, String api);

  /// No description provided for @errorBadResponse.
  ///
  /// In zh, this message translates to:
  /// **'服务器响应异常：{detail}'**
  String errorBadResponse(String detail);

  /// No description provided for @errorNetwork.
  ///
  /// In zh, this message translates to:
  /// **'网络错误：{detail}'**
  String errorNetwork(String detail);

  /// No description provided for @errorInternal.
  ///
  /// In zh, this message translates to:
  /// **'内部错误：{detail}'**
  String errorInternal(String detail);

  /// No description provided for @like.
  ///
  /// In zh, this message translates to:
  /// **'收藏到我喜欢'**
  String get like;

  /// No description provided for @unlike.
  ///
  /// In zh, this message translates to:
  /// **'取消喜欢'**
  String get unlike;

  /// No description provided for @liked.
  ///
  /// In zh, this message translates to:
  /// **'已添加到我喜欢'**
  String get liked;

  /// No description provided for @unliked.
  ///
  /// In zh, this message translates to:
  /// **'已取消喜欢'**
  String get unliked;

  /// No description provided for @addToPlaylist.
  ///
  /// In zh, this message translates to:
  /// **'加入歌单'**
  String get addToPlaylist;

  /// No description provided for @addedToPlaylist.
  ///
  /// In zh, this message translates to:
  /// **'已加入「{name}」'**
  String addedToPlaylist(String name);

  /// No description provided for @removeFromPlaylist.
  ///
  /// In zh, this message translates to:
  /// **'从歌单中删除'**
  String get removeFromPlaylist;

  /// No description provided for @removedFromPlaylist.
  ///
  /// In zh, this message translates to:
  /// **'已从「{name}」删除'**
  String removedFromPlaylist(String name);

  /// No description provided for @actionFailed.
  ///
  /// In zh, this message translates to:
  /// **'操作失败：{error}'**
  String actionFailed(String error);

  /// No description provided for @loginRequired.
  ///
  /// In zh, this message translates to:
  /// **'请先在「我的」页登录'**
  String get loginRequired;

  /// No description provided for @noMyPlaylists.
  ///
  /// In zh, this message translates to:
  /// **'没有可加入的歌单'**
  String get noMyPlaylists;

  /// No description provided for @more.
  ///
  /// In zh, this message translates to:
  /// **'更多'**
  String get more;

  /// No description provided for @singerNamed.
  ///
  /// In zh, this message translates to:
  /// **'歌手：{name}'**
  String singerNamed(String name);

  /// No description provided for @albumNamed.
  ///
  /// In zh, this message translates to:
  /// **'专辑：{name}'**
  String albumNamed(String name);

  /// No description provided for @comments.
  ///
  /// In zh, this message translates to:
  /// **'评论'**
  String get comments;

  /// No description provided for @hotComments.
  ///
  /// In zh, this message translates to:
  /// **'热门评论'**
  String get hotComments;

  /// No description provided for @latestComments.
  ///
  /// In zh, this message translates to:
  /// **'最新评论'**
  String get latestComments;

  /// No description provided for @commentTotal.
  ///
  /// In zh, this message translates to:
  /// **'共 {count} 条评论'**
  String commentTotal(int count);

  /// No description provided for @noComments.
  ///
  /// In zh, this message translates to:
  /// **'还没有评论'**
  String get noComments;

  /// No description provided for @replies.
  ///
  /// In zh, this message translates to:
  /// **'回复'**
  String get replies;

  /// No description provided for @viewReplies.
  ///
  /// In zh, this message translates to:
  /// **'查看 {count} 条回复'**
  String viewReplies(int count);

  /// No description provided for @replyTo.
  ///
  /// In zh, this message translates to:
  /// **'回复 {name}：'**
  String replyTo(String name);

  /// No description provided for @loadMore.
  ///
  /// In zh, this message translates to:
  /// **'加载更多'**
  String get loadMore;

  /// No description provided for @tabSongs.
  ///
  /// In zh, this message translates to:
  /// **'歌曲'**
  String get tabSongs;

  /// No description provided for @tabAlbums.
  ///
  /// In zh, this message translates to:
  /// **'专辑'**
  String get tabAlbums;

  /// No description provided for @publishedOn.
  ///
  /// In zh, this message translates to:
  /// **'发行于 {date}'**
  String publishedOn(String date);

  /// No description provided for @settings.
  ///
  /// In zh, this message translates to:
  /// **'设置'**
  String get settings;

  /// No description provided for @settingsGeneral.
  ///
  /// In zh, this message translates to:
  /// **'通用'**
  String get settingsGeneral;

  /// No description provided for @settingsCache.
  ///
  /// In zh, this message translates to:
  /// **'缓存'**
  String get settingsCache;

  /// No description provided for @settingsAccount.
  ///
  /// In zh, this message translates to:
  /// **'账号'**
  String get settingsAccount;

  /// No description provided for @defaultQuality.
  ///
  /// In zh, this message translates to:
  /// **'默认音质'**
  String get defaultQuality;

  /// No description provided for @defaultQualityHint.
  ///
  /// In zh, this message translates to:
  /// **'选的音质没有或播不了时会自动降低'**
  String get defaultQualityHint;

  /// No description provided for @audioCacheLimit.
  ///
  /// In zh, this message translates to:
  /// **'歌曲缓存上限'**
  String get audioCacheLimit;

  /// No description provided for @audioCacheLimitHint.
  ///
  /// In zh, this message translates to:
  /// **'边听边存，超出后删除最久没听的歌'**
  String get audioCacheLimitHint;

  /// No description provided for @audioCacheOff.
  ///
  /// In zh, this message translates to:
  /// **'关闭'**
  String get audioCacheOff;

  /// No description provided for @audioCacheCustom.
  ///
  /// In zh, this message translates to:
  /// **'自定义'**
  String get audioCacheCustom;

  /// No description provided for @audioCacheCustomTitle.
  ///
  /// In zh, this message translates to:
  /// **'自定义缓存上限'**
  String get audioCacheCustomTitle;

  /// No description provided for @audioCacheCustomUnit.
  ///
  /// In zh, this message translates to:
  /// **'MB'**
  String get audioCacheCustomUnit;

  /// No description provided for @audioCacheSize.
  ///
  /// In zh, this message translates to:
  /// **'歌曲缓存'**
  String get audioCacheSize;

  /// No description provided for @apiCacheSize.
  ///
  /// In zh, this message translates to:
  /// **'其他缓存'**
  String get apiCacheSize;

  /// No description provided for @apiCacheSizeHint.
  ///
  /// In zh, this message translates to:
  /// **'歌单、搜索、歌词等数据'**
  String get apiCacheSizeHint;

  /// No description provided for @clear.
  ///
  /// In zh, this message translates to:
  /// **'清除'**
  String get clear;

  /// No description provided for @clearAudioCacheConfirm.
  ///
  /// In zh, this message translates to:
  /// **'清除所有已缓存的歌曲？'**
  String get clearAudioCacheConfirm;

  /// No description provided for @clearApiCacheConfirm.
  ///
  /// In zh, this message translates to:
  /// **'清除歌单、搜索、歌词等缓存数据？'**
  String get clearApiCacheConfirm;

  /// No description provided for @cacheCleared.
  ///
  /// In zh, this message translates to:
  /// **'已清除'**
  String get cacheCleared;

  /// No description provided for @logoutConfirm.
  ///
  /// In zh, this message translates to:
  /// **'确定退出登录？'**
  String get logoutConfirm;

  /// No description provided for @ok.
  ///
  /// In zh, this message translates to:
  /// **'确定'**
  String get ok;

  /// No description provided for @likedSongs.
  ///
  /// In zh, this message translates to:
  /// **'我喜欢'**
  String get likedSongs;

  /// No description provided for @recentPlays.
  ///
  /// In zh, this message translates to:
  /// **'最近播放'**
  String get recentPlays;

  /// No description provided for @myPlaylists.
  ///
  /// In zh, this message translates to:
  /// **'我的歌单'**
  String get myPlaylists;

  /// No description provided for @playlistsCreated.
  ///
  /// In zh, this message translates to:
  /// **'创建的'**
  String get playlistsCreated;

  /// No description provided for @playlistsCollected.
  ///
  /// In zh, this message translates to:
  /// **'收藏的'**
  String get playlistsCollected;

  /// No description provided for @shufflePlay.
  ///
  /// In zh, this message translates to:
  /// **'随机播放'**
  String get shufflePlay;

  /// No description provided for @seeAll.
  ///
  /// In zh, this message translates to:
  /// **'全部'**
  String get seeAll;

  /// No description provided for @renamePlaylist.
  ///
  /// In zh, this message translates to:
  /// **'重命名'**
  String get renamePlaylist;

  /// No description provided for @deletePlaylist.
  ///
  /// In zh, this message translates to:
  /// **'删除歌单'**
  String get deletePlaylist;

  /// No description provided for @delete.
  ///
  /// In zh, this message translates to:
  /// **'删除'**
  String get delete;

  /// No description provided for @playlistNameHint.
  ///
  /// In zh, this message translates to:
  /// **'歌单名'**
  String get playlistNameHint;

  /// No description provided for @deletePlaylistConfirm.
  ///
  /// In zh, this message translates to:
  /// **'确定删除歌单「{name}」吗？删除后无法恢复。'**
  String deletePlaylistConfirm(String name);

  /// No description provided for @playlistRenamed.
  ///
  /// In zh, this message translates to:
  /// **'已重命名'**
  String get playlistRenamed;

  /// No description provided for @playlistDeleted.
  ///
  /// In zh, this message translates to:
  /// **'已删除歌单'**
  String get playlistDeleted;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'zh'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'zh':
      return AppLocalizationsZh();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
