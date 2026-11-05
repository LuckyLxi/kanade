import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:kanade/src/rust/api/music.dart' as api;
import 'package:kanade/src/rust/api/types.dart';
import 'package:kanade/ui/album_page.dart';
import 'package:kanade/ui/locate_current.dart';
import 'package:kanade/ui/song_list_page.dart';
import 'package:kanade/ui/song_tile.dart';
import 'package:window_manager/window_manager.dart';

import 'harness.dart';

/// 静音播放歌单靠后的一首，回到顶上看定位钮浮出来，点它滚过去并闪一下，钮再收回去。
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  testWidgets('locate the playing song in a playlist', (tester) async {
    final out = Directory('${Directory.systemTemp.path}/kanade_locate_frames')..createSync(recursive: true);
    Future<void> wait([int ms = 1800]) => tester.runAsync(() => Future<void>.delayed(Duration(milliseconds: ms)));
    Future<void> screenshot(String name) => tester.runAsync(() async {
      // ignore: invalid_use_of_protected_member
      final layer = tester.binding.renderViews.first.layer! as OffsetLayer;
      final image = await layer.toImage(Offset.zero & tester.view.physicalSize, pixelRatio: 1);
      final png = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      File('${out.path}/$name.png').writeAsBytesSync(png!.buffer.asUint8List());
    });
    final locate = find.byIcon(Icons.my_location_rounded);
    bool buttonShown() => find.descendant(of: find.byType(LocateCurrentSong), matching: locate).evaluate().isNotEmpty;

    final (player, nav) = await launchWithSong(tester);
    await windowManager.setSize(const Size(430, 900));
    final found = (await tester.runAsync(
      () => api.search(keyword: '周杰伦', kind: SearchKind.playlist, page: 1, pageSize: 10),
    ))!;
    final p = found.playlists.firstWhere((p) => p.songCount >= 80);
    nav.push(SongListPage.playlist(p.id, p.title));
    await wait(4000);
    final songs = tester.widget<SongTile>(find.byType(SongTile).first).songs;
    await tester.runAsync(() => player.playList(songs, songs.length * 2 ~/ 3));
    await wait(1500);
    // 那首放不了会自动跳到下一首，以实际在放的为准
    final target = songs.indexWhere((s) => s.mid == player.current?.mid);
    expect(target, greaterThan(30));
    // 正在播放的在下面看不到：钮浮出来
    expect(buttonShown(), isTrue);
    await screenshot('shown');

    // 记下滚动这段的每帧耗时和位置，看卡不卡、是不是先快后慢
    final timings = <FrameTiming>[];
    void onTimings(List<FrameTiming> t) => timings.addAll(t);
    final pos = tester.state<ScrollableState>(find.byType(Scrollable).last).position;
    final clock = Stopwatch()..start();
    final samples = <(int, double)>[];
    void onScroll() => samples.add((clock.elapsedMilliseconds, pos.pixels));
    pos.addListener(onScroll);
    SchedulerBinding.instance.addTimingsCallback(onTimings);
    await tester.tap(locate);
    await wait(1100);
    SchedulerBinding.instance.removeTimingsCallback(onTimings);
    pos.removeListener(onScroll);
    final build = [for (final t in timings) t.buildDuration.inMicroseconds / 1000];
    final raster = [for (final t in timings) t.rasterDuration.inMicroseconds / 1000];
    String stat(List<double> v) {
      final s = [...v]..sort();
      return 'max ${s.last.toStringAsFixed(1)} p90 ${s[(s.length * 0.9).floor()].toStringAsFixed(1)} ms';
    }

    debugPrint('LOCATE frames=${timings.length} build ${stat(build)} raster ${stat(raster)} '
        'over16=${timings.where((t) => t.totalSpan.inMicroseconds > 16700).length}');
    final t0 = samples.first.$1;
    debugPrint('LOCATE path ${samples.map((s) => '${s.$1 - t0}:${s.$2.round()}').join(' ')}');
    await wait(200);
    final row = find.byWidgetPredicate((w) => w is SongTile && w.index == target);
    expect(row, findsOneWidget);
    final y = tester.getCenter(row).dy;
    final h = tester.view.physicalSize.height / tester.view.devicePixelRatio;
    // 中间偏上
    expect(y, inInclusiveRange(h * 0.3, h * 0.55));
    await screenshot('flash');
    await wait(1500);
    expect(buttonShown(), isFalse);
    await screenshot('arrived');

    // 往回滚到看不见，钮再出来
    await tester.drag(find.byType(CustomScrollView).last, const Offset(0, 1500));
    await wait(1200);
    expect(buttonShown(), isTrue);

    // 专辑页：正在放的就在头部下面看得到，不出钮；头部和歌曲列表照常排
    final song = player.current!;
    nav.push(AlbumPage.route(song.albumMid, song.albumName));
    await wait(4000);
    expect(find.byType(SongTile), findsWidgets);
    await screenshot('album');
    expect(tester.takeException(), isNull);
  });
}
