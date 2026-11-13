import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:kanade/ui/mini_player.dart';
import 'package:kanade/ui/player_page.dart';
import 'package:kanade/ui/player_route.dart';
import 'package:window_manager/window_manager.dart';

import 'harness.dart';

/// 播放页音质按钮：点开长成菜单、点外面收起、再点开选一档的逐帧截图。
/// 图片存到系统临时目录的 kanade_quality_frames 里。模拟手机平台只能在 debug 下：
/// flutter drive -d windows --driver=test_driver/integration_test.dart --target=integration_test/quality_menu_frames_test.dart
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  testWidgets('音质菜单逐帧截图', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    final out = Directory('${Directory.systemTemp.path}/kanade_quality_frames');
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

    final (_, nav) = await launchWithSong(tester, setup: () => windowManager.setSize(const Size(430, 900)));
    await tester.tap(find.byType(MiniPlayer));
    await wait(800);
    unawaited(nav.push(PlayerRoute(anchor: MiniPlayer.anchor)));
    await wait(1500);
    await tester.runAsync(() => shoot('chip'));

    final chip = find.byType(QualityMenu);
    await tester.tap(chip);
    await frames('open', [16, 50, 90, 140, 200, 280, 400, 700]);

    // 点菜单外面收起
    await tester.tapAt(const Offset(30, 120));
    await frames('close', [16, 50, 90, 140, 200, 350]);

    // 再点开，选第一档
    await tester.tap(chip);
    await wait(700);
    final page = tester.getRect(find.byType(PlayerPage));
    final menuTop = tester.getTopLeft(chip).dy;
    await tester.tapAt(Offset(page.center.dx, menuTop - 60));
    await frames('pick', [40, 120, 220, 300, 380, 480, 800]);

    debugDefaultTargetPlatformOverride = null;
    // ignore: avoid_print
    print('FRAMES: ${out.path}');
  });
}
