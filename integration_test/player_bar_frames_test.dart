import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:kanade/ui/desktop_shell.dart';
import 'package:kanade/ui/discover_page.dart';
import 'package:kanade/ui/mini_player.dart';
import 'package:window_manager/window_manager.dart';

import 'harness.dart';

/// 播放条的各种变形按时间点截图：圆球展开 / 收起、上拖打开、下拉关闭、点开、左右滑切歌，
/// 最后切到宽窗口看桌面播放栏。手机交互用 debugDefaultTargetPlatformOverride 在桌面上模拟。
/// 图片存到系统临时目录的 kanade_bar_frames 里，路径会打印出来。
/// 模拟手机平台只能在 debug 下：
/// flutter drive -d windows --driver=test_driver/integration_test.dart --target=integration_test/player_bar_frames_test.dart
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  testWidgets('播放条变形逐帧截图', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    final out = Directory('${Directory.systemTemp.path}/kanade_bar_frames');
    if (out.existsSync()) out.deleteSync(recursive: true);
    out.createSync();

    final view = tester.binding.renderViews.first;
    var index = 0;
    Future<void> shoot(String name) async {
      // ignore: invalid_use_of_protected_member
      final layer = view.layer! as OffsetLayer;
      // 根图层已经乘过设备像素比，范围要按物理像素给
      final image = await layer.toImage(Offset.zero & view.flutterView.physicalSize, pixelRatio: 1);
      final png = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      final file = '${(index++).toString().padLeft(2, '0')}_$name.png';
      File('${out.path}/$file').writeAsBytesSync(png!.buffer.asUint8List());
    }

    Future<void> series(String name, List<int> times) async {
      var last = 0;
      for (final ms in times) {
        await Future<void>.delayed(Duration(milliseconds: ms - last));
        last = ms;
        await shoot('${name}_${ms.toString().padLeft(3, '0')}');
      }
    }

    Future<void> frames(String name, List<int> times) => tester.runAsync(() => series(name, times));

    Future<void> drag(Offset from, Offset step, int steps, {required int stepMs, String? midShot}) async {
      final g = await tester.startGesture(from);
      var time = Duration.zero;
      for (var i = 0; i < steps; i++) {
        time += Duration(milliseconds: stepMs);
        await g.moveBy(step, timeStamp: time);
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 16)));
        if (i == steps ~/ 2 && midShot != null) await tester.runAsync(() => shoot(midShot));
      }
      await g.up(timeStamp: time + Duration(milliseconds: stepMs));
    }

    // 第一首歌出现：小圆从导航栏右端分裂出来
    final (_, nav) = await launchWithSong(
      tester,
      setup: () => windowManager.setSize(const Size(430, 900)),
      onPlay: () => series('appear', [0, 60, 140, 240, 400, 800]),
    );

    final bar = find.byType(MiniPlayer);
    // 进出二级页面：导航栏和播放条融合、弹成底部胶囊，再倒着分开
    Future<void> nested(String name) async {
      final tabNav = Navigator.of(tester.element(find.byType(DiscoverPage)));
      unawaited(tabNav.push(MaterialPageRoute<void>(builder: (_) => const Scaffold(backgroundColor: Colors.black))));
      await frames('${name}_in', [40, 100, 160, 240, 320, 420, 560, 900]);
      tabNav.pop();
      await frames('${name}_out', [40, 100, 160, 240, 320, 420, 560, 900]);
    }

    await frames('circle', [0]);
    await nested('nested_circle');

    await tester.tap(bar);
    await frames('expand', [60, 160, 260, 600]);

    await tester.drag(find.byType(Scrollable).hitTestable().first, const Offset(0, -240));
    await frames('collapse', [60, 160, 260, 600]);

    await tester.tap(bar);
    await frames('expand_again', [600]);
    await nested('nested_capsule');

    // 按住往上拖打开
    await drag(tester.getCenter(bar), const Offset(0, -40), 8, stepMs: 16, midShot: 'drag_up_mid');
    await frames('drag_up_release', [80, 200, 500]);

    // 播放页里往下拉关闭
    final size = tester.getSize(find.byType(MaterialApp));
    await drag(Offset(size.width / 2, 300), const Offset(0, 40), 10, stepMs: 40, midShot: 'drag_down_mid');
    await frames('drag_down_release', [80, 200, 500]);

    // 点一下打开，返回键关闭
    await tester.tapAt(tester.getTopLeft(bar) + const Offset(100, 20));
    await frames('tap_open', [40, 120, 200, 300, 420, 700]);
    nav.pop();
    await frames('pop', [60, 160, 260, 360, 600]);

    // 左滑切下一首
    await drag(tester.getCenter(bar), const Offset(-30, 0), 4, stepMs: 16, midShot: 'swipe_mid');
    await frames('swipe_release', [70, 200, 500]);

    // 宽窗口：桌面播放栏
    debugDefaultTargetPlatformOverride = null;
    await tester.runAsync(() => windowManager.setSize(const Size(1280, 800)));
    await frames('desktop', [800]);
    await tester.tapAt(tester.getTopLeft(find.byType(DesktopPlayerBar)) + const Offset(45, 42));
    await frames('desktop_open', [60, 160, 260, 400, 700]);
    nav.pop();
    await frames('desktop_close', [80, 200, 600]);

    // ignore: avoid_print
    print('FRAMES: ${out.path}');
  });
}
