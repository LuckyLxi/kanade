import 'dart:io';
import 'dart:ui' as ui;

import 'package:material_ui/material_ui.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:kanade/app.dart';
import 'package:kanade/ui/feed_column.dart';
import 'package:kanade/ui/glass.dart';
import 'package:kanade/ui/song_tile.dart';
import 'package:kanade/ui/widgets.dart';
import 'package:window_manager/window_manager.dart';

import 'harness.dart';

/// 推荐页的三种刷新：顶部刷新键整页刷新、歌曲栏单独刷新、专属乐流换一批。需要已登录，只读。
/// 截图存到系统临时目录的 kanade_home_refresh 里。
/// flutter drive -d windows --driver=test_driver/integration_test.dart --target=integration_test/home_refresh_test.dart
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  testWidgets('推荐页刷新', (tester) async {
    final out = Directory('${Directory.systemTemp.path}/kanade_home_refresh');
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

    List<String> titles() => find
        .byType(SectionHeader, skipOffstage: false)
        .evaluate()
        .map((e) => (e.widget as SectionHeader).text)
        .toList();
    List<String> songs() => find
        .byType(SongTile, skipOffstage: false)
        .evaluate()
        .map((e) => e.widget as SongTile)
        .map((t) => t.songs[t.index].mid)
        .toList();

    await initTestApp();
    await windowManager.setSize(const Size(1280, 860));
    await tester.pumpWidget(KanadeGlass.wrap(child: const AppProviders(mediaSession: false, child: KanadeApp())));
    for (var i = 0; i < 20 && find.byType(SongTile, skipOffstage: false).evaluate().isEmpty; i++) {
      await settle(1000);
    }
    await settle(1500);
    await shoot('0_start');
    final before = (titles(), songs());
    debugPrint('start: ${before.$1}');
    expect(before.$2, isNotEmpty);

    // 第一个刷新键在「推荐 / 排行榜」那排，其余在栏目标题上
    final topRefresh = find.byType(RefreshIconButton).first;
    expect(
      find.ancestor(of: topRefresh, matching: find.byType(SectionHeader)),
      findsNothing,
      reason: 'the first refresh button should be the page-level one',
    );
    await tester.tap(topRefresh);
    await settle(300);
    await shoot('1_page_refreshing');
    await settle(4000);
    final afterPage = (titles(), songs());
    debugPrint('after page refresh: ${afterPage.$1}');
    await shoot('2_page_refreshed');
    expect(afterPage.$2, isNot(equals(before.$2)), reason: 'whole-page refresh should bring new songs');

    final sectionRefresh = find.descendant(of: find.byType(SectionHeader), matching: find.byType(RefreshIconButton));
    expect(sectionRefresh, findsWidgets, reason: 'the song section should have its own refresh button');
    final header = find.ancestor(of: sectionRefresh.first, matching: find.byType(SectionHeader));
    final oldTitle = (header.evaluate().first.widget as SectionHeader).text;
    await tester.tap(sectionRefresh.first);
    await settle(4000);
    final afterSection = (titles(), songs());
    debugPrint('section "$oldTitle" refreshed: ${afterSection.$1}');
    await shoot('3_section_refreshed');
    expect(afterSection.$2, isNot(equals(afterPage.$2)), reason: 'section refresh should bring new songs');

    // 专属乐流
    final scroll = tester.state<ScrollableState>(
      find.ancestor(of: find.byType(FeedColumn, skipOffstage: false), matching: find.byType(Scrollable)).first,
    );
    scroll.position.jumpTo(scroll.position.maxScrollExtent);
    await settle(3000);
    final columnHeader = find.textContaining('专属乐流', skipOffstage: false);
    await tester.runAsync(() => Scrollable.ensureVisible(tester.element(columnHeader)));
    await settle(1500);
    String firstCard() {
      final e = find.byWidgetPredicate((w) => w.runtimeType.toString() == '_Card').evaluate().first;
      final c = (e.widget as dynamic).card;
      return '${c.kind}:${c.title}:${c.songs.isEmpty ? c.playlist?.id : c.songs.first.mid}';
    }

    final cardBefore = firstCard();
    await shoot('4_column');
    final columnRefresh = find.descendant(
      of: find.ancestor(of: columnHeader, matching: find.byType(SectionHeader)),
      matching: find.byType(RefreshIconButton),
    );
    await tester.tap(columnRefresh);
    await settle(4000);
    final cardAfter = firstCard();
    debugPrint('column first card: $cardBefore -> $cardAfter');
    await shoot('5_column_refreshed');
    expect(cardAfter, isNot(equals(cardBefore)));
  });
}
