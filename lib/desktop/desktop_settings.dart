import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../src/rust/api/music.dart' as api;

/// 点窗口关闭按钮时做什么。
enum CloseAction { ask, tray, exit }

enum HotkeyAction {
  toggle,
  previous,
  next,
  volumeUp,
  volumeDown,
  like,
  window,
  lyrics,
}

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

/// Windows 的组合键：[modifiers] 是 RegisterHotKey 的 MOD_* 位，[key] 是虚拟键码。
class Hotkey {
  const Hotkey(this.modifiers, this.key);

  static const alt = 0x1;
  static const ctrl = 0x2;
  static const shift = 0x4;

  final int modifiers;
  final int key;

  /// 录制时按下的键换成组合键，认不出的键或修饰键不够时返回 null。
  /// 至少要两个修饰键：Ctrl+C、Alt+F4 这类单修饰键组合各个软件都在用，注册成全局的会把它们抢走。
  static Future<Hotkey?> fromEvent(KeyEvent event) async {
    final keyboard = HardwareKeyboard.instance;
    final modifiers =
        (keyboard.isControlPressed ? ctrl : 0) |
        (keyboard.isAltPressed ? alt : 0) |
        (keyboard.isShiftPressed ? shift : 0);
    if (const {0, ctrl, alt, shift}.contains(modifiers)) return null;
    final scan = _scanCodes[event.physicalKey];
    final key = scan == null
        ? _virtualKeys[event.logicalKey]
        : await DesktopSettings.channel.invokeMethod<int>('virtualKey', scan);
    if (key == null || !_keyLabels.containsKey(key)) return null;
    return Hotkey(modifiers, key);
  }

  String get label => [
    if (modifiers & ctrl != 0) 'Ctrl',
    if (modifiers & alt != 0) 'Alt',
    if (modifiers & shift != 0) 'Shift',
    _keyLabels[key] ?? '?',
  ].join('+');

  @override
  bool operator ==(Object other) =>
      other is Hotkey && other.modifiers == modifiers && other.key == key;

  @override
  int get hashCode => Object.hash(modifiers, key);
}

const _defaultHotkeys = {
  HotkeyAction.toggle: Hotkey(Hotkey.ctrl | Hotkey.alt, 0x50), // P
  HotkeyAction.previous: Hotkey(Hotkey.ctrl | Hotkey.alt, 0x25), // ←
  HotkeyAction.next: Hotkey(Hotkey.ctrl | Hotkey.alt, 0x27), // →
  HotkeyAction.volumeUp: Hotkey(Hotkey.ctrl | Hotkey.alt, 0x26), // ↑
  HotkeyAction.volumeDown: Hotkey(Hotkey.ctrl | Hotkey.alt, 0x28), // ↓
  HotkeyAction.like: Hotkey(Hotkey.ctrl | Hotkey.alt, 0x4C), // L
  HotkeyAction.window: Hotkey(Hotkey.ctrl | Hotkey.alt, 0x4D), // M
};

/// 字母和数字键按位置记扫描码，由系统按当前键盘布局换成虚拟键码：
/// 它们的虚拟键码随布局变（AZERTY 的 A/Q 对调、数字行要按 Shift），按字符查会对不上。
final _scanCodes = <PhysicalKeyboardKey, int>{
  for (final (i, scan) in const [
    0x1E, 0x30, 0x2E, 0x20, 0x12, 0x21, 0x22, 0x23, 0x17, 0x24, 0x25, 0x26, //
    0x32, 0x31, 0x18, 0x19, 0x10, 0x13, 0x1F, 0x14, 0x16, 0x2F, 0x11, 0x2D,
    0x15, 0x2C,
  ].indexed)
    PhysicalKeyboardKey(PhysicalKeyboardKey.keyA.usbHidUsage + i): scan,
  // HID 和扫描码的数字行都是 1…9、0 的顺序
  for (var i = 0; i < 10; i++)
    PhysicalKeyboardKey(PhysicalKeyboardKey.digit1.usbHidUsage + i): 0x02 + i,
};

/// 其余的键不随布局变，直接对应虚拟键码。
final _virtualKeys = <LogicalKeyboardKey, int>{
  for (final (i, k) in [
    LogicalKeyboardKey.f1,
    LogicalKeyboardKey.f2,
    LogicalKeyboardKey.f3,
    LogicalKeyboardKey.f4,
    LogicalKeyboardKey.f5,
    LogicalKeyboardKey.f6,
    LogicalKeyboardKey.f7,
    LogicalKeyboardKey.f8,
    LogicalKeyboardKey.f9,
    LogicalKeyboardKey.f10,
    LogicalKeyboardKey.f11,
    LogicalKeyboardKey.f12,
  ].indexed)
    k: 0x70 + i,
  LogicalKeyboardKey.space: 0x20,
  LogicalKeyboardKey.pageUp: 0x21,
  LogicalKeyboardKey.pageDown: 0x22,
  LogicalKeyboardKey.end: 0x23,
  LogicalKeyboardKey.home: 0x24,
  LogicalKeyboardKey.arrowLeft: 0x25,
  LogicalKeyboardKey.arrowUp: 0x26,
  LogicalKeyboardKey.arrowRight: 0x27,
  LogicalKeyboardKey.arrowDown: 0x28,
  LogicalKeyboardKey.insert: 0x2D,
  LogicalKeyboardKey.delete: 0x2E,
};

final _keyLabels = <int, String>{
  for (var i = 0; i < 26; i++) 0x41 + i: String.fromCharCode(0x41 + i),
  for (var i = 0; i < 10; i++) 0x30 + i: '$i',
  for (var i = 0; i < 12; i++) 0x70 + i: 'F${i + 1}',
  0x20: 'Space',
  0x21: 'PageUp',
  0x22: 'PageDown',
  0x23: 'End',
  0x24: 'Home',
  0x25: '←',
  0x26: '↑',
  0x27: '→',
  0x28: '↓',
  0x2D: 'Insert',
  0x2E: 'Delete',
};

/// Windows 桌面相关的设置：关闭窗口、全局快捷键、开机自启动。原生部分在 windows/runner/desktop_integration.cpp。
class DesktopSettings extends ChangeNotifier {
  DesktopSettings()
    : closeAction =
          CloseAction.values.asNameMap()[api.getPref(key: _closeActionKey)] ??
          CloseAction.ask,
      hotkeysEnabled = api.getPref(key: _hotkeysEnabledKey) != 'false',
      hotkeys = _loadHotkeys() {
    _loadLyrics();
  }

  static const channel = MethodChannel('kanade/desktop');
  static const _closeActionKey = 'close_action';
  static const _hotkeysEnabledKey = 'hotkeys_enabled';
  static const _hotkeysKey = 'hotkeys';
  static const _lyricsKey = 'desktop_lyrics';

  CloseAction closeAction;
  bool hotkeysEnabled;

  /// 桌面歌词。锁定、字号和位置在歌词窗口上改，原生部分报回来再存下。
  bool lyricsVisible = false;
  bool lyricsLocked = false;
  int lyricsFontSize = 32;
  int lyricsSung = lyricsColors[0];
  int lyricsUnsung = lyricsColors[1];
  bool lyricsSingleLine = false;
  LyricsAlign lyricsAlign = LyricsAlign.stagger;

  /// 和播放页的开关分开，在歌词窗口的工具栏上切换。
  bool lyricsTranslation = false;
  bool lyricsRomaji = false;

  /// 窗口左上角的屏幕坐标，没拖过是 null。
  (int, int)? _lyricsPosition;

  /// 每个操作的组合键，null 是用户清掉了。
  final Map<HotkeyAction, Hotkey?> hotkeys;

  /// 注册失败的组合键，多半是被别的软件占了。
  Set<HotkeyAction> taken = {};

  /// 真正的 App 接上原生部分后才注册快捷键，集成测试里不抢系统的组合键。
  bool _active = false;

  /// 录制新组合键时先全部注销，不然按下的旧组合键被系统截走，录不到。
  bool _recording = false;

  static Map<HotkeyAction, Hotkey?> _loadHotkeys() {
    final saved = <String, Object?>{};
    try {
      saved.addAll(
        (jsonDecode(api.getPref(key: _hotkeysKey) ?? '{}') as Map)
            .cast<String, Object?>(),
      );
    } on FormatException {
      // 存坏了就用默认值
    }
    return {
      for (final a in HotkeyAction.values)
        a: !saved.containsKey(a.name)
            ? _defaultHotkeys[a]
            : switch (saved[a.name]) {
                [final int m, final int k] => Hotkey(m, k),
                _ => null,
              },
    };
  }

  void setCloseAction(CloseAction a) {
    closeAction = a;
    api.setPref(key: _closeActionKey, value: a.name);
    notifyListeners();
  }

  void setHotkeysEnabled(bool v) {
    hotkeysEnabled = v;
    api.setPref(key: _hotkeysEnabledKey, value: '$v');
    notifyListeners();
    _register();
  }

  /// 同一个组合键只留给最新设置的操作。
  void setHotkey(HotkeyAction action, Hotkey? key) {
    if (key != null) {
      for (final a in HotkeyAction.values) {
        if (hotkeys[a] == key) hotkeys[a] = null;
      }
    }
    hotkeys[action] = key;
    api.setPref(
      key: _hotkeysKey,
      value: jsonEncode({
        for (final MapEntry(:key, :value) in hotkeys.entries)
          key.name: value == null ? null : [value.modifiers, value.key],
      }),
    );
    notifyListeners();
    _register();
  }

  set recording(bool v) {
    _recording = v;
    _register();
  }

  void activate() {
    _active = true;
    _register();
    _pushLyrics();
  }

  void _loadLyrics() {
    try {
      final saved = jsonDecode(api.getPref(key: _lyricsKey) ?? '{}') as Map;
      lyricsVisible = saved['visible'] == true;
      lyricsLocked = saved['locked'] == true;
      if (saved['fontSize'] case final int v) lyricsFontSize = v;
      if (saved['sung'] case final int v) lyricsSung = v;
      if (saved['unsung'] case final int v) lyricsUnsung = v;
      lyricsSingleLine = saved['singleLine'] == true;
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

  void _saveLyrics() => api.setPref(
    key: _lyricsKey,
    value: jsonEncode({
      'visible': lyricsVisible,
      'locked': lyricsLocked,
      'fontSize': lyricsFontSize,
      'sung': lyricsSung,
      'unsung': lyricsUnsung,
      'singleLine': lyricsSingleLine,
      'align': lyricsAlign.name,
      'translation': lyricsTranslation,
      'romaji': lyricsRomaji,
      if (_lyricsPosition case (final x, final y)) ...{'x': x, 'y': y},
    }),
  );

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

  void setLyricsAlign(LyricsAlign v) {
    lyricsAlign = v;
    _lyricsChanged();
  }

  void _lyricsChanged() {
    _saveLyrics();
    notifyListeners();
    _pushLyrics();
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

  Future<void> _pushLyrics() async {
    if (!_active) return;
    try {
      await channel.invokeMethod('lyricsConfig', {
        'visible': lyricsVisible,
        'locked': lyricsLocked,
        'fontSize': lyricsFontSize,
        'sung': lyricsSung,
        'unsung': lyricsUnsung,
        'singleLine': lyricsSingleLine,
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
      });
    } catch (e) {
      debugPrint('push desktop lyrics config failed: $e');
    }
  }

  Future<void> _register() async {
    if (!_active) return;
    final list = [
      if (hotkeysEnabled && !_recording)
        for (final MapEntry(:key, :value) in hotkeys.entries)
          if (value != null) (key, value),
    ];
    try {
      final ok = await channel.invokeListMethod<bool>('setHotkeys', [
        for (final (a, k) in list)
          {'action': a.name, 'modifiers': k.modifiers, 'key': k.key},
      ]);
      // 录制期间全部注销了，不算被占用
      if (_recording) return;
      taken = {
        for (final (i, (a, _)) in list.indexed)
          if (ok?[i] != true) a,
      };
      notifyListeners();
    } catch (e) {
      debugPrint('register hotkeys failed: $e');
    }
  }

  /// 以系统里的启动项为准，用户可能在任务管理器里关掉了它。
  Future<bool> autostart() async =>
      await channel.invokeMethod<bool>('getAutostart') ?? false;

  Future<void> setAutostart(bool v) => channel.invokeMethod('setAutostart', v);

  static const _rendering = MethodChannel('kanade/rendering');

  Future<bool> softwareRendering() async =>
      await _rendering.invokeMethod<bool>('get') ?? false;

  Future<void> setSoftwareRendering(bool v) =>
      _rendering.invokeMethod('set', v);
}
