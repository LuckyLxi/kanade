import 'dart:async';
import 'dart:developer' show Timeline;
import 'dart:io';
import 'dart:ui';

import 'package:material_ui/material_ui.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:kanade/data/data_ext.dart';
import 'package:kanade/ui/desktop_shell.dart';
import 'package:kanade/ui/player_background.dart';
import 'package:kanade/ui/player_lyrics.dart';
import 'package:kanade/ui/player_page.dart';

import 'harness.dart';

/// 打开播放页时逐帧记录内存和渲染耗时，分别测整页和各个部件，定位转场掉帧 / 内存暴涨。
/// flutter drive --profile -d windows --driver=test_driver/integration_test.dart --target=integration_test/player_perf_test.dart
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  testWidgets('播放页转场性能', (tester) async {
    final (player, nav) = await launchWithSong(tester);
    Route<void> slide(Widget child) => PageRouteBuilder(
          opaque: false,
          transitionDuration: const Duration(milliseconds: 500),
          pageBuilder: (_, _, _) => child,
          transitionsBuilder: (_, a, _, c) => SlideTransition(
            position: Tween(begin: const Offset(0, 1), end: Offset.zero).animate(a),
            child: c,
          ),
        );
    final art = await tester.runAsync(() => loadCoverArt(bigCoverUrl(player.current!)));

    final cases = <String, Route<void> Function()>{
      // 冷启动先测真实转场，避免背景 / 歌词用例提前预热首次绘制。
      'bar': () => PlayerPage.route(anchor: DesktopPlayerBar.anchor),
      'black': () => slide(const ColoredBox(color: Colors.black)),
      'bg': () => slide(PlayerBackground(art: art, animate: true)),
      'lyrics': () => slide(const ColoredBox(color: Colors.black, child: LyricView(fontSize: 36))),
      'full': PlayerPage.route,
    };
    final view = tester.view;
    final report = StringBuffer(
      'view ${view.physicalSize.width} x ${view.physicalSize.height}, dpr ${view.devicePixelRatio}\n',
    );
    for (final MapEntry(key: name, value: make) in cases.entries) {
      for (var round = 0; round < 2; round++) {
        final r = await tester.runAsync(() => _measure(() => nav.push(make()), () => nav.pop()));
        report.writeln('$name#$round  $r');
      }
    }
    // ignore: avoid_print
    print('\n===== PERF =====\n$report================');
    binding.reportData = {'perf': report.toString()};
  });
}

Future<String> _measure(void Function() open, void Function() close) async {
  final timings = <FrameTiming>[];
  final openedAt = Timeline.now;
  // 引擎可能批量补报注册回调之前的帧，不能把首页启动的编译算进转场。
  void onTimings(List<FrameTiming> t) =>
      timings.addAll(t.where((frame) => frame.timestampInMicroseconds(FramePhase.buildStart) >= openedAt));
  final before = ProcessInfo.currentRss;
  var peak = before;
  final sampler = Timer.periodic(const Duration(milliseconds: 10), (_) {
    final rss = ProcessInfo.currentRss;
    if (rss > peak) peak = rss;
  });
  SchedulerBinding.instance.addTimingsCallback(onTimings);
  open();
  await Future<void>.delayed(const Duration(milliseconds: 1200));
  SchedulerBinding.instance.removeTimingsCallback(onTimings);
  final settled = ProcessInfo.currentRss;
  close();
  await Future<void>.delayed(const Duration(milliseconds: 1500));
  sampler.cancel();
  final after = ProcessInfo.currentRss;

  int ms(Duration d) => d.inMicroseconds ~/ 1000;
  final build = timings.map((t) => ms(t.buildDuration)).fold(0, (a, b) => a > b ? a : b);
  final raster = timings.map((t) => ms(t.rasterDuration)).fold(0, (a, b) => a > b ? a : b);
  final slow = timings.where((t) => t.totalSpan > const Duration(milliseconds: 17)).length;
  int mb(int b) => b ~/ (1 << 20);
  return 'rss ${mb(before)}MB -> peak ${mb(peak)}MB, settled ${mb(settled)}MB, after close ${mb(after)}MB | '
      'frames ${timings.length}, slow $slow, max build ${build}ms, max raster ${raster}ms';
}
