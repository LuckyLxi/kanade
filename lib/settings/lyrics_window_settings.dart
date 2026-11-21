import 'dart:convert';
import 'dart:io';

import 'package:material_ui/material_ui.dart';

import '../src/rust/api/music.dart' as api;

/// 桌面歌词的对齐。错开是上一行靠左、下一行往右缩进，只在两行时有。
enum LyricsAlign { left, center, right, stagger }

/// 桌面歌词可选的颜色。
const lyricsColors = [
  0xFFD4FF3A,
  0xFFFFFFFF,
  0xFF5AC8FA,
  0xFFFF7EB3,
  0xFFFFA53A,
  0xFFB18CFF,
];

/// 歌词窗口的设置：Windows 上是桌面歌词（推送见 DesktopIntegration），
/// Android 上是悬浮歌词（lib/player/floating_lyrics.dart）。
/// 锁定、字号和位置在歌词窗口上改，原生部分报回来再存下。
class LyricsWindowSettings extends ChangeNotifier {
  LyricsWindowSettings() {
    _loadLyrics();
  }

  static const _lyricsKey = 'desktop_lyrics';

  bool lyricsVisible = false;
  bool lyricsLocked = false;
  int lyricsFontSize = Platform.isAndroid ? 22 : 32;
  int lyricsSung = lyricsColors[0];
  int lyricsUnsung = lyricsColors[1];
  bool lyricsSingleLine = false;
  bool lyricsOutline = true;
  LyricsAlign lyricsAlign = LyricsAlign.stagger;

  /// 和播放页的开关分开，在歌词窗口的工具栏上切换。
  bool lyricsTranslation = false;
  bool lyricsRomaji = false;

  /// 窗口左上角的屏幕坐标，没拖过是 null。
  (int, int)? _lyricsPosition;

  void _loadLyrics() {
    try {
      final saved = jsonDecode(api.getPref(key: _lyricsKey) ?? '{}') as Map;
      lyricsVisible = saved['visible'] == true;
      lyricsLocked = saved['locked'] == true;
      if (saved['fontSize'] case final int v) lyricsFontSize = v;
      if (saved['sung'] case final int v) lyricsSung = v;
      if (saved['unsung'] case final int v) lyricsUnsung = v;
      lyricsSingleLine = saved['singleLine'] == true;
      lyricsOutline = saved['outline'] != false;
      lyricsAlign = LyricsAlign.values.firstWhere(
        (a) => a.name == saved['align'],
        orElse: () => LyricsAlign.stagger,
      );
      lyricsTranslation = saved['translation'] == true;
      lyricsRomaji = saved['romaji'] == true;
      if (saved case {'x': final int x, 'y': final int y}) {
        _lyricsPosition = (x, y);
      }
    } on FormatException {
      // 存坏了就用默认值
    }
  }

  String _lyricsJson() => jsonEncode({
    'visible': lyricsVisible,
    'locked': lyricsLocked,
    'fontSize': lyricsFontSize,
    'sung': lyricsSung,
    'unsung': lyricsUnsung,
    'singleLine': lyricsSingleLine,
    'outline': lyricsOutline,
    'align': lyricsAlign.name,
    'translation': lyricsTranslation,
    'romaji': lyricsRomaji,
    if (_lyricsPosition case (final x, final y)) ...{'x': x, 'y': y},
  });

  void _saveLyrics() => api.setPref(key: _lyricsKey, value: _lyricsJson());

  /// 另一个进程改了设置后重读。没变就不通知，两个进程互相转告时不会来回转。
  void reloadLyrics() {
    final before = _lyricsJson();
    _loadLyrics();
    if (_lyricsJson() != before) notifyListeners();
  }

  void setLyricsVisible(bool v) {
    lyricsVisible = v;
    _lyricsChanged();
  }

  void setLyricsLocked(bool v) {
    lyricsLocked = v;
    _lyricsChanged();
  }

  void setLyricsSung(int color) {
    lyricsSung = color;
    _lyricsChanged();
  }

  void setLyricsUnsung(int color) {
    lyricsUnsung = color;
    _lyricsChanged();
  }

  void setLyricsSingleLine(bool v) {
    lyricsSingleLine = v;
    _lyricsChanged();
  }

  void setLyricsOutline(bool v) {
    lyricsOutline = v;
    _lyricsChanged();
  }

  void setLyricsAlign(LyricsAlign v) {
    lyricsAlign = v;
    _lyricsChanged();
  }

  void _lyricsChanged() {
    _saveLyrics();
    notifyListeners();
  }

  /// 歌词窗口上的改动（拖动、锁定、字号、翻译、关闭），以及托盘和快捷键的开关。
  void applyLyricsState(Map<Object?, Object?> state) {
    lyricsVisible = state['visible'] == true;
    lyricsLocked = state['locked'] == true;
    lyricsTranslation = state['translation'] == true;
    lyricsRomaji = state['romaji'] == true;
    if (state['fontSize'] case final int v) lyricsFontSize = v;
    if (state case {'x': final int x, 'y': final int y}) {
      _lyricsPosition = (x, y);
    }
    _saveLyrics();
    notifyListeners();
  }

  /// 推给原生歌词窗口的设置，Windows 和 Android 一样。
  Map<String, Object?> get lyricsConfig => {
    'visible': lyricsVisible,
    'locked': lyricsLocked,
    'fontSize': lyricsFontSize,
    'sung': lyricsSung,
    'unsung': lyricsUnsung,
    'singleLine': lyricsSingleLine,
    'outline': lyricsOutline,
    'align': lyricsAlign.index,
    'translation': lyricsTranslation,
    'romaji': lyricsRomaji,
    'x': _lyricsPosition?.$1,
    'y': _lyricsPosition?.$2,
    // 原生那边用 App 自带的 Material Icons 字体画
    'icons': {
      for (final (name, icon) in [
        ('previous', Icons.skip_previous_rounded),
        ('play', Icons.play_arrow_rounded),
        ('pause', Icons.pause_rounded),
        ('next', Icons.skip_next_rounded),
        ('smaller', Icons.text_decrease_rounded),
        ('bigger', Icons.text_increase_rounded),
        ('translation', Icons.translate_rounded),
        ('romaji', Icons.abc_rounded),
        ('lock', Icons.lock_outline_rounded),
        ('unlock', Icons.lock_open_rounded),
        ('close', Icons.close_rounded),
      ])
        name: icon.codePoint,
    },
  };
}
