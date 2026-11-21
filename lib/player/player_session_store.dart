import 'dart:convert';

import '../data/song_json.dart';
import '../src/rust/api/music.dart' as api;
import '../src/rust/api/types.dart';

/// 播放会话的存储格式；播放模式由控制器解释。
/// 队列单独存一份，只在换了队列时重写：切歌只改位置，长队列不用每次都整个写一遍。
class PlayerSessionStore {
  static const _key = 'last_session';
  static const _queueKey = 'last_session_queue';

  /// 上次写进去（或读出来）的队列。控制器改队列总是换一个新列表，同一个就不用再写。
  List<Song>? _written;

  ({List<Song> queue, int index, String? mode, Map<String, dynamic>? radio})?
  read() {
    final raw = api.getPref(key: _key);
    if (raw == null) return null;
    try {
      final m = jsonDecode(raw) as Map<String, dynamic>;
      // 旧版本把队列和位置存在一起
      final list = m['queue'] ?? jsonDecode(api.getPref(key: _queueKey)!);
      final songs = [
        for (final s in list as List) songFromJson(s as Map<String, dynamic>),
      ];
      final index = m['index'] as int;
      if (index < 0 || index >= songs.length) return null;
      // 队列和位置分两次写，中间退出时两边对不上
      if (m['mid'] case final String mid when songs[index].mid != mid) {
        return null;
      }
      if (m['queue'] == null) _written = songs;
      return (
        queue: songs,
        index: index,
        mode: m['mode'] is String ? m['mode'] as String : null,
        radio: m['radio'] as Map<String, dynamic>?,
      );
    } catch (_) {
      return null;
    }
  }

  /// 队列删空了：下次启动不再恢复。读的时候解析失败就当没有会话。
  void clear() {
    _written = null;
    api.setPref(key: _key, value: '');
  }

  void write(
    List<Song> queue,
    int index,
    String mode, {
    Map<String, Object?>? radio,
  }) {
    if (!identical(queue, _written)) {
      api.setPref(
        key: _queueKey,
        value: jsonEncode([for (final song in queue) songToJson(song)]),
      );
      _written = queue;
    }
    api.setPref(
      key: _key,
      value: jsonEncode({
        'index': index,
        'mid': index >= 0 && index < queue.length ? queue[index].mid : null,
        'mode': mode,
        'radio': ?radio,
      }),
    );
  }
}
