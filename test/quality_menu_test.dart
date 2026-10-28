import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanade/l10n/app_localizations.dart';
import 'package:kanade/player/player_controller.dart';
import 'package:kanade/src/rust/api/types.dart';
import 'package:kanade/ui/player_page.dart';
import 'package:provider/provider.dart';

class _Player extends ChangeNotifier implements PlayerController {
  @override
  List<QualityOption> qualityOptions = const [
    QualityOption(quality: Quality.master, available: true),
    QualityOption(
      quality: Quality.lossless,
      available: false,
      reason: QualityUnavailableReason.noPermission,
    ),
    QualityOption(quality: Quality.high, available: true),
    QualityOption(quality: Quality.aicodec, available: false, reason: QualityUnavailableReason.unsupported),
    QualityOption(quality: Quality.dts, available: false, reason: QualityUnavailableReason.unverified),
    QualityOption(quality: Quality.hires, available: false, reason: QualityUnavailableReason.fileUnavailable),
  ];

  @override
  bool qualitiesLoading = false;

  @override
  Object? qualitiesError;

  @override
  Quality quality = Quality.high;

  @override
  Quality? actualQuality = Quality.high;

  int refreshCount = 0;

  @override
  Future<void> setQuality(Quality value) async {
    quality = value;
    actualQuality = value;
    notifyListeners();
  }

  @override
  Future<void> refreshQualities() async => refreshCount++;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<void> _showMenu(WidgetTester tester, _Player player, {Locale locale = const Locale('zh')}) async {
  await tester.pumpWidget(
    ChangeNotifierProvider<PlayerController>.value(
      value: player,
      child: MaterialApp(
        locale: locale,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(appBar: AppBar(title: const QualityMenu())),
      ),
    ),
  );
}

void main() {
  testWidgets('播放器音质菜单只展示当前歌曲可播放的档位', (tester) async {
    final player = _Player();
    addTearDown(player.dispose);
    await _showMenu(tester, player);
    expect(find.text('高品质 320k'), findsOneWidget);
    await tester.tap(find.byType(QualityMenu));
    await tester.pumpAndSettle();
    expect(find.text('臻品母带'), findsOneWidget);
    expect(find.text('标准 128k'), findsNothing);
    expect(find.textContaining('无损 FLAC'), findsNothing);
    expect(find.textContaining('AI 音质'), findsNothing);
    expect(find.textContaining('DTS:X'), findsNothing);
    expect(find.textContaining('Hi-Res'), findsNothing);
    expect(player.quality, Quality.high);
    await tester.tap(find.text('臻品母带'));
    await tester.pumpAndSettle();
    expect(player.quality, Quality.master);
    expect(find.text('臻品母带'), findsOneWidget);
  });

  testWidgets('英文界面同样只显示可播放音质', (tester) async {
    final player = _Player();
    addTearDown(player.dispose);
    await _showMenu(tester, player, locale: const Locale('en'));
    await tester.tap(find.byType(QualityMenu));
    await tester.pumpAndSettle();
    expect(find.text('Master'), findsOneWidget);
    expect(find.textContaining('Lossless FLAC'), findsNothing);
  });

  testWidgets('没有可播放档位时显示空状态', (tester) async {
    final player = _Player()
      ..qualityOptions = const [
        QualityOption(quality: Quality.lossless, available: false, reason: QualityUnavailableReason.noPermission),
      ];
    addTearDown(player.dispose);
    await _showMenu(tester, player);
    await tester.tap(find.byType(QualityMenu));
    await tester.pumpAndSettle();
    expect(find.textContaining('无损 FLAC'), findsNothing);
    expect(find.text('暂无可用音质'), findsOneWidget);
  });

  testWidgets('降级播放时显示实际音质和请求的音质', (tester) async {
    final player = _Player()
      ..quality = Quality.master
      ..actualQuality = Quality.high;
    addTearDown(player.dispose);
    await _showMenu(tester, player);
    expect(find.text('高品质 320k（无权获取臻品母带）'), findsOneWidget);
  });

  testWidgets('音质加载中不可打开菜单', (tester) async {
    final player = _Player()..qualitiesLoading = true;
    addTearDown(player.dispose);
    await _showMenu(tester, player);
    final menu = tester.widget<PopupMenuButton<Quality>>(find.byType(PopupMenuButton<Quality>));
    expect(menu.enabled, isFalse);
  });

  testWidgets('音质请求失败后允许重新获取', (tester) async {
    final player = _Player()..qualitiesError = '请求失败';
    addTearDown(player.dispose);
    await _showMenu(tester, player);
    await tester.tap(find.byType(QualityMenu));
    await tester.pumpAndSettle();
    await tester.tap(find.text('音质获取失败，点击重试'));
    await tester.pumpAndSettle();
    expect(player.refreshCount, 1);
    expect(player.quality, Quality.high);
  });
}
