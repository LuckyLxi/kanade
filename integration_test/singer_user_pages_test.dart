import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:kanade/app.dart';
import 'package:kanade/l10n/l10n_ext.dart';
import 'package:kanade/src/rust/api/music.dart' as api;
import 'package:kanade/ui/song_tile.dart';
import 'package:kanade/ui/singer_page.dart';
import 'package:kanade/ui/mine_page.dart';
import 'package:kanade/ui/follow_button.dart';
import 'package:kanade/ui/theme.dart';
import 'package:kanade/ui/user_page.dart';
import 'package:kanade/ui/video_tile.dart';
import 'package:kanade/ui/widgets.dart';
import 'package:window_manager/window_manager.dart';

import 'harness.dart';

/// 只浏览页面，不点击关注、创建或播放按钮。HAR 只用于定位原有公开主页样本。
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  testWidgets('singer and user pages load without writes', (tester) async {
    final out = Directory('build/singer_user_frames')..createSync(recursive: true);
    Future<void> wait([int ms = 1800]) => tester.runAsync(() => Future<void>.delayed(Duration(milliseconds: ms)));
    Future<void> screenshot(String name) => tester.runAsync(() async {
      // ignore: invalid_use_of_protected_member
      final layer = tester.binding.renderViews.first.layer! as OffsetLayer;
      final image = await layer.toImage(Offset.zero & tester.view.physicalSize, pixelRatio: 1);
      final png = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      File('${out.path}/$name.png').writeAsBytesSync(png!.buffer.asUint8List());
    });

    await initTestApp();
    await windowManager.setSize(const Size(430, 900));
    await tester.pumpWidget(
      AppProviders(
        mediaSession: false,
        child: MaterialApp(
          locale: const Locale('zh'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          theme: buildTheme(Brightness.light),
          home: const SingerPage(mid: '002wbPaC0L9C3A', name: '鸣潮先约电台'),
        ),
      ),
    );
    await wait(3500);
    await screenshot('featured');
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -500));
    await wait(600);
    expect(find.text('精选专辑'), findsOneWidget);
    await screenshot('featured_collapsed');
    await tester.tap(find.widgetWithText(Pill, '详情'));
    await wait(600);
    expect(find.text('简介'), findsOneWidget);
    expect(find.text('守护'), findsOneWidget);
    await screenshot('singer_about');
    await tester.tap(find.widgetWithText(Pill, '视频'));
    await wait();
    expect(find.byType(VideoTile), findsWidgets);
    final latest = tester.widgetList<VideoTile>(find.byType(VideoTile)).take(3).map((v) => v.video.vid).toList();
    await tester.tap(find.widgetWithText(Pill, '最热'));
    await wait();
    expect(find.byType(VideoTile), findsWidgets);
    expect(tester.widget<Pill>(find.widgetWithText(Pill, '最热')).selected, isTrue);
    final hot = tester.widgetList<VideoTile>(find.byType(VideoTile)).take(3).map((v) => v.video.vid).toList();
    expect(hot, isNot(orderedEquals(latest)));
    await screenshot('singer_hot_videos');
    await tester.tap(find.widgetWithText(Pill, '动画版'));
    await wait();
    expect(find.byType(VideoTile), findsOneWidget);
    expect(tester.widget<Pill>(find.widgetWithText(Pill, '最热')).selected, isTrue);
    await tester.tap(find.widgetWithText(Pill, '最新'));
    await wait();
    expect(tester.widget<Pill>(find.widgetWithText(Pill, '最新')).selected, isTrue);
    await screenshot('singer_videos');
    expect(tester.takeException(), isNull);

    final harPath = Platform.environment['QQMUSIC_TEST_HAR'];
    expect(harPath, isNotNull, reason: 'Set QQMUSIC_TEST_HAR to the local profile capture');
    final har = jsonDecode(File(harPath!).readAsStringSync().replaceFirst('\uFEFF', '')) as Map<String, dynamic>;
    Map<String, dynamic>? profile;
    for (final entry in har['log']['entries'] as List<dynamic>) {
      if (!(entry['request']['url'] as String).contains('fcg_get_profile_homepage')) continue;
      final response = jsonDecode(entry['response']['content']['text'] as String) as Map<String, dynamic>;
      if ((response['data']['mydiss']['num'] as int) > 0) {
        profile = response['data'] as Map<String, dynamic>;
        break;
      }
    }
    expect(profile, isNotNull);
    final creator = profile!['creator'] as Map<String, dynamic>;
    Navigator.of(tester.element(find.byType(SingerPage)))
        .pushReplacement(UserPage.route(creator['encrypt_uin'] as String, creator['nick'] as String));
    await wait(3000);
    expect(find.byType(UserPage), findsOneWidget);
    expect(find.byType(ListTile), findsWidgets);
    await screenshot('user_head');
    await tester.tap(find.widgetWithText(Pill, '我喜欢'));
    await wait();
    expect(find.byType(SongTile), findsWidgets);
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -600));
    await wait(600);
    await screenshot('liked_songs_scrolled');
    await tester.tap(find.widgetWithText(Pill, '专辑'));
    await wait();
    await screenshot('liked_albums_pinned');
    await screenshot('liked_songs');
    await tester.tap(find.widgetWithText(Pill, '歌单'));
    await wait();
    expect(find.byType(ListTile), findsWidgets);
    await screenshot('saved_playlists');
    await tester.tap(find.widgetWithText(Pill, '专辑'));
    await wait();
    expect(find.byType(AlbumTile), findsWidgets);
    await screenshot('saved_albums');
    expect(tester.takeException(), isNull);

    await tester.tap(find.widgetWithText(Pill, '视频'));
    await wait();
    expect(find.text('暂无内容'), findsOneWidget);
    final targetsPath = Platform.environment['QQMUSIC_TEST_ASSET_TARGETS'];
    expect(targetsPath, isNotNull);
    final targets = jsonDecode(File(targetsPath!).readAsStringSync()) as Map<String, dynamic>;
    final videoUser = await tester.runAsync(() => api.getUserProfile(euin: targets['video_user'] as String));
    Navigator.of(tester.element(find.byType(UserPage)))
        .pushReplacement(UserPage.route(videoUser!.euin, videoUser.name));
    await wait();
    await tester.tap(find.widgetWithText(Pill, '我喜欢'));
    await tester.pump();
    await tester.tap(find.widgetWithText(Pill, '视频'));
    await wait();
    expect(find.byType(VideoTile), findsWidgets);
    await screenshot('liked_videos');
    expect(tester.takeException(), isNull);

    // 简介位置显示认证说明
    Navigator.of(tester.element(find.byType(UserPage)))
        .pushReplacement(UserPage.route('ownk7e-l7e4kNn**', '鸣潮先约电台'));
    await wait();
    expect(find.textContaining('官方认证'), findsOneWidget);
    await screenshot('user_intro');

    Navigator.of(tester.element(find.byType(UserPage)))
        .pushReplacement(MaterialPageRoute<void>(builder: (_) => const MinePage()));
    await wait();
    await tester.tap(find.byTooltip('新建歌单'));
    await wait(400);
    expect(find.byType(AlertDialog), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'cancelled-without-submitting');
    await tester.tap(find.text('取消'));
    await wait(500);
    expect(find.byType(AlertDialog), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.tap(find.byType(CircleAvatar).first);
    await wait();
    expect(find.byType(UserPage), findsOneWidget);
    expect(find.byType(FollowButton), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
