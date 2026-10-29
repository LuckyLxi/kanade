import 'dart:async';

import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';

import 'auth/auth_controller.dart';
import 'l10n/app_localizations.dart';
import 'library/library_controller.dart';
import 'player/media_session.dart';
import 'player/player_controller.dart';
import 'settings/locale_controller.dart';
import 'src/rust/api/music.dart' as api;
import 'src/rust/frb_generated.dart';
import 'ui/glass.dart';
import 'ui/home_shell.dart';
import 'ui/theme.dart';
import 'ui/title_bar.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  await RustLib.init();
  await setupWindow();
  final dir = await getApplicationSupportDirectory();
  await api.initCore(dataDir: dir.path);
  // 预热玻璃着色器，避免第一次出现玻璃时闪白
  await KanadeGlass.initialize();

  runApp(
    KanadeGlass.wrap(
      child: MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => LocaleController()),
          ChangeNotifierProvider(create: (_) => AuthController()),
          ChangeNotifierProvider(create: (context) => PlayerController(context.read<AuthController>())),
          ChangeNotifierProvider(
            create: (context) {
              final library = LibraryController(context.read<AuthController>());
              // 系统媒体卡片要同时看播放状态和红心状态，在这里一起接上
              unawaited(
                MediaSession.attach(context.read<PlayerController>(), library, context.read<LocaleController>()),
              );
              return library;
            },
            lazy: false,
          ),
        ],
        child: const KanadeApp(),
      ),
    ),
  );
}

class KanadeApp extends StatelessWidget {
  const KanadeApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      onGenerateTitle: (context) => AppLocalizations.of(context).appTitle,
      locale: context.watch<LocaleController>().locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      debugShowCheckedModeBanner: false,
      theme: buildTheme(Brightness.light),
      darkTheme: buildTheme(Brightness.dark),
      builder: (context, child) => WindowFrame(child: child!),
      home: const HomeShell(),
    );
  }
}
