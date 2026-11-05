import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:record/record.dart';

import '../data/recognition_pcm.dart';
import '../l10n/l10n_ext.dart';
import '../src/rust/api/music.dart' as api;
import '../src/rust/api/types.dart';
import 'sheet.dart';
import 'song_tile.dart';

Future<void> showRecognizeSheet(BuildContext context) => showKanadeSheet<void>(
  context: context,
  builder: (_) => const _RecognizeSheet(),
);

enum _Phase { listening, found, notFound, failed }

class _RecognizeSheet extends StatefulWidget {
  const _RecognizeSheet();

  @override
  State<_RecognizeSheet> createState() => _RecognizeSheetState();
}

class _RecognizeSheetState extends State<_RecognizeSheet> {
  /// 按官方 App 的节奏上传：前 3 秒每秒一次，之后每 3 秒一次，录满 15 秒还没认出来就放弃。
  static const _uploadAt = {1, 2, 3, 6, 9, 12, 15};
  static const _maxSeconds = 15;

  final _recorder = AudioRecorder();
  final _buffer = BytesBuilder(copy: false);
  StreamSubscription<Uint8List>? _sub;
  Timer? _ticker;
  var _sampleRate = recognitionSampleRate;
  var _channels = 1;
  var _session = 0;
  var _seconds = 0;
  var _uploading = false;

  _Phase _phase = _Phase.listening;
  Song? _song;
  String? _error;

  @override
  void initState() {
    super.initState();
    _start();
  }

  @override
  void dispose() {
    _stop();
    _recorder.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    setState(() {
      _phase = _Phase.listening;
      _song = null;
      _error = null;
      _seconds = 0;
    });
    _buffer.clear();
    _session = DateTime.now().millisecondsSinceEpoch;
    try {
      if (!await _recorder.hasPermission()) {
        _fail((l) => l.recognizeNoMic);
        return;
      }
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
        ),
      );
      if (!mounted) return;
      _sub = stream.listen(_buffer.add);
      _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
        setState(() => _seconds++);
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
        setState(() {
          _phase = _Phase.found;
          _song = song;
        });
      } else if (_seconds >= _maxSeconds) {
        _stop();
        setState(() => _phase = _Phase.notFound);
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
    setState(() {
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
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SheetHeader(
          title: l.recognizeSong,
          subtitle: _phase == _Phase.listening ? l.recognizeHint : null,
        ),
        switch (_phase) {
          _Phase.listening => Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Column(
              children: [
                Icon(Icons.mic_rounded, size: 48, color: scheme.onSurface),
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
