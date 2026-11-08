import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:kanade/ui/desktop_shell.dart';
import 'package:kanade/ui/discover_page.dart';
import 'package:kanade/ui/mini_player.dart';
import 'package:kanade/ui/player_route.dart';
import 'package:window_manager/window_manager.dart';

import 'harness.dart';

/// 按住播放条往上拖一段停住截图，看拖动途中的玻璃：桌面播放栏、手机一级页面、手机二级页面。
/// 图片存到系统临时目录的 kanade_drag_shots 里。模拟手机平台只能在 debug 下：
/// flutter drive -d windows --driver=test_driver/integration_test.dart --target=integration_test/bar_drag_shots_test.dart
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  testWidgets('拖动途中的播放条', (tester) async {
    final out = Directory('${Directory.systemTemp.path}/kanade_drag_shots');
    if (out.existsSync()) out.deleteSync(recursive: true);
    out.createSync();
    final view = tester.binding.renderViews.first;
    Future<void> wait(int ms) => tester.runAsync(() => Future<void>.delayed(Duration(milliseconds: ms)));
    Future<void> shoot(String name) => tester.runAsync(() async {
      // ignore: invalid_use_of_protected_member
      final layer = view.layer! as OffsetLayer;
      final image = await layer.toImage(Offset.zero & view.flutterView.physicalSize, pixelRatio: 1);
      final png = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      File('${out.path}/$name.png').writeAsBytesSync(png!.buffer.asUint8List());
    });

    /// 按住往上拖 [dy] 停住，截 [name]，再拖回去松手（收回）。
    Future<void> holdDrag(Offset from, double dy, String name) async {
      await shoot('${name}_before');
      final g = await tester.startGesture(from);
      for (var i = 0; i < 10; i++) {
        await g.moveBy(Offset(0, -dy / 10));
        await wait(16);
      }
      await wait(400);
      await shoot(name);
      for (var i = 0; i < 10; i++) {
        await g.moveBy(Offset(0, dy / 10));
        await wait(16);
      }
      await g.up();
      await wait(1000);
    }

    /// 慢慢拖上去再拖回来，每一步记下播放条里封面量出来的位置（飞行封面的起点），打印最大偏移；应该一直不动。
    Future<void> sweep(PlayerBarAnchor anchor, Offset from, String name) async {
      final rest = anchor.coverRect!;
      var worst = 0.0;
      final g = await tester.startGesture(from);
      for (var i = 0; i < 160; i++) {
        await g.moveBy(Offset(0, i < 80 ? -5 : 5));
        await wait(16);
        final r = anchor.coverRect;
        if (r != null) worst = [worst, (r.topLeft - rest.topLeft).distance, (r.size.width - rest.width).abs()].reduce(math.max);
      }
      await g.up();
      await wait(1000);
      // ignore: avoid_print
      print('SWEEP $name: cover start moved at most ${worst.toStringAsFixed(2)} px');
    }

    await launchWithSong(tester, setup: () => windowManager.setSize(const Size(1280, 800)));
    await wait(1500);
    await sweep(DesktopPlayerBar.anchor, tester.getTopLeft(find.byType(DesktopPlayerBar)) + const Offset(300, 20), 'desktop');
    // 栏里歌名右边的空白处
    for (final dy in [60.0, 120.0, 180.0, 200.0, 240.0, 350.0]) {
      await holdDrag(tester.getTopLeft(find.byType(DesktopPlayerBar)) + const Offset(300, 20), dy, 'desktop_${dy.round()}');
    }
    if (const bool.fromEnvironment('DESKTOP_ONLY')) return;

    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    await tester.runAsync(() => windowManager.setSize(const Size(430, 900)));
    await wait(1200);
    final bar = find.byType(MiniPlayer);
    // 第一次放歌时是导航栏旁的圆球，点开成胶囊
    if (tester.getSize(bar).width < 100) {
      await tester.tap(bar);
      await wait(800);
    }
    await holdDrag(tester.getTopLeft(bar) + const Offset(140, 32), 60, 'mobile');

    final tabNav = Navigator.of(tester.element(find.byType(DiscoverPage)));
    tabNav.push(MaterialPageRoute<void>(builder: (_) => const Scaffold(body: Center(child: Text('二级页面')))));
    await wait(1200);
    await holdDrag(tester.getTopLeft(bar) + const Offset(140, 32), 60, 'nested');
    await sweep(MiniPlayer.anchor, tester.getTopLeft(bar) + const Offset(140, 32), 'nested');
    tabNav.pop();
    await wait(800);
    debugDefaultTargetPlatformOverride = null;
    // ignore: avoid_print
    print('SHOTS: ${out.path}');
  });
}
