import 'dart:async';
import 'dart:io';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:kanade/auth/auth_controller.dart';
import 'package:kanade/library/library_controller.dart';
import 'package:kanade/main.dart';
import 'package:kanade/player/player_controller.dart';
import 'package:kanade/settings/locale_controller.dart';
import 'package:kanade/src/rust/api/music.dart' as api;
import 'package:kanade/src/rust/frb_generated.dart';
import 'package:kanade/ui/home_shell.dart';
import 'package:kanade/ui/player_background.dart';
import 'package:kanade/ui/player_lyrics.dart';
import 'package:kanade/ui/player_page.dart';
import 'package:media_kit/media_kit.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';

/// 打开播放页时逐帧记录内存和渲染耗时，分别测整页和各个部件，定位转场掉帧 / 内存暴涨。
/// flutter drive --profile -d windows --driver=test_driver/integration_test.dart --target=integration_test/player_perf_test.dart
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  testWidgets('播放页转场性能', (tester) async {
    MediaKit.ensureInitialized();
    await RustLib.init();
    final dir = await getApplicationSupportDirectory();
    await api.initCore(dataDir: dir.path);

    late PlayerController player;
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => LocaleController()),
          ChangeNotifierProvider(create: (_) => AuthController()),
          ChangeNotifierProvider(create: (context) => player = PlayerController(context.read<AuthController>())),
          ChangeNotifierProvider(create: (context) => LibraryController(context.read<AuthController>()), lazy: false),
        ],
        child: const KanadeApp(),
      ),
    );

    final songs = await tester.runAsync(() async {
      final groups = await api.getToplists();
      final top = groups.first.lists.first;
      return (await api.getToplistDetail(topId: top.topId, period: top.period)).songs;
    });
    await tester.runAsync(() async {
      await player.setVolume(0);
      await player.playList(songs!, 0);
      // 等歌词、封面素材都就绪，测的是稳态下打开播放页
      for (var i = 0; i < 50 && player.lyric == null; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
      await Future<void>.delayed(const Duration(seconds: 3));
    });

    final ctx = tester.element(find.byType(HomeShell));
    final nav = Navigator.of(ctx, rootNavigator: true);
    Route<void> slide(Widget child) => PageRouteBuilder(
          opaque: false,
          transitionDuration: const Duration(milliseconds: 500),
          pageBuilder: (_, _, _) => child,
          transitionsBuilder: (_, a, _, c) => SlideTransition(
            position: Tween(begin: const Offset(0, 1), end: Offset.zero).animate(a),
            child: c,
          ),
        );
    final art = await tester.runAsync(() => loadCoverArt(player.current!.coverUrl.replaceFirst('300x300', '500x500')));

    Route<void> bg(int parts) {
      debugBackgroundParts = parts;
      return slide(PlayerBackground(art: art, animate: true));
    }

    final cases = <String, Route<void> Function()>{
      'black': () => slide(const ColoredBox(color: Colors.black)),
      'bg cover only': () => bg(1),
      'bg blobs only': () => bg(2),
      'bg scrim only': () => bg(4),
      'bg all': () => bg(7),
      'lyrics': () => slide(const ColoredBox(color: Colors.black, child: LyricView(fontSize: 36))),
      'full': PlayerPage.route,
    };
    final report = StringBuffer();
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
  void onTimings(List<FrameTiming> t) => timings.addAll(t);
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
