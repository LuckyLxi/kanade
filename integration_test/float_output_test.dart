// 看 32 位浮点输出开关实际交给系统的格式，用的 mpv 命令和 _LocalPlayerController 一样。
// Windows 共享模式本来就是 float，只能在手机上跑：
// flutter test integration_test/float_output_test.dart -d cde2d04 --no-uninstall
// 有 android/key.properties 时覆盖安装、保留数据；不加 --no-uninstall 跑完会把 App 卸掉。
// 跑完手机上是测试包，要再装回正式版。
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:kanade/auth/auth_controller.dart';
import 'package:kanade/player/player_controller.dart';
import 'package:kanade/src/rust/api/music.dart' as api;
import 'package:kanade/src/rust/api/types.dart';
import 'package:media_kit/media_kit.dart';

import 'harness.dart';

const _on = ['af', 'add', '@kanadefloat:format=format=float'];
const _off = ['af', 'remove', '@kanadefloat'];

File _sineWav(Directory dir) {
  const rate = 44100, seconds = 20, channels = 2;
  final samples = rate * seconds;
  final data = ByteData(44 + samples * channels * 2);
  void str(int o, String s) {
    for (var i = 0; i < s.length; i++) {
      data.setUint8(o + i, s.codeUnitAt(i));
    }
  }

  str(0, 'RIFF');
  data.setUint32(4, data.lengthInBytes - 8, Endian.little);
  str(8, 'WAVE');
  str(12, 'fmt ');
  data.setUint32(16, 16, Endian.little);
  data.setUint16(20, 1, Endian.little);
  data.setUint16(22, channels, Endian.little);
  data.setUint32(24, rate, Endian.little);
  data.setUint32(28, rate * channels * 2, Endian.little);
  data.setUint16(32, channels * 2, Endian.little);
  data.setUint16(34, 16, Endian.little);
  str(36, 'data');
  data.setUint32(40, samples * channels * 2, Endian.little);
  for (var i = 0; i < samples; i++) {
    final v = (sin(2 * pi * 440 * i / rate) * 3000).round();
    for (var c = 0; c < channels; c++) {
      data.setInt16(44 + (i * channels + c) * 2, v, Endian.little);
    }
  }
  return File('${dir.path}/sine.wav')
    ..writeAsBytesSync(data.buffer.asUint8List());
}

Future<Player> _player() async {
  final player = Player();
  addTearDown(player.dispose);
  await player.setVolume(0);
  return player;
}

Future<String> _format(NativePlayer native) =>
    native.getProperty('audio-out-params/format');

Future<void> _settle() => Future<void>.delayed(const Duration(seconds: 1));

/// 等到真的在出声（换歌时还要等换成别的歌），再多放一会儿让输出格式定下来。
Future<void> _playing(PlayerController player, {Song? after}) async {
  for (var i = 0; i < 100; i++) {
    if (player.playing &&
        player.position.value > Duration.zero &&
        player.current != after) {
      await _settle();
      return;
    }
    await Future<void>.delayed(const Duration(milliseconds: 200));
  }
  fail('没放起来：${player.current?.name} error=${player.error}');
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();

  late File wav;
  setUp(() {
    final dir = Directory.systemTemp.createTempSync('kanade_float');
    addTearDown(() => dir.deleteSync(recursive: true));
    wav = _sineWav(dir);
  });

  test('播放中开关后 ao-reload 当场换格式，且不打断播放', () async {
    final player = await _player();
    final native = player.platform as NativePlayer;
    await player.open(Media(wav.path));
    await _settle();
    expect(await _format(native), isNot(startsWith('float')));

    await native.command(_on);
    await native.command(['ao-reload']);
    await _settle();
    expect(await _format(native), startsWith('float'));
    final before = player.state.position;
    await _settle();
    expect(player.state.playing, isTrue);
    expect(player.state.position, greaterThan(before));

    await native.command(_off);
    await native.command(['ao-reload']);
    await _settle();
    expect(await _format(native), isNot(startsWith('float')));
  });

  test('播放中先只加滤镜，换歌前再 ao-reload，新歌用浮点', () async {
    final player = await _player();
    final native = player.platform as NativePlayer;
    await player.open(Media(wav.path));
    await _settle();
    await native.command(_on);
    await _settle();
    expect(await _format(native), isNot(startsWith('float')));
    await native.command(['ao-reload']);
    await player.open(Media(wav.path));
    await _settle();
    expect(await _format(native), startsWith('float'));
  });

  // 要登录且能拿到无损：有损格式解码出来本来就是浮点，看不出开关的作用。
  test('播放器里开关、换歌、重启，无损歌的输出格式跟着开关走', () async {
    await initTestApp();
    final auth = AuthController(watchSession: false);
    expect(auth.loggedIn, isTrue, reason: '先在手机上登录');
    final groups = await api.getToplists();
    final top = groups.first.lists.first;
    final songs = (await api.getToplistDetail(
      topId: top.topId,
      period: top.period,
    )).songs;

    final live = <PlayerController>[];
    addTearDown(() {
      for (final p in live) {
        p.dispose();
      }
    });
    Future<(PlayerController, NativePlayer)> launch() async {
      final engine = Player();
      final player = PlayerController(auth, player: engine);
      live.add(player);
      player.setDefaultQuality(Quality.lossless);
      await player.setVolume(0);
      await player.playList(songs, 0);
      await _playing(player);
      return (player, engine.platform as NativePlayer);
    }

    Future<bool> filtered(NativePlayer native) async =>
        (await native.getProperty('af')).contains('kanadefloat');
    Future<void> check(
      String step,
      PlayerController player,
      NativePlayer native, {
      required bool float,
    }) async {
      final format = await _format(native);
      // ignore: avoid_print
      print(
        '$step: ${player.current?.name} ${player.actualQuality} '
        'decoded=${await native.getProperty('audio-params/format')} out=$format',
      );
      expect(player.actualQuality, Quality.lossless);
      expect(format, float ? startsWith('float') : isNot(startsWith('float')));
      final before = player.position.value;
      await _settle();
      expect(player.playing, isTrue);
      expect(player.position.value, greaterThan(before));
    }

    var (player, native) = await launch();
    player.setFloatOutput(false);
    await _settle();
    expect(await filtered(native), isFalse);
    await check('关', player, native, float: false);

    // 正在放时打开：滤镜当场加上，但先不重建，这首照旧
    player.setFloatOutput(true);
    await _settle();
    expect(await filtered(native), isTrue);
    await check('放着打开', player, native, float: false);

    // 换歌时补上重建，新歌用浮点
    final first = player.current;
    await player.next();
    await _playing(player, after: first);
    await check('换歌后', player, native, float: true);

    // 暂停时关掉、再打开：当场重建
    for (final on in [false, true]) {
      await player.pause();
      player.setFloatOutput(on);
      await _settle();
      expect(await filtered(native), on);
      await player.play();
      await _settle();
      await check(on ? '暂停时打开' : '暂停时关掉', player, native, float: on);
    }

    // 开关开着重启：第一首就是浮点
    live.remove(player);
    player.dispose();
    (player, native) = await launch();
    expect(player.floatOutput, isTrue);
    await check('重启后', player, native, float: true);
  });

  test('启动时开关已打开：先加滤镜再开第一首，空闲时 ao-reload 不出错', () async {
    final player = await _player();
    final native = player.platform as NativePlayer;
    await native.command(_on);
    await native.command(['ao-reload']);
    await player.open(Media(wav.path));
    await _settle();
    expect(await _format(native), startsWith('float'));
    expect(player.state.playing, isTrue);
  });
}
