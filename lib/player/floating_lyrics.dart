import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';

import '../settings/locale_controller.dart';
import '../settings/lyric_settings.dart';
import '../settings/lyrics_window_settings.dart';
import '../src/rust/api/music.dart' as api;
import '../src/rust/api/types.dart';
import 'android_playback_connection.dart';
import 'lyrics_feed.dart';
import 'playback_messages.dart';
import 'player_controller.dart';

/// Android 悬浮歌词，在播放所在的进程里把设置、歌词和进度推给原生的悬浮窗（FloatingLyrics.kt）。
/// 设置和 Windows 桌面歌词是同一份 [LyricsWindowSettings]。
class FloatingLyrics {
  FloatingLyrics._(this._p, this._settings, this._lyricSettings, this._locale) {
    _channel.setMethodCallHandler(_onCall);
    _p.addListener(_onPlayer);
    _lyricSettings.addListener(_feed.push);
    _p.position.addListener(_feed.sync);
    _settings.addListener(_onSettings);
    _onSettings();
  }

  static const _channel = MethodChannel('kanade/lyrics');

  final PlayerController _p;
  final LyricsWindowSettings _settings;
  final LyricSettings _lyricSettings;
  final LocaleController _locale;
  late final _feed = LyricsFeed(
    _channel,
    _p,
    _lyricSettings,
    _locale,
    lyric: () => _p.loadDisplayMetadata
        ? _p.lyric
        : _fetchedMid == _p.current?.mid
        ? _fetched
        : null,
  );
  String? _config;

  /// 单独的播放进程不加载展示用的歌词，开着悬浮歌词时自己取。
  String? _fetchedMid;
  Lyric? _fetched;

  static void attach(
    PlayerController p,
    LyricsWindowSettings settings,
    LyricSettings lyricSettings,
    LocaleController locale,
  ) {
    if (Platform.isAndroid) {
      FloatingLyrics._(p, settings, lyricSettings, locale);
    }
  }

  void _onSettings() {
    final config = _settings.lyricsConfig;
    final json = jsonEncode(config);
    if (json != _config) {
      _config = json;
      unawaited(_channel.invokeMethod('lyricsConfig', config));
    }
    _onPlayer();
  }

  void _onPlayer() {
    _fetch();
    _feed.push();
  }

  void _fetch() {
    final song = _p.current;
    if (_p.loadDisplayMetadata ||
        !_settings.lyricsVisible ||
        song == null ||
        song.mid == _fetchedMid) {
      return;
    }
    _fetchedMid = song.mid;
    _fetched = null;
    api
        .getLyric(mid: song.mid, id: song.id)
        .then(
          (l) {
            if (_fetchedMid != song.mid) return;
            _fetched = l;
            _feed.push();
          },
          onError: (Object _) {
            // 下次播放器有动静时再取
            if (_fetchedMid == song.mid) _fetchedMid = null;
          },
        );
  }

  /// 界面进程的连接断了。可能是界面崩了，没来得及说自己看不见了，让原生那边自己再查一次。
  static void uiDisconnected() =>
      unawaited(_channel.invokeMethod('uiDisconnected'));

  Future<void> _onCall(MethodCall call) async {
    switch (call.method) {
      case 'lyricsState':
        _settings.applyLyricsState(call.arguments as Map);
      case 'action':
        switch (call.arguments as String) {
          case 'previous':
            await _p.previous();
          case 'toggle':
            await _p.toggle();
          case 'next':
            await _p.next();
        }
    }
  }
}

/// 界面进程这边：悬浮歌词在播放进程里，设置改了让它重读；
/// 它那边改了（锁定、字号、拖动、关闭、通知栏解锁）再读回来。
class FloatingLyricsLink {
  FloatingLyricsLink(this._remote, this._settings, this._lyricSettings) {
    _settings.addListener(_push);
    _lyricSettings.addListener(_push);
    _subs = [
      _remote.floatingLyrics.listen((_) => _settings.reloadLyrics()),
      // 断开期间的转告收不到，重连后重读，免得拿旧的一份把悬浮窗上的改动盖掉
      _remote.restarts.listen((_) => _settings.reloadLyrics()),
    ];
  }

  final AndroidPlaybackConnection _remote;
  final LyricsWindowSettings _settings;
  final LyricSettings _lyricSettings;
  late final List<StreamSubscription<Object?>> _subs;

  void _push() => _remote
      .call(PlaybackOp.floatingLyrics, _lyricSettings.wordByWord)
      .ignore();

  void dispose() {
    _settings.removeListener(_push);
    _lyricSettings.removeListener(_push);
    for (final sub in _subs) {
      unawaited(sub.cancel());
    }
  }
}
