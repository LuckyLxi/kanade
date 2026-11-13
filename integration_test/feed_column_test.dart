import 'dart:io';
import 'dart:ui' as ui;

import 'package:material_ui/material_ui.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:kanade/app.dart';
import 'package:kanade/player/player_controller.dart';
import 'package:kanade/ui/feed_column.dart';
import 'package:kanade/ui/glass.dart';
import 'package:kanade/ui/home_shell.dart';
import 'package:provider/provider.dart';
import 'package:window_manager/window_manager.dart';

import 'harness.dart';

/// 推荐页底部的专属乐流：出现、滑到底翻页、点单曲卡从这首开始刷歌（静音）。需要已登录。
/// 点卡片会真的开始播放，账号的云端最近播放里会多一条。
/// 截图存到系统临时目录的 kanade_feed_frames 里。
/// flutter drive -d windows --driver=test_driver/integration_test.dart --target=integration_test/feed_column_test.dart
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  testWidgets('专属乐流', (tester) async {
    final out = Directory('${Directory.systemTemp.path}/kanade_feed_frames');
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
    final cards = find.byWidgetPredicate((w) => w.runtimeType.toString() == '_Card');

    await initTestApp();
    await windowManager.setSize(const Size(430, 900));
    await tester.pumpWidget(KanadeGlass.wrap(child: const AppProviders(mediaSession: false, child: KanadeApp())));
    for (var i = 0; i < 20 && find.byType(FeedColumn, skipOffstage: false).evaluate().isEmpty; i++) {
      await settle(1000);
    }
    await shoot('00_start');
    final player = tester.element(find.byType(HomeShell)).read<PlayerController>();
    await tester.runAsync(() => player.setVolume(0));

    final scroll = tester.state<ScrollableState>(
      find.ancestor(of: find.byType(FeedColumn, skipOffstage: false), matching: find.byType(Scrollable)).first,
    );
    Future<void> toBottom() async {
      scroll.position.jumpTo(scroll.position.maxScrollExtent);
      await settle(2500);
    }

    // 瀑布流只构建屏幕附近的卡片，按卡片内容累计见过多少张
    final seen = <String>{};
    void collect() {
      for (final e in cards.evaluate()) {
        final c = (e.widget as dynamic).card;
        seen.add('${c.kind}:${c.title}:${c.songs.isEmpty ? c.playlist?.id : c.songs.first.mid}');
      }
    }

    await toBottom();
    collect();
    expect(seen, isNotEmpty, reason: 'the column should load its first page for a logged-in user');
    final header = find.textContaining('专属乐流', skipOffstage: false);
    expect(header, findsOneWidget);
    await tester.runAsync(() => Scrollable.ensureVisible(tester.element(header)));
    await settle(1500);
    collect();
    await shoot('0_phone_header');

    final first = seen.length;
    for (var i = 0; i < 4; i++) {
      await toBottom();
      collect();
    }
    debugPrint('feed column cards seen: first=$first after scrolling=${seen.length}');
    expect(seen.length, greaterThan(first + 8), reason: 'scrolling to the end should load more pages');
    await shoot('1_phone_more');

    // 点第一张单曲卡：应从这首开始刷歌
    await tester.runAsync(() => Scrollable.ensureVisible(tester.element(header)));
    await settle(800);
    final songCard = cards.evaluate().map((e) => e.widget as dynamic).firstWhere((w) => w.card.kind.toString().endsWith('song'));
    final song = songCard.card.songs.first;
    await tester.tap(find.byWidget(songCard as Widget));
    await settle(4000);
    debugPrint('tapped ${song.name} (${song.mid}), now playing ${player.current?.name} (${player.current?.mid}), queue ${player.queue.length}');
    expect(player.current?.mid, song.mid);
    await shoot('2_phone_after_tap');
    await tester.runAsync(() => player.pause());

    await windowManager.setSize(const Size(1280, 860));
    await settle(1500);
    await tester.runAsync(() => Scrollable.ensureVisible(tester.element(header)));
    await settle(1500);
    await shoot('3_desktop_header');
  });
}
