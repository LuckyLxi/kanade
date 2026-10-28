import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanade/auth/auth_controller.dart';
import 'package:kanade/library/library_controller.dart';
import 'package:kanade/main.dart';
import 'package:kanade/player/player_controller.dart';
import 'package:kanade/settings/locale_controller.dart';
import 'package:kanade/src/rust/api/music.dart' as api;
import 'package:kanade/src/rust/frb_generated.dart';
import 'package:kanade/ui/home_shell.dart';
import 'package:kanade/ui/title_bar.dart';
import 'package:media_kit/media_kit.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';

/// 启动完整应用，静音播放榜单第一首，等歌词和封面素材就绪。
/// 返回播放器和根导航，用来打开播放页做测量。
Future<(PlayerController, NavigatorState)> launchWithSong(WidgetTester tester) async {
  MediaKit.ensureInitialized();
  await setupWindow();
  await RustLib.init();
  final dir = await getApplicationSupportDirectory();
  await api.initCore(dataDir: dir.path);

  late PlayerController player;
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => LocaleController()),
        ChangeNotifierProvider(create: (_) => AuthController()),
        ChangeNotifierProvider(create: (context) => player = PlayerController(context.read<AuthController>())),
        ChangeNotifierProvider(create: (context) => LibraryController(context.read<AuthController>()), lazy: false),
      ],
      child: const KanadeApp(),
    ),
  );

  final songs = await tester.runAsync(() async {
    final groups = await api.getToplists();
    final top = groups.first.lists.first;
    return (await api.getToplistDetail(topId: top.topId, period: top.period)).songs;
  });
  await tester.runAsync(() async {
    await player.setVolume(0);
    await player.playList(songs!, 0);
    for (var i = 0; i < 50 && player.lyric == null; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    await Future<void>.delayed(const Duration(seconds: 3));
  });

  final nav = Navigator.of(tester.element(find.byType(HomeShell)), rootNavigator: true);
  return (player, nav);
}
