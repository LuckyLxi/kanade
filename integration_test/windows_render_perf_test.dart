import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:kanade/ui/desktop_shell.dart';
import 'package:kanade/ui/discover_page.dart';
import 'package:kanade/ui/player_route.dart';
import 'package:kanade/ui/song_list_page.dart';
import 'package:window_manager/window_manager.dart';

import 'harness.dart';

/// Real Windows raster measurements for large lists and player morphs.
/// flutter drive --no-pub --profile -d windows --driver=test_driver/integration_test.dart --target=integration_test/windows_render_perf_test.dart
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  testWidgets('Windows windowed/fullscreen scroll and player rendering', (
    tester,
  ) async {
    final (player, rootNav) = await launchWithSong(tester);
    final originalSize = await windowManager.getSize();
    final originalFullscreen = await windowManager.isFullScreen();
    final report = <String, Object?>{};
    Future<void> wait(int ms) =>
        tester.runAsync(() => Future<void>.delayed(Duration(milliseconds: ms)));
    try {
      for (final fullscreen in [false, true]) {
        await tester.runAsync(() => windowManager.setFullScreen(fullscreen));
        await wait(800);
        final mode = fullscreen ? 'fullscreen' : 'windowed';
        final tabNav = Navigator.of(tester.element(find.byType(DiscoverPage)));
        // Both affected pages share SongListPage. Reuse loaded songs so the
        // measured scroll has no network dependency or library mutations.
        final songs = List.generate(
          500,
          (i) => player.queue[i % player.queue.length],
        );
        for (final title in ['我喜欢', '最近播放']) {
          tabNav.push(
            MaterialPageRoute<void>(
              builder: (_) => SongListPage(
                title: title,
                searchable: true,
                load: () async => (
                  title: title,
                  cover: '',
                  period: '',
                  description: '',
                  songs: songs,
                  owned: null,
                ),
              ),
            ),
          );
          await wait(1200);
          final scroll = tester
              .state<ScrollableState>(
                find
                    .descendant(
                      of: find.byType(SongListPage),
                      matching: find.byType(Scrollable),
                    )
                    .first,
              )
              .position;
          report['$mode/$title/scroll'] = await tester.runAsync(
            () => _measure(() async {
              for (var i = 0; i < 30; i++) {
                scroll.pointerScroll(i < 15 ? 360 : -360);
                await Future<void>.delayed(const Duration(milliseconds: 80));
              }
              await Future<void>.delayed(const Duration(milliseconds: 400));
            }),
          );
          for (var round = 0; round < 2; round++) {
            report['$mode/$title/player#$round'] = await tester.runAsync(
              () => _measure(() async {
                rootNav.push(PlayerRoute(anchor: DesktopPlayerBar.anchor));
                await Future<void>.delayed(const Duration(milliseconds: 900));
                rootNav.pop();
                await Future<void>.delayed(const Duration(milliseconds: 900));
              }),
            );
          }
          tabNav.pop();
          await wait(600);
        }
      }
    } finally {
      await tester.runAsync(() async {
        await windowManager.setFullScreen(originalFullscreen);
        if (!originalFullscreen) await windowManager.setSize(originalSize);
      });
    }
    binding.reportData = report;
    // ignore: avoid_print
    print('WINDOWS RENDER PERF: $report');
  });
}

Future<Map<String, Object>> _measure(Future<void> Function() action) async {
  final frames = <FrameTiming>[];
  void onTimings(List<FrameTiming> timings) => frames.addAll(timings);
  final before = ProcessInfo.currentRss;
  var peak = before;
  final sampler = Timer.periodic(const Duration(milliseconds: 10), (_) {
    if (ProcessInfo.currentRss > peak) peak = ProcessInfo.currentRss;
  });
  SchedulerBinding.instance.addTimingsCallback(onTimings);
  try {
    await action();
  } finally {
    sampler.cancel();
    SchedulerBinding.instance.removeTimingsCallback(onTimings);
  }
  expect(
    frames,
    isNotEmpty,
    reason: 'the measurement must include real raster frames',
  );
  expect(
    peak - before,
    lessThan(512 << 20),
    reason: 'a short scroll or player transition must not allocate gigabytes',
  );
  return {
    'rssBeforeMB': before ~/ (1 << 20),
    'rssPeakMB': peak ~/ (1 << 20),
    'rssAfterMB': ProcessInfo.currentRss ~/ (1 << 20),
    'frames': frames.length,
    'slowFrames': frames
        .where((f) => f.totalSpan > const Duration(milliseconds: 17))
        .length,
    'maxRasterMs': frames.fold<double>(
      0.0,
      (max, f) => f.rasterDuration.inMicroseconds / 1000 > max
          ? f.rasterDuration.inMicroseconds / 1000
          : max,
    ),
  };
}
