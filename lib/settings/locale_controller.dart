import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/widgets.dart';

import '../l10n/app_localizations.dart';
import '../src/rust/api/music.dart' as api;

/// 界面语言。null 表示跟随系统；选择持久化在 Rust 层的 kv 表里。
class LocaleController extends ChangeNotifier {
  LocaleController() : locale = _parse(api.getPref(key: _key));

  static const _key = 'locale';

  Locale? locale;

  static Locale? _parse(String? v) => v == null || v == 'system' ? null : Locale(v);

  /// 当前语言的文案，给拿不到 BuildContext 的地方用（系统媒体卡片）。
  /// 跟随系统时按系统语言找，不支持的语言用第一个。
  AppLocalizations get strings {
    final l = locale ?? PlatformDispatcher.instance.locale;
    final supported = AppLocalizations.supportedLocales.any(
      (s) => s.languageCode == l.languageCode,
    );
    return lookupAppLocalizations(
      supported
          ? Locale(l.languageCode)
          : AppLocalizations.supportedLocales.first,
    );
  }

  void setLocale(Locale? l) {
    locale = l;
    api.setPref(key: _key, value: l?.languageCode ?? 'system');
    notifyListeners();
  }

  void reloadLocale() {
    locale = _parse(api.getPref(key: _key));
    notifyListeners();
  }
}
