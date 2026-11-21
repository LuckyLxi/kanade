import 'dart:async';
import 'dart:io';

import 'package:flutter_rust_bridge/flutter_rust_bridge.dart' show Int64List;
import 'package:flutter_test/flutter_test.dart';
import 'package:kanade/auth/auth_controller.dart';
import 'package:kanade/data/song_json.dart';
import 'package:kanade/library/library_controller.dart';
import 'package:kanade/player/android_playback_connection.dart';
import 'package:kanade/player/playback_messages.dart';
import 'package:kanade/player/player_controller.dart';
import 'package:kanade/player/player_error.dart';
import 'package:kanade/player/player_session_store.dart';
import 'package:kanade/settings/locale_controller.dart';
import 'package:kanade/src/rust/api/types.dart';
import 'package:kanade/src/rust/frb_generated.dart';
import 'package:media_kit/media_kit.dart';

Song _song(int id) => Song(
  id: id,
  mid: 'm$id',
  name: 'song$id',
  singers: [],
  albumMid: '',
  albumName: '',
  durationSecs: 200,
  mediaMid: 'media$id',
  coverUrl: '',
  vip: false,
  hasHq: true,
  hasFlac: true,
  mvVid: '',
);

class _Api implements RustLibApi {
  final prefs = <String, String>{};
  final lyrics = <int, Completer<Lyric>>{};
  final choruses = <int, Completer<ChorusRange?>>{};
  final qualities = <String, Completer<List<QualityOption>>>{};
  final requests = <int>[];
  final unavailable = <String>{};
  final audioRequests = <String>[];
  @override
  UserInfo? crateApiMusicCurrentUser() => null;
  @override
  String? crateApiMusicGetPref({required String key}) => prefs[key];
  @override
  void crateApiMusicSetPref({required String key, required String value}) {
    prefs[key] = value;
  }

  @override
  Future<Lyric> crateApiMusicGetLyric({required String mid, required int id}) =>
      (lyrics[id] ??= Completer<Lyric>()).future;
  @override
  Future<ChorusRange?> crateApiMusicGetSongChorus({required int id}) {
    requests.add(id);
    return (choruses[id] ??= Completer<ChorusRange?>()).future;
  }

  @override
  Future<List<QualityOption>> crateApiMusicGetSongQualities({
    required String mid,
  }) => (qualities[mid] ??= Completer<List<QualityOption>>()).future;
  @override
  String? crateApiMusicGetCachedAudio({
    required String mid,
    required Quality quality,
  }) => unavailable.contains(mid) ? null : 'C:/test/$mid.mp3';
  @override
  Future<SongUrl> crateApiMusicGetSongUrl({
    required String mid,
    required String mediaMid,
    required Quality quality,
  }) async {
    audioRequests.add(mid);
    throw StateError('Unavailable audio: $mid');
  }

  @override
  CachedAudio? crateApiMusicGetAnyCachedAudio({required String mid}) => null;

  @override
  CachedAudio? crateApiMusicGetDownloadedAudio({required String mid}) => null;
  final radarPages = <int>[];
  @override
  Future<List<Song>> crateApiMusicGetRadarSongs({
    required Int64List seed,
    required int page,
  }) async {
    radarPages.add(page);
    return [_song(2), _song(3)];
  }

  void complete(int id) {
    lyrics[id]!.complete(Lyric(lines: const [], plain: 'lyric$id'));
    choruses[id]!.complete(
      ChorusRange(startMs: id * 1000, endMs: id * 1000 + 500),
    );
    qualities['m$id']!.complete(const [
      QualityOption(quality: Quality.high, available: true),
    ]);
  }

  void reset() {
    prefs.clear();
    lyrics.clear();
    choruses.clear();
    qualities.clear();
    requests.clear();
    unavailable.clear();
    audioRequests.clear();
    radarPages.clear();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Streams implements PlayerStream {
  @override
  Stream<bool> get playing => const Stream.empty();
  @override
  Stream<bool> get buffering => const Stream.empty();
  @override
  Stream<bool> get completed => const Stream.empty();
  @override
  Stream<Duration> get position => const Stream.empty();
  @override
  Stream<Duration> get duration => const Stream.empty();
  @override
  Stream<String> get error => const Stream.empty();
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Engine implements Player {
  final opened = <Playable>[];
  bool disposed = false;
  @override
  final PlayerState state = const PlayerState();
  @override
  PlayerStream get stream => _Streams();
  @override
  PlatformPlayer? get platform => null;
  @override
  Future<void> open(Playable media, {bool play = true}) async {
    opened.add(media);
  }

  @override
  Future<void> setVolume(double volume) async {}
  @override
  Future<void> dispose() async {
    disposed = true;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Socket implements Socket {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Connection implements AndroidPlaybackConnection {
  final _updates = StreamController<PlaybackMessage>.broadcast(sync: true);
  final _restarts = StreamController<void>.broadcast(sync: true);
  final calls = <(String, Object?)>[];
  void update(PlaybackMessage message) => _updates.add(message);
  bool get listened => _updates.hasListener || _restarts.hasListener;
  @override
  Stream<PlaybackMessage> get state => _updates.stream;
  @override
  Stream<void> get restarts => _restarts.stream;
  @override
  Future<Socket> connect() async => _Socket();
  @override
  void setWatching(bool watching) {}
  @override
  Future<Object?> call(PlaybackOp op, [Object? argument]) async {
    calls.add((op.name, argument));
    return null;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

PlaybackMessage _snapshot(List<Song> queue, int index) => {
  'queue': queue.map(songToJson).toList(),
  'index': index,
  'playing': false,
  'loading': false,
  'buffering': false,
  'duration': 200000,
  'defaultQuality': 'high',
  'quality': 'high',
  'actualQuality': null,
  'mode': 'sequence',
  'volume': 100,
  'fade': 0,
  'sleepAt': null,
  'sleepAfterSong': false,
  'floatOutput': false,
  'normalizeVolume': false,
  'error': null,
};

void main() {
  final api = _Api();
  setUpAll(() => RustLib.initMock(api: api));
  setUp(api.reset);

  for (final remote in [false, true]) {
    late AuthController auth;
    late LibraryController library;
    late LocaleController locale;
    late PlayerController player;
    late _Engine engine;
    _Connection? connection;
    void create() {
      auth = AuthController(watchSession: false);
      library = LibraryController(auth);
      locale = LocaleController();
      engine = _Engine();
      player = remote
          ? PlayerController.android(
              auth,
              library,
              locale,
              connection = _Connection(),
            )
          : PlayerController(auth, player: engine);
    }

    void close() {
      player.dispose();
      library.dispose();
      locale.dispose();
      auth.dispose();
    }

    Future<void> select(List<Song> queue, int index) async {
      if (remote) {
        connection!.update(_snapshot(queue, index));
      } else {
        await player.playList(queue, index);
      }
    }

    testWidgets(
      '${remote ? "remote" : "local"}: playAt selects the requested index',
      (tester) async {
        create();
        addTearDown(close);
        await select([_song(1), _song(2)], 0);
        await player.playAt(1);
        if (remote) {
          expect(connection!.calls, [('playAt', 1)]);
          connection!.update(_snapshot([_song(1), _song(2)], 1));
          expect(engine.opened, isEmpty);
        } else {
          expect((engine.opened.last as Media).uri, contains('m2.mp3'));
        }
        expect(player.current?.mid, 'm2');
        expect(player.index, 1);
      },
    );

    testWidgets(
      '${remote ? "remote" : "local"}: restore loads metadata without playing',
      (tester) async {
        PlayerSessionStore().write([_song(1)], 0, 'shuffle');
        create();
        expect(player.mode, PlayMode.shuffle);
        expect(api.requests, [1]);
        api.complete(1);
        await tester.pump();
        expect(player.lyric?.plain, 'lyric1');
        expect(player.chorus?.startMs, 1000);
        expect(engine.opened, isEmpty);
        expect(player.playing, isFalse);
        close();
      },
    );

    if (!remote) {
      testWidgets('local: restored position waits for play', (tester) async {
        PlayerSessionStore().write([_song(1)], 0, 'sequence');
        create();
        addTearDown(close);
        await player.restorePosition(const Duration(seconds: 42));
        expect(engine.opened, isEmpty);
        expect(player.position.value, const Duration(seconds: 42));
        await player.play();
        expect(
          (engine.opened.single as Media).start,
          const Duration(seconds: 42),
        );
      });

      testWidgets('local: restored radio keeps fetching from the next page', (
        tester,
      ) async {
        PlayerSessionStore().write(
          [_song(1), _song(2)],
          1,
          'sequence',
          radio: {
            'kind': 'radar',
            'seed': [1],
            'id': null,
            'pages': 1,
          },
        );
        create();
        addTearDown(close);
        await player.play();
        await tester.pump();
        expect(api.radarPages, [2]);
        expect(player.queue.map((s) => s.mid), ['m1', 'm2', 'm3']);
      });

      testWidgets('local: seeking a restored song plays from there', (
        tester,
      ) async {
        PlayerSessionStore().write([_song(1)], 0, 'sequence');
        create();
        addTearDown(close);
        await player.seek(const Duration(seconds: 42));
        expect(
          (engine.opened.single as Media).start,
          const Duration(seconds: 42),
        );
      });
    }

    testWidgets(
      '${remote ? "remote" : "local"}: switching clears chorus and discards stale metadata',
      (tester) async {
        create();
        await select([_song(1)], 0);
        await select([_song(2)], 0);
        expect(player.chorus, isNull);
        api.complete(2);
        await tester.pump();
        api.complete(1);
        await tester.pump();
        expect(api.requests, [1, 2]);
        expect(player.lyric?.plain, 'lyric2');
        expect(player.chorus?.startMs, 2000);
        expect(player.qualityOptions, hasLength(1));
        await select([], -1);
        expect(player.current, isNull);
        expect(player.lyric, isNull);
        expect(player.chorus, isNull);
        expect(player.qualityOptions, isEmpty);
        close();
      },
    );

    testWidgets(
      '${remote ? "remote" : "local"}: empty queue invalidates pending requests',
      (tester) async {
        create();
        await select([_song(1)], 0);
        await select([], -1);
        api.complete(1);
        await tester.pump();
        expect(player.chorus, isNull);
        expect(player.lyric, isNull);
        expect(player.qualityOptions, isEmpty);
        expect(player.qualitiesLoading, isFalse);
        close();
      },
    );

    testWidgets(
      '${remote ? "remote" : "local"}: disposal invalidates pending requests',
      (tester) async {
        create();
        await select([_song(1)], 0);
        close();
        api.complete(1);
        await tester.pump();
        expect(player.chorus, isNull);
        expect(player.lyric, isNull);
        expect(remote ? !connection!.listened : engine.disposed, isTrue);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('remote commands retain wire format without a local engine', (
    tester,
  ) async {
    final auth = AuthController(watchSession: false);
    final library = LibraryController(auth);
    final locale = LocaleController();
    late _Connection connection;
    final player = PlayerController.android(
      auth,
      library,
      locale,
      connection = _Connection(),
    );
    await player.playList([_song(1)], 0);
    expect(connection.calls.single.$1, 'playList');
    expect(connection.calls.single.$2, [
      [
        {
          'id': 1,
          'mid': 'm1',
          'name': 'song1',
          'singers': <Object?>[],
          'albumMid': '',
          'albumName': '',
          'durationSecs': 200,
          'mediaMid': 'media1',
          'coverUrl': '',
          'vip': false,
          'hasHq': true,
          'hasFlac': true,
          'mvVid': '',
          'gainDb': 0.0,
        },
      ],
      0,
    ]);
    await player.pause();
    await player.seek(const Duration(seconds: 5));
    player.setMode(PlayMode.shuffle);
    player.setSleepTimer(const Duration(minutes: 1));
    await player.setVolume(25);
    player.setNormalizeVolume(true);
    await tester.pump();
    expect(connection.calls.skip(1), [
      ('pause', null),
      ('seek', 5000),
      ('mode', 'shuffle'),
      ('sleep', 60),
      ('volume', 25.0),
      ('normalizeVolume', true),
    ]);
    expect(player.volume, 25);
    player.dispose();
    library.dispose();
    locale.dispose();
    auth.dispose();
  });

  testWidgets('player state survives the snapshot round trip', (tester) async {
    final auth = AuthController(watchSession: false);
    final library = LibraryController(auth);
    final locale = LocaleController();
    final source = PlayerController(auth, player: _Engine())
      ..queue = [_song(1), _song(2)]
      ..index = 1
      ..playing = true
      ..loading = true
      ..buffering = true
      ..duration = const Duration(seconds: 200)
      ..defaultQuality = Quality.lossless
      ..quality = Quality.high
      ..actualQuality = Quality.standard
      ..mode = PlayMode.shuffle
      ..volume = 40
      ..fade = const Duration(seconds: 3)
      ..sleepAt = DateTime.fromMillisecondsSinceEpoch(1700000000000)
      ..sleepAfterSong = true
      ..floatOutput = true
      ..normalizeVolume = true
      ..error = const StreamFailed('boom');
    late _Connection connection;
    final remote = PlayerController.android(
      auth,
      library,
      locale,
      connection = _Connection(),
    );
    connection.update(encodePlayerState(source, includeQueue: true));
    expect(remote.queue.map((s) => s.mid), ['m1', 'm2']);
    expect(remote.index, 1);
    expect(remote.playing, true);
    expect(remote.loading, true);
    expect(remote.buffering, true);
    expect(remote.duration, source.duration);
    expect(remote.defaultQuality, Quality.lossless);
    expect(remote.quality, Quality.high);
    expect(remote.actualQuality, Quality.standard);
    expect(remote.mode, PlayMode.shuffle);
    expect(remote.volume, 40);
    expect(remote.fade, source.fade);
    expect(remote.sleepAt, source.sleepAt);
    expect(remote.sleepAfterSong, true);
    expect(remote.floatOutput, true);
    expect(remote.normalizeVolume, true);
    expect((remote.error as StreamFailed).message, 'boom');
    remote.dispose();
    source.dispose();
    library.dispose();
    locale.dispose();
    auth.dispose();
  });

  testWidgets('failed songs are skipped once and manual selection retries', (
    tester,
  ) async {
    final auth = AuthController(watchSession: false);
    final engine = _Engine();
    final player = PlayerController(
      auth,
      player: engine,
      loadDisplayMetadata: false,
    );
    addTearDown(() {
      player.dispose();
      auth.dispose();
    });
    api.unavailable.addAll(['m1', 'm2', 'm3']);
    await player.playList([_song(1), _song(2), _song(3)], 0);
    expect(api.audioRequests, ['m1', 'm2', 'm3']);
    expect(engine.opened, isEmpty);
    expect(player.loading, isFalse);
    expect(player.playing, isFalse);
    expect(player.error, isA<PlaybackFailed>());

    api.unavailable.remove('m2');
    await player.playAt(0);
    expect(api.audioRequests, ['m1', 'm2', 'm3', 'm1']);
    expect(player.current?.mid, 'm2');
    expect(engine.opened, hasLength(1));
    expect(player.error, isNull);
    expect(player.loading, isFalse);
  });

  testWidgets('shuffle consumes next songs in insertion order', (tester) async {
    final auth = AuthController(watchSession: false);
    final player = PlayerController(
      auth,
      player: _Engine(),
      loadDisplayMetadata: false,
    );
    addTearDown(() {
      player.dispose();
      auth.dispose();
    });
    await player.playList([_song(1), _song(2)], 0);
    player.setMode(PlayMode.shuffle);
    player.playNext(_song(3));
    player.playNext(_song(4));
    await player.next();
    expect(player.current?.mid, 'm4');
    await player.next();
    expect(player.current?.mid, 'm3');
  });

  testWidgets('shuffle previous walks back through played songs', (
    tester,
  ) async {
    final auth = AuthController(watchSession: false);
    final player = PlayerController(
      auth,
      player: _Engine(),
      loadDisplayMetadata: false,
    );
    addTearDown(() {
      player.dispose();
      auth.dispose();
    });
    await player.playList([for (var i = 1; i <= 8; i++) _song(i)], 0);
    player.setMode(PlayMode.shuffle);
    final played = [player.current!.mid];
    for (var i = 0; i < 3; i++) {
      await player.next();
      played.add(player.current!.mid);
    }
    for (var i = played.length - 2; i >= 0; i--) {
      await player.previous();
      expect(player.current?.mid, played[i]);
    }
  });

  testWidgets('manual selection overrides pending next songs', (tester) async {
    final auth = AuthController(watchSession: false);
    final player = PlayerController(
      auth,
      player: _Engine(),
      loadDisplayMetadata: false,
    );
    addTearDown(() {
      player.dispose();
      auth.dispose();
    });
    await player.playList([_song(1), _song(2)], 0);
    player.setMode(PlayMode.shuffle);
    player.playNext(_song(3));
    player.playNext(_song(4));
    await player.playAt(3);
    expect(player.current?.mid, 'm2');
    player.playNext(_song(5));
    await player.next();
    expect(player.current?.mid, 'm5');
  });

  testWidgets('background playback omits display metadata', (tester) async {
    final auth = AuthController(watchSession: false);
    final engine = _Engine();
    final player = PlayerController(
      auth,
      player: engine,
      loadDisplayMetadata: false,
    );
    await player.playList([_song(1)], 0);
    expect(engine.opened, hasLength(1));
    expect(api.requests, isEmpty);
    expect(api.lyrics, isEmpty);
    expect(api.qualities, isEmpty);
    player.dispose();
    auth.dispose();
  });
}
