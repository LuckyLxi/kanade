import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:media_kit/media_kit.dart';

import '../auth/auth_controller.dart';
import '../src/rust/api/music.dart' as api;
import '../src/rust/api/types.dart';
import 'audio_source.dart';
import 'player_error.dart';

enum PlayMode { sequence, repeatOne, shuffle }

/// 刚打开、还没加载成功的音源。这时出错就降一档重试。
class _Attempt {
  _Attempt(this.song, this.source, this.start, this.play, this.token, this.urlToken);

  final Song song;
  final AudioSource source;
  final Duration? start;
  final bool play;
  final int token;
  final int urlToken;
}

/// 播放队列 + media_kit 播放器。播放链接和歌词都由 Rust 层提供。
class PlayerController extends ChangeNotifier {
  PlayerController(this._auth) {
    _auth.addListener(_onAuthChanged);
    _subs.addAll([
      _player.stream.playing.listen((v) {
        // 一首放完时 mpv 会先报「暂停」，紧接着就自动切下一首。不能把它当成暂停告诉系统，
        // 否则 Android 会撤掉后台播放服务和唤醒锁，切歌时在后台重新起不来，
        // 结果是被杀后台，或者进度在走却没声音。
        if (!v && _atEnd()) return;
        playing = v;
        _reportPlay();
        notifyListeners();
      }),
      _player.stream.buffering.listen((v) {
        buffering = v;
        notifyListeners();
      }),
      _player.stream.position.listen((v) => position.value = v),
      _player.stream.duration.listen((v) {
        duration = v;
        // 拿到时长说明音源已经加载成功
        if (v > Duration.zero) _attempt = null;
        _reportPlay();
        notifyListeners();
      }),
      _player.stream.completed.listen((done) {
        if (done) _onCompleted();
      }),
      _player.stream.error.listen((e) {
        // 个别音频帧解不出来（多见于文件开头结尾），mpv 会跳过继续放，不算出错
        if (e.startsWith('Error decoding')) return;
        if (_attempt != null) {
          _downgrade(e);
          return;
        }
        error = StreamFailed(e);
        notifyListeners();
      }),
    ]);
    _restoreSession();
  }

  final Player _player = Player(configuration: const PlayerConfiguration(title: 'Kanade'));
  final AuthController _auth;
  final List<StreamSubscription> _subs = [];
  final _random = Random();

  List<Song> queue = [];
  int index = -1;

  static const _defaultQualityKey = 'default_quality';
  static const _sessionKey = 'last_session';

  /// 上次的队列是启动时恢复出来的，还没取过音源：按播放键时才真正打开。
  bool _restored = false;

  /// 设置里的默认音质，启动时作为播放器的初始音质。
  Quality defaultQuality = Quality.values.asNameMap()[api.getPref(key: _defaultQualityKey)] ?? Quality.high;

  /// 播放器里选择的音质，切歌后继续沿用；歌曲没有该档位或播不了时会降级。
  late Quality quality = defaultQuality;
  PlayMode mode = PlayMode.sequence;

  bool playing = false;
  bool buffering = false;
  bool loading = false;
  Duration duration = Duration.zero;
  final ValueNotifier<Duration> position = ValueNotifier(Duration.zero);

  /// 实际播放的音质（请求的音质不可用时 Rust 层会降级）。
  Quality? actualQuality;
  List<QualityOption> qualityOptions = [];
  bool qualitiesLoading = false;
  Object? qualitiesError;
  Lyric? lyric;
  PlayerError? error;

  /// 每次切歌递增，用来丢弃过期的异步结果。
  int _token = 0;
  int _qualitiesToken = 0;

  /// 每次重新取播放链接（切歌、切音质或降级重试）递增。
  int _urlToken = 0;

  _Attempt? _attempt;

  /// 当前这首歌之前已经连续跳过了几首播不了的歌。
  int _skipped = 0;

  /// 已经上报过最近播放的那次切歌（`_token`），切音质、拖进度不再重复上报。
  int _reportedToken = -1;

  /// 歌曲加载成功并真正开始播放后，记一次云端最近播放。只在登录时，失败不影响播放。
  void _reportPlay() {
    final song = current;
    if (song == null || !playing || _attempt != null || _player.state.duration <= Duration.zero) return;
    if (_reportedToken == _token || !_auth.loggedIn) return;
    _reportedToken = _token;
    api.reportPlay(songId: song.id).ignore();
  }

  /// 当前这首已经放到结尾（马上会自动切歌）。
  bool _atEnd() {
    final s = _player.state;
    return s.completed || (s.duration > Duration.zero && s.position >= s.duration - const Duration(seconds: 1));
  }

  /// 切歌失败停下来时，按播放器的真实状态更新（放完时报的暂停之前被忽略了）。
  void _syncPlaying() => playing = _player.state.playing;

  Song? get current => index >= 0 && index < queue.length ? queue[index] : null;

  /// 电台模式（猜你喜欢、刷歌）下用来取下一批歌；普通播放列表为 null。
  Future<List<Song>> Function()? _radio;
  bool _radioLoading = false;

  Future<void> playList(List<Song> songs, int start) async {
    _radio = null;
    queue = List.of(songs);
    await playAt(start);
  }

  /// 开始电台播放。`first` 是已经预取到的第一批（比如首页卡片封面用的那批），
  /// 没有就现取；第一批取不到时抛出异常，由调用方提示。
  Future<void> playRadio(Future<List<Song>> Function() fetch, {List<Song>? first}) async {
    first ??= await fetch();
    if (first.isEmpty) throw StateError('radio returned no songs');
    _radio = fetch;
    queue = List.of(first);
    await playAt(0);
  }

  /// 往电台队列末尾补一批，跳过已经在队列里的歌。返回是否补到了新歌。
  Future<bool> _extendRadio() async {
    final fetch = _radio;
    if (fetch == null || _radioLoading) return false;
    _radioLoading = true;
    try {
      final known = {for (final s in queue) s.mid};
      final more = (await fetch()).where((s) => known.add(s.mid)).toList();
      if (_radio != fetch || more.isEmpty) return false;
      queue = [...queue, ...more];
      _saveSession();
      notifyListeners();
      return true;
    } catch (_) {
      return false;
    } finally {
      _radioLoading = false;
    }
  }

  Future<void> playAt(int i, {int skipped = 0}) async {
    if (i < 0 || i >= queue.length) return;
    final token = ++_token;
    final urlToken = ++_urlToken;
    _attempt = null;
    _skipped = skipped;
    _restored = false;
    index = i;
    _saveSession();
    loading = true;
    error = null;
    lyric = null;
    actualQuality = null;
    position.value = Duration.zero;
    duration = Duration(seconds: queue[i].durationSecs);
    notifyListeners();

    final song = queue[i];
    // 电台快放完时提前取下一批，切歌时不用等
    if (_radio != null && i >= queue.length - 2) unawaited(_extendRadio());
    unawaited(refreshQualities());
    _loadLyric(song, token);
    try {
      await _open(song, quality, token: token, urlToken: urlToken);
    } catch (e) {
      if (token != _token || urlToken != _urlToken) return;
      error = PlaybackFailed(song, e);
      if (await _skipFailed()) return;
      _syncPlaying();
    }
    // 降级重试已经接手时由它收尾
    if (token != _token || urlToken != _urlToken) return;
    loading = false;
    notifyListeners();
  }

  /// 自动跳过无法播放的歌，整个队列都失败时停下。返回是否跳了。
  Future<bool> _skipFailed() async {
    if (queue.length <= 1 || _skipped >= queue.length - 1) return false;
    loading = false;
    notifyListeners();
    await playAt((index + 1) % queue.length, skipped: _skipped + 1);
    return true;
  }

  /// 取音源并交给播放器。取不到任何音质的链接时抛出异常；
  /// 拿到了却播不了的情况由 [_downgrade] 处理。
  Future<void> _open(Song song, Quality q,
      {required int token, required int urlToken, Duration? start, bool play = true}) async {
    bool stale() => token != _token || urlToken != _urlToken;
    final src = await AudioSource.resolve(song, q, stale: stale);
    if (src == null || stale()) return;
    actualQuality = src.quality;
    _attempt = _Attempt(song, src, start, play, token, urlToken);
    try {
      await _player.open(src.media(start: start), play: play);
    } catch (e) {
      _downgrade(e);
    }
  }

  /// 音源加载失败：缓存文件坏了就删掉重新在线取，在线的就降一档，降到底算这首歌播不了。
  void _downgrade(Object cause) {
    final a = _attempt;
    _attempt = null;
    if (a == null || a.token != _token || a.urlToken != _urlToken) return;
    final next = a.source.fallback();
    unawaited(() async {
      try {
        if (next == null) throw cause;
        final urlToken = ++_urlToken;
        loading = true;
        notifyListeners();
        await _open(a.song, next, token: a.token, urlToken: urlToken, start: a.start, play: a.play);
        if (a.token != _token || urlToken != _urlToken) return;
      } catch (e) {
        if (a.token != _token) return;
        error = PlaybackFailed(a.song, e);
        if (await _skipFailed()) return;
        _syncPlaying();
      }
      loading = false;
      notifyListeners();
    }());
  }

  Future<void> _loadLyric(Song song, int token) async {
    try {
      final l = await api.getLyric(mid: song.mid, id: song.id);
      if (token != _token) return;
      lyric = l;
      notifyListeners();
    } catch (_) {}
  }

  void _onAuthChanged() => unawaited(refreshQualities());

  Future<void> refreshQualities() async {
    final song = current;
    final token = ++_qualitiesToken;
    qualityOptions = [];
    qualitiesError = null;
    qualitiesLoading = song != null;
    notifyListeners();
    if (song == null) return;
    try {
      final options = await api.getSongQualities(mid: song.mid);
      if (token != _qualitiesToken) return;
      qualityOptions = options;
    } catch (e) {
      if (token != _qualitiesToken) return;
      qualitiesError = e;
    }
    if (token != _qualitiesToken) return;
    qualitiesLoading = false;
    notifyListeners();
  }

  void _onCompleted() {
    if (queue.isEmpty) return;
    if (mode == PlayMode.repeatOne) {
      _player.seek(Duration.zero);
      _player.play();
    } else {
      next();
    }
  }

  Future<void> next() async {
    if (queue.isEmpty) return;
    // 电台按顺序往下播，到头时现取一批，取不到才回到开头
    if (_radio != null) {
      if (index + 1 >= queue.length) await _extendRadio();
      await playAt((index + 1) % queue.length);
      return;
    }
    if (mode == PlayMode.shuffle && queue.length > 1) {
      var n = index;
      while (n == index) {
        n = _random.nextInt(queue.length);
      }
      await playAt(n);
    } else {
      await playAt((index + 1) % queue.length);
    }
  }

  Future<void> previous() async {
    if (queue.isEmpty) return;
    if (position.value > const Duration(seconds: 5)) {
      await _player.seek(Duration.zero);
      return;
    }
    await playAt((index - 1 + queue.length) % queue.length);
  }

  Future<void> toggle() => playing ? pause() : play();

  Future<void> play() => _restored ? playAt(index) : _player.play();

  Future<void> pause() async {
    await _player.pause();
    // 快放完时按暂停，播放器报的暂停会被当成放完而忽略，这里补上
    _syncPlaying();
    notifyListeners();
  }

  Future<void> seek(Duration d) => _player.seek(d);

  /// 设置里改默认音质：保存下来，并从下一首开始使用。
  void setDefaultQuality(Quality q) {
    defaultQuality = q;
    quality = q;
    api.setPref(key: _defaultQualityKey, value: q.name);
    notifyListeners();
  }

  void cycleMode() => setMode(PlayMode.values[(mode.index + 1) % PlayMode.values.length]);

  void setMode(PlayMode m) {
    mode = m;
    _saveSession();
    notifyListeners();
  }

  /// 音量 0–100。
  double volume = 100;

  Future<void> setVolume(double v) {
    volume = v.clamp(0, 100);
    notifyListeners();
    return _player.setVolume(volume);
  }

  /// 切换当前歌曲的音质：从当前进度继续播放，暂停状态保持暂停。
  /// 取链接失败时继续播放原来的音质。
  Future<void> setQuality(Quality q) async {
    final song = current;
    final previous = quality;
    quality = q;
    if (song == null || q == actualQuality) {
      notifyListeners();
      return;
    }
    final token = _token;
    final urlToken = ++_urlToken;
    loading = true;
    error = null;
    notifyListeners();
    try {
      await _open(song, q, token: token, urlToken: urlToken, start: position.value, play: playing);
      if (token != _token || urlToken != _urlToken) return;
    } catch (e) {
      if (token != _token || urlToken != _urlToken) return;
      quality = previous;
      error = PlaybackFailed(song, e);
    }
    loading = false;
    notifyListeners();
  }

  /// 记下队列、当前歌曲和播放模式，下次启动时播放栏还显示这首。
  void _saveSession() {
    if (current == null) return;
    api.setPref(
      key: _sessionKey,
      value: jsonEncode({'queue': [for (final s in queue) _songToJson(s)], 'index': index, 'mode': mode.name}),
    );
  }

  /// 恢复上次的队列，只显示不播放。电台模式恢复成普通列表。
  void _restoreSession() {
    final raw = api.getPref(key: _sessionKey);
    if (raw == null) return;
    try {
      final m = jsonDecode(raw) as Map<String, dynamic>;
      final songs = [for (final s in m['queue'] as List) _songFromJson(s as Map<String, dynamic>)];
      final i = m['index'] as int;
      if (i < 0 || i >= songs.length) return;
      queue = songs;
      index = i;
      mode = PlayMode.values.asNameMap()[m['mode']] ?? mode;
      duration = Duration(seconds: songs[i].durationSecs);
      _restored = true;
    } catch (_) {
      return;
    }
    // 播放页打开时就能看到歌词和音质
    unawaited(refreshQualities());
    _loadLyric(queue[index], _token);
  }

  static Map<String, Object?> _songToJson(Song s) => {
        'id': s.id,
        'mid': s.mid,
        'name': s.name,
        'singers': [for (final g in s.singers) {'mid': g.mid, 'name': g.name}],
        'albumMid': s.albumMid,
        'albumName': s.albumName,
        'durationSecs': s.durationSecs,
        'mediaMid': s.mediaMid,
        'coverUrl': s.coverUrl,
        'vip': s.vip,
        'hasHq': s.hasHq,
        'hasFlac': s.hasFlac,
      };

  static Song _songFromJson(Map<String, dynamic> m) => Song(
        id: m['id'] as int,
        mid: m['mid'] as String,
        name: m['name'] as String,
        singers: [
          for (final g in m['singers'] as List)
            Singer(mid: (g as Map)['mid'] as String, name: g['name'] as String),
        ],
        albumMid: m['albumMid'] as String,
        albumName: m['albumName'] as String,
        durationSecs: m['durationSecs'] as int,
        mediaMid: m['mediaMid'] as String,
        coverUrl: m['coverUrl'] as String,
        vip: m['vip'] as bool,
        hasHq: m['hasHq'] as bool,
        hasFlac: m['hasFlac'] as bool,
      );

  /// 当前应高亮的歌词行。
  int lyricIndexAt(Duration pos) {
    final lines = lyric?.lines ?? const [];
    final ms = pos.inMilliseconds;
    var lo = 0, hi = lines.length - 1, ans = -1;
    while (lo <= hi) {
      final mid = (lo + hi) >> 1;
      if (lines[mid].timeMs <= ms) {
        ans = mid;
        lo = mid + 1;
      } else {
        hi = mid - 1;
      }
    }
    return ans;
  }

  @override
  void dispose() {
    ++_qualitiesToken;
    _auth.removeListener(_onAuthChanged);
    for (final s in _subs) {
      s.cancel();
    }
    _player.dispose();
    position.dispose();
    super.dispose();
  }
}
