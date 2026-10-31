import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:kanade/ui/desktop_shell.dart';
import 'package:kanade/ui/discover_page.dart';
import 'package:kanade/ui/mini_player.dart';
import 'package:kanade/ui/player_route.dart';
import 'package:kanade/ui/player_page.dart';
import 'package:kanade/ui/song_list_page.dart';
import 'package:window_manager/window_manager.dart';

import 'harness.dart';
import 'windows_process_memory.dart';

/// Real Windows raster measurements for large lists and player morphs.
/// flutter drive --no-pub --profile -d windows --driver=test_driver/integration_test.dart --target=integration_test/windows_render_perf_test.dart
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  testWidgets('Windows windowed/fullscreen scroll and player rendering', (
    tester,
  ) async {
    const songKeyword = String.fromEnvironment('PERF_SONG');
    final (player, rootNav) = await launchWithSong(
      tester,
      mediaSession: true,
      songKeyword: songKeyword.isEmpty ? null : songKeyword,
    );
    expect(
      player.error,
      isNull,
      reason: 'rendering must be measured during successful audio playback',
    );
    expect(
      player.playing,
      isTrue,
      reason: 'a stopped player does not exercise the animated background',
    );
    final originalSize = await windowManager.getSize();
    final originalFullscreen = await windowManager.isFullScreen();
    final originalMaximized = await windowManager.isMaximized();
    final report = <String, Object?>{};
    Future<void> wait(int ms) =>
        tester.runAsync(() => Future<void>.delayed(Duration(milliseconds: ms)));
    try {
      const modes = String.fromEnvironment(
        'RENDER_MODES',
        defaultValue: 'narrow,windowed,maximized,fullscreen',
      );
      for (final mode in modes.split(',')) {
        await tester.runAsync(() async {
          await windowManager.setFullScreen(false);
          await windowManager.unmaximize();
          if (mode == 'maximized') {
            await windowManager.maximize();
          } else if (mode == 'fullscreen') {
            await windowManager.setFullScreen(true);
          } else {
            await windowManager.setSize(
              mode == 'narrow' ? const Size(430, 900) : const Size(1280, 720),
            );
          }
        });
        await wait(800);
        if (mode != 'narrow') {
          report['fixture'] = {
            'song': player.current!.name,
            'lyricLines': player.lyric?.lines.length ?? 0,
          };
          final positionBefore = player.position.value;
          report['$mode/home/tapWhilePlaying'] = await tester.runAsync(
            () => _measure(() async {
              await tester.tapAt(DesktopPlayerBar.anchor.coverRect!.center);
              await Future<void>.delayed(const Duration(seconds: 10));
              expect(find.byType(PlayerPage), findsOneWidget);
              final page = tester.element(find.byType(PlayerPage));
              await tester.tapAt(
                Offset(
                  MediaQuery.sizeOf(page).width / 2,
                  MediaQuery.paddingOf(page).top + 12,
                ),
              );
              await Future<void>.delayed(const Duration(milliseconds: 1500));
              expect(find.byType(PlayerPage), findsNothing);
            }),
          );
          expect(player.playing, isTrue);
          expect(player.position.value, greaterThan(positionBefore));
        }
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
            await tester.runAsync(
              () => round == 0 ? player.pause() : player.play(),
            );
            await wait(400);
            final positionBefore = player.position.value;
            final playing = round == 1;
            expect(player.playing, playing);
            final anchor = find.byType(DesktopPlayerBar).evaluate().isNotEmpty
                ? DesktopPlayerBar.anchor
                : MiniPlayer.anchor;
            report['$mode/$title/${playing ? 'playing' : 'paused'}'] =
                await tester.runAsync(
                  () => _measure(() async {
                    rootNav.push(PlayerRoute(anchor: anchor));
                    await Future<void>.delayed(
                      Duration(seconds: playing ? 5 : 1),
                    );
                    rootNav.pop();
                    await Future<void>.delayed(
                      const Duration(milliseconds: 1500),
                    );
                  }),
                );
            expect(player.error, isNull);
            expect(player.playing, playing);
            if (playing) {
              expect(
                player.position.value,
                greaterThan(positionBefore),
                reason: 'audio must advance throughout the transition',
              );
            }
          }
          tabNav.pop();
          await wait(600);
        }
      }
    } finally {
      await tester.runAsync(() async {
        await windowManager.setFullScreen(originalFullscreen);
        if (!originalFullscreen) {
          await windowManager.setSize(originalSize);
          if (originalMaximized) await windowManager.maximize();
        }
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
  final memory = WindowsProcessMemory();
  final privateBefore = memory.privateBytes;
  var privatePeak = privateBefore;
  final osPeakBefore = memory.peakCommitBytes;
  var osPeakAfter = osPeakBefore;
  final sampler = Timer.periodic(const Duration(milliseconds: 10), (_) {
    if (ProcessInfo.currentRss > peak) peak = ProcessInfo.currentRss;
    final private = memory.privateBytes;
    if (private > privatePeak) privatePeak = private;
  });
  SchedulerBinding.instance.addTimingsCallback(onTimings);
  try {
    await action();
    osPeakAfter = memory.peakCommitBytes;
  } finally {
    sampler.cancel();
    SchedulerBinding.instance.removeTimingsCallback(onTimings);
    memory.dispose();
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
  expect(
    privatePeak - privateBefore,
    lessThan(512 << 20),
    reason: 'private committed memory must also remain bounded',
  );
  if (osPeakAfter > osPeakBefore) {
    expect(
      osPeakAfter - privateBefore,
      lessThan(512 << 20),
      reason: 'the OS peak counter must catch allocations between samples',
    );
  }
  return {
    'rssBeforeMB': before ~/ (1 << 20),
    'rssPeakMB': peak ~/ (1 << 20),
    'rssAfterMB': ProcessInfo.currentRss ~/ (1 << 20),
    'privateBeforeMB': privateBefore ~/ (1 << 20),
    'privatePeakMB': privatePeak ~/ (1 << 20),
    'osPeakCommitMB': osPeakAfter ~/ (1 << 20),
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
