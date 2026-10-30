import 'package:flutter/scheduler.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:kanade/ui/desktop_shell.dart';
import 'package:kanade/ui/player_route.dart';

import 'harness.dart';

/// 反复开关播放页，每次关掉后检查还在不在出帧。加 --dart-define=MEDIA=true 时接上系统媒体卡片。
/// flutter drive --profile -d windows --driver=test_driver/integration_test.dart --target=integration_test/player_freeze_test.dart
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  testWidgets('开关播放页不卡死', (tester) async {
    const media = bool.fromEnvironment('MEDIA');
    final (_, nav) = await launchWithSong(tester, mediaSession: media);
    Future<void> wait(int ms) => tester.runAsync(() => Future<void>.delayed(Duration(milliseconds: ms)));
    // ignore: avoid_print
    void log(String s) => print('[freeze] $s');

    var frames = 0;
    SchedulerBinding.instance.addPersistentFrameCallback((_) => frames++);
    for (var i = 0; i < 4; i++) {
      nav.push(PlayerRoute(anchor: DesktopPlayerBar.anchor));
      await wait(1500);
      nav.pop();
      final before = frames;
      await wait(2000);
      log('round $i: frames during 2s after close = ${frames - before}');
      expect(frames - before, greaterThan(30));
    }
  });
}
