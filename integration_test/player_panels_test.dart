import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:kanade/player/player_controller.dart';
import 'package:kanade/src/rust/api/music.dart' as api;
import 'package:kanade/ui/mini_player.dart';
import 'package:kanade/ui/player_lyrics.dart';
import 'package:kanade/ui/player_page.dart';
import 'package:kanade/ui/player_route.dart';
import 'package:window_manager/window_manager.dart';

import 'harness.dart';

/// 播放页面板和控件截图：手机上左滑歌词、上滑队列、往下拉 / 返回键回到主页面，
/// 播放模式按钮、音量按钮展开成音量条；最后切到宽窗口看电脑布局和队列按钮。
/// 图片存到系统临时目录的 kanade_panel_frames 里。模拟手机平台只能在 debug 下：
/// flutter drive -d windows --driver=test_driver/integration_test.dart --target=integration_test/player_panels_test.dart
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  testWidgets('播放页面板和控件截图', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    final out = Directory('${Directory.systemTemp.path}/kanade_panel_frames');
    if (out.existsSync()) out.deleteSync(recursive: true);
    out.createSync();

    final view = tester.binding.renderViews.first;
    var index = 0;
    Future<void> shoot(String name) async {
      // ignore: invalid_use_of_protected_member
      final layer = view.layer! as OffsetLayer;
      final image = await layer.toImage(Offset.zero & view.flutterView.physicalSize, pixelRatio: 1);
      final png = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      File('${out.path}/${(index++).toString().padLeft(2, '0')}_$name.png').writeAsBytesSync(png!.buffer.asUint8List());
    }

    Future<void> wait(int ms) => tester.runAsync(() => Future<void>.delayed(Duration(milliseconds: ms)));
    Future<void> frames(String name, List<int> times) => tester.runAsync(() async {
      var last = 0;
      for (final ms in times) {
        await Future<void>.delayed(Duration(milliseconds: ms - last));
        last = ms;
        await shoot('${name}_${ms.toString().padLeft(3, '0')}');
      }
    });
    /// [midShot] 在拖到一半、手指还按着时截一张；[hold] 是松手前停住不动多久（慢慢松手，没有速度）。
    Future<void> drag(Offset from, Offset step, int steps, {String? midShot, int hold = 0}) async {
      final g = await tester.startGesture(from);
      var time = Duration.zero;
      for (var i = 0; i < steps; i++) {
        time += const Duration(milliseconds: 16);
        await g.moveBy(step, timeStamp: time);
        await wait(16);
        if (i == steps ~/ 2 && midShot != null) await tester.runAsync(() => shoot(midShot));
      }
      if (hold > 0) {
        await wait(hold);
        time += Duration(milliseconds: hold);
        await g.moveBy(Offset.zero, timeStamp: time);
      }
      await g.up(timeStamp: time + const Duration(milliseconds: 16));
    }

    final (player, nav) = await launchWithSong(tester, setup: () => windowManager.setSize(const Size(430, 900)));
    final mode = player.mode;
    // 测试会切换播放模式，结束时把存的值改回去
    final savedMode = api.getPref(key: 'play_mode');
    addTearDown(() => api.setPref(key: 'play_mode', value: savedMode ?? mode.name));

    // 播放条先是小圆，点开成长条再打开播放页
    await tester.tap(find.byType(MiniPlayer));
    await wait(800);
    unawaited(nav.push(PlayerRoute(anchor: MiniPlayer.anchor)));
    await wait(1200);
    await tester.runAsync(() => shoot('main'));
    final page = tester.getRect(find.byType(PlayerPage));

    // 左滑翻到歌词，页面跟着手指走；歌词一出来就停在当前句
    await drag(page.center, const Offset(-24, 0), 10, midShot: 'lyrics_mid');
    await frames('lyrics', [100, 250, 600]);
    expect(find.byType(LyricView), findsOneWidget);
    // 右滑翻回来
    await drag(page.center, const Offset(24, 0), 10, midShot: 'lyrics_back_mid');
    await frames('lyrics_back', [100, 250, 600]);
    expect(find.byType(LyricView), findsNothing);
    // 拖不到一半、慢慢松手：弹回主页面
    await drag(page.center, const Offset(-12, 0), 8, hold: 300);
    await frames('lyrics_bounce', [100, 600]);
    expect(find.byType(LyricView), findsNothing);
    // 歌词页按返回直接关掉播放页
    await drag(page.center, const Offset(-24, 0), 10);
    await wait(600);
    await nav.maybePop();
    await frames('lyrics_pop', [100, 700]);
    expect(find.byType(PlayerPage), findsNothing);
    unawaited(nav.push(PlayerRoute(anchor: MiniPlayer.anchor)));
    await wait(1200);

    // 上滑翻到队列；队列页按返回只翻回主页面，不关播放页
    await drag(page.center, const Offset(0, -30), 10);
    await wait(600);
    await nav.maybePop();
    await frames('queue_pop', [100, 700]);
    expect(find.byType(PlayerPage), findsOneWidget);
    expect(find.text('接下来播放').evaluate().length + find.text('Up next').evaluate().length, 0);

    // 再上滑翻到队列，在列表顶上往下拉翻回来
    await drag(page.center, const Offset(0, -30), 10, midShot: 'queue_mid');
    await frames('queue', [100, 250, 600]);
    await drag(page.center, const Offset(0, 24), 12, midShot: 'queue_back_mid');
    await frames('queue_back', [100, 250, 600]);
    expect(find.text('接下来播放').evaluate().length + find.text('Up next').evaluate().length, 0);

    // 播放模式点一下换一种
    await tester.tap(find.byIcon(_icon(player.mode)).last);
    await frames('mode', [150, 400]);
    expect(player.mode, isNot(mode));

    // 音量按钮长成音量条，往上拖一段，点外面收回（测试里音量是 0）
    final button = tester.getRect(find.byIcon(Icons.volume_off_rounded).last);
    await tester.tapAt(button.center);
    await frames('volume_open', [40, 100, 180, 400]);
    await drag(button.center - const Offset(0, 20), const Offset(0, -12), 10);
    await frames('volume_drag', [100]);
    expect(player.volume, greaterThan(30));
    await tester.tapAt(page.center);
    await frames('volume_close', [40, 100, 180, 400]);

    // 宽窗口：右边默认歌词，队列按钮切换
    await tester.runAsync(() => windowManager.setSize(const Size(1280, 800)));
    await frames('wide', [800]);
    await tester.tap(find.byIcon(Icons.format_list_bulleted_rounded).last);
    await frames('wide_queue', [600]);

    // ignore: avoid_print
    print('\n===== PANEL FRAMES: ${out.path} =====');
    debugDefaultTargetPlatformOverride = null;
  });
}

IconData _icon(PlayMode mode) => switch (mode) {
  PlayMode.sequence => Icons.repeat_rounded,
  PlayMode.repeatOne => Icons.repeat_one_rounded,
  PlayMode.shuffle => Icons.shuffle_rounded,
};
