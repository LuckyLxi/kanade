import '../data/song_json.dart';
import '../src/rust/api/error.dart';
import '../src/rust/api/types.dart';
import 'android_playback_connection.dart';
import 'player_controller.dart';
import 'player_error.dart';

/// 界面发给播放服务的命令；名字就是线上的 method。
enum PlaybackOp {
  playList,
  playRadio,
  playNext,
  playAt,
  removeAt,
  moveQueue,
  next,
  previous,
  play,
  pause,
  toggle,
  seek,
  restorePosition,
  mode,
  defaultQuality,
  fade,
  sleep,
  sleepAfterSong,
  volume,
  quality,
  auth,
  locale,
  like,
  cacheInfo,
  cacheLimit,
  clearAudioCache,
}

PlaybackMessage encodePlayerState(
  PlayerController player, {
  required bool includeQueue,
}) => {
  if (includeQueue) 'queue': player.queue.map(songToJson).toList(),
  'index': player.index,
  'playing': player.playing,
  'loading': player.loading,
  'buffering': player.buffering,
  'duration': player.duration.inMilliseconds,
  'defaultQuality': player.defaultQuality.name,
  'quality': player.quality.name,
  'actualQuality': player.actualQuality?.name,
  'mode': player.mode.name,
  'volume': player.volume,
  'fade': player.fade.inSeconds,
  'sleepAt': player.sleepAt?.millisecondsSinceEpoch,
  'sleepAfterSong': player.sleepAfterSong,
  'error': encodePlayerError(player.error),
};

void decodePlayerState(PlayerController player, PlaybackMessage message) {
  if (message['queue'] case final List<Object?> items) {
    player.queue = items
        .cast<Map<String, dynamic>>()
        .map(songFromJson)
        .toList();
  }
  player.index = message['index'] as int;
  player.playing = message['playing'] as bool;
  player.loading = message['loading'] as bool;
  player.buffering = message['buffering'] as bool;
  player.duration = Duration(milliseconds: message['duration'] as int);
  player.defaultQuality = Quality.values.byName(
    message['defaultQuality'] as String,
  );
  player.quality = Quality.values.byName(message['quality'] as String);
  player.actualQuality = Quality.values.asNameMap()[message['actualQuality']];
  player.mode = PlayMode.values.byName(message['mode'] as String);
  player.volume = (message['volume'] as num).toDouble();
  player.fade = Duration(seconds: message['fade'] as int);
  player.sleepAt = switch (message['sleepAt']) {
    final int ms => DateTime.fromMillisecondsSinceEpoch(ms),
    _ => null,
  };
  player.sleepAfterSong = message['sleepAfterSong'] as bool;
  player.error = decodePlayerError(message['error']);
}

List<Object?> encodePlaybackException(Object error) => switch (error) {
  ApiError_NotLoggedIn() => ['notLoggedIn'],
  ApiError_NoPlayableUrl() => ['noPlayableUrl'],
  ApiError_UnsupportedFormat() => ['unsupportedFormat'],
  ApiError_UnverifiedFormat() => ['unverifiedFormat'],
  ApiError_LoginFailed(:final detail) => ['loginFailed', detail],
  ApiError_InvalidCookie(:final missing) => ['invalidCookie', missing],
  ApiError_ServerError(:final api, :final code) => ['serverError', api, code],
  ApiError_BadResponse(:final detail) => ['badResponse', detail],
  ApiError_Network(:final detail) => ['network', detail],
  ApiError_Internal(:final detail) => ['internal', detail],
  _ => ['message', error.toString()],
};

Object decodePlaybackException(Object? value) => switch (value) {
  ['notLoggedIn'] => const ApiError.notLoggedIn(),
  ['noPlayableUrl'] => const ApiError.noPlayableUrl(),
  ['unsupportedFormat'] => const ApiError.unsupportedFormat(),
  ['unverifiedFormat'] => const ApiError.unverifiedFormat(),
  ['loginFailed', String detail] => ApiError.loginFailed(detail: detail),
  ['invalidCookie', String missing] => ApiError.invalidCookie(missing: missing),
  ['serverError', String api, String code] => ApiError.serverError(
    api: api,
    code: code,
  ),
  ['badResponse', String detail] => ApiError.badResponse(detail: detail),
  ['network', String detail] => ApiError.network(detail: detail),
  ['internal', String detail] => ApiError.internal(detail: detail),
  ['message', String message] => message,
  _ => StateError('Invalid playback error'),
};

Object? encodePlayerError(PlayerError? error) => switch (error) {
  PlaybackFailed(:final song, :final cause) => [
    songToJson(song),
    encodePlaybackException(cause),
  ],
  StreamFailed(:final message) => message,
  null => null,
};

PlayerError? decodePlayerError(Object? value) => switch (value) {
  [Map<String, dynamic> song, final cause] => PlaybackFailed(
    songFromJson(song),
    decodePlaybackException(cause),
  ),
  String message => StreamFailed(message),
  _ => null,
};
