import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:kanade/src/rust/api/music.dart' as api;

import 'harness.dart';

/// 真实播放一首歌：经本机中转边播边存，拖动进度不中断，下完后能从缓存再播。
/// flutter drive -d windows --driver=test_driver/integration_test.dart --target=integration_test/audio_cache_test.dart
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  testWidgets('歌曲边播边存', (tester) async {
    final (player, _) = await launchWithSong(tester, setup: () async {
      api.setAudioCacheLimitMb(mb: 1024);
      await api.clearAudioCache();
    });
    final song = player.current!;
    final quality = player.actualQuality!;
    expect(player.error, isNull);
    expect(player.position.value, greaterThan(Duration.zero));

    // 拖到后面：还没下到的部分直接转发
    final target = player.duration * 0.7;
    await tester.runAsync(() async {
      await player.seek(target);
      await Future<void>.delayed(const Duration(seconds: 4));
    });
    expect(player.error, isNull);
    expect(player.position.value, greaterThan(target));

    // 等整首下完进索引（不能轮询 getCachedAudio，它会停掉正在进行的下载）
    await tester.runAsync(() async {
      for (var i = 0; i < 240 && await api.getAudioCacheSize() == 0; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 500));
      }
    });
    final size = await tester.runAsync(api.getAudioCacheSize);
    expect(size, greaterThan(0));
    // ignore: avoid_print
    print('cached ${song.name} ($quality): $size bytes');

    // 换一首再回来，应当直接用本地文件
    await tester.runAsync(() async {
      await player.next();
      await Future<void>.delayed(const Duration(seconds: 3));
    });
    expect(api.getCachedAudio(mid: song.mid, quality: quality), isNotNull);
    await tester.runAsync(() async {
      await player.playAt(0);
      await Future<void>.delayed(const Duration(seconds: 3));
    });
    expect(player.error, isNull);
    expect(player.actualQuality, quality);
    expect(player.position.value, greaterThan(Duration.zero));
  });
}
