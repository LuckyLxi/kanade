import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/services.dart';

import '../data/data_ext.dart';
import '../settings/locale_controller.dart';
import '../settings/lyric_settings.dart';
import '../src/rust/api/types.dart';
import 'player_controller.dart';

/// 把歌词和进度推给原生的歌词窗口：Windows 桌面歌词和 Android 悬浮歌词共用。
/// 原生那边自己往前走进度，这里只在播放状态变了或进度跳了时对一下。
class LyricsFeed {
  LyricsFeed(
    this._channel,
    this._p,
    this._lyricSettings,
    this._locale, {
    Lyric? Function()? lyric,
  }) : _lyricOf = lyric;

  final MethodChannel _channel;
  final PlayerController _p;
  final LyricSettings _lyricSettings;
  final LocaleController _locale;
  final Lyric? Function()? _lyricOf;

  /// 上次推过去的内容，没变就不再推。
  Song? _song;
  Lyric? _lyric;
  bool? _words;

  int _syncedMs = 0;
  bool _syncedPlaying = false;
  final _sinceSync = Stopwatch();

  void push() {
    final s = _p.current;
    final lyric = (_lyricOf ?? () => _p.lyric)();
    final words = _lyricSettings.wordByWord;
    if (identical(s, _song) && identical(lyric, _lyric) && words == _words) {
      sync();
      return;
    }
    _song = s;
    _lyric = lyric;
    _words = words;
    unawaited(
      _channel.invokeMethod('lyricsContent', {
        'title': s == null
            ? _locale.strings.appTitle
            : '${s.name} - ${singerNames(s)}',
        'lines': [
          for (final line in lyric?.lines ?? const <LyricLine>[])
            {
              'time': line.timeMs,
              'text': line.text,
              'trans': line.trans,
              'roma': line.roma,
              'words': Int32List.fromList([
                if (words)
                  for (final w in line.words) ...[
                    w.startMs,
                    w.durationMs,
                    w.text.length,
                  ],
              ]),
            },
        ],
      }),
    );
    sync(force: true);
  }

  void sync({bool force = false}) {
    final playing = _p.advancing && !_p.buffering && !_p.loading;
    final ms = _p.position.value.inMilliseconds;
    final expected =
        _syncedMs + (_syncedPlaying ? _sinceSync.elapsedMilliseconds : 0);
    if (!force && playing == _syncedPlaying && (ms - expected).abs() < 300) {
      return;
    }
    _syncedMs = ms;
    _syncedPlaying = playing;
    _sinceSync
      ..reset()
      ..start();
    unawaited(
      _channel.invokeMethod('lyricsSync', {'position': ms, 'playing': playing}),
    );
  }
}
