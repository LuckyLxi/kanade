import 'package:flutter/widgets.dart';

import '../src/rust/api/music.dart' as api;

/// 界面语言。null 表示跟随系统；选择持久化在 Rust 层的 kv 表里。
class LocaleController extends ChangeNotifier {
  LocaleController() : locale = _parse(api.getPref(key: _key));

  static const _key = 'locale';

  Locale? locale;

  static Locale? _parse(String? v) => v == null || v == 'system' ? null : Locale(v);

  void setLocale(Locale? l) {
    locale = l;
    api.setPref(key: _key, value: l?.languageCode ?? 'system');
    notifyListeners();
  }
}
