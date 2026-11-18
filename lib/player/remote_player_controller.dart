part of 'player_controller.dart';

class _RemotePlayerController extends PlayerController {
  _RemotePlayerController(
    super.auth,
    this._library,
    this._locale,
    String directory, {
    AndroidPlaybackConnection Function(String, void Function(PlaybackMessage))?
    connectionFactory,
  }) : super._() {
    _connection =
        (connectionFactory ??
        (directory, onUpdate) => AndroidPlaybackConnection(
          directory,
          onUpdate,
          onRestart: _resumePosition,
        ))(directory, _applyUpdate);
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
  bool _resuming = false;

  void _connect() {
    _connection.setWatching(true);
    _ignore(_connection.connect());
  }

  // 新拉起的播放进程从会话里恢复了同一首歌，但进度归零：把界面记得的进度交给它，
  // 按播放键时从这里接着放。只存在内存里，两个进程都重启时还是从头开始。
  // 交回之前它报上来的 0 不显示，进度条不会闪回开头
  void _resumePosition() {
    final at = position.value;
    if (current == null || at == Duration.zero) return;
    _resuming = true;
    _ignore(restorePosition(at).whenComplete(() => _resuming = false));
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
    _lastLike = null;
    _ignore(_connection.call(PlaybackOp.auth));
  }

  void _syncLocale() => _ignore(_connection.call(PlaybackOp.locale));

  void _syncLiked() {
    final song = current;
    if (song == null || !_library.canLike) return;
    final liked = _library.isLiked(song);
    final key = (song.mid, liked);
    if (_lastLike == key) return;
    _lastLike = key;
    _ignore(_connection.call(PlaybackOp.like, [songToJson(song), liked]));
  }

  void _applyUpdate(PlaybackMessage message) {
    if (_disposed) return;
    if (message['position'] case final int milliseconds) {
      if (_resuming) return;
      position.value = Duration(milliseconds: milliseconds);
      return;
    }
    final before = current?.mid;
    decodePlayerState(this, message);
    if (before != current?.mid) _refreshDisplayMetadata();
    if (current case final song?) {
      if (message['liked'] case final bool liked) {
        _lastLike = (song.mid, liked);
        _library.updateLiked(song, liked);
      }
    }
    notifyListeners();
  }

  Future<void> _send(PlaybackOp op, [Object? arguments]) async {
    await _connection.call(op, arguments);
  }

  static List<Map<String, Object?>> _songs(List<Song> songs) =>
      songs.map(songToJson).toList();

  @override
  Future<void> playList(List<Song> songs, int start) =>
      _send(PlaybackOp.playList, [_songs(songs), start]);

  @override
  Future<void> playRadio(RadioSource source, {List<Song>? first}) => _send(
    PlaybackOp.playRadio,
    [source.kind, source.seed, source.id, first == null ? null : _songs(first)],
  );

  @override
  PlayNextResult playNext(Song song) {
    if (current?.mid == song.mid) return PlayNextResult.current;
    _ignore(_send(PlaybackOp.playNext, songToJson(song)));
    return current == null ? PlayNextResult.started : PlayNextResult.queued;
  }

  @override
  Future<void> playAt(int i) => _send(PlaybackOp.playAt, i);

  // 删除和挪动先改界面这边的队列，拖完松手列表不会先弹回原位再等播放服务的快照
  @override
  Future<void> removeAt(int i) {
    if (i < 0 || i >= queue.length) return Future.value();
    final before = current?.mid;
    final (q, n) = removeFromQueue(queue, index, i);
    queue = q;
    index = n;
    if (before != current?.mid) _refreshDisplayMetadata();
    notifyListeners();
    return _send(PlaybackOp.removeAt, i);
  }

  @override
  void moveQueue(int from, int to) {
    if (from == to ||
        from < 0 ||
        from >= queue.length ||
        to < 0 ||
        to >= queue.length) {
      return;
    }
    final (q, n) = moveInQueue(queue, index, from, to);
    queue = q;
    index = n;
    notifyListeners();
    _ignore(_send(PlaybackOp.moveQueue, [from, to]));
  }

  @override
  Future<void> next() => _send(PlaybackOp.next);

  @override
  Future<void> previous() => _send(PlaybackOp.previous);

  @override
  Future<void> play() => _send(PlaybackOp.play);

  @override
  Future<void> pause() => _send(PlaybackOp.pause);

  @override
  Future<void> toggle() => _send(PlaybackOp.toggle);

  @override
  Future<void> seek(Duration d) => _send(PlaybackOp.seek, d.inMilliseconds);

  @override
  Future<void> restorePosition(Duration d) =>
      _send(PlaybackOp.restorePosition, d.inMilliseconds);

  @override
  void setMode(PlayMode m) {
    mode = m;
    notifyListeners();
    _ignore(_send(PlaybackOp.mode, m.name));
  }

  @override
  void setDefaultQuality(Quality q) {
    defaultQuality = quality = q;
    notifyListeners();
    _ignore(_send(PlaybackOp.defaultQuality, q.name));
  }

  @override
  void setFade(Duration d) {
    fade = d;
    notifyListeners();
    _ignore(_send(PlaybackOp.fade, d.inSeconds));
  }

  // 定时在播放服务里走，界面退到后台或被回收也照样到点停
  @override
  void setSleepTimer(Duration? d) {
    sleepAt = d == null ? null : DateTime.now().add(d);
    notifyListeners();
    _ignore(_send(PlaybackOp.sleep, d?.inSeconds));
  }

  @override
  void setSleepAfterSong(bool v) {
    sleepAfterSong = v;
    notifyListeners();
    _ignore(_send(PlaybackOp.sleepAfterSong, v));
  }

  @override
  Future<void> setVolume(double v) {
    volume = v.clamp(0, 100);
    notifyListeners();
    return _send(PlaybackOp.volume, volume);
  }

  @override
  Future<void> setQuality(Quality q) => _send(PlaybackOp.quality, q.name);

  @override
  Future<({int limitMb, int bytes})> audioCacheInfo() async {
    final value = await _connection.call(PlaybackOp.cacheInfo) as List<Object?>;
    return (limitMb: value[0] as int, bytes: value[1] as int);
  }

  @override
  Future<void> setAudioCacheLimit(int mb) => _send(PlaybackOp.cacheLimit, mb);

  @override
  Future<void> clearAudioCache() => _send(PlaybackOp.clearAudioCache);

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
