import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:media_kit/media_kit.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';

import 'auth/auth_controller.dart';
import 'desktop/desktop_integration.dart';
import 'desktop/desktop_settings.dart';
import 'download/download_controller.dart';
import 'l10n/app_localizations.dart';
import 'l10n/localizations_delegates.dart';
import 'library/library_controller.dart';
import 'player/android_playback_connection.dart';
import 'player/media_session.dart';
import 'player/player_controller.dart';
import 'settings/locale_controller.dart';
import 'settings/lyric_settings.dart';
import 'settings/theme_controller.dart';
import 'src/rust/api/music.dart' as api;
import 'src/rust/frb_generated.dart';
import 'ui/cover_shadow.dart';
import 'ui/glass.dart';
import 'ui/home_shell.dart';
import 'ui/player_page.dart';
import 'ui/theme.dart';
import 'ui/theme_reveal.dart';
import 'ui/title_bar.dart';

/// 启动前的初始化：播放器、Rust 层和它的数据目录、窗口、着色器。main 和集成测试共用。
/// 集成测试传 [dataDir] 用数据库副本，别和真正的 App 共用 kanade.db。
/// [hidden] 是开机自启动：窗口不弹出来，只留托盘图标。
Future<void> initApp({
  String? dataDir,
  bool separateAndroidPlayback = false,
  bool hidden = false,
}) async {
  MediaKit.ensureInitialized();
  await RustLib.init();
  await setupWindow(show: !hidden);
  final directory = dataDir ?? (await getApplicationSupportDirectory()).path;
  if (separateAndroidPlayback) {
    await api.initUiCore(dataDir: directory);
  } else {
    await api.initCore(dataDir: directory);
  }
  // 预热玻璃着色器，避免第一次出现玻璃时闪白
  await KanadeGlass.initialize();
  unawaited(loadCoverShadow());
  if (Platform.isWindows) {
    unawaited(
      WidgetsBinding.instance.waitUntilFirstFrameRasterized.then(
        (_) => PlayerPage.warmUp(),
      ),
    );
  }
}

/// 全部状态对象。[mediaSession] 为 false 时不接系统媒体卡片（集成测试用）。
class AppProviders extends StatelessWidget {
  const AppProviders({
    super.key,
    required this.child,
    this.mediaSession = true,
    this.androidPlaybackDirectory,
  });

  final Widget child;
  final bool mediaSession;
  final String? androidPlaybackDirectory;

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => LocaleController()),
        ChangeNotifierProvider(create: (_) => ThemeController()),
        ChangeNotifierProvider(create: (_) => LyricSettings()),
        ChangeNotifierProvider(create: (_) => DesktopSettings()),
        ChangeNotifierProvider(create: (_) => AuthController()),
        // 启动时就去取红心列表
        ChangeNotifierProvider(
          create: (context) =>
              LibraryController(context.read<AuthController>()),
          lazy: false,
        ),
        // Android 上播放和下载都在播放进程里，两边共用这条连接
        Provider<AndroidPlaybackConnection?>(
          create: (_) => switch (androidPlaybackDirectory) {
            final directory? => AndroidPlaybackConnection(directory),
            null => null,
          },
          dispose: (_, connection) => connection?.dispose(),
        ),
        ChangeNotifierProvider(
          lazy: androidPlaybackDirectory == null,
          create: (context) =>
              switch (context.read<AndroidPlaybackConnection?>()) {
                final connection? => PlayerController.android(
                  context.read<AuthController>(),
                  context.read<LibraryController>(),
                  context.read<LocaleController>(),
                  connection,
                ),
                null => PlayerController(context.read<AuthController>()),
              },
        ),
        ChangeNotifierProvider(
          create: (context) =>
              DownloadController(context.read<AndroidPlaybackConnection?>()),
        ),
      ],
      child: mediaSession && androidPlaybackDirectory == null
          ? _MediaSessionHost(child: child)
          : child,
    );
  }
}

/// 系统媒体卡片要同时看播放状态、红心状态和语言，几个状态对象都建好后在这里接上一次。
/// Windows 的托盘和全局快捷键也在这里接，集成测试不接。
class _MediaSessionHost extends StatefulWidget {
  const _MediaSessionHost({required this.child});

  final Widget child;

  @override
  State<_MediaSessionHost> createState() => _MediaSessionHostState();
}

class _MediaSessionHostState extends State<_MediaSessionHost> {
  @override
  void initState() {
    super.initState();
    unawaited(
      MediaSession.attach(
        context.read<PlayerController>(),
        context.read<LibraryController>(),
        context.read<LocaleController>(),
      ),
    );
    DesktopIntegration.attach(
      context.read<PlayerController>(),
      context.read<LibraryController>(),
      context.read<LocaleController>(),
      context.read<DesktopSettings>(),
      context.read<LyricSettings>(),
      _navigator,
    );
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// 按空格播放/暂停。文本框吃空格、按钮开关用空格激活的那层快捷键在 MaterialApp 里、
/// 比这里靠外，这里要自己让开。
class _SpaceToggle extends StatelessWidget {
  const _SpaceToggle({required this.child});

  final Widget child;

  static bool _focusUsesSpace() {
    final focused = FocusManager.instance.primaryFocus?.context;
    if (focused == null) return false;
    if (focused.findAncestorStateOfType<EditableTextState>() != null) {
      return true;
    }
    final activate = Actions.maybeFind<ActivateIntent>(focused);
    return activate != null && activate.isEnabled(const ActivateIntent());
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      canRequestFocus: false,
      skipTraversal: true,
      onKeyEvent: (node, event) {
        if (event.logicalKey != LogicalKeyboardKey.space ||
            event is KeyUpEvent ||
            HardwareKeyboard.instance.isControlPressed ||
            HardwareKeyboard.instance.isAltPressed ||
            HardwareKeyboard.instance.isShiftPressed ||
            HardwareKeyboard.instance.isMetaPressed ||
            _focusUsesSpace()) {
          return KeyEventResult.ignored;
        }
        if (event is KeyDownEvent) {
          unawaited(context.read<PlayerController>().toggle());
        }
        return KeyEventResult.handled;
      },
      child: child,
    );
  }
}

/// 托盘那边点关闭时要在这里弹询问框，它不在任何页面里。
final _navigator = GlobalKey<NavigatorState>();

class KanadeApp extends StatelessWidget {
  const KanadeApp({super.key});

  @override
  Widget build(BuildContext context) {
    final locale = context.watch<LocaleController>().locale;
    final themeMode = context.watch<ThemeController>().mode;
    return ThemeReveal(
      builder: (context, revealing) => MaterialApp(
        navigatorKey: _navigator,
        onGenerateTitle: (context) => AppLocalizations.of(context).appTitle,
        locale: locale,
        localizationsDelegates: localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        debugShowCheckedModeBanner: false,
        theme: buildTheme(Brightness.light),
        darkTheme: buildTheme(Brightness.dark),
        themeMode: themeMode,
        // 圆形切换时新主题要一步到位，渐变交给圆圈；跟随系统切换时保持默认渐变
        themeAnimationDuration: revealing
            ? Duration.zero
            : kThemeAnimationDuration,
        builder: (context, child) =>
            _SpaceToggle(child: WindowFrame(child: child!)),
        // 上面盖着弹窗或播放页时，首页不跟着键盘缩放：
        // 发现页的网格按排版约束建，键盘每动一帧都会整块重建，弹窗里输入时卡顿
        home: Builder(
          builder: (context) => MediaQuery.removeViewInsets(
            context: context,
            removeBottom: !(ModalRoute.of(context)?.isCurrent ?? true),
            child: const HomeShell(),
          ),
        ),
      ),
    );
  }
}
