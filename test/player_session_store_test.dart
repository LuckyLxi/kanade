import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:kanade/player/player_session_store.dart';
import 'package:kanade/src/rust/api/types.dart';
import 'package:kanade/src/rust/frb_generated.dart';

class _Api implements RustLibApi {
  final prefs = <String, String>{};
  @override
  String? crateApiMusicGetPref({required String key}) => prefs[key];
  @override
  void crateApiMusicSetPref({required String key, required String value}) =>
      prefs[key] = value;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

const _song = Song(
  id: 1,
  mid: 'mid',
  name: 'song',
  singers: [Singer(mid: 'singer', name: 'artist')],
  albumMid: 'album',
  albumName: 'title',
  durationSecs: 200,
  mediaMid: 'media',
  coverUrl: 'cover',
  vip: true,
  hasHq: true,
  hasFlac: true,
  mvVid: 'video',
);

void main() {
  final api = _Api();
  final store = PlayerSessionStore();
  setUpAll(() => RustLib.initMock(api: api));
  setUp(api.prefs.clear);

  test('round trips all song fields and keeps independent preferences', () {
    api.prefs['play_mode'] = 'shuffle';
    store.write([_song], 0, 'sequence');
    final session = store.read()!;
    final restored = session.queue.single;
    expect(
      (restored.id, restored.mid, restored.name),
      (_song.id, _song.mid, _song.name),
    );
    expect(
      (restored.singers.single.mid, restored.singers.single.name),
      ('singer', 'artist'),
    );
    expect(
      (restored.albumMid, restored.albumName, restored.durationSecs),
      ('album', 'title', 200),
    );
    expect(
      (restored.mediaMid, restored.coverUrl, restored.mvVid),
      ('media', 'cover', 'video'),
    );
    expect(
      (restored.vip, restored.hasHq, restored.hasFlac),
      (true, true, true),
    );
    expect(session.index, 0);
    expect(session.mode, 'sequence');
    expect(api.prefs['play_mode'], 'shuffle');
  });

  test('reads legacy song without MV and legacy mode', () {
    store.write([_song], 0, 'repeatOne');
    final json = jsonDecode(api.prefs['last_session']!) as Map<String, dynamic>;
    (json['queue'] as List).single.remove('mvVid');
    api.prefs['last_session'] = jsonEncode(json);
    expect(store.read()!.queue.single.mvVid, '');
    expect(store.read()!.mode, 'repeatOne');
  });

  test('missing, malformed and out of range sessions are ignored', () {
    expect(store.read(), isNull);
    for (final raw in [
      'invalid',
      '{}',
      '{"queue":[],"index":0}',
      '{"queue":[],"index":-1}',
    ]) {
      api.prefs['last_session'] = raw;
      expect(store.read(), isNull);
    }
    store.write([_song], 1, 'sequence');
    expect(store.read(), isNull);
    store.write([_song], -1, 'sequence');
    expect(store.read(), isNull);
  });
}
