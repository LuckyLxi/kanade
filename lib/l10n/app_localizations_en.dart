// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'Kanade';

  @override
  String get tabDiscover => 'Discover';

  @override
  String get tabSearch => 'Search';

  @override
  String get tabMine => 'Me';

  @override
  String get windowMinimize => 'Minimize';

  @override
  String get windowMaximize => 'Maximize';

  @override
  String get windowRestore => 'Restore';

  @override
  String get windowClose => 'Close';

  @override
  String get language => 'Language';

  @override
  String get languageSystem => 'System default';

  @override
  String get retry => 'Retry';

  @override
  String get cancel => 'Cancel';

  @override
  String loadFailed(String error) {
    return 'Failed to load: $error';
  }

  @override
  String get recommendedPlaylists => 'Recommended playlists';

  @override
  String get recommendedSongs => 'Picked for you';

  @override
  String get discoverRecommend => 'For you';

  @override
  String get discoverToplists => 'Charts';

  @override
  String get radioGuessYouLike => 'Guess you like';

  @override
  String get radioRadar => 'Discovery mode';

  @override
  String radioFailed(String error) {
    return 'Couldn\'t start the radio: $error';
  }

  @override
  String get newSongs => 'New releases';

  @override
  String viewAllSongs(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'View all $count songs',
      one: 'View 1 song',
    );
    return '$_temp0';
  }

  @override
  String updatedAt(String period) {
    return 'Updated $period';
  }

  @override
  String playAll(int count) {
    return 'Play all ($count)';
  }

  @override
  String songCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count songs',
      one: '1 song',
    );
    return '$_temp0';
  }

  @override
  String get searchHint => 'Search songs, artists, albums, videos';

  @override
  String get searchPrompt => 'Type a keyword and press Enter';

  @override
  String get searchHot => 'Trending';

  @override
  String get searchRecommended => 'You might like';

  @override
  String get filterSongsHint => 'Search title or artist';

  @override
  String get searchNoResults => 'No results found';

  @override
  String searchFailed(String error) {
    return 'Search failed: $error';
  }

  @override
  String searchTotal(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count songs in total',
      one: '1 song in total',
    );
    return '$_temp0';
  }

  @override
  String get quality => 'Quality';

  @override
  String get qualityLoading => 'Loading qualities';

  @override
  String qualityFailed(String error) {
    return 'Failed to load qualities: $error';
  }

  @override
  String get qualityFailedRetry => 'Failed to load qualities, tap to retry';

  @override
  String get qualityNoneForSong => 'No qualities available for this song';

  @override
  String get qualityNone => 'No qualities available';

  @override
  String qualityWithReason(String quality, String reason) {
    return '$quality ($reason)';
  }

  @override
  String qualityDowngraded(String actual, String requested) {
    return '$actual (no access to $requested)';
  }

  @override
  String get qualityLow => 'Smooth 96k';

  @override
  String get qualityStandard => 'Standard 128k';

  @override
  String get qualityHigh => 'High 320k';

  @override
  String get qualityLossless => 'Lossless FLAC';

  @override
  String get qualityMaster => 'Master';

  @override
  String get qualityAtmos => 'Premium';

  @override
  String get qualityAtmos51 => 'Premium Surround 5.1';

  @override
  String get qualityAtmos71 => 'Premium Surround 7.1';

  @override
  String get qualityDolby => 'Dolby Atmos';

  @override
  String get qualityOgg320 => 'High OGG 320k';

  @override
  String get qualityAiCodec => 'AI audio';

  @override
  String get qualityVinyl => 'Vinyl';

  @override
  String get reasonUnsupported => 'format not supported by the player';

  @override
  String get reasonUnverified => 'not yet verified for playback';

  @override
  String get reasonNoPermission => 'no access on this account';

  @override
  String get reasonDeviceRestricted => 'restricted on this device';

  @override
  String get reasonNoLink => 'no link available';

  @override
  String get reasonVerifyFailed => 'check failed, try again later';

  @override
  String get reasonFileUnavailable => 'audio file unavailable';

  @override
  String get logout => 'Log out';

  @override
  String get loginPrompt =>
      'Log in to sync your playlists and play songs your account has access to';

  @override
  String get loginQq => 'Log in with QQ';

  @override
  String get loginWechat => 'Log in with WeChat';

  @override
  String get loginQqMusic => 'Log in with QQ Music app';

  @override
  String get loginCookie => 'Log in with cookie';

  @override
  String get noPlaylists => 'No playlists yet';

  @override
  String get qrLoading => 'Loading QR code…';

  @override
  String get qrScanHintQq => 'Scan with QQ on your phone';

  @override
  String get qrScanHintWechat => 'Scan with WeChat on your phone';

  @override
  String get qrScanHintQqMusic =>
      'Scan with the QQ Music app. You\'ll be logged in as that app\'s account.';

  @override
  String get qrScanned => 'Scanned. Confirm on your phone';

  @override
  String get qrExpired => 'QR code expired';

  @override
  String get qrRefused => 'Login was cancelled on your phone';

  @override
  String get qrRefresh => 'Refresh QR code';

  @override
  String get qrOpenQq => 'Log in with QQ app';

  @override
  String get qrQqNotInstalled => 'Couldn\'t open QQ. Is the QQ app installed?';

  @override
  String get qrSaveImage => 'Save QR code';

  @override
  String get qrSavedQq =>
      'Saved to gallery. In QQ\'s Scan, pick the image from your album.';

  @override
  String get qrOpenQqMusic => 'Authorize in QQ Music app';

  @override
  String get qrQqMusicNotInstalled =>
      'Couldn\'t open QQ Music. Is the QQ Music app installed?';

  @override
  String get qrWechatSameDeviceTip =>
      'WeChat can\'t log in on the same phone. If your QQ Music app uses a WeChat account, use \"Log in with QQ Music app\" instead.';

  @override
  String qrSaveFailed(String error) {
    return 'Save failed: $error';
  }

  @override
  String qrFailed(String error) {
    return 'Failed to get QR code: $error';
  }

  @override
  String get cookieLoginTitle => 'Cookie login';

  @override
  String get cookieLoginHint =>
      'Log in at y.qq.com in a browser, then copy the Cookie from developer tools and paste it here (it must include uin and qm_keyst).';

  @override
  String get login => 'Log in';

  @override
  String get swipeForLyrics => '← Swipe left for lyrics';

  @override
  String get noLyrics => 'No lyrics';

  @override
  String get modeSequence => 'Repeat all';

  @override
  String get modeRepeatOne => 'Repeat one';

  @override
  String get modeShuffle => 'Shuffle';

  @override
  String get lyrics => 'Lyrics';

  @override
  String get upNext => 'Up next';

  @override
  String get playNext => 'Play next';

  @override
  String get queuedNext => 'Will play next';

  @override
  String get alreadyPlaying => 'Already playing';

  @override
  String get volume => 'Volume';

  @override
  String get queue => 'Queue';

  @override
  String playbackError(String error) {
    return 'Playback error: $error';
  }

  @override
  String songUnplayable(String song, String error) {
    return 'Can\'t play \"$song\": $error';
  }

  @override
  String get errorNotLoggedIn => 'Not logged in';

  @override
  String get errorNoPlayableUrl =>
      'No playable link (login or VIP may be required)';

  @override
  String errorLoginFailed(String detail) {
    return 'Login failed: $detail';
  }

  @override
  String errorInvalidCookie(String field) {
    return 'Cookie is missing $field';
  }

  @override
  String errorServer(String code, String api) {
    return 'Server returned error code $code ($api)';
  }

  @override
  String errorBadResponse(String detail) {
    return 'Unexpected server response: $detail';
  }

  @override
  String errorNetwork(String detail) {
    return 'Network error: $detail';
  }

  @override
  String errorInternal(String detail) {
    return 'Internal error: $detail';
  }

  @override
  String get like => 'Like';

  @override
  String get unlike => 'Unlike';

  @override
  String get likeShort => 'Like';

  @override
  String get likedShort => 'Liked';

  @override
  String get liked => 'Added to Liked Songs';

  @override
  String get unliked => 'Removed from Liked Songs';

  @override
  String get addToPlaylist => 'Add to playlist';

  @override
  String addedToPlaylist(String name) {
    return 'Added to \"$name\"';
  }

  @override
  String get removeFromPlaylist => 'Remove from playlist';

  @override
  String removedFromPlaylist(String name) {
    return 'Removed from \"$name\"';
  }

  @override
  String actionFailed(String error) {
    return 'Failed: $error';
  }

  @override
  String get loginRequired => 'Please log in on the Mine tab first';

  @override
  String get noMyPlaylists => 'No playlists to add to';

  @override
  String get more => 'More';

  @override
  String singerNamed(String name) {
    return 'Artist: $name';
  }

  @override
  String albumNamed(String name) {
    return 'Album: $name';
  }

  @override
  String get comments => 'Comments';

  @override
  String get hotComments => 'Top comments';

  @override
  String get latestComments => 'Latest comments';

  @override
  String commentTotal(int count) {
    return '$count comments';
  }

  @override
  String get noComments => 'No comments yet';

  @override
  String get replies => 'Replies';

  @override
  String viewReplies(int count) {
    return 'View $count replies';
  }

  @override
  String replyTo(String name) {
    return 'Reply to $name: ';
  }

  @override
  String get loadMore => 'Load more';

  @override
  String get tabSongs => 'Songs';

  @override
  String get tabAlbums => 'Albums';

  @override
  String publishedOn(String date) {
    return 'Released $date';
  }

  @override
  String get settings => 'Settings';

  @override
  String get settingsGeneral => 'General';

  @override
  String get settingsCache => 'Cache';

  @override
  String get settingsAccount => 'Account';

  @override
  String get defaultQuality => 'Default quality';

  @override
  String get defaultQualityHint =>
      'Falls back to a lower quality when unavailable or unplayable';

  @override
  String get audioCacheLimit => 'Song cache limit';

  @override
  String get audioCacheLimitHint =>
      'Songs are saved while playing; least recently played are removed first';

  @override
  String get audioCacheOff => 'Off';

  @override
  String get audioCacheCustom => 'Custom';

  @override
  String get audioCacheCustomTitle => 'Custom cache limit';

  @override
  String get audioCacheCustomUnit => 'MB';

  @override
  String get audioCacheSize => 'Song cache';

  @override
  String get apiCacheSize => 'Other cache';

  @override
  String get apiCacheSizeHint => 'Playlists, search results, lyrics and more';

  @override
  String get clear => 'Clear';

  @override
  String get clearAudioCacheConfirm => 'Clear all cached songs?';

  @override
  String get clearApiCacheConfirm =>
      'Clear cached playlists, search results, lyrics and more?';

  @override
  String get cacheCleared => 'Cleared';

  @override
  String get logoutConfirm => 'Log out?';

  @override
  String get ok => 'OK';

  @override
  String get likedSongs => 'Liked songs';

  @override
  String get recentPlays => 'Recently played';

  @override
  String get myPlaylists => 'My playlists';

  @override
  String get playlistsCreated => 'Created';

  @override
  String get playlistsCollected => 'Saved';

  @override
  String get shufflePlay => 'Shuffle';

  @override
  String get seeAll => 'See all';

  @override
  String get renamePlaylist => 'Rename';

  @override
  String get deletePlaylist => 'Delete playlist';

  @override
  String get delete => 'Delete';

  @override
  String get playlistNameHint => 'Playlist name';

  @override
  String deletePlaylistConfirm(String name) {
    return 'Delete playlist \"$name\"? This can\'t be undone.';
  }

  @override
  String get playlistRenamed => 'Renamed';

  @override
  String get playlistDeleted => 'Playlist deleted';

  @override
  String get nothingPlaying => 'Nothing playing';

  @override
  String get searchKindSong => 'Songs';

  @override
  String get searchKindSinger => 'Artists';

  @override
  String get searchKindAlbum => 'Albums';

  @override
  String get searchKindPlaylist => 'Playlists';

  @override
  String get searchKindVideo => 'Videos';

  @override
  String get searchKindLyric => 'Lyrics';

  @override
  String searchTotalItems(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count results',
      one: '1 result',
    );
    return '$_temp0';
  }

  @override
  String singerStats(int songs, int albums) {
    return '$songs songs · $albums albums';
  }

  @override
  String get searchKindUser => 'Users';

  @override
  String get mvUnavailable => 'This video can\'t be played right now';

  @override
  String userFansFollows(String fans, String follows) {
    return '$fans followers · $follows following';
  }

  @override
  String userBriefStats(String fans, int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count playlists',
      one: '1 playlist',
    );
    return '$fans followers · $_temp0';
  }

  @override
  String userPlaylists(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count playlists',
      one: '1 playlist',
    );
    return '$_temp0';
  }

  @override
  String get userNoPlaylists => 'No public playlists';

  @override
  String userFans(String fans) {
    return '$fans followers';
  }
}
