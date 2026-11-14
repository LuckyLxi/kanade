import 'dart:developer' show Timeline;
import 'dart:io';
import 'dart:ui' show FramePhase, Size;

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:kanade/ui/desktop_shell.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'package:window_manager/window_manager.dart';

import 'harness.dart';

/// 点导航栏切换标签页（发现 / 搜索 / 我的）时逐帧记录构建 / 光栅耗时。
/// 第一轮包含页面第一次显示的开销，后面几轮是来回切换的稳态。只浏览，不改数据。
/// flutter drive --profile -d <设备> --driver=test_driver/integration_test.dart --target=integration_test/tab_switch_perf_test.dart
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  testWidgets('标签页切换开销', (tester) async {
    // 在桌面上模拟手机交互（导航栏收起的圆球等），只在 debug 下有效
    if (const bool.fromEnvironment('TAB_PAINTS')) {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
    }
    await launchWithSong(tester);
    Future<void> wait(int ms) =>
        tester.runAsync(() => Future<void>.delayed(Duration(milliseconds: ms)));
    // --dart-define=TAB_NARROW=true：Windows 上把窗口缩窄，走手机布局（底部导航栏）
    if (Platform.isWindows && const bool.fromEnvironment('TAB_NARROW')) {
      await tester.runAsync(() => windowManager.setSize(const Size(430, 900)));
      await wait(1000);
    }
    final bar = find.byType(GlassTabBar).evaluate().isNotEmpty
        ? find.byType(GlassTabBar)
        : find.byType(DesktopSidebar);
    Finder tab(String label) =>
        find.descendant(of: bar, matching: find.text(label)).first;
    final report = StringBuffer(
      'layout ${bar.evaluate().first.widget.runtimeType}\n',
    );

    Future<void> switchTo(String name, String label) async {
      final timings = <FrameTiming>[];
      void onTimings(List<FrameTiming> t) => timings.addAll(t);
      SchedulerBinding.instance.addTimingsCallback(onTimings);
      final tapAt = Timeline.now;
      await tester.tap(tab(label), warnIfMissed: false);
      await wait(700);
      SchedulerBinding.instance.removeTimingsCallback(onTimings);
      double ms(Duration d) => d.inMicroseconds / 1000;
      // 帧和帧之间的空档：快照在帧外面由光栅线程画，卡在那里不会算进 raster 耗时
      double at(FrameTiming t, FramePhase p) =>
          (t.timestampInMicroseconds(p) - tapAt) / 1000;
      if (timings.isNotEmpty) {
        var gap = 0.0, lag = 0.0, span = 0.0;
        for (var i = 0; i < timings.length; i++) {
          final t = timings[i];
          lag = [
            lag,
            at(t, FramePhase.rasterStart) - at(t, FramePhase.buildFinish),
          ].reduce((a, b) => a > b ? a : b);
          span = [span, ms(t.totalSpan)].reduce((a, b) => a > b ? a : b);
          // 只看滑动那 0.3 秒里的空档，滑完之后没东西动本来就不出帧
          if (i > 0 && at(t, FramePhase.vsyncStart) < 400) {
            final g =
                at(t, FramePhase.rasterFinish) -
                at(timings[i - 1], FramePhase.rasterFinish);
            if (g > gap) gap = g;
          }
        }
        report.writeln(
          '${name.padRight(14)} first vsync ${at(timings.first, FramePhase.vsyncStart).toStringAsFixed(1)} '
          'first shown ${at(timings.first, FramePhase.rasterFinish).toStringAsFixed(1)} '
          'max gap ${gap.toStringAsFixed(1)} max queue ${lag.toStringAsFixed(1)} max span ${span.toStringAsFixed(1)}',
        );
      }
      final raster = timings.map((t) => ms(t.rasterDuration)).toList()..sort();
      final build = timings.map((t) => ms(t.buildDuration)).toList()..sort();
      final slow = raster.where((x) => x > 8.33).length;
      final slowBuild = build.where((x) => x > 8.33).length;
      String tail(List<double> xs) => xs.isEmpty
          ? '-'
          : 'avg ${(xs.reduce((a, b) => a + b) / xs.length).toStringAsFixed(2)} '
                'p90 ${xs[(xs.length * .9).floor()].toStringAsFixed(2)} max ${xs.last.toStringAsFixed(2)}';
      report.writeln(
        '${name.padRight(14)} frames ${timings.length.toString().padLeft(3)}, raster ${tail(raster)}, '
        'build ${tail(build)}, >8.3ms raster $slow build $slowBuild',
      );
      await wait(500);
    }

    await wait(1500);
    // --dart-define=TAB_SHOTS=true：发现页切到排行榜（不登录也有封面），动画放慢 6 倍，
    // 每次点完打印 SHOT，外面用 adb screencap 截滑动中途的画面，看封面在不在
    if (const bool.fromEnvironment('TAB_SHOTS')) {
      await tester.tap(find.text('排行榜').first, warnIfMissed: false);
      await wait(4000);
      timeDilation = 6;
      for (final (name, label) in [
        ('mine1', '我的'),
        ('discover1', '发现'),
        ('mine2', '我的'),
        ('discover2', '发现'),
      ]) {
        await tester.tap(tab(label), warnIfMissed: false);
        // ignore: avoid_print
        print('SHOT $name');
        await wait(4000);
      }
      timeDilation = 1;
      return;
    }
    // --dart-define=TAB_PAINTS=true（只在 debug 下有效）：记录静止和滑动期间谁在要求重绘
    if (const bool.fromEnvironment('TAB_PAINTS')) {
      Future<void> paints(String name, Future<void> Function() during) async {
        final counts = <String, int>{};
        final original = debugPrint;
        List<String>? record;
        void flush() {
          if (record == null) return;
          final key = record!.join('\n    ');
          counts[key] = (counts[key] ?? 0) + 1;
        }

        debugPrint = (String? message, {int? wrapWidth}) {
          for (final line in (message ?? '').split('\n')) {
            if (line.startsWith('markNeedsPaint() called for')) {
              flush();
              record = [line.replaceAll(RegExp(r'#[0-9a-f]{5}'), '')];
            } else if (record != null &&
                record!.length < 9 &&
                line.contains('package:') &&
                !line.contains('package:flutter/src/rendering/object.dart') &&
                !line.contains('package:flutter/src/scheduler/')) {
              record!.add(line.trim());
            }
          }
        };
        debugPrintMarkNeedsPaintStacks = true;
        await during();
        debugPrintMarkNeedsPaintStacks = false;
        debugPrint = original;
        flush();
        final sorted = counts.entries.toList()
          ..sort((a, b) => b.value.compareTo(a.value));
        // ignore: avoid_print
        print('===== PAINTS $name =====');
        for (final e in sorted.take(12)) {
          // ignore: avoid_print
          print('${e.value}x ${e.key}');
        }
      }

      await paints('idle 发现', () => wait(400));
      await paints('发现→我的', () async {
        await tester.tap(tab('我的'), warnIfMissed: false);
        await wait(250);
      });
      await wait(800);
      await paints('idle 我的', () => wait(400));
      await paints('我的→发现', () async {
        await tester.tap(tab('发现'), warnIfMissed: false);
        await wait(250);
      });
      debugDefaultTargetPlatformOverride = null;
      return;
    }
    for (var round = 0; round < 4; round++) {
      await switchTo('#$round 发现→搜索', '搜索');
      await switchTo('#$round 搜索→我的', '我的');
      await switchTo('#$round 我的→发现', '发现');
      await switchTo('#$round 发现→我的', '我的');
      await switchTo('#$round 我的→发现', '发现');
    }
    // ignore: avoid_print
    print('\n===== TAB SWITCH =====\n$report======================');
    binding.reportData = {'tabs': report.toString()};
  });
}
