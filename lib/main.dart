import 'dart:io';

import 'package:flutter/widgets.dart';

import 'app.dart';
import 'ui/glass.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initApp();
  runApp(
    // Windows 引擎同步无障碍信息时会崩（flutter_windows.dll 里的
    // AccessibilityBridge::CreateRemoveReparentedNodesUpdate，开关播放页最容易触发），
    // 只针对播放栏的滑条和转场副本处理挡不住，只好在 Windows 上整个不提供无障碍信息。
    // 升级 Flutter 后可以去掉这层，再反复开关播放页看还崩不崩。
    ExcludeSemantics(
      excluding: Platform.isWindows,
      child: KanadeGlass.wrap(child: const AppProviders(child: KanadeApp())),
    ),
  );
}
