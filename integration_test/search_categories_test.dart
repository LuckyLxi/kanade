import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:kanade/app.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:kanade/ui/glass.dart';
import 'package:kanade/ui/mv_page.dart';
import 'package:kanade/ui/search_page.dart';
import 'package:kanade/ui/widgets.dart';
import 'package:window_manager/window_manager.dart';

import 'harness.dart';

/// 依次切换搜索结果的六个分类并截图，存到系统临时目录的 kanade_search_frames 里。
/// flutter drive -d windows --driver=test_driver/integration_test.dart --target=integration_test/search_categories_test.dart
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  testWidgets('分类搜索', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    final out = Directory('${Directory.systemTemp.path}/kanade_search_frames');
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
    Future<void> settle([int ms = 2500]) => tester.runAsync(() => Future<void>.delayed(Duration(milliseconds: ms)));

    await initTestApp();
    await windowManager.setSize(const Size(430, 900));
    await tester.pumpWidget(KanadeGlass.wrap(child: const AppProviders(mediaSession: false, child: KanadeApp())));
    await settle();

    await tester.tap(find.byIcon(Icons.search).first);
    await settle(800);
    final field = find.descendant(of: find.byType(SearchPage), matching: find.byType(TextField));
    await tester.enterText(field, '周杰伦');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await settle(4000);

    final failures = <String>[];
    for (final (i, label) in ['歌曲', '歌手', '专辑', '歌单', '视频', '歌词', '用户'].indexed) {
      await tester.tap(find.widgetWithText(Pill, label));
      await settle(4000);
      await shoot('${i}_$label');
      // 每个分类都应该至少出来一行结果，而不是转圈或报错
      if (find.descendant(of: find.byType(SearchPage), matching: find.byType(ListTile)).evaluate().isEmpty) failures.add(label);
    }

    // 视频滚到底，确认能翻页
    await tester.tap(find.widgetWithText(Pill, '视频'));
    await settle(500);
    final list = find.descendant(of: find.byType(SearchPage), matching: find.byType(Scrollable)).last;
    for (var i = 0; i < 6; i++) {
      await tester.drag(list, const Offset(0, -2500));
      await settle(1500);
    }
    await shoot('7_视频翻页');

    // 打开第一条视频：播放 8 秒后位置应该在走
    await tester.drag(list, const Offset(0, 100000));
    await settle(800);
    await tester.tap(find.descendant(of: find.byType(SearchPage), matching: find.byType(ListTile)).first);
    // 播放器一出现就静音，测试不出声
    for (var i = 0; i < 100 && find.byType(Video).evaluate().isEmpty; i++) {
      await settle(100);
    }
    await tester.runAsync(() => tester.widget<Video>(find.byType(Video)).controller.player.setVolume(0));
    await settle(8000);
    await shoot('8_MV');
    final position = tester.widget<Video>(find.byType(Video)).controller.player.state.position;
    expect(position, greaterThan(const Duration(seconds: 2)), reason: 'MV 没有开始播放');
    Navigator.of(tester.element(find.byType(MvPage))).pop();
    await settle(800);

    // 用户主页
    await tester.tap(find.widgetWithText(Pill, '用户'));
    await settle(1500);
    await shoot('9_用户列表');
    // 第一个通常是歌手账号（没有歌单标签），点第二个
    await tester.tap(find.descendant(of: find.byType(SearchPage), matching: find.byType(ListTile)).at(1));
    await settle(4000);
    await shoot('10_用户主页');

    debugDefaultTargetPlatformOverride = null;
    expect(failures, isEmpty, reason: '这些分类没有结果：$failures');
  });
}
