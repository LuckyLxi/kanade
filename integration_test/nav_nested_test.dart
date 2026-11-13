import 'package:material_ui/material_ui.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:kanade/src/rust/api/music.dart' as api;
import 'package:kanade/src/rust/api/types.dart';
import 'package:kanade/ui/discover_page.dart';
import 'package:kanade/ui/mini_player.dart';
import 'package:kanade/ui/song_list_page.dart';

import 'harness.dart';

/// 手机上进出歌单页：导航栏和播放条融成底部胶囊再分开，播放条分别从圆球和胶囊出发。
/// 每次转场打印帧耗时；外面可以同时 adb screenrecord 看动画。只浏览，不收藏。
/// flutter drive --profile -d <手机> --driver=test_driver/integration_test.dart --target=integration_test/nav_nested_test.dart
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  testWidgets('二级页导航栏转场', (tester) async {
    final (_, root) = await launchWithSong(tester);
    Future<void> wait(int ms) => tester.runAsync(() => Future<void>.delayed(Duration(milliseconds: ms)));
    final found = (await tester.runAsync(
      () => api.search(keyword: '周杰伦', kind: SearchKind.playlist, page: 1, pageSize: 10),
    ))!;
    final playlist = found.playlists.first;
    final report = StringBuffer();

    Future<void> transition(String name, void Function() run) async {
      final timings = <FrameTiming>[];
      void onTimings(List<FrameTiming> t) => timings.addAll(t);
      SchedulerBinding.instance.addTimingsCallback(onTimings);
      // ignore: avoid_print
      print('MARK $name');
      run();
      await wait(1200);
      SchedulerBinding.instance.removeTimingsCallback(onTimings);
      double ms(Duration d) => d.inMicroseconds / 1000;
      final raster = timings.map((t) => ms(t.rasterDuration)).toList()..sort();
      final build = timings.map((t) => ms(t.buildDuration)).toList()..sort();
      final slow = raster.where((x) => x > 8.33).length;
      String tail(List<double> xs) => xs.isEmpty
          ? '-'
          : 'avg ${(xs.reduce((a, b) => a + b) / xs.length).toStringAsFixed(2)} '
                'p90 ${xs[(xs.length * .9).floor()].toStringAsFixed(2)} max ${xs.last.toStringAsFixed(2)}';
      report.writeln(
        '$name: frames ${timings.length}, raster ${tail(raster)}, build ${tail(build)}, raster>8.3ms $slow',
      );
      await wait(600);
    }

    final discover = Navigator.of(tester.element(find.byType(DiscoverPage)));
    Future<void> roundTrip(String from) async {
      await transition('$from-enter', () => discover.push(SongListPage.playlist(playlist.id, playlist.title)));
      await wait(800);
      await transition('$from-exit', discover.pop);
    }

    await wait(1500);
    // 手机上第一次放歌时播放条是导航栏旁边的圆球
    await roundTrip('circle');
    await tester.tap(find.byType(MiniPlayer));
    await wait(1200);
    await roundTrip('capsule');
    // 进去还没落稳就返回，看半路折返
    await transition('capsule-interrupt', () async {
      discover.push(SongListPage.playlist(playlist.id, playlist.title));
      await Future<void>.delayed(const Duration(milliseconds: 160));
      discover.pop();
    });
    // 从播放条打开播放页再关上：播放页盖着时播放条的玻璃要藏起来，关上后回来。
    // 打印 SNAP 后停几秒，外面可以 adb screencap 截图
    await wait(1500);
    await tester.tap(find.byType(MiniPlayer));
    await wait(2000);
    // ignore: avoid_print
    print('SNAP player-open');
    await wait(2500);
    root.pop();
    await wait(1500);
    // ignore: avoid_print
    print('SNAP player-closed');
    await wait(2500);
    // ignore: avoid_print
    print('\n===== NAV NESTED =====\n$report======================');
    binding.reportData = {'nested': report.toString()};
  });
}
