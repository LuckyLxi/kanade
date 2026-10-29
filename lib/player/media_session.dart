import 'dart:async';
import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart';
import 'package:smtc_windows/smtc_windows.dart';

import '../src/rust/api/types.dart';
import 'player_controller.dart';

/// 系统媒体控件的一种实现。
abstract class _Sink {
  void song(Song? s, Duration duration);
  void state({required bool playing, required bool loading, required Duration position, required Duration duration});
}

/// 把播放状态同步给系统的媒体卡片：Android 是通知栏和锁屏（audio_service），
/// Windows 是音量浮窗里的媒体控件（SMTC）。卡片上点的按钮再转回 [PlayerController]。
///
/// 进度不逐帧推：系统拿到「某时刻在某位置、是否在播」后会自己往前走，
/// 只在播放状态变化或进度跳变（拖动、切歌）时重新告诉它。
class MediaSession {
  MediaSession._(this._p, this._sink) {
    _p.addListener(_sync);
    _p.position.addListener(_onPosition);
    _sync();
  }

  final PlayerController _p;
  final _Sink _sink;

  String? _songKey;
  bool? _playing;
  bool? _loading;
  Duration _anchor = Duration.zero;
  final _clock = Stopwatch();

  /// 在支持的平台上接入系统媒体控件，其他平台什么都不做。失败只影响系统卡片，不影响播放。
  static Future<void> attach(PlayerController p) async {
    try {
      final _Sink? sink;
      if (Platform.isAndroid) {
        sink = await _AndroidSink.create(p);
      } else if (Platform.isWindows) {
        sink = await _WindowsSink.create(p);
      } else {
        sink = null;
      }
      if (sink != null) MediaSession._(p, sink);
    } catch (e) {
      debugPrint('media session unavailable: $e');
    }
  }

  void _sync() {
    final song = _p.current;
    final key = song == null ? null : '${song.mid}/${_p.duration.inMilliseconds}';
    if (key != _songKey) {
      _songKey = key;
      _sink.song(song, _p.duration);
      _pushState();
      return;
    }
    final loading = _p.loading || _p.buffering;
    if (_p.playing != _playing || loading != _loading) _pushState();
  }

  void _onPosition() {
    final expected = _anchor + (_playing == true && _loading == false ? _clock.elapsed : Duration.zero);
    if ((_p.position.value - expected).abs() > const Duration(milliseconds: 1500)) _pushState();
  }

  void _pushState() {
    _playing = _p.playing;
    _loading = _p.loading || _p.buffering;
    _anchor = _p.position.value;
    _clock
      ..reset()
      ..start();
    _sink.state(playing: _playing!, loading: _loading!, position: _anchor, duration: _p.duration);
  }
}

String _artist(Song s) => s.singers.map((e) => e.name).join(' / ');

/// 封面有些是 http 链接，Android 默认不允许明文请求，Windows 也更稳妥用 https。
Uri _cover(Song s) => Uri.parse(s.coverUrl.replaceFirst('http://', 'https://').replaceFirst('300x300', '500x500'));

class _AndroidSink extends BaseAudioHandler with SeekHandler implements _Sink {
  _AndroidSink(this._p);

  final PlayerController _p;

  static Future<_AndroidSink> create(PlayerController p) => AudioService.init(
        builder: () => _AndroidSink(p),
        config: const AudioServiceConfig(
          androidNotificationChannelId: 'com.kanade.kanade.playback',
          androidNotificationChannelName: 'Playback',
          androidNotificationOngoing: true,
        ),
      );

  @override
  void song(Song? s, Duration duration) => mediaItem.add(s == null
      ? null
      : MediaItem(
          id: s.mid,
          title: s.name,
          artist: _artist(s),
          album: s.albumName,
          duration: duration,
          artUri: _cover(s),
        ));

  @override
  void state({required bool playing, required bool loading, required Duration position, required Duration duration}) {
    playbackState.add(PlaybackState(
      controls: [
        MediaControl.skipToPrevious,
        playing ? MediaControl.pause : MediaControl.play,
        MediaControl.skipToNext,
      ],
      systemActions: const {MediaAction.seek},
      androidCompactActionIndices: const [0, 1, 2],
      processingState: _p.current == null
          ? AudioProcessingState.idle
          : loading
              ? AudioProcessingState.loading
              : AudioProcessingState.ready,
      playing: playing,
      updatePosition: position,
    ));
  }

  @override
  Future<void> play() => _p.play();

  @override
  Future<void> pause() => _p.pause();

  @override
  Future<void> stop() => _p.pause();

  @override
  Future<void> skipToNext() => _p.next();

  @override
  Future<void> skipToPrevious() => _p.previous();

  @override
  Future<void> seek(Duration position) => _p.seek(position);
}

class _WindowsSink implements _Sink {
  _WindowsSink(this._p) {
    _smtc.buttonPressStream.listen((b) {
      switch (b) {
        case PressedButton.play:
          _p.play();
        case PressedButton.pause:
          _p.pause();
        case PressedButton.next:
          _p.next();
        case PressedButton.previous:
          _p.previous();
        default:
      }
    });
  }

  static Future<_WindowsSink> create(PlayerController p) async {
    await SMTCWindows.initialize();
    return _WindowsSink(p);
  }

  final PlayerController _p;

  /// 没在放歌时不显示卡片，第一次有歌时再打开。
  final _smtc = SMTCWindows(
    enabled: false,
    config: const SMTCConfig(
      playEnabled: true,
      pauseEnabled: true,
      nextEnabled: true,
      prevEnabled: true,
      stopEnabled: false,
      fastForwardEnabled: false,
      rewindEnabled: false,
    ),
  );

  @override
  void song(Song? s, Duration duration) {
    if (s == null) {
      if (_smtc.enabled) _smtc.disableSmtc();
      return;
    }
    if (!_smtc.enabled) _smtc.enableSmtc();
    _smtc.updateMetadata(MusicMetadata(
      title: s.name,
      artist: _artist(s),
      album: s.albumName,
      thumbnail: _cover(s).toString(),
    ));
  }

  @override
  void state({required bool playing, required bool loading, required Duration position, required Duration duration}) {
    if (!_smtc.enabled) return;
    _smtc.setPlaybackStatus(playing ? PlaybackStatus.playing : PlaybackStatus.paused);
    _smtc.updateTimeline(PlaybackTimeline(
      startTimeMs: 0,
      endTimeMs: duration.inMilliseconds,
      positionMs: position.inMilliseconds,
      minSeekTimeMs: 0,
      maxSeekTimeMs: duration.inMilliseconds,
    ));
  }
}
