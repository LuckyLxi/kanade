import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:kanade/data/song_json.dart';
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

  test('reads legacy session with the queue inline and song without MV', () {
    store.write([_song], 0, 'repeatOne');
    final song =
        (jsonDecode(api.prefs['last_session_queue']!) as List).single
            as Map<String, dynamic>;
    song.remove('mvVid');
    api.prefs.remove('last_session_queue');
    api.prefs['last_session'] = jsonEncode({
      'queue': [song],
      'index': 0,
      'mode': 'repeatOne',
    });
    expect(store.read()!.queue.single.mvVid, '');
    expect(store.read()!.mode, 'repeatOne');
  });

  test('rewrites the queue only when it changes', () {
    final queue = [_song];
    store.write(queue, 0, 'sequence');
    api.prefs['last_session_queue'] = 'kept';
    store.write(queue, 0, 'shuffle');
    expect(api.prefs['last_session_queue'], 'kept');
    expect(jsonDecode(api.prefs['last_session']!)['mode'], 'shuffle');
    store.write([...queue, _song], 1, 'shuffle');
    expect(jsonDecode(api.prefs['last_session_queue']!), hasLength(2));
    expect(store.read()!.index, 1);
  });

  test('ignores a session whose position was not saved with its queue', () {
    store.write([_song], 0, 'sequence');
    api.prefs['last_session_queue'] = jsonEncode([
      songToJson(
        const Song(
          id: 2,
          mid: 'other',
          name: 'other',
          singers: [],
          albumMid: '',
          albumName: '',
          durationSecs: 1,
          mediaMid: '',
          coverUrl: '',
          vip: false,
          hasHq: false,
          hasFlac: false,
          mvVid: '',
        ),
      ),
    ]);
    expect(PlayerSessionStore().read(), isNull);
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
