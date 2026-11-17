import 'dart:async';
import 'dart:io';

import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../l10n/l10n_ext.dart';
import '../player/player_controller.dart';
import '../recognition/android_recognition_platform.dart';
import '../recognition/device_capture.dart';
import '../recognition/recognition_controller.dart';
import '../src/rust/api/types.dart';
import 'sheet.dart';
import 'sliding_segments.dart';
import 'song_tile.dart';

Future<void> showRecognizeSheet(BuildContext context) => showKanadeSheet<void>(
  context: context,
  builder: (_) => const _RecognizeSheet(),
);

class _RecognizeSheet extends StatefulWidget {
  const _RecognizeSheet();

  @override
  State<_RecognizeSheet> createState() => _RecognizeSheetState();
}

class _RecognizeSheetState extends State<_RecognizeSheet> {
  static const _resize = Duration(milliseconds: 300);
  static const _resizeCurve = Curves.easeOutCubic;
  late final RecognitionController _controller;
  AndroidRecognitionPlatform? _platform;
  late AppLocalizations _l;

  RecognitionPhase get _phase => _controller.phase;
  Song? get _song => _controller.song;
  int get _seconds => _controller.seconds;
  bool? get _canOverlay => _platform?.canOverlay;
  String? get _error => switch (_controller.error) {
    RecognitionFailure.noMicrophone => _l.recognizeNoMic,
    RecognitionFailure.silent => _l.recognizeSilent,
    final error? => errorText(_l, error),
    null => null,
  };

  @override
  void initState() {
    super.initState();
    _controller = RecognitionController(context.read<PlayerController>());
    _controller.addListener(_onChanged);
    unawaited(_controller.start());
    unawaited(
      DeviceCapture.create(title: () => _l.recognizeSong).then((device) {
        if (mounted) setState(() => _controller.device = device);
      }),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _l = AppLocalizations.of(context);
    if (Platform.isAndroid) {
      _platform ??= AndroidRecognitionPlatform(
        _controller,
        title: _l.recognizeSong,
        message: () => _phase == RecognitionPhase.paused
            ? _l.recognizePaused
            : _error ?? _l.recognizeNotFound,
        onChanged: _onChanged,
        onClose: () {
          if (mounted) Navigator.of(context).pop();
        },
      );
      _platform!.title = _l.recognizeSong;
    }
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _controller.removeListener(_onChanged);
    _platform?.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final muted = TextStyle(color: scheme.onSurfaceVariant);
    final device = _controller.source == RecognitionSource.device;
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
            subtitle:
                _phase != RecognitionPhase.listening &&
                    _phase != RecognitionPhase.paused
                ? null
                : _controller.captureDenied
                ? l.recognizeCaptureDenied
                : !device
                ? l.recognizeHint
                : Platform.isWindows
                ? l.recognizeHintComputer
                : l.recognizeHintPhone,
          ),
        ),
        AnimatedSize(
          duration: _resize,
          curve: _resizeCurve,
          alignment: Alignment.topCenter,
          child: _controller.device == null
              ? const SizedBox(width: double.infinity)
              : Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: SlidingSegments(
                    labels: [
                      l.recognizeSourceMic,
                      Platform.isWindows
                          ? l.recognizeSourceComputer
                          : l.recognizeSourcePhone,
                    ],
                    selected: _controller.source.index,
                    onSelect: (i) =>
                        _controller.setSource(RecognitionSource.values[i]),
                  ),
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
                        onTap: () => _platform!.openSettings(),
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
              key: ValueKey((_phase, device)),
              child: switch (_phase) {
                RecognitionPhase.listening ||
                RecognitionPhase.paused => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 24),
                  child: Column(
                    children: [
                      // 点图标暂停；暂停后再点从头开始听
                      IconButton(
                        iconSize: 48,
                        color: scheme.onSurface,
                        onPressed: _phase == RecognitionPhase.listening
                            ? _controller.pause
                            : _controller.start,
                        icon: Icon(
                          _phase == RecognitionPhase.paused
                              ? Icons.play_arrow_rounded
                              : !device
                              ? Icons.mic_rounded
                              : Platform.isWindows
                              ? Icons.computer_rounded
                              : Icons.smartphone_rounded,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _phase == RecognitionPhase.paused
                            ? l.recognizePaused
                            : l.recognizeListening,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _phase == RecognitionPhase.paused
                            ? l.recognizeTapResume
                            : l.recognizeElapsed(_seconds),
                        style: muted,
                      ),
                    ],
                  ),
                ),
                RecognitionPhase.found => SheetGroup(
                  children: [
                    SongTile(songs: [_song!], index: 0),
                  ],
                ),
                RecognitionPhase.notFound || RecognitionPhase.failed => Padding(
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
          onPressed:
              _phase == RecognitionPhase.listening ||
                  _phase == RecognitionPhase.paused
              ? () => Navigator.of(context).pop()
              : _controller.start,
          child: Text(switch (_phase) {
            RecognitionPhase.listening || RecognitionPhase.paused => l.cancel,
            RecognitionPhase.failed => l.retry,
            _ => l.recognizeAgain,
          }),
        ),
      ],
    );
  }
}
