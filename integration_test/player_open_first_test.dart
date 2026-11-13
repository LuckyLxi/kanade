import 'package:material_ui/material_ui.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:kanade/ui/desktop_shell.dart';
import 'package:window_manager/window_manager.dart';

import 'harness.dart';

/// Windows：点播放栏打开播放页再关上，连做几轮，看第一次是否比后面卡。第一轮抓时间线，列出最长的事件。
/// flutter drive --profile -d windows --driver=test_driver/integration_test.dart --target=integration_test/player_open_first_test.dart
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  testWidgets('播放页首次打开', (tester) async {
    final (_, root) = await launchWithSong(tester);
    Future<void> wait(int ms) => tester.runAsync(() => Future<void>.delayed(Duration(milliseconds: ms)));
    await tester.runAsync(() => windowManager.setSize(const Size(1280, 800)));
    await wait(1500);
    final report = StringBuffer();

    Future<void> measure(String name, Future<void> Function() run) async {
      final frames = <FrameTiming>[];
      void onTimings(List<FrameTiming> t) => frames.addAll(t);
      SchedulerBinding.instance.addTimingsCallback(onTimings);
      await run();
      await wait(const bool.fromEnvironment("SHORT") ? 0 : 300);
      SchedulerBinding.instance.removeTimingsCallback(onTimings);
      double ms(Duration d) => d.inMicroseconds / 1000;
      final worst = [...frames]..sort((a, b) => b.totalSpan.compareTo(a.totalSpan));
      report.writeln(
        '$name: frames ${frames.length}, >16.7ms ${frames.where((f) => ms(f.totalSpan) > 16.7).length}, worst '
        '${worst.take(4).map((f) => 'total ${ms(f.totalSpan).toStringAsFixed(1)}/build ${ms(f.buildDuration).toStringAsFixed(1)}/raster ${ms(f.rasterDuration).toStringAsFixed(1)}').join(', ')}',
      );
    }

    Future<void> traced(String name, Future<void> Function() run) async {
      if (!name.endsWith('0')) return measure(name, run);
      await binding.traceAction(() async {
        await wait(const bool.fromEnvironment("SHORT") ? 50 : 500);
        await measure(name, run);
      }, reportKey: name, streams: const ['Embedder']);
      final data = binding.reportData![name] as Map;
      final events = ((data['traceEvents'] ?? const []) as List).cast<Map>();
      final open = <String, List<Map>>{};
      final spans = <(double, String)>[];
      for (final e in events) {
        final tid = '${e['tid']}';
        final ts = (e['ts'] as num? ?? 0).toDouble();
        if (e['ph'] == 'X') {
          spans.add(((e['dur'] as num? ?? 0).toDouble() / 1000, '${e['name']} tid=$tid'));
        } else if (e['ph'] == 'B') {
          (open[tid] ??= []).add(e);
        } else if (e['ph'] == 'E' && (open[tid]?.isNotEmpty ?? false)) {
          final b = open[tid]!.removeLast();
          if ('${b['name']}' == 'shader_compile' && ts - (b['ts'] as num).toDouble() > 50000) {
            report.writeln('    STACK ${open[tid]!.map((x) => '${x['name']}${x['args'] is Map && (x['args'] as Map).isNotEmpty ? x['args'] : ''}').join(' > ')}');
          }
          spans.add(((ts - (b['ts'] as num).toDouble()) / 1000, '${b['name']} tid=$tid depth=${open[tid]!.length}'));
        }
      }
      spans.sort((a, b) => b.$1.compareTo(a.$1));
      report.writeln('  $name events ${events.length}, top spans:');
      for (final s in spans.where((s) => s.$1 > 8).take(40)) {
        report.writeln('    ${s.$1.toStringAsFixed(1)}ms ${s.$2}');
      }
      binding.reportData!.remove(name);
    }

    for (var i = 0; i < 3; i++) {
      await traced('open$i', () async {
        await tester.tapAt(DesktopPlayerBar.anchor.coverRect!.center);
        await wait(const bool.fromEnvironment("SHORT") ? 250 : 1200);
      });
      await traced('close$i', () async {
        root.pop();
        await wait(1000);
      });
      await wait(800);
    }
    // ignore: avoid_print
    print('PLAYER OPEN FIRST\n$report');
    expect(find.byType(DesktopPlayerBar), findsOneWidget);
  });
}
