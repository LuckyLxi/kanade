import 'dart:convert';

import '../src/rust/api/music.dart' as api;
import '../src/rust/api/types.dart';

/// 播放会话的存储格式；播放模式由控制器解释。
class PlayerSessionStore {
  static const _key = 'last_session';

  ({List<Song> queue, int index, String? mode})? read() {
    final raw = api.getPref(key: _key);
    if (raw == null) return null;
    try {
      final m = jsonDecode(raw) as Map<String, dynamic>;
      final songs = [
        for (final s in m['queue'] as List)
          songFromJson(s as Map<String, dynamic>),
      ];
      final index = m['index'] as int;
      if (index < 0 || index >= songs.length) return null;
      return (
        queue: songs,
        index: index,
        mode: m['mode'] is String ? m['mode'] as String : null,
      );
    } catch (_) {
      return null;
    }
  }

  void write(List<Song> queue, int index, String mode) {
    api.setPref(
      key: _key,
      value: jsonEncode({
        'queue': [for (final song in queue) songToJson(song)],
        'index': index,
        'mode': mode,
      }),
    );
  }

  static Map<String, Object?> songToJson(Song s) => {
    'id': s.id,
    'mid': s.mid,
    'name': s.name,
    'singers': [
      for (final g in s.singers) {'mid': g.mid, 'name': g.name},
    ],
    'albumMid': s.albumMid,
    'albumName': s.albumName,
    'durationSecs': s.durationSecs,
    'mediaMid': s.mediaMid,
    'coverUrl': s.coverUrl,
    'vip': s.vip,
    'hasHq': s.hasHq,
    'hasFlac': s.hasFlac,
    'mvVid': s.mvVid,
  };

  static Song songFromJson(Map<String, dynamic> m) => Song(
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
    mvVid: m['mvVid'] as String? ?? '',
  );
}
