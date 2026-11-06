import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:kanade/app.dart';
import 'package:kanade/src/rust/api/music.dart' as api;
import 'package:kanade/ui/foryou_settings_page.dart';
import 'package:kanade/ui/glass.dart';
import 'package:kanade/ui/home_shell.dart';
import 'package:kanade/ui/settings_page.dart';
import 'package:window_manager/window_manager.dart';

import 'harness.dart';

/// 设置里的「自定义推荐页」：读出列表，临时切换第一个可选项并保存，确认生效后恢复原来的选择。
/// 会真实改动账号设置两次，结束时与开始时相同。需要已登录。
/// 截图存到系统临时目录的 kanade_foryou 里。
/// flutter drive -d windows --driver=test_driver/integration_test.dart --target=integration_test/foryou_settings_test.dart
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  testWidgets('自定义推荐页', (tester) async {
    final out = Directory('${Directory.systemTemp.path}/kanade_foryou');
    if (out.existsSync()) out.deleteSync(recursive: true);
    out.createSync();
    final view = tester.binding.renderViews.first;
    Future<void> shoot(String name) => tester.runAsync(() async {
      // ignore: invalid_use_of_protected_member
      final layer = view.layer! as OffsetLayer;
      final image = await layer.toImage(Offset.zero & view.flutterView.physicalSize, pixelRatio: 1);
      final png = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      File('${out.path}/$name.png').writeAsBytesSync(png!.buffer.asUint8List());
    });
    Future<void> settle(int ms) => tester.runAsync(() => Future<void>.delayed(Duration(milliseconds: ms)));
    String states(List<dynamic> items) => items.map((i) => '${i.title}:${i.fixed ? 'fixed' : i.chosen}').join(' ');

    await initTestApp();
    await windowManager.setSize(const Size(1280, 860));
    await tester.pumpWidget(KanadeGlass.wrap(child: const AppProviders(mediaSession: false, child: KanadeApp())));
    await settle(4000);

    final before = (await tester.runAsync(api.getForyouConfig))!;
    debugPrint('before: ${states(before)}');
    final original = [for (final i in before) if (i.chosen) i.id];
    final target = before.firstWhere((i) => !i.fixed);
    final title = target.title;

    final nav = Navigator.of(tester.element(find.byType(HomeShell)), rootNavigator: true);
    nav.push(SettingsPage.route());
    await settle(1500);
    await shoot('0_settings');
    await tester.tap(find.text('自定义推荐页'));
    await settle(3000);
    await shoot('1_page');
    expect(find.text(title), findsOneWidget);

    try {
      await tester.tap(find.text(title));
      await settle(300);
      await shoot('2_toggled');
      await tester.tap(find.text('保存'));
      await settle(3000);
      await shoot('3_saved');
      final after = (await tester.runAsync(api.getForyouConfig))!;
      debugPrint('after save: ${states(after)}');
      expect(after.firstWhere((i) => i.title == title).chosen, !target.chosen);
    } finally {
      await tester.runAsync(() => api.saveForyouConfig(chosen: original));
      final restored = (await tester.runAsync(api.getForyouConfig))!;
      debugPrint('restored: ${states(restored)}');
      expect([for (final i in restored) if (i.chosen) i.id]..sort(), [...original]..sort());
    }
    expect(foryouSaved.value, greaterThan(0));
  });
}
