import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:kanade/ui/discover_page.dart';
import 'package:kanade/ui/mini_player.dart';

import 'harness.dart';

/// 手机上：二级页面里按住播放条往上拖，停在几个位置截图，看边缘有没有露出玻璃。
/// 截图以 base64 放进 reportData，驱动端写到 build/integration_response_data.json。
/// flutter drive --profile -d <手机> --driver=test_driver/integration_test.dart --target=integration_test/nested_drag_phone_test.dart
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  testWidgets('二级页面拖动播放条', (tester) async {
    await launchWithSong(tester);
    Future<void> wait(int ms) => tester.runAsync(() => Future<void>.delayed(Duration(milliseconds: ms)));
    final view = tester.binding.renderViews.first;
    final shots = <String, String>{};
    Future<void> shoot(String name) => tester.runAsync(() async {
      // ignore: invalid_use_of_protected_member
      final layer = view.layer! as OffsetLayer;
      final image = await layer.toImage(Offset.zero & view.flutterView.physicalSize, pixelRatio: 1);
      final png = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      shots[name] = base64Encode(png!.buffer.asUint8List());
    });

    final bar = find.byType(MiniPlayer);
    await wait(1500);
    // 第一次放歌时是导航栏旁的圆球，点开成胶囊
    if (tester.getSize(bar).width < 100) {
      await tester.tap(bar);
      await wait(1000);
    }
    // 背后放一页彩色的列表，玻璃的边缘和折射才看得出来
    final tabNav = Navigator.of(tester.element(find.byType(DiscoverPage)));
    tabNav.push(
      MaterialPageRoute<void>(
        builder: (_) => Scaffold(
          body: ListView.builder(
            itemBuilder: (_, i) => Container(
              height: 72,
              color: HSLColor.fromAHSL(1, (i * 37) % 360.0, 0.6, 0.45).toColor(),
              alignment: Alignment.centerLeft,
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Text('第 $i 行', style: const TextStyle(color: Colors.white, fontSize: 18)),
            ),
          ),
        ),
      ),
    );
    await wait(1500);
    await shoot('rest');

    for (final dy in [20.0, 60.0, 120.0]) {
      final g = await tester.startGesture(tester.getTopLeft(bar) + const Offset(140, 32));
      for (var i = 0; i < 10; i++) {
        await g.moveBy(Offset(0, -dy / 10));
        await wait(16);
      }
      await wait(500);
      await shoot('drag_${dy.round()}');
      for (var i = 0; i < 10; i++) {
        await g.moveBy(Offset(0, dy / 10));
        await wait(16);
      }
      await g.up();
      await wait(1200);
    }
    tabNav.pop();
    await wait(800);
    binding.reportData = {'shots': shots};
  });
}
