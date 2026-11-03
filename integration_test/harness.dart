import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanade/app.dart';
import 'package:path_provider/path_provider.dart';
import 'package:kanade/player/player_controller.dart';
import 'package:kanade/src/rust/api/music.dart' as api;
import 'package:kanade/src/rust/api/types.dart';
import 'package:kanade/ui/glass.dart';
import 'package:kanade/ui/home_shell.dart';
import 'package:provider/provider.dart';

/// 集成测试用的初始化：把 App 的数据库复制到临时目录再启动，登录态和设置照旧，
/// 但测试的读写和被 flutter drive 直接杀掉都只落在副本上。
/// 和真实 App 共用 kanade.db 时，接口缓存表已经坏过好几次。
Future<void> initTestApp() async {
  final live = await getApplicationSupportDirectory();
  final copy = Directory('${Directory.systemTemp.path}/kanade_test_data');
  if (copy.existsSync()) copy.deleteSync(recursive: true);
  copy.createSync();
  // -shm 是共享内存索引，打开时会按 -wal 重建，不用复制
  for (final name in ['kanade.db', 'kanade.db-wal']) {
    final f = File('${live.path}/$name');
    if (f.existsSync()) f.copySync('${copy.path}/$name');
  }
  await initApp(dataDir: copy.path);
}

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
  await initTestApp();
  await setup?.call();

  // 测试里默认不接系统媒体卡片
  // 与 main 保持一致，避免 Windows 无障碍桥接错误干扰转场测量。
  await tester.pumpWidget(
    ExcludeSemantics(
      excluding: Platform.isWindows,
      child: KanadeGlass.wrap(
        child: AppProviders(mediaSession: mediaSession, child: const KanadeApp()),
      ),
    ),
  );
  final player = tester.element(find.byType(HomeShell)).read<PlayerController>();

  final songs = await tester.runAsync(() async {
    if (songKeyword != null) {
      final result = await api.search(keyword: songKeyword, kind: SearchKind.song, page: 1, pageSize: 20);
      expect(result.songs, isNotEmpty, reason: 'the requested reproduction track must exist');
      return [result.songs.first];
    }
    final groups = await api.getToplists();
    final top = groups.first.lists.first;
    return (await api.getToplistDetail(topId: top.topId, period: top.period)).songs;
  });
  // 测试里静音。改的是数据库副本，不会把用户的音量留成 0
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
