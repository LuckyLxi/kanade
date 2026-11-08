import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:path_provider/path_provider.dart';

import 'app.dart';
import 'player/android_playback_service.dart';
import 'ui/glass.dart';

@pragma('vm:entry-point')
Future<void> androidPlaybackMain() => runAndroidPlayback();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (Platform.isAndroid) {
    final cache = PaintingBinding.instance.imageCache;
    final foregroundLimit = cache.maximumSizeBytes;
    // 后台按 LRU 回收解码后的图片，仍在页面上使用的图片由页面持有。
    AppLifecycleListener(
      onPause: () => cache.maximumSizeBytes = 24 << 20,
      onResume: () => cache.maximumSizeBytes = foregroundLimit,
    );
  }
  final separateAndroidPlayback =
      Platform.isAndroid &&
      const bool.fromEnvironment(
        'KANADE_SEPARATE_ANDROID_PLAYBACK',
        defaultValue: true,
      );
  final androidPlaybackDirectory = separateAndroidPlayback
      ? (await getApplicationSupportDirectory()).path
      : null;
  await initApp(
    dataDir: androidPlaybackDirectory,
    separateAndroidPlayback: separateAndroidPlayback,
  );
  runApp(
    // Windows 引擎同步无障碍信息时会崩（flutter_windows.dll 里的
    // AccessibilityBridge::CreateRemoveReparentedNodesUpdate，开关播放页最容易触发），
    // 只针对播放栏的滑条和转场副本处理挡不住，只好在 Windows 上整个不提供无障碍信息。
    // 升级 Flutter 后可以去掉这层，再反复开关播放页看还崩不崩。
    ExcludeSemantics(
      excluding: Platform.isWindows,
      child: KanadeGlass.wrap(
        child: AppProviders(
          androidPlaybackDirectory: androidPlaybackDirectory,
          child: const KanadeApp(),
        ),
      ),
    ),
  );
}
