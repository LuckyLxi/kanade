import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../data/data_ext.dart';
import '../l10n/app_localizations.dart';
import '../library/library_controller.dart';
import '../player/media_session.dart';
import '../player/player_controller.dart';
import '../settings/locale_controller.dart';
import '../settings/lyric_settings.dart';
import '../src/rust/api/types.dart';
import '../ui/kanade_dialog.dart';
import 'desktop_settings.dart';

/// Windows 托盘、关闭到托盘和全局快捷键。点关闭按钮、托盘菜单和快捷键由原生部分转过来，
/// 托盘提示和菜单文字从这里推过去。
class DesktopIntegration {
  DesktopIntegration._(
    this._p,
    this._library,
    this._locale,
    this._settings,
    this._lyricSettings,
    this._navigator,
  ) {
    _channel.setMethodCallHandler(_onCall);
    _p.addListener(_pushTray);
    _locale.addListener(_pushTray);
    _pushTray();
    _p.addListener(_pushLyrics);
    _lyricSettings.addListener(_pushLyrics);
    _p.position.addListener(_syncLyrics);
    _pushLyrics();
    _settings.activate();
    unawaited(_channel.invokeMethod('interceptClose', true));
  }

  static const _channel = DesktopSettings.channel;

  final PlayerController _p;
  final LibraryController _library;
  final LocaleController _locale;
  final DesktopSettings _settings;
  final LyricSettings _lyricSettings;
  final GlobalKey<NavigatorState> _navigator;
  Object? _tray;
  bool _asking = false;

  /// 上次推给桌面歌词的内容，没变就不再推。
  Song? _lyricSong;
  Lyric? _lyric;
  bool? _lyricWords;

  /// 桌面歌词自己往前走进度，只在播放状态变了或进度跳了时对一下。
  int _syncedMs = 0;
  bool _syncedPlaying = false;
  final _sinceSync = Stopwatch();

  static void attach(
    PlayerController p,
    LibraryController library,
    LocaleController locale,
    DesktopSettings settings,
    LyricSettings lyricSettings,
    GlobalKey<NavigatorState> navigator,
  ) {
    if (Platform.isWindows) {
      DesktopIntegration._(
        p,
        library,
        locale,
        settings,
        lyricSettings,
        navigator,
      );
    }
  }

  void _pushLyrics() {
    final s = _p.current;
    final lyric = _p.lyric;
    final words = _lyricSettings.wordByWord;
    if (identical(s, _lyricSong) &&
        identical(lyric, _lyric) &&
        words == _lyricWords) {
      _syncLyrics();
      return;
    }
    _lyricSong = s;
    _lyric = lyric;
    _lyricWords = words;
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
    _syncLyrics(force: true);
  }

  void _syncLyrics({bool force = false}) {
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

  void _pushTray() {
    final s = _p.current;
    final l = _locale.strings;
    final line = s == null ? '' : '${s.name} - ${singerNames(s)}';
    final tray = (line, _p.playing, _locale.locale);
    if (tray == _tray) return;
    _tray = tray;
    unawaited(
      _channel.invokeMethod('updateTray', {
        'tip': s == null ? l.appTitle : line,
        'playing': _p.playing,
        'labels': {
          'title': s?.name ?? '',
          'artist': s == null ? '' : singerNames(s),
          'play': l.play,
          'pause': l.pause,
          'previous': l.previousSong,
          'next': l.nextSong,
          'lyricsShow': l.desktopLyricsShow,
          'lyricsHide': l.desktopLyricsHide,
          'lyricsUnlock': l.desktopLyricsUnlock,
          'show': l.trayShowWindow,
          'exit': l.trayExit,
        },
        // 原生那边用 App 自带的 Material Icons 字体画
        'icons': {
          for (final (name, icon) in [
            ('song', Icons.music_note_rounded),
            ('play', Icons.play_arrow_rounded),
            ('pause', Icons.pause_rounded),
            ('previous', Icons.skip_previous_rounded),
            ('next', Icons.skip_next_rounded),
            ('lyricsShow', Icons.lyrics_outlined),
            ('lyricsHide', Icons.lyrics_outlined),
            ('lyricsUnlock', Icons.lock_open_rounded),
            ('show', Icons.web_asset_rounded),
            ('exit', Icons.power_settings_new_rounded),
          ])
            name: icon.codePoint,
        },
      }),
    );
  }

  Future<void> _onCall(MethodCall call) async {
    switch (call.method) {
      case 'closeRequested':
        await _onClose();
      case 'tray' || 'hotkey':
        await _run(call.arguments as String);
      case 'lyricsState':
        _settings.applyLyricsState(call.arguments as Map);
    }
  }

  Future<void> _run(String action) async {
    switch (action) {
      case 'toggle':
        await _p.toggle();
      case 'previous':
        await _p.previous();
      case 'next':
        await _p.next();
      case 'volumeUp':
        await _p.setVolume((_p.volume + 5).clamp(0, 100));
      case 'volumeDown':
        await _p.setVolume((_p.volume - 5).clamp(0, 100));
      case 'like':
        await MediaSession.toggleLike(_p, _library);
    }
  }

  Future<void> _onClose() async {
    var action = _settings.closeAction;
    if (action == CloseAction.ask) {
      if (_asking) return;
      _asking = true;
      final ({CloseAction action, bool remember})? choice;
      try {
        // 从任务栏缩略图关闭时窗口可能是最小化的，不先叫出来就看不到询问框
        await _channel.invokeMethod('show');
        final context = _navigator.currentContext;
        if (context == null || !context.mounted) return;
        choice = await _askClose(context);
      } finally {
        _asking = false;
      }
      if (choice == null) return;
      action = choice.action;
      if (choice.remember) _settings.setCloseAction(action);
    }
    await _channel.invokeMethod(action == CloseAction.tray ? 'hide' : 'quit');
  }
}

Future<({CloseAction action, bool remember})?> _askClose(BuildContext context) {
  var remember = false;
  return showKanadeDialog(
    context,
    builder: (context) {
      final l = AppLocalizations.of(context);
      void pick(CloseAction a) =>
          Navigator.of(context).pop((action: a, remember: remember));
      return KanadeDialog(
        icon: Icons.close_rounded,
        title: l.closeAskTitle,
        message: l.closeAskMessage,
        content: StatefulBuilder(
          builder: (context, setState) => CheckboxListTile(
            value: remember,
            onChanged: (v) => setState(() => remember = v!),
            title: Text(l.closeAskRemember),
            controlAffinity: ListTileControlAffinity.leading,
            contentPadding: EdgeInsets.zero,
            dense: true,
          ),
        ),
        actions: [
          KanadeDialogAction(
            label: l.closeToTray,
            primary: true,
            onPressed: () => pick(CloseAction.tray),
          ),
          KanadeDialogAction(
            label: l.closeExit,
            onPressed: () => pick(CloseAction.exit),
          ),
        ],
      );
    },
  );
}
