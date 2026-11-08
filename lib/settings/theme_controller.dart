import 'package:flutter/material.dart';

import '../src/rust/api/music.dart' as api;

/// 浅色/深色。没手动切过就跟随系统；切过以后固定，持久化在 Rust 层的 kv 表里。
class ThemeController extends ChangeNotifier {
  ThemeController() : mode = _parse(api.getPref(key: _key));

  static const _key = 'theme';

  ThemeMode mode;

  static ThemeMode _parse(String? v) => switch (v) {
    'light' => ThemeMode.light,
    'dark' => ThemeMode.dark,
    _ => ThemeMode.system,
  };

  void setMode(ThemeMode m) {
    mode = m;
    api.setPref(key: _key, value: m.name);
    notifyListeners();
  }
}
