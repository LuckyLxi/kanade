import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:flutter_localizations/flutter_localizations.dart'
    show GlobalWidgetsLocalizations;
import 'package:material_ui/material_ui.dart';

import 'app_localizations.dart';

/// gen-l10n 生成的 `AppLocalizations.localizationsDelegates` 仍用 flutter_localizations
/// 里旧的 Material/Cupertino 本地化，和 material_ui / cupertino_ui 的类型对不上，
/// 组件会退回英文。这里换成新包自带的 delegate。
const localizationsDelegates = <LocalizationsDelegate<dynamic>>[
  AppLocalizations.delegate,
  GlobalMaterialLocalizations.delegate,
  GlobalCupertinoLocalizations.delegate,
  GlobalWidgetsLocalizations.delegate,
];
