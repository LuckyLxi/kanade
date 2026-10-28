import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';

import 'auth/auth_controller.dart';
import 'l10n/app_localizations.dart';
import 'library/library_controller.dart';
import 'player/player_controller.dart';
import 'settings/locale_controller.dart';
import 'src/rust/api/music.dart' as api;
import 'src/rust/frb_generated.dart';
import 'ui/home_shell.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  await RustLib.init();
  final dir = await getApplicationSupportDirectory();
  await api.initCore(dataDir: dir.path);

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => LocaleController()),
        ChangeNotifierProvider(create: (_) => AuthController()),
        ChangeNotifierProvider(create: (context) => PlayerController(context.read<AuthController>())),
        ChangeNotifierProvider(create: (context) => LibraryController(context.read<AuthController>()), lazy: false),
      ],
      child: const KanadeApp(),
    ),
  );
}

class KanadeApp extends StatelessWidget {
  const KanadeApp({super.key});

  static const _seed = Color(0xFF31C27C);

  @override
  Widget build(BuildContext context) {
    ThemeData theme(Brightness b) => ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: _seed, brightness: b),
          useMaterial3: true,
        );
    return MaterialApp(
      onGenerateTitle: (context) => AppLocalizations.of(context).appTitle,
      locale: context.watch<LocaleController>().locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      debugShowCheckedModeBanner: false,
      theme: theme(Brightness.light),
      darkTheme: theme(Brightness.dark),
      home: const HomeShell(),
    );
  }
}
