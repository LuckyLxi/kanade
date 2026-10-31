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
import 'package:kanade/ui/toast.dart';
import 'package:window_manager/window_manager.dart';

import 'harness.dart';

/// 提示在各种布局下的位置和进出动画截图，存到系统临时目录的 kanade_toast_frames 里。
/// flutter drive -d windows --driver=test_driver/integration_test.dart --target=integration_test/toast_frames_test.dart
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  testWidgets('提示截图', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    final out = Directory('${Directory.systemTemp.path}/kanade_toast_frames');
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
      final file = '${(index++).toString().padLeft(2, '0')}_$name.png';
      File('${out.path}/$file').writeAsBytesSync(png!.buffer.asUint8List());
    }

    Future<void> frames(String name, List<int> times) => tester.runAsync(() async {
      var last = 0;
      for (final ms in times) {
        await Future<void>.delayed(Duration(milliseconds: ms - last));
        last = ms;
        await shoot('${name}_${ms.toString().padLeft(4, '0')}');
      }
    });

    void toast(String text, ToastKind kind) => showToast(tester.element(find.byType(DiscoverPage)), text, kind: kind);

    final (_, nav) = await launchWithSong(tester, setup: () => windowManager.setSize(const Size(430, 900)));
    final bar = find.byType(MiniPlayer);
    await frames('settle', [800]);

    // 播放条是圆球
    toast('已添加到我喜欢', ToastKind.liked);
    await frames('circle', [0, 60, 120, 240, 600]);

    // 播放条展开成胶囊，新提示顶掉旧的
    await tester.tap(bar);
    await frames('expand', [600]);
    toast('操作失败：网络连接超时，请稍后再试一次', ToastKind.error);
    await frames('capsule_error', [60, 300]);
    toast('已从「通勤」移除', ToastKind.success);
    await frames('replace', [60, 120, 300]);
    await frames('gone', [3000]);

    // 播放页打开时放到顶上
    await tester.tapAt(tester.getTopLeft(bar) + const Offset(100, 20));
    await frames('player_open', [700]);
    toast('已添加到我喜欢', ToastKind.liked);
    await frames('player', [300]);
    nav.pop();
    await frames('player_close', [700]);

    // 宽窗口：桌面播放栏上方，内容区居中
    debugDefaultTargetPlatformOverride = null;
    await tester.runAsync(() => windowManager.setSize(const Size(1280, 800)));
    await frames('desktop', [800]);
    toast('缓存已清除', ToastKind.success);
    await frames('desktop_toast', [300]);
    await tester.tapAt(tester.getTopLeft(find.byType(DesktopPlayerBar)) + const Offset(45, 42));
    await frames('desktop_open', [700]);
    toast('已添加到我喜欢', ToastKind.liked);
    await frames('desktop_player', [300]);
    nav.pop();

    // ignore: avoid_print
    print('toast frames: ${out.path}');
  });
}
