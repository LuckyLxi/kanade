import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:record/record.dart';

import '../data/data_ext.dart';
import '../data/recognition_pcm.dart';
import '../l10n/l10n_ext.dart';
import '../player/player_controller.dart';
import '../src/rust/api/music.dart' as api;
import '../src/rust/api/types.dart';
import 'sheet.dart';
import 'song_tile.dart';

Future<void> showRecognizeSheet(BuildContext context) => showKanadeSheet<void>(
  context: context,
  builder: (_) => const _RecognizeSheet(),
);

enum _Phase { listening, found, notFound, failed }

/// Android 上切到别的软件时浮在屏幕边的按钮和录音用的前台服务，原生实现在
/// RecognizeBubble.kt / RecognizeService.kt。
const _bubble = MethodChannel('kanade/recognize');

class _RecognizeSheet extends StatefulWidget {
  const _RecognizeSheet();

  @override
  State<_RecognizeSheet> createState() => _RecognizeSheetState();
}

class _RecognizeSheetState extends State<_RecognizeSheet> {
  /// 按官方 App 的节奏上传：前 3 秒每秒一次，之后每 3 秒一次，录满 15 秒还没认出来就放弃。
  static const _uploadAt = {1, 2, 3, 6, 9, 12, 15};
  static const _maxSeconds = 15;
  static const _resize = Duration(milliseconds: 300);
  static const _resizeCurve = Curves.easeOutCubic;

  final _recorder = AudioRecorder();
  final _buffer = BytesBuilder(copy: false);
  StreamSubscription<Uint8List>? _sub;
  Timer? _ticker;
  var _sampleRate = recognitionSampleRate;
  var _channels = 1;
  var _session = 0;
  var _seconds = 0;
  var _uploading = false;

  late final PlayerController _player;

  /// 识曲时是不是我们暂停的播放，是的话关掉弹窗时接着放。
  var _paused = false;

  AppLifecycleListener? _lifecycle;

  /// 有没有悬浮窗权限，还没查到时是 null；没有时弹窗里提示去开。
  bool? _canOverlay;
  var _micGranted = false;
  var _service = false;

  /// App 切到后台了，这时悬浮按钮在显示。
  var _away = false;
  var _finished = false;

  _Phase _phase = _Phase.listening;
  Song? _song;
  String? _error;

  @override
  void initState() {
    super.initState();
    _player = context.read<PlayerController>();
    if (Platform.isAndroid) {
      _lifecycle = AppLifecycleListener(onHide: _onHide, onShow: _onShow);
      _bubble.setMethodCallHandler(_onBubbleAction);
      _checkOverlay();
    }
    _start();
  }

  @override
  void dispose() {
    _finish();
    _recorder.dispose();
    _lifecycle?.dispose();
    if (Platform.isAndroid) _bubble.setMethodCallHandler(null);
    super.dispose();
  }

  /// 结束识曲：停录音、收起悬浮按钮、接着放之前的歌。从悬浮按钮关掉时 App 在后台，
  /// 弹窗的退场动画要等切回来才播得完，所以不等 dispose，这里先收尾。
  void _finish() {
    if (_finished) return;
    _finished = true;
    _stop();
    if (Platform.isAndroid) {
      _bubble.invokeMethod('hide');
      if (_service) _bubble.invokeMethod('stopService');
    }
    // 用户点了识别出来的歌，那首已经在放了，不再去动它
    if (_paused && !_player.playing) unawaited(_player.play());
  }

  Future<void> _checkOverlay() async {
    final can = await _bubble.invokeMethod<bool>('canOverlay') ?? false;
    if (!mounted) return;
    setState(() => _canOverlay = can);
    _ensureService();
  }

  /// 前台服务要在 App 还在前台、已经有麦克风权限时启动，之后切走系统才让接着录音。
  Future<void> _ensureService() async {
    if (_service || _canOverlay != true || !_micGranted || _finished) return;
    _service = true;
    final title = AppLocalizations.of(context).recognizeSong;
    _service =
        await _bubble.invokeMethod<bool>('startService', {'title': title}) ??
        false;
  }

  void _onHide() {
    _away = true;
    if (_canOverlay != true || _finished) return;
    _syncBubble();
    _bubble.invokeMethod('show');
  }

  void _onShow() {
    _away = false;
    _bubble.invokeMethod('hide');
    // 可能刚从系统设置里开了悬浮窗权限回来
    _checkOverlay();
  }

  Future<void> _onBubbleAction(MethodCall call) async {
    switch (call.arguments) {
      case 'play':
        unawaited(_player.playList([_song!], 0));
      case 'retry':
        unawaited(_start());
      case 'close':
        _finish();
        Navigator.of(context).pop();
    }
  }

  void _syncBubble() {
    if (!_away || _canOverlay != true) return;
    final song = _song;
    _bubble.invokeMethod('update', {
      'mode': switch (_phase) {
        _Phase.listening => 'listening',
        _Phase.found => 'found',
        _ => 'message',
      },
      'seconds': _seconds,
      'title': song?.name,
      'artist': song == null ? null : singerNames(song),
      'cover': song == null ? null : httpsUrl(song.coverUrl),
      'message': _error ?? AppLocalizations.of(context).recognizeNotFound,
    });
  }

  /// 改状态时顺便告诉悬浮按钮；App 在后台不出帧，build 不会跑，所以不能在 build 里同步。
  void _set(VoidCallback fn) {
    setState(fn);
    _syncBubble();
  }

  Future<void> _start() async {
    _set(() {
      _phase = _Phase.listening;
      _song = null;
      _error = null;
      _seconds = 0;
    });
    _buffer.clear();
    _session = DateTime.now().millisecondsSinceEpoch;
    try {
      // 先停掉正在放的歌，免得麦克风录到自己放的声音
      if (_player.playing) {
        _paused = true;
        await _player.pause();
      }
      if (!await _recorder.hasPermission()) {
        _fail((l) => l.recognizeNoMic);
        return;
      }
      _micGranted = true;
      unawaited(_ensureService());
      // Windows 会按麦克风支持的格式调整，这里记下实际格式，上传前再转换。
      await _recorder.setOnConfigChanged((c) {
        _sampleRate = c.sampleRate;
        _channels = c.numChannels;
      });
      final stream = await _recorder.startStream(
        const RecordConfig(
          encoder: AudioEncoder.pcm16bits,
          sampleRate: recognitionSampleRate,
          numChannels: 1,
          // 不抢音频焦点：要识别的歌往往在别的软件里放，抢了它就停了，自己的播放上面已经暂停
          audioInterruption: AudioInterruptionMode.none,
        ),
      );
      if (!mounted) return;
      _sub = stream.listen(_buffer.add);
      _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
        _set(() => _seconds++);
        if (_uploadAt.contains(_seconds) && !_uploading) _upload();
      });
    } catch (e) {
      _fail((l) => errorText(l, e));
    }
  }

  Future<void> _upload() async {
    final session = _session;
    final pcm = toRecognitionPcm(
      _buffer.toBytes(),
      sampleRate: _sampleRate,
      channels: _channels,
    );
    _uploading = true;
    try {
      final song = await api.recognizeSong(sessionId: session, pcm: pcm);
      if (!mounted || session != _session || _phase != _Phase.listening) return;
      if (song != null) {
        _stop();
        _set(() {
          _phase = _Phase.found;
          _song = song;
        });
      } else if (_seconds >= _maxSeconds) {
        _stop();
        _set(() => _phase = _Phase.notFound);
      }
    } catch (e) {
      if (mounted && session == _session) {
        _fail((l) => errorText(l, e));
      }
    } finally {
      _uploading = false;
    }
  }

  void _fail(String Function(AppLocalizations l) message) {
    _stop();
    if (!mounted) return;
    _set(() {
      _phase = _Phase.failed;
      _error = message(AppLocalizations.of(context));
    });
  }

  void _stop() {
    _ticker?.cancel();
    _ticker = null;
    _sub?.cancel();
    _sub = null;
    _recorder.stop();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final muted = TextStyle(color: scheme.onSurfaceVariant);
    // 弹窗贴着底边，内容高度一变，顶边就平滑地落下或升起
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AnimatedSize(
          duration: _resize,
          curve: _resizeCurve,
          alignment: Alignment.topCenter,
          child: SheetHeader(
            title: l.recognizeSong,
            subtitle: _phase == _Phase.listening ? l.recognizeHint : null,
          ),
        ),
        // 没有悬浮窗权限时提示去开，开了以后切回来这行就收起
        AnimatedSize(
          duration: _resize,
          curve: _resizeCurve,
          alignment: Alignment.topCenter,
          child: _canOverlay == false
              ? Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: SheetGroup(
                    children: [
                      SheetRow(
                        title: l.recognizeBubble,
                        subtitle: l.recognizeBubbleHint,
                        leading: const Icon(
                          Icons.picture_in_picture_alt_rounded,
                        ),
                        chevron: true,
                        onTap: () =>
                            _bubble.invokeMethod('openOverlaySettings'),
                      ),
                    ],
                  ),
                )
              : const SizedBox(width: double.infinity),
        ),
        AnimatedSize(
          duration: _resize,
          curve: _resizeCurve,
          alignment: Alignment.topCenter,
          child: AnimatedSwitcher(
            duration: _resize,
            // 高度只按新内容算，旧内容淡出时超出的部分由外面的 AnimatedSize 裁掉
            layoutBuilder: (current, previous) => Stack(
              clipBehavior: Clip.none,
              alignment: Alignment.topCenter,
              children: [
                for (final child in previous)
                  Positioned(top: 0, left: 0, right: 0, child: child),
                ?current,
              ],
            ),
            child: KeyedSubtree(
              key: ValueKey(_phase),
              child: switch (_phase) {
                _Phase.listening => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 24),
                  child: Column(
                    children: [
                      Icon(
                        Icons.mic_rounded,
                        size: 48,
                        color: scheme.onSurface,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        l.recognizeListening,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 4),
                      Text(l.recognizeElapsed(_seconds), style: muted),
                    ],
                  ),
                ),
                _Phase.found => SheetGroup(
                  children: [
                    SongTile(songs: [_song!], index: 0),
                  ],
                ),
                _Phase.notFound || _Phase.failed => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 24),
                  child: Text(
                    _error ?? l.recognizeNotFound,
                    textAlign: TextAlign.center,
                    style: muted,
                  ),
                ),
              },
            ),
          ),
        ),
        const SizedBox(height: 12),
        FilledButton(
          // 白底黑字（亮色模式反过来），抗色只留给播放相关
          style: FilledButton.styleFrom(
            backgroundColor: scheme.onSurface,
            foregroundColor: scheme.surface,
            minimumSize: const Size(64, 46),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          onPressed: _phase == _Phase.listening
              ? () => Navigator.of(context).pop()
              : _start,
          child: Text(switch (_phase) {
            _Phase.listening => l.cancel,
            _Phase.failed => l.retry,
            _ => l.recognizeAgain,
          }),
        ),
      ],
    );
  }
}
