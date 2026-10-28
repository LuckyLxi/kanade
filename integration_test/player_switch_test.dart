import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:kanade/ui/player_background.dart';
import 'package:kanade/ui/player_page.dart';

import 'harness.dart';

/// 播放页开着时切歌，检查背景有没有换成新封面的颜色。
/// 切歌前后各截一张图存到系统临时目录的 kanade_switch 里。
/// flutter drive --profile -d windows --driver=test_driver/integration_test.dart --target=integration_test/player_switch_test.dart
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  testWidgets('播放页内切歌换背景', (tester) async {
    final (player, nav) = await launchWithSong(tester);
    final out = Directory('${Directory.systemTemp.path}/kanade_switch');
    if (out.existsSync()) out.deleteSync(recursive: true);
    out.createSync();

    final view = tester.binding.renderViews.first;
    Future<void> shoot(String name) async {
      // ignore: invalid_use_of_protected_member
      final layer = view.layer! as OffsetLayer;
      final image = await layer.toImage(Offset.zero & view.size, pixelRatio: 0.5);
      final png = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      File('${out.path}/$name.png').writeAsBytesSync(png!.buffer.asUint8List());
    }

    CoverArt? art() => tester.widget<PlayerBackground>(find.byType(PlayerBackground)).art;

    final log = StringBuffer();
    await tester.runAsync(() async {
      nav.push(PlayerPage.route());
      await Future<void>.delayed(const Duration(seconds: 2));
      await shoot('before');
      final first = art();
      log.writeln('before: ${player.current!.name} ${first?.palette.first}');
      for (var i = 1; i <= 3; i++) {
        await player.playAt(i);
        await Future<void>.delayed(const Duration(seconds: 3));
        await shoot('after_$i');
        final now = art();
        log.writeln('after $i: ${player.current!.name} ${now?.palette.first} changed=${!identical(now, first)}');      }
    });
    // ignore: avoid_print
    print('\n===== SWITCH =====\n$log${out.path}\n==================');
  });
}
