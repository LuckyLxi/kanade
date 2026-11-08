part of 'player_controller.dart';

class _RemotePlayerController extends PlayerController {
  _RemotePlayerController(
    super.auth,
    this._library,
    this._locale,
    String directory,
  ) : super._remote() {
    _connection = AndroidPlaybackConnection(directory, _applyUpdate);
    _lifecycle = AppLifecycleListener(
      onResume: _connect,
      onPause: () => _connection.setWatching(false),
    );
    _auth.addListener(_syncAuth);
    _library.addListener(_syncLiked);
    _locale.addListener(_syncLocale);
    _connect();
  }

  final LibraryController _library;
  final LocaleController _locale;
  late final AndroidPlaybackConnection _connection;
  late final AppLifecycleListener _lifecycle;
  (String, bool)? _lastLike;
  bool _disposed = false;

  void _connect() {
    _connection.setWatching(true);
    _ignore(_connection.connect());
  }

  void _ignore(Future<Object?> future) {
    unawaited(
      future.then<void>(
        (_) {},
        onError: (Object failure) {
          if (_disposed) return;
          error = StreamFailed(failure.toString());
          notifyListeners();
        },
      ),
    );
  }

  void _syncAuth() {
    _onAuthChanged();
    _lastLike = null;
    _ignore(_connection.call('auth'));
  }

  void _syncLocale() => _ignore(_connection.call('locale'));

  void _syncLiked() {
    final song = current;
    if (song == null || !_library.canLike) return;
    final liked = _library.isLiked(song);
    final key = (song.mid, liked);
    if (_lastLike == key) return;
    _lastLike = key;
    _ignore(
      _connection.call('like', [PlayerSessionStore.songToJson(song), liked]),
    );
  }

  void _applyUpdate(PlaybackMessage message) {
    if (_disposed) return;
    if (message['position'] case final int milliseconds) {
      position.value = Duration(milliseconds: milliseconds);
      return;
    }
    final before = current?.mid;
    if (message['queue'] case final List<Object?> items) {
      queue = items
          .cast<Map<String, dynamic>>()
          .map(PlayerSessionStore.songFromJson)
          .toList();
    }
    index = message['index'] as int;
    playing = message['playing'] as bool;
    loading = message['loading'] as bool;
    buffering = message['buffering'] as bool;
    duration = Duration(milliseconds: message['duration'] as int);
    defaultQuality = Quality.values.byName(message['defaultQuality'] as String);
    quality = Quality.values.byName(message['quality'] as String);
    actualQuality = Quality.values.asNameMap()[message['actualQuality']];
    mode = PlayMode.values.byName(message['mode'] as String);
    volume = (message['volume'] as num).toDouble();
    error = decodePlayerError(message['error']);
    if (current case final song?) {
      if (message['liked'] case final bool liked) {
        _lastLike = (song.mid, liked);
        _library.updateLiked(song, liked);
      }
      if (before != song.mid) {
        lyric = null;
        unawaited(refreshQualities());
        _loadLyric(song, ++_token);
      }
    }
    notifyListeners();
  }

  Future<void> _send(String method, [Object? arguments]) async {
    await _connection.call(method, arguments);
  }

  static List<Map<String, Object?>> _songs(List<Song> songs) =>
      songs.map(PlayerSessionStore.songToJson).toList();

  @override
  Future<void> playList(List<Song> songs, int start) =>
      _send('playList', [_songs(songs), start]);

  @override
  Future<void> playRadio(RadioSource source, {List<Song>? first}) => _send(
    'playRadio',
    [source.kind, source.seed, source.id, first == null ? null : _songs(first)],
  );

  @override
  PlayNextResult playNext(Song song) {
    if (current?.mid == song.mid) return PlayNextResult.current;
    _ignore(_send('playNext', PlayerSessionStore.songToJson(song)));
    return current == null ? PlayNextResult.started : PlayNextResult.queued;
  }

  @override
  Future<void> playAt(int i, {int skipped = 0, int pinnedNext = 0}) =>
      _send('playAt', i);

  @override
  Future<void> next() => _send('next');

  @override
  Future<void> previous() => _send('previous');

  @override
  Future<void> play() => _send('play');

  @override
  Future<void> pause() => _send('pause');

  @override
  Future<void> toggle() => _send('toggle');

  @override
  Future<void> seek(Duration d) => _send('seek', d.inMilliseconds);

  @override
  void setMode(PlayMode m) {
    mode = m;
    notifyListeners();
    _ignore(_send('mode', m.name));
  }

  @override
  void setDefaultQuality(Quality q) {
    defaultQuality = quality = q;
    notifyListeners();
    _ignore(_send('defaultQuality', q.name));
  }

  @override
  Future<void> setVolume(double v) {
    volume = v.clamp(0, 100);
    notifyListeners();
    return _send('volume', volume);
  }

  @override
  Future<void> setQuality(Quality q) => _send('quality', q.name);

  @override
  Future<({int limitMb, int bytes})> audioCacheInfo() async {
    final value = await _connection.call('cacheInfo') as List<Object?>;
    return (limitMb: value[0] as int, bytes: value[1] as int);
  }

  @override
  Future<void> setAudioCacheLimit(int mb) => _send('cacheLimit', mb);

  @override
  Future<void> clearAudioCache() => _send('clearAudioCache');

  @override
  void dispose() {
    _disposed = true;
    _auth.removeListener(_syncAuth);
    _library.removeListener(_syncLiked);
    _locale.removeListener(_syncLocale);
    _lifecycle.dispose();
    _connection.dispose();
    super.dispose();
  }
}
