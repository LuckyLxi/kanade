import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanade/app.dart';
import 'package:kanade/player/player_controller.dart';
import 'package:kanade/src/rust/api/music.dart' as api;
import 'package:kanade/ui/glass.dart';
import 'package:kanade/ui/home_shell.dart';
import 'package:provider/provider.dart';

/// 启动完整应用，静音播放榜单第一首，等歌词和封面素材就绪。
/// 返回播放器和根导航，用来打开播放页做测量。
/// [setup] 在 Rust 层初始化后、开始播放前执行；[onPlay] 在刚开始播放（第一首歌刚出现）时执行。
/// [songKeyword] 指定复现歌曲时，只播放搜索结果的第一首，避免失败后跳到其他歌。
Future<(PlayerController, NavigatorState)> launchWithSong(
  WidgetTester tester, {
  Future<void> Function()? setup,
  Future<void> Function()? onPlay,
  bool mediaSession = false,
  String? songKeyword,
}) async {
  await initApp();
  await setup?.call();

  // 测试里默认不接系统媒体卡片
  await tester.pumpWidget(KanadeGlass.wrap(child: AppProviders(mediaSession: mediaSession, child: const KanadeApp())));
  final player = tester.element(find.byType(HomeShell)).read<PlayerController>();

  final songs = await tester.runAsync(() async {
    if (songKeyword != null) {
      final result = await api.searchSongs(keyword: songKeyword, page: 1, pageSize: 20);
      expect(result.songs, isNotEmpty, reason: 'the requested reproduction track must exist');
      return [result.songs.first];
    }
    final groups = await api.getToplists();
    final top = groups.first.lists.first;
    return (await api.getToplistDetail(topId: top.topId, period: top.period)).songs;
  });
  await tester.runAsync(() async {
    await player.setVolume(0);
    final playing = player.playList(songs!, 0);
    await onPlay?.call();
    await playing;
    for (var i = 0; i < 50 && player.lyric == null; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    await Future<void>.delayed(const Duration(seconds: 3));
  });

  final nav = Navigator.of(tester.element(find.byType(HomeShell)), rootNavigator: true);
  return (player, nav);
}
