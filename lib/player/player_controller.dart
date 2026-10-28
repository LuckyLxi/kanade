import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:media_kit/media_kit.dart';

import '../auth/auth_controller.dart';
import '../src/rust/api/music.dart' as api;
import '../src/rust/api/types.dart';

enum PlayMode { sequence, repeatOne, shuffle }

/// 播放错误。文案在界面层按当前语言生成。
sealed class PlayerError {
  const PlayerError();
}

class PlaybackFailed extends PlayerError {
  const PlaybackFailed(this.song, this.cause);

  final Song song;
  final Object cause;
}

/// media_kit 播放过程中报告的错误原文。
class StreamFailed extends PlayerError {
  const StreamFailed(this.message);

  final String message;
}

/// 播放队列 + media_kit 播放器。播放链接和歌词都由 Rust 层提供。
class PlayerController extends ChangeNotifier {
  PlayerController(this._auth) {
    _auth.addListener(_onAuthChanged);
    _subs.addAll([
      _player.stream.playing.listen((v) {
        playing = v;
        notifyListeners();
      }),
      _player.stream.buffering.listen((v) {
        buffering = v;
        notifyListeners();
      }),
      _player.stream.position.listen((v) => position.value = v),
      _player.stream.duration.listen((v) {
        duration = v;
        notifyListeners();
      }),
      _player.stream.completed.listen((done) {
        if (done) _onCompleted();
      }),
      _player.stream.error.listen((e) {
        error = StreamFailed(e);
        notifyListeners();
      }),
    ]);
  }

  final Player _player = Player(configuration: const PlayerConfiguration(title: 'Kanade'));
  final AuthController _auth;
  final List<StreamSubscription> _subs = [];
  final _random = Random();

  List<Song> queue = [];
  int index = -1;

  /// 播放器里选择的音质，切歌后继续沿用；歌曲没有该档位时 Rust 层会降级。
  Quality quality = Quality.high;
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

  /// 每次重新取播放链接（切歌或切音质）递增。
  int _urlToken = 0;

  Song? get current => index >= 0 && index < queue.length ? queue[index] : null;

  /// 电台模式（猜你喜欢、刷歌）下用来取下一批歌；普通播放列表为 null。
  Future<List<Song>> Function()? _radio;
  bool _radioLoading = false;

  Future<void> playList(List<Song> songs, int start) async {
    _radio = null;
    queue = List.of(songs);
    await playAt(start);
  }

  /// 开始电台播放。第一批取不到时抛出异常，由调用方提示。
  Future<void> playRadio(Future<List<Song>> Function() fetch) async {
    final first = await fetch();
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
    index = i;
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
      final u = await api.getSongUrl(mid: song.mid, mediaMid: song.mediaMid, quality: quality);
      if (token != _token || urlToken != _urlToken) return;
      actualQuality = u.quality;
      await _player.open(_media(u.url));
    } catch (e) {
      if (token != _token || urlToken != _urlToken) return;
      error = PlaybackFailed(song, e);
      // 自动跳过无法播放的歌，整个队列都失败时停下
      if (queue.length > 1 && skipped < queue.length - 1) {
        loading = false;
        notifyListeners();
        await playAt((i + 1) % queue.length, skipped: skipped + 1);
        return;
      }
    }
    loading = false;
    notifyListeners();
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

  Future<void> toggle() => _player.playOrPause();

  Future<void> seek(Duration d) => _player.seek(d);

  void cycleMode() => setMode(PlayMode.values[(mode.index + 1) % PlayMode.values.length]);

  void setMode(PlayMode m) {
    mode = m;
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
      final u = await api.getSongUrl(mid: song.mid, mediaMid: song.mediaMid, quality: q);
      if (token != _token || urlToken != _urlToken) return;
      actualQuality = u.quality;
      await _player.open(_media(u.url, start: position.value), play: playing);
    } catch (e) {
      if (token != _token || urlToken != _urlToken) return;
      quality = previous;
      error = PlaybackFailed(song, e);
    }
    loading = false;
    notifyListeners();
  }

  static Media _media(String url, {Duration? start}) =>
      Media(url, httpHeaders: const {'Referer': 'https://y.qq.com/'}, start: start);

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
