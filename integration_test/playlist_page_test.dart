import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:kanade/app.dart';
import 'package:kanade/l10n/l10n_ext.dart';
import 'package:kanade/src/rust/api/music.dart' as api;
import 'package:kanade/src/rust/api/types.dart';
import 'package:kanade/ui/song_list_page.dart';
import 'package:kanade/ui/theme.dart';
import 'package:kanade/ui/widgets.dart';
import 'package:window_manager/window_manager.dart';

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

    await initApp();
    await windowManager.setSize(const Size(430, 900));
    final found = (await tester.runAsync(
      () => api.search(keyword: '周杰伦', kind: SearchKind.playlist, page: 1, pageSize: 10),
    ))!;
    final p = found.playlists.firstWhere((p) => p.songCount >= 20);
    final nav = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      AppProviders(
        mediaSession: false,
        child: MaterialApp(
          navigatorKey: nav,
          locale: const Locale('zh'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          theme: buildTheme(Brightness.dark),
          home: const Scaffold(),
        ),
      ),
    );
    nav.currentState!.push(SongListPage.playlist(p.id, p.title));
    await wait(4000);
    expect(find.byType(SongTile), findsWidgets);
    expect(find.byTooltip('随机播放'), findsOneWidget);
    await screenshot('hero');

    await tester.drag(find.byType(CustomScrollView), const Offset(0, -500));
    await wait(600);
    await screenshot('collapsed');

    await tester.drag(find.byType(CustomScrollView), const Offset(0, 800));
    await wait(600);
    await tester.tap(find.byTooltip('搜索歌名、歌手'));
    await wait(600);
    expect(find.byType(TextField), findsOneWidget);
    await tester.enterText(find.byType(TextField), '周杰伦');
    await wait(600);
    expect(find.textContaining('找到'), findsOneWidget);
    await screenshot('search');

    await tester.tap(find.text('取消'));
    await wait(600);
    expect(find.byType(TextField), findsNothing);
    expect(find.byTooltip('随机播放'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
