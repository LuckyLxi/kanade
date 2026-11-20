import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:kanade/settings/lyric_settings.dart';
import 'package:kanade/ui/mini_player.dart';
import 'package:kanade/ui/player_lyrics.dart';
import 'package:kanade/ui/player_page.dart';
import 'package:kanade/ui/player_route.dart';
import 'package:provider/provider.dart';
import 'package:window_manager/window_manager.dart';

import 'harness.dart';

/// 歌词页开关翻译、罗马音：小字展开收起时当前句一直停在原地。
/// 每帧记下当前句的位置，截图存到系统临时目录的 kanade_lyric_reveal 里。
/// profile 下不截图，改记每次开关那一秒的帧耗时。
/// flutter drive -d windows --driver=test_driver/integration_test.dart --target=integration_test/lyric_reveal_test.dart
/// flutter drive --profile -d cde2d04 --keep-app-running --driver=test_driver/integration_test.dart --target=integration_test/lyric_reveal_test.dart
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  testWidgets('歌词翻译、罗马音展开收起', (tester) async {
    // 电脑上模拟手机手势；手机上本来就是，profile 下也不让改
    if (Platform.isWindows) {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
    }
    final out = Directory('${Directory.systemTemp.path}/kanade_lyric_reveal');
    if (out.existsSync()) out.deleteSync(recursive: true);
    out.createSync();

    final view = tester.binding.renderViews.first;
    Future<void> shoot(String name) async {
      if (kProfileMode) return;
      // ignore: invalid_use_of_protected_member
      final layer = view.layer! as OffsetLayer;
      final image = await layer.toImage(
        Offset.zero & view.flutterView.physicalSize,
        pixelRatio: 1,
      );
      final png = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      File('${out.path}/$name.png').writeAsBytesSync(png!.buffer.asUint8List());
    }

    Future<void> wait(int ms) =>
        tester.runAsync(() => Future<void>.delayed(Duration(milliseconds: ms)));

    final (player, nav) = await launchWithSong(
      tester,
      songKeyword: 'YOASOBI 夜に駆ける',
      setup: Platform.isWindows
          ? () => windowManager.setSize(const Size(430, 900))
          : null,
    );
    final lyric = player.lyric!;
    final withTrans = lyric.lines.where((l) => l.trans.isNotEmpty).length;
    final withRoma = lyric.lines.where((l) => l.roma.isNotEmpty).length;
    debugPrint('lines ${lyric.lines.length} trans $withTrans roma $withRoma');
    expect(withTrans, greaterThan(0));

    await wait(1500);
    await tester.tap(find.byType(MiniPlayer));
    await wait(800);
    unawaited(nav.push(PlayerRoute(anchor: MiniPlayer.anchor)));
    await wait(1200);
    final page = tester.getRect(find.byType(PlayerPage));
    final g = await tester.startGesture(page.center);
    var time = Duration.zero;
    for (var i = 0; i < 10; i++) {
      time += const Duration(milliseconds: 16);
      await g.moveBy(const Offset(-24, 0), timeStamp: time);
      await wait(16);
    }
    await g.up(timeStamp: time + const Duration(milliseconds: 16));
    await wait(800);
    expect(find.byType(LyricView), findsOneWidget);

    // 停在中间某一句：直接改进度，歌放不了也不影响，之后也不会换句
    await tester.runAsync(() async {
      await player.pause();
      player.position.value = Duration(
        milliseconds: lyric.lines[lyric.lines.length ~/ 2 - 2].timeMs + 500,
      );
    });
    await wait(1500);

    final settings = tester
        .element(find.byType(LyricView))
        .read<LyricSettings>();
    final sweep = find.byWidgetPredicate(
      (w) => w.runtimeType.toString() == '_Sweep',
    );
    final initialRomaji = settings.romaji;
    final initialTrans = settings.translation;
    addTearDown(() {
      settings.setRomaji(initialRomaji);
      settings.setTranslation(initialTrans);
    });

    Future<void> toggle(
      String name,
      void Function() change, {
      bool still = true,
    }) async {
      await tester.runAsync(() => shoot('${name}_before'));
      final before = tester.getRect(sweep).top;
      final timings = <FrameTiming>[];
      void onTimings(List<FrameTiming> t) => timings.addAll(t);
      SchedulerBinding.instance.addTimingsCallback(onTimings);
      change();
      final tops = <double>[];
      await tester.runAsync(() async {
        final clock = Stopwatch()..start();
        var shot = 0;
        const shots = [120, 300];
        while (clock.elapsedMilliseconds < 1000) {
          await Future<void>.delayed(const Duration(milliseconds: 16));
          tops.add(tester.getRect(sweep).top);
          if (shot < shots.length && clock.elapsedMilliseconds >= shots[shot]) {
            await shoot('${name}_${shots[shot++]}');
          }
        }
        await shoot('${name}_after');
        // 帧耗时是攒一批才报上来的
        await Future<void>.delayed(const Duration(milliseconds: 300));
      });
      SchedulerBinding.instance.removeTimingsCallback(onTimings);
      double ms(Duration d) => d.inMicroseconds / 1000;
      final build = timings.map((t) => ms(t.buildDuration)).toList()..sort();
      final raster = timings.map((t) => ms(t.rasterDuration)).toList()..sort();
      if (timings.isNotEmpty) {
        debugPrint(
          '$name frames ${timings.length} '
          'build p50 ${build[build.length ~/ 2].toStringAsFixed(1)} max ${build.last.toStringAsFixed(1)} '
          'raster p50 ${raster[raster.length ~/ 2].toStringAsFixed(1)} max ${raster.last.toStringAsFixed(1)} '
          'over8ms ${timings.where((t) => ms(t.totalSpan) > 8.3).length}',
        );
      }
      final drift = tops
          .map((t) => (t - before).abs())
          .reduce((a, b) => a > b ? a : b);
      debugPrint('$name: before $before max drift $drift');
      if (still) expect(drift, lessThan(1));
    }

    // 对照：平常换一句时整页滑动的开销。第一次换句有一次性的开销，先换一次热身
    final mid = lyric.lines.length ~/ 2;
    await tester.runAsync(() async {
      player.position.value = Duration(
        milliseconds: lyric.lines[mid].timeMs + 500,
      );
    });
    await wait(2000);
    await toggle(
      'line_change',
      () => player.position.value = Duration(
        milliseconds: lyric.lines[mid + 1].timeMs + 500,
      ),
      still: false,
    );
    await wait(1500);
    await toggle('trans_off', () => settings.setTranslation(false));
    await toggle('trans_on', () => settings.setTranslation(true));
    if (withRoma > 0) {
      await toggle('roma_off', () => settings.setRomaji(false));
      await toggle('roma_on', () => settings.setRomaji(true));
    }
    // 中途反悔：收到一半又打开，不该跳
    await toggle('trans_flip', () {
      settings.setTranslation(false);
      Timer(
        const Duration(milliseconds: 150),
        () => settings.setTranslation(true),
      );
    });
    await nav.maybePop();
    await wait(1200);
    if (Platform.isWindows) debugDefaultTargetPlatformOverride = null;
  });
}
