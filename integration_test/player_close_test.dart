import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:kanade/ui/desktop_shell.dart';
import 'package:kanade/ui/mini_player.dart';
import 'package:kanade/ui/player_route.dart';

import 'harness.dart';

/// 播放页关闭动画的逐帧耗时和进度曲线：直接关、点过歌词 / 队列再关、暂停再继续后关。
/// flutter drive --profile -d windows --driver=test_driver/integration_test.dart --target=integration_test/player_close_test.dart
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  testWidgets('播放页关闭性能', (tester) async {
    final (_, nav) = await launchWithSong(tester);
    Future<void> wait(int ms) => tester.runAsync(() => Future<void>.delayed(Duration(milliseconds: ms)));

    final cases = <String, Future<void> Function()>{
      'plain': () async {},
      'lyrics': () async {
        await tester.tap(find.byIcon(Icons.lyrics_outlined).last);
        await wait(800);
        await tester.tap(find.byIcon(Icons.lyrics_outlined).last);
      },
      // 歌词开着直接退出
      'lyricsOpen': () async {
        await tester.tap(find.byIcon(Icons.lyrics_outlined).last);
      },
      'queue': () async {
        await tester.tap(find.byIcon(Icons.format_list_bulleted_rounded).last);
        await wait(800);
        await tester.tap(find.byIcon(Icons.format_list_bulleted_rounded).last);
      },
      'pause': () async {
        await tester.tap(find.byType(AnimatedIcon).last);
        await wait(1000);
        await tester.tap(find.byType(AnimatedIcon).last);
      },
    };
    final report = StringBuffer();
    for (var round = 0; round < 2; round++) {
      for (final MapEntry(key: name, value: act) in cases.entries) {
        final route = PlayerRoute(anchor: Platform.isAndroid ? MiniPlayer.anchor : DesktopPlayerBar.anchor);
        nav.push(route);
        await wait(1200);
        await act();
        await wait(1200);
        final r = await tester.runAsync(() => _measureClose(route, () => nav.pop()));
        report.writeln('$name#$round  $r');
        await wait(600);
      }
    }
    // ignore: avoid_print
    print('\n===== CLOSE =====\n$report================');
    binding.reportData = {'close': report.toString()};
  });
}

Future<String> _measureClose(PlayerRoute route, void Function() close) async {
  final timings = <FrameTiming>[];
  void onTimings(List<FrameTiming> t) => timings.addAll(t);
  SchedulerBinding.instance.addTimingsCallback(onTimings);
  // 每 80ms 记一次看到的进度，比较动画本身走得快慢
  final watch = Stopwatch()..start();
  final samples = <String>[];
  var done = -1;
  final sampler = Timer.periodic(const Duration(milliseconds: 80), (_) {
    samples.add(route.progress.toStringAsFixed(2));
    if (done < 0 && route.animation!.isDismissed) done = watch.elapsedMilliseconds;
  });
  close();
  await Future<void>.delayed(const Duration(milliseconds: 900));
  sampler.cancel();
  SchedulerBinding.instance.removeTimingsCallback(onTimings);
  int us(Duration d) => d.inMicroseconds;
  final build = timings.map((t) => us(t.buildDuration)).toList()..sort();
  final raster = timings.map((t) => us(t.rasterDuration)).toList()..sort();
  String p(List<int> xs, double q) => xs.isEmpty ? '-' : (xs[((xs.length - 1) * q).round()] / 1000).toStringAsFixed(1);
  final slow = timings.where((t) => t.totalSpan > const Duration(milliseconds: 17)).length;
  return 'frames ${timings.length}, slow $slow | build p50 ${p(build, .5)} max ${p(build, 1)} | '
      'raster p50 ${p(raster, .5)} max ${p(raster, 1)} | done ${done}ms | ${samples.join(' ')}';
}
