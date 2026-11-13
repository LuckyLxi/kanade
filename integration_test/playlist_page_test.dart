import 'dart:io';
import 'dart:ui' as ui;

import 'package:material_ui/material_ui.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:kanade/app.dart';
import 'package:kanade/l10n/l10n_ext.dart';
import 'package:kanade/src/rust/api/music.dart' as api;
import 'package:kanade/src/rust/api/types.dart';
import 'package:kanade/ui/song_tile.dart';
import 'package:kanade/ui/discover_page.dart';
import 'package:kanade/ui/home_shell.dart';
import 'package:kanade/ui/song_list_page.dart';
import 'package:kanade/ui/theme.dart';
import 'package:window_manager/window_manager.dart';

import 'harness.dart';

/// 只浏览：打开一个公开歌单，收起头部，再用顶栏搜索筛歌。不播放、不收藏。
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  testWidgets('playlist page hero, collapse and in-list search', (tester) async {
    final out = Directory('build/playlist_frames')..createSync(recursive: true);
    Future<void> wait([int ms = 1800]) => tester.runAsync(() => Future<void>.delayed(Duration(milliseconds: ms)));
    Future<void> screenshot(String name) => tester.runAsync(() async {
      // ignore: invalid_use_of_protected_member
      final layer = tester.binding.renderViews.first.layer! as OffsetLayer;
      final image = await layer.toImage(Offset.zero & tester.view.physicalSize, pixelRatio: 1);
      final png = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      File('${out.path}/$name.png').writeAsBytesSync(png!.buffer.asUint8List());
    });
    // 系统返回键：和安卓一样从根 Navigator 开始，经过外壳的 PopScope
    Future<void> systemBack() async {
      await tester.runAsync(() => binding.handlePopRoute());
      await wait(700);
    }

    await initTestApp();
    await windowManager.setSize(const Size(430, 900));
    final found = (await tester.runAsync(
      () => api.search(keyword: '周杰伦', kind: SearchKind.playlist, page: 1, pageSize: 10),
    ))!;
    final p = found.playlists.firstWhere((p) => p.songCount >= 20);
    await tester.pumpWidget(
      AppProviders(
        mediaSession: false,
        child: MaterialApp(
          locale: const Locale('zh'),
          localizationsDelegates: localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          theme: buildTheme(Brightness.dark),
          home: const HomeShell(),
        ),
      ),
    );
    await wait(3000);
    Navigator.of(tester.element(find.byType(DiscoverPage))).push(SongListPage.playlist(p.id, p.title));
    await wait(4000);
    expect(find.byType(SongTile), findsWidgets);
    expect(find.byTooltip('随机播放'), findsOneWidget);
    await screenshot('hero');

    await tester.drag(find.byType(CustomScrollView).last, const Offset(0, -500));
    await wait(600);
    await screenshot('collapsed');

    // 从半收起的位置点搜索，看头部和按钮行怎么收
    await tester.drag(find.byType(CustomScrollView).last, const Offset(0, 420));
    await wait(600);
    await tester.tap(find.byTooltip('搜索歌名、歌手'));
    for (final ms in [60, 120, 180]) {
      await wait(ms - (ms == 60 ? 0 : 60));
      await screenshot('search_in_$ms');
    }
    await wait(500);
    expect(find.byType(TextField), findsOneWidget);
    await tester.enterText(find.byType(TextField), '周杰伦');
    await wait(600);
    expect(find.textContaining('找到'), findsOneWidget);
    await screenshot('search');

    // 系统返回先退出搜索，页面还在
    await systemBack();
    expect(find.byType(TextField), findsNothing);
    expect(find.byType(SongListPage), findsOneWidget);
    expect(find.byTooltip('随机播放'), findsOneWidget);
    await screenshot('search_closed');

    // 再按一次才离开歌单页
    await systemBack();
    expect(find.byType(SongListPage), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
