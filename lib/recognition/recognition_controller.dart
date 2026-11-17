import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:record/record.dart';

import '../data/recognition_pcm.dart';
import '../player/player_controller.dart';
import '../src/rust/api/music.dart' as api;
import '../src/rust/api/types.dart';
import 'device_capture.dart';

enum RecognitionPhase { listening, paused, found, notFound, failed }

enum RecognitionSource { microphone, device }

/// silent：录设备内声音 15 秒全是静音，可能没在放，或者该应用禁止被录。
enum RecognitionFailure { noMicrophone, silent }

/// 一次识曲会话；不依赖页面、文案或 Android 悬浮窗。
class RecognitionController extends ChangeNotifier {
  RecognitionController(this._player, {AudioRecorder? recorder})
    : _recorder = recorder ?? AudioRecorder();

  static const _uploadAt = {1, 2, 3, 6, 9, 12, 15};
  static const _maxSeconds = 15;
  final PlayerController _player;
  final AudioRecorder _recorder;
  final _buffer = BytesBuilder(copy: false);
  StreamSubscription<Uint8List>? _sub;
  Timer? _ticker;
  var _sampleRate = recognitionSampleRate;
  var _channels = 1;
  var _generation = 0;
  var _session = 0;
  var _uploading = false;
  var _paused = false;
  String? _pausedSong;
  bool _disposed = false;
  // 录音设备的启动、停止串行执行，旧 startStream 结束后不会停掉新会话。
  Future<void> _recordingWork = Future.value();
  Future<void>? _finishing;

  /// 为 null 时这台设备不能录内部声音。
  DeviceCapture? device;
  RecognitionSource source = RecognitionSource.microphone;

  /// 用户拒绝了内录授权，已经退回麦克风。
  bool captureDenied = false;

  RecognitionPhase phase = RecognitionPhase.listening;
  Song? song;
  Object? error;
  int seconds = 0;
  bool micGranted = false;
  bool finished = false;

  bool _stale(int generation) => finished || generation != _generation;

  /// 换录音来源，正在听时立刻用新来源重新开始。
  void setSource(RecognitionSource value) {
    if (finished || value == source) return;
    source = value;
    captureDenied = false;
    unawaited(start());
  }

  /// 暂停只停录音，Kanade 的歌仍等关掉弹窗再恢复；继续就是 [start]，从头开始听。
  void pause() {
    if (finished || phase != RecognitionPhase.listening) return;
    ++_generation;
    _stopCapture();
    phase = RecognitionPhase.paused;
    notifyListeners();
  }

  Future<void> start() {
    if (finished) return Future.value();
    final generation = ++_generation;
    _cancelCapture();
    phase = RecognitionPhase.listening;
    song = null;
    error = null;
    seconds = 0;
    _uploading = false;
    _buffer.clear();
    // 同一毫秒内重试也必须使用不同的服务端会话。
    final now = DateTime.now().millisecondsSinceEpoch;
    _session = now > _session ? now : _session + 1;
    notifyListeners();
    return _recordingWork = _recordingWork.then((_) => _start(generation));
  }

  Future<void> _stopRecording() async {
    await _recorder.stop();
    await device?.stop();
  }

  Future<void> _start(int generation) async {
    if (_stale(generation)) return;
    try {
      await _stopRecording();
      if (_stale(generation)) return;
      if (_player.playing) {
        _paused = true;
        _pausedSong = _player.current?.mid;
        await _player.pause();
      }
      if (_stale(generation)) return;
      final capture = source == RecognitionSource.device ? device : null;
      if (capture == null || capture.needsMicrophone) {
        final granted = await _recorder.hasPermission();
        if (_stale(generation)) return;
        if (!granted) {
          _fail(RecognitionFailure.noMicrophone);
          return;
        }
        micGranted = true;
        notifyListeners();
      }
      if (capture != null) {
        final stream = await capture.start();
        if (_stale(generation)) {
          await capture.stop();
          return;
        }
        if (stream != null) {
          _sampleRate = capture.sampleRate;
          _channels = capture.channels;
          _listen(generation, stream);
          return;
        }
        source = RecognitionSource.microphone;
        captureDenied = true;
        notifyListeners();
      }
      _sampleRate = recognitionSampleRate;
      _channels = 1;
      await _recorder.setOnConfigChanged((config) {
        if (_stale(generation)) return;
        _sampleRate = config.sampleRate;
        _channels = config.numChannels;
      });
      if (_stale(generation)) return;
      final stream = await _recorder.startStream(
        const RecordConfig(
          encoder: AudioEncoder.pcm16bits,
          sampleRate: recognitionSampleRate,
          numChannels: 1,
          audioInterruption: AudioInterruptionMode.none,
        ),
      );
      if (_stale(generation)) return;
      _listen(generation, stream);
    } catch (e) {
      if (!_stale(generation)) _fail(e);
    }
  }

  void _listen(int generation, Stream<Uint8List> stream) {
    _sub = stream.listen(
      _buffer.add,
      onError: (Object e) {
        if (!_stale(generation)) _fail(e);
      },
    );
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      seconds++;
      notifyListeners();
      if (_uploadAt.contains(seconds) && !_uploading) {
        unawaited(_upload(generation));
      }
    });
  }

  Future<void> _upload(int generation) async {
    final session = _session;
    _uploading = true;
    try {
      final pcm = toRecognitionPcm(
        _buffer.toBytes(),
        sampleRate: _sampleRate,
        channels: _channels,
      );
      final result = await api.recognizeSong(sessionId: session, pcm: pcm);
      if (_stale(generation) || phase != RecognitionPhase.listening) return;
      if (result != null) {
        _stopCapture();
        phase = RecognitionPhase.found;
        song = result;
        notifyListeners();
      } else if (seconds >= _maxSeconds) {
        if (source == RecognitionSource.device && pcm.every((b) => b == 0)) {
          _fail(RecognitionFailure.silent);
          return;
        }
        _stopCapture();
        phase = RecognitionPhase.notFound;
        notifyListeners();
      }
    } catch (e) {
      if (!_stale(generation)) _fail(e);
    } finally {
      if (!_stale(generation)) _uploading = false;
    }
  }

  void _fail(Object cause) {
    _stopCapture();
    phase = RecognitionPhase.failed;
    error = cause;
    notifyListeners();
  }

  void _cancelCapture() {
    _ticker?.cancel();
    _ticker = null;
    unawaited(_sub?.cancel());
    _sub = null;
  }

  void _stopCapture() {
    _cancelCapture();
    _recordingWork = _recordingWork.then((_) => _stopRecording());
  }

  Future<void> playResult() async {
    final result = song;
    if (finished || result == null) return;
    _paused = false;
    await _player.playList([result], 0);
  }

  /// 后台关闭也立即使请求失效，不等待页面退场动画。
  Future<void> finish() {
    if (_finishing case final work?) return work;
    finished = true;
    ++_generation;
    _cancelCapture();
    notifyListeners();
    return _finishing = _recordingWork.then((_) async {
      await _stopRecording();
      if (_paused && !_player.playing && _player.current?.mid == _pausedSong) {
        await _player.play();
      }
    });
  }

  @override
  void dispose() {
    if (_disposed) return;
    final done = finish();
    _disposed = true;
    unawaited(done.whenComplete(_recorder.dispose));
    super.dispose();
  }
}
