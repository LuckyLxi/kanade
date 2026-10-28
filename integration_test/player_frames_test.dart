import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:kanade/ui/player_page.dart';

import 'harness.dart';

/// 打开 / 关闭播放页时按时间点截下整个窗口，检查转场动画每一帧长什么样。
/// 图片存到系统临时目录的 kanade_frames 里，路径会打印出来。
/// flutter drive --profile -d windows --driver=test_driver/integration_test.dart --target=integration_test/player_frames_test.dart
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  testWidgets('播放页转场逐帧截图', (tester) async {
    final (_, nav) = await launchWithSong(tester);
    final out = Directory('${Directory.systemTemp.path}/kanade_frames');
    if (out.existsSync()) out.deleteSync(recursive: true);
    out.createSync();

    final view = tester.binding.renderViews.first;
    Future<void> shoot(String name) async {
      // debugLayer 在 profile 模式下是 null，直接取根图层
      // ignore: invalid_use_of_protected_member
      final layer = view.layer! as OffsetLayer;
      final image = await layer.toImage(Offset.zero & view.size, pixelRatio: 0.5);
      final png = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      File('${out.path}/$name.png').writeAsBytesSync(png!.buffer.asUint8List());
    }

    await tester.runAsync(() async {
      await shoot('00_home');
      nav.push(PlayerPage.route());
      var last = 0;
      for (final ms in [30, 80, 140, 220, 320, 450, 700]) {
        await Future<void>.delayed(Duration(milliseconds: ms - last));
        last = ms;
        await shoot('open_${ms.toString().padLeft(3, '0')}');
      }
      nav.pop();
      last = 0;
      for (final ms in [40, 120, 220, 330]) {
        await Future<void>.delayed(Duration(milliseconds: ms - last));
        last = ms;
        await shoot('close_${ms.toString().padLeft(3, '0')}');
      }
    });
    // ignore: avoid_print
    print('FRAMES: ${out.path}');
  });
}
