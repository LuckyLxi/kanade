import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';

/// 液态玻璃的统一参数，照搬 Hazuki 调好的那套（圆弧透镜 + 亮边 + 暗边）。
abstract final class KanadeGlass {
  static const double navigationControlHeight = 58;

  static final bool _isFlutterTest = Platform.environment.containsKey('FLUTTER_TEST');

  /// Windows 没有 shader image filter，用共享内容纹理做折射；
  /// 玻璃控件要放在 [backdropSource] 外面，否则会采样到自己。
  static Widget backdropScope({required Widget child}) => Platform.isWindows ? GlassBackdropScope(child: child) : child;

  static Widget backdropSource({required Widget child}) =>
      Platform.isWindows ? GlassBackdropSource(child: child) : child;

  static GlassQuality get navigationQuality =>
      !_isFlutterTest && !Platform.isWindows && !Platform.isLinux && ui.ImageFilter.isShaderFilterSupported
      ? GlassQuality.premium
      : GlassQuality.standard;

  static bool _usesPremiumRenderer(BuildContext context, GlassQuality quality) {
    final ceiling = GlassAdaptiveScopeData.maybeOf(context)?.effectiveQuality;
    return quality == GlassQuality.premium &&
        navigationQuality == GlassQuality.premium &&
        (ceiling == null || ceiling == GlassQuality.premium);
  }

  /// 宽圆弧透镜。premium 引擎的 bevel 以 3 倍基准像素计，72 ≈ 24 逻辑像素过渡。
  static LiquidGlassSettings surfaceSettings(BuildContext context, {GlassQuality quality = GlassQuality.standard}) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final circularLens = _usesPremiumRenderer(context, quality) || Platform.isWindows;
    return LiquidGlassSettings(
      thickness: circularLens ? 72 : 10,
      blur: 2,
      refractiveIndex: 1.18,
      lensModel: circularLens ? GlassLensModel.circularArc : GlassLensModel.spherical,
      refractionAmount: circularLens ? 24 : 0,
      chromaticAberration: 0,
      lightAngle: 2.356194490192345,
      lightIntensity: circularLens ? 0.65 : 0.9,
      fresnelStrength: 1.2,
      edgeAbsorption: isDark ? 0.14 : 0.12,
      rimShade: circularLens ? (isDark ? 0.45 : 0.65) : 0,
      rimShadeEnds: isDark ? 0 : 0.2,
      rimLight: circularLens ? (isDark ? 1.05 : 0.85) : 0,
      ambientStrength: 0,
      saturation: 1.15,
      glassColor: isDark ? const Color(0x20141820) : const Color(0x14FFFFFF),
      bodyMode: GlassBodyMode.clear,
      glowIntensity: 0,
      shadowElevation: 0.35,
    );
  }

  /// 导航栏里滑动的那颗透镜。栏本身已经是玻璃，里面别再放玻璃控件。
  static const indicatorSettings = LiquidGlassSettings(
    thickness: 30,
    blur: 0,
    refractiveIndex: 1.15,
    lensModel: GlassLensModel.circularArcWithDepth,
    refractionAmount: 14,
    chromaticAberration: 0.3,
    lightIntensity: 0.75,
    fresnelStrength: 1,
    edgeAbsorption: 0.05,
    rimShade: 0.35,
    rimLight: 0.75,
    ambientStrength: 0,
    saturation: 1,
    bodyMode: GlassBodyMode.clear,
    glowIntensity: 0,
    shadowElevation: 0,
  );

  /// 着色压得很淡，让后面的封面透得出来。
  static LiquidGlassSettings navigationSettings(BuildContext context) => surfaceSettings(
    context,
    quality: navigationQuality,
  ).copyWith(glassColor: Theme.of(context).colorScheme.surfaceContainer.withValues(alpha: 0.16));

  /// 播放条和导航栏用同一套透镜，边缘的折射和高光保持一致。
  static LiquidGlassSettings playerBarSettings(BuildContext context) =>
      surfaceSettings(context, quality: navigationQuality);

  /// 播放条上有歌名和一排按钮，玻璃太透时底下的文字会和它们叠在一起。
  /// glassColor 在 Windows 的折射路径上几乎看不出来，所以在玻璃里面再垫一层半透明底色。
  static Color playerBarScrim(BuildContext context) =>
      Theme.of(context).colorScheme.surfaceContainer.withValues(alpha: 0.72);

  static Future<void> initialize() => LiquidGlassWidgets.initialize(enablePerformanceMonitor: false);

  static Widget wrap({required Widget child}) => LiquidGlassWidgets.wrap(
    brightnessResolver: Theme.maybeBrightnessOf,
    respectSystemAccessibility: true,
    // 自适应画质的测速会把滚动、解码图片的帧也算进去，容易把透镜降级成普通毛玻璃
    adaptiveQuality: false,
    theme: GlassThemeData.simple(quality: GlassQuality.standard),
    child: child,
  );
}
