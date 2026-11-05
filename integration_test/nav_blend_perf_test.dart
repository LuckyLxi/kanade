import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:kanade/ui/glass.dart';
import 'package:kanade/ui/theme.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';

/// 量进二级页时导航栏和播放条“粘连成一块”（放进同一个玻璃层的融合组）比现在分开画贵多少。
/// 几种画法走同一条循环动画，背后是同样在滑动的页面，逐帧记录构建 / 光栅耗时。
/// 不碰 Rust 和数据库。
/// flutter drive --profile -d <手机> --driver=test_driver/integration_test.dart --target=integration_test/nav_blend_perf_test.dart
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  testWidgets('导航栏粘连开销', (tester) async {
    await KanadeGlass.initialize();
    final variant = ValueNotifier(_Variant.current);
    await tester.pumpWidget(
      KanadeGlass.wrap(
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: buildTheme(Brightness.dark),
          home: _Bench(variant: variant),
        ),
      ),
    );
    final view = tester.view;
    final report = StringBuffer(
      'view ${view.physicalSize.width.round()} x ${view.physicalSize.height.round()}, '
      'dpr ${view.devicePixelRatio}, impeller shader filter ${ui.ImageFilter.isShaderFilterSupported}, '
      'quality ${KanadeGlass.navigationQuality.name}\n',
    );
    // --dart-define=NAV_BLEND_SNAP=true：不量，只把动画停在融合中途几处，外面用 adb screencap 截图看粘连有没有生效
    if (const bool.fromEnvironment('NAV_BLEND_SNAP')) {
      for (final v in [_Variant.separate, _Variant.blendFull]) {
        for (final t in [.25, .35, .5]) {
          variant.value = v;
          _freeze.value = t;
          await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 800)));
          // ignore: avoid_print
          print('SNAP ${v.name}_$t');
          await tester.runAsync(() => Future<void>.delayed(const Duration(seconds: 3)));
        }
      }
      return;
    }
    // 先整轮预热一遍，shader 和纹理都建好再量
    for (var round = 0; round < 3; round++) {
      for (final v in _Variant.values) {
        variant.value = v;
        final r = await tester.runAsync(() => _measure(seconds: round == 0 ? 2 : 6));
        if (round > 0) report.writeln('${v.name.padRight(9)}#$round  $r');
      }
    }
    // ignore: avoid_print
    print('\n===== NAV BLEND PERF =====\n$report==========================');
    binding.reportData = {'perf': report.toString()};
  });
}

/// 不为 null 时动画停在这个进度（截图用）。
final _freeze = ValueNotifier<double?>(null);

enum _Variant {
  /// 现在的画法：GlassTabBar 自己一层，播放条自己一层，融合时导航栏盖在上面淡掉。
  current,

  /// 两块玻璃各自一层，形状和粘连版走同一条路线（只是不融合）。
  separate,

  /// 两块玻璃放进同一个铺满全屏的玻璃层，开融合。
  blendFull,

  /// 同上，但玻璃层只包住底部那一条。
  blendBand,
}

Future<String> _measure({required int seconds}) async {
  // 切换画法后先等几帧，把切换本身的构建排除掉
  await Future<void>.delayed(const Duration(milliseconds: 600));
  final timings = <FrameTiming>[];
  final startedAt = DateTime.now().microsecondsSinceEpoch;
  void onTimings(List<FrameTiming> t) => timings.addAll(t);
  final before = ProcessInfo.currentRss;
  var peak = before;
  final sampler = Timer.periodic(
    const Duration(milliseconds: 50),
    (_) => peak = math.max(peak, ProcessInfo.currentRss),
  );
  SchedulerBinding.instance.addTimingsCallback(onTimings);
  await Future<void>.delayed(Duration(seconds: seconds));
  SchedulerBinding.instance.removeTimingsCallback(onTimings);
  sampler.cancel();
  final elapsed = (DateTime.now().microsecondsSinceEpoch - startedAt) / 1e6;

  double ms(Duration d) => d.inMicroseconds / 1000;
  String stats(List<double> xs) {
    if (xs.isEmpty) return '-';
    xs.sort();
    double at(double p) => xs[math.min(xs.length - 1, (xs.length * p).floor())];
    final avg = xs.reduce((a, b) => a + b) / xs.length;
    return 'avg ${avg.toStringAsFixed(2)} p50 ${at(.5).toStringAsFixed(2)} '
        'p90 ${at(.9).toStringAsFixed(2)} p99 ${at(.99).toStringAsFixed(2)} max ${xs.last.toStringAsFixed(2)}';
  }

  final raster = timings.map((t) => ms(t.rasterDuration)).toList();
  final build = timings.map((t) => ms(t.buildDuration)).toList();
  final over8 = raster.where((x) => x > 8.33).length;
  final over16 = timings.where((t) => t.totalSpan > const Duration(microseconds: 16667)).length;
  int mb(int b) => b ~/ (1 << 20);
  return 'fps ${(timings.length / elapsed).toStringAsFixed(1)} | raster ms: ${stats(raster)} | '
      'build ms: ${stats(build)} | raster>8.3ms $over8/${timings.length}, total>16.7ms $over16 | '
      'rss ${mb(before)}->${mb(peak)}MB';
}

class _Bench extends StatefulWidget {
  const _Bench({required this.variant});

  final ValueNotifier<_Variant> variant;

  @override
  State<_Bench> createState() => _BenchState();
}

class _BenchState extends State<_Bench> with SingleTickerProviderStateMixin {
  // 进一次再出一次，来回循环
  late final _t = AnimationController(vsync: this, duration: const Duration(milliseconds: 700))..repeat(reverse: true);

  @override
  void dispose() {
    _t.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surface,
      child: KanadeGlass.backdropScope(
        child: Stack(
          children: [
            Positioned.fill(
              child: KanadeGlass.backdropSource(
                child: AnimatedBuilder(
                  animation: _t,
                  builder: (context, _) {
                    final p = Curves.easeOutCubic.transform(_t.value);
                    final w = MediaQuery.sizeOf(context).width;
                    return ClipRect(
                      child: Stack(
                        children: [
                          Positioned.fill(
                            child: Transform.translate(
                              offset: Offset(-p * w * .25, 0),
                              child: const RepaintBoundary(child: _Page(seed: 0)),
                            ),
                          ),
                          Positioned.fill(
                            child: Transform.translate(
                              offset: Offset((1 - p) * w, 0),
                              child: const RepaintBoundary(child: _Page(seed: 5)),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ),
            Positioned.fill(
              child: ValueListenableBuilder(
                valueListenable: widget.variant,
                builder: (context, v, _) => AnimatedBuilder(
                  animation: Listenable.merge([_t, _freeze]),
                  builder: (context, _) =>
                      _chrome(context, v, _freeze.value ?? Curves.easeInOutCubic.transform(_t.value)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 几何和 home_shell.dart 一致：导航栏胶囊、上方播放条胶囊、底部胶囊。
  Widget _chrome(BuildContext context, _Variant v, double t) {
    const navPad = 6.0;
    const navHeight = KanadeGlass.navigationControlHeight + navPad * 2;
    const pillInset = 12.0;
    const circleSize = KanadeGlass.navigationControlHeight;
    const circleGap = 8.0;
    const miniH = 64.0;
    final size = MediaQuery.sizeOf(context);
    final safeBottom = MediaQuery.paddingOf(context).bottom;
    final navWidth = (size.width - 32 - circleSize - circleGap).clamp(0.0, 300.0);
    final navLeft = (size.width - navWidth) / 2;
    final navTop = size.height - safeBottom - navHeight;
    final pill = Rect.fromLTWH(navLeft + pillInset, navTop + navPad, navWidth - pillInset * 2, circleSize);
    final capsule = Rect.fromLTWH(16, navTop - 2 - miniH, size.width - 32, miniH);
    final bottom = Rect.fromLTWH(16, size.height - safeBottom - 8 - miniH, size.width - 32, miniH);

    final f = const Interval(0, .55).transform(t);
    final d = const Interval(.45, 1).transform(t);
    final bar = Rect.lerp(Rect.lerp(capsule, pill, f), bottom, d)!;
    // 导航栏那块先缩向播放条，再跟着它一起落到底部
    final navShape = Rect.lerp(pill, bar, const Interval(.2, .6).transform(t))!;
    final iconOpacity = 1 - const Interval(0, .4).transform(t);

    final settings = KanadeGlass.navigationSettings(context);
    final quality = KanadeGlass.navigationQuality;
    LiquidShape shapeOf(Rect r) => LiquidRoundedRectangle(borderRadius: math.min(r.width, r.height) / 2);
    Widget ownLayer(Rect r, [Widget? child]) => Positioned.fromRect(
      rect: r,
      child: GlassContainer(useOwnLayer: true, settings: settings, quality: quality, shape: shapeOf(r), child: child),
    );
    Widget grouped(Rect r) => Positioned.fromRect(
      rect: r,
      child: GlassContainer(quality: quality, shape: shapeOf(r)),
    );
    final icons = Positioned.fromRect(
      rect: pill,
      child: IgnorePointer(
        child: Opacity(opacity: iconOpacity, child: const _Icons()),
      ),
    );
    final face = Positioned.fromRect(
      rect: bar,
      child: const IgnorePointer(child: _Face()),
    );

    switch (v) {
      case _Variant.current:
        final navOpacity = 1 - const Interval(.3, .7).transform(f);
        return Stack(
          children: [
            ownLayer(bar),
            face,
            Positioned(
              left: navLeft,
              top: navTop,
              width: navWidth,
              height: navHeight,
              child: Opacity(opacity: navOpacity, child: _tabBar(context, navWidth)),
            ),
          ],
        );
      case _Variant.separate:
        return Stack(children: [ownLayer(navShape), ownLayer(bar), icons, face]);
      case _Variant.blendFull:
      case _Variant.blendBand:
        final layer = AdaptiveLiquidGlassLayer(
          settings: settings,
          quality: quality,
          blendAmount: 20,
          child: Stack(children: [grouped(navShape), grouped(bar)]),
        );
        // 底部那一条：从播放条胶囊上沿往上留一点余量
        final band = Rect.fromLTRB(0, capsule.top - 24, size.width, size.height);
        return Stack(
          children: [
            if (v == _Variant.blendFull)
              Positioned.fill(child: layer)
            else
              Positioned.fromRect(
                rect: band,
                // 玻璃层只有这么大，里面的形状换算成相对它的位置
                child: AdaptiveLiquidGlassLayer(
                  settings: settings,
                  quality: quality,
                  blendAmount: 20,
                  child: Stack(children: [grouped(navShape.shift(-band.topLeft)), grouped(bar.shift(-band.topLeft))]),
                ),
              ),
            icons,
            face,
          ],
        );
    }
  }

  Widget _tabBar(BuildContext context, double navWidth) {
    final scheme = Theme.of(context).colorScheme;
    const foreground = Colors.white;
    return MediaQuery(
      data: MediaQuery.of(context).copyWith(platformBrightness: Brightness.dark),
      child: GlassTabBar.bottom(
        selectedIndex: 0,
        onTabSelected: (_) {},
        tabs: [for (final (icon, label) in _tabs) GlassTab(icon: Icon(icon), label: label, semanticLabel: label)],
        quality: KanadeGlass.navigationQuality,
        settings: KanadeGlass.navigationSettings(context),
        indicatorSettings: KanadeGlass.indicatorSettings,
        indicatorColor: foreground.withValues(alpha: 0.1),
        selectedIconColor: scheme.primary,
        selectedLabelColor: scheme.primary,
        unselectedIconColor: foreground,
        unselectedLabelColor: foreground,
        adaptiveBrightness: false,
        magnification: 1.2,
        horizontalPadding: 12,
        verticalPadding: 6,
        barHeight: KanadeGlass.navigationControlHeight,
        tabWidth: (navWidth - 24) / _tabs.length,
        barBorderRadius: GlassDefaults.capsuleRadius,
        indicatorBorderRadius: GlassDefaults.capsuleRadius,
      ),
    );
  }
}

const _tabs = [(Icons.explore, '发现'), (Icons.search, '搜索'), (Icons.person_outline, '我的')];

class _Icons extends StatelessWidget {
  const _Icons();

  @override
  Widget build(BuildContext context) {
    final lime = Theme.of(context).colorScheme.primary;
    return Row(
      children: [
        for (final (i, (icon, label)) in _tabs.indexed)
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, color: i == 0 ? lime : Colors.white),
                Text(label, style: TextStyle(fontSize: 10, color: i == 0 ? lime : Colors.white)),
              ],
            ),
          ),
      ],
    );
  }
}

class _Face extends StatelessWidget {
  const _Face();

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      final h = box.maxHeight;
      return ClipRect(
        child: Stack(
          children: [
            Positioned(left: (h - 44) / 2, top: (h - 44) / 2, child: const _Tile(seed: 3, size: 44, radius: 22)),
            Positioned(
              left: 66,
              right: 60,
              top: (h - 36) / 2,
              child: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('海底的月亮', maxLines: 1, overflow: TextOverflow.clip, style: TextStyle(fontSize: 15)),
                  Text('林雾', maxLines: 1, style: TextStyle(fontSize: 12, color: Colors.white70)),
                ],
              ),
            ),
          ],
        ),
      );
    },
  );
}

/// 背后的页面：一排彩色方块 + 一列歌曲行，让玻璃有东西可折射。
class _Page extends StatelessWidget {
  const _Page({required this.seed});

  final int seed;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Colors.black,
      child: ListView(
        physics: const NeverScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 56, 16, 0),
        children: [
          Row(
            children: [
              for (var i = 0; i < 3; i++) ...[
                if (i > 0) const SizedBox(width: 10),
                Expanded(
                  child: AspectRatio(aspectRatio: 1, child: _Tile(seed: seed + i, radius: 12)),
                ),
              ],
            ],
          ),
          const SizedBox(height: 16),
          for (var i = 0; i < 14; i++)
            SizedBox(
              height: 58,
              child: Row(
                children: [
                  _Tile(seed: seed + i, size: 44, radius: 8),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('歌曲 ${seed * 10 + i}', style: const TextStyle(fontSize: 15)),
                        const Text('歌手', style: TextStyle(fontSize: 12, color: Colors.white54)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({required this.seed, this.size, required this.radius});

  final int seed;
  final double? size;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final hue = (seed * 47) % 360.0;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            HSLColor.fromAHSL(1, hue, .8, .58).toColor(),
            HSLColor.fromAHSL(1, (hue + 50) % 360, .7, .32).toColor(),
          ],
        ),
      ),
    );
  }
}
