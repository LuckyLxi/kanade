import 'dart:io';

import 'package:flutter/services.dart';

import '../src/rust/api/music.dart' as api;

/// 录这台设备正在播放的声音，每块是 16 位小端 PCM。
abstract interface class DeviceCapture {
  int get sampleRate;
  int get channels;

  /// Android 内录也要麦克风权限；Windows 不需要。
  bool get needsMicrophone;

  /// 用户拒绝授权时返回 null。取消订阅或 [stop] 后停止录音。
  Future<Stream<Uint8List>?> start();

  Future<void> stop();

  /// Android 10 以下没有系统内录，返回 null；其他平台也是 null。
  static Future<DeviceCapture?> create({
    required String Function() title,
  }) async {
    if (Platform.isWindows) return _WindowsCapture();
    if (!Platform.isAndroid) return null;
    final can = await _AndroidCapture._channel.invokeMethod<bool>(
      'canCaptureDevice',
    );
    return can == true ? _AndroidCapture(title) : null;
  }
}

class _WindowsCapture implements DeviceCapture {
  // 与 rust/src/device_audio.rs 的输出格式一致
  @override
  int get sampleRate => 44100;
  @override
  int get channels => 2;
  @override
  bool get needsMicrophone => false;

  @override
  Future<Stream<Uint8List>?> start() async => api.startDeviceCapture();

  @override
  Future<void> stop() async => api.stopDeviceCapture();
}

class _AndroidCapture implements DeviceCapture {
  _AndroidCapture(this._title);

  static const _channel = MethodChannel('kanade/recognize');
  static const _pcm = EventChannel('kanade/recognize/pcm');
  final String Function() _title;

  // 与 RecognizeService.SAMPLE_RATE 一致
  @override
  int get sampleRate => 16000;
  @override
  int get channels => 1;
  @override
  bool get needsMicrophone => true;

  @override
  Future<Stream<Uint8List>?> start() async {
    final granted = await _channel.invokeMethod<bool>('requestCapture', {
      'title': _title(),
    });
    return granted == true ? _pcm.receiveBroadcastStream().cast() : null;
  }

  // 原生侧在取消订阅时停止
  @override
  Future<void> stop() async {}
}
