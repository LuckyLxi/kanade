import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanade/l10n/app_localizations.dart';
import 'package:kanade/library/library_controller.dart';
import 'package:kanade/player/player_controller.dart';
import 'package:kanade/src/rust/api/types.dart';
import 'package:kanade/src/rust/frb_generated.dart';
import 'package:kanade/ui/mv_page.dart';
import 'package:kanade/ui/sheet.dart';
import 'package:kanade/ui/song_list_page.dart';
import 'package:kanade/ui/song_tile.dart';
import 'package:provider/provider.dart';

class _Api implements RustLibApi {
  final mvRequests = <String>[];
  final similarRequests = <int>[];
  Future<List<Song>> Function() similar = () async => [_song()];

  @override
  Future<MvDetail> crateApiMusicGetMvDetail({required String vid}) {
    mvRequests.add(vid);
    return Completer<MvDetail>().future;
  }

  @override
  Future<List<Song>> crateApiMusicGetSimilarSongs({required int songId}) {
    similarRequests.add(songId);
    return similar();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Library extends ChangeNotifier implements LibraryController {
  @override
  bool isLiked(Song song) => false;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Player extends ChangeNotifier implements PlayerController {
  @override
  Song? get current => null;

  @override
  bool get playing => false;

  List<Song>? played;
  int? start;

  @override
  Future<void> playList(List<Song> songs, int start) async {
    played = songs;
    this.start = start;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Song _song({String vid = 'video-vid'}) => Song(
  id: 667137632,
  mid: 'song-mid',
  name: 'Turning Around',
  singers: const [],
  albumMid: '',
  albumName: '',
  durationSecs: 247,
  mediaMid: 'song-mid',
  coverUrl: '',
  vip: false,
  hasHq: false,
  hasFlac: false,
  mvVid: vid,
);

Future<_Player> _show(WidgetTester tester, Song song) async {
  tester.view.physicalSize = const Size(430, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final player = _Player();
  final library = _Library();
  addTearDown(player.dispose);
  addTearDown(library.dispose);
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<PlayerController>.value(value: player),
        ChangeNotifierProvider<LibraryController>.value(value: library),
      ],
      child: MaterialApp(
        locale: const Locale('zh'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(body: SongTile(songs: [song], index: 0)),
      ),
    ),
  );
  return player;
}

Future<void> _more(WidgetTester tester) async {
  await tester.tap(find.byIcon(Icons.more_vert).first);
  await tester.pumpAndSettle();
}

void main() {
  final api = _Api();
  setUpAll(() => RustLib.initMock(api: api));
  setUp(() {
    api.mvRequests.clear();
    api.similarRequests.clear();
    api.similar = () async => [_song()];
  });

  for (final longPress in [false, true]) {
    testWidgets(
      '${longPress ? 'long press' : 'more button'} opens MV with the song VID',
      (tester) async {
        await _show(tester, _song());
        if (longPress) {
          await tester.longPress(find.byType(SongTile));
          await tester.pumpAndSettle();
        } else {
          await _more(tester);
        }
        expect(find.text('观看 MV'), findsOneWidget);
        expect(find.text('查找相似歌曲'), findsOneWidget);
        expect(api.mvRequests, isEmpty);
        expect(api.similarRequests, isEmpty);
        await tester.tap(find.text('观看 MV'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 500));
        expect(find.byType(SheetHeader), findsNothing);
        expect(tester.widget<MvPage>(find.byType(MvPage)).vid, 'video-vid');
        expect(api.mvRequests, ['video-vid']);
      },
    );
  }

  testWidgets(
    'song without VID offers similar songs and the returned list is playable',
    (tester) async {
      final player = await _show(tester, _song(vid: ''));
      await _more(tester);
      expect(find.text('观看 MV'), findsNothing);
      await tester.tap(find.text('查找相似歌曲'));
      await tester.pumpAndSettle();
      expect(find.byType(SheetHeader), findsNothing);
      expect(find.byType(SongListPage), findsOneWidget);
      expect(api.similarRequests, [667137632]);
      final tile = find.descendant(
        of: find.byType(SongListPage),
        matching: find.byType(SongTile),
      );
      expect(tile, findsOneWidget);
      await tester.tap(tile);
      expect(player.played!.single.mid, 'song-mid');
      expect(player.start, 0);
    },
  );

  testWidgets('similar songs show an error and retry the same song', (
    tester,
  ) async {
    api.similar = () async => throw StateError('rejected');
    await _show(tester, _song());
    await _more(tester);
    await tester.tap(find.text('查找相似歌曲'));
    await tester.pumpAndSettle();
    expect(find.text('重试'), findsOneWidget);
    api.similar = () async => [_song()];
    await tester.tap(find.text('重试'));
    await tester.pumpAndSettle();
    expect(api.similarRequests, [667137632, 667137632]);
    expect(find.byType(SongTile), findsOneWidget);
  });

  testWidgets('empty similar songs cannot start playback', (tester) async {
    api.similar = () async => [];
    final player = await _show(tester, _song());
    await _more(tester);
    await tester.tap(find.text('查找相似歌曲'));
    await tester.pumpAndSettle();
    expect(find.byType(SongTile), findsNothing);
    for (final icon in [Icons.play_arrow_rounded, Icons.shuffle_rounded]) {
      final play = find.descendant(
        of: find.byType(SongListPage),
        matching: find.widgetWithIcon(IconButton, icon),
      );
      expect(play, findsOneWidget);
      expect(tester.widget<IconButton>(play).onPressed, isNull);
      await tester.tap(play);
      await tester.pump();
    }
    expect(player.played, isNull);
  });
}
