import 'dart:ui' as ui;

import 'package:material_ui/material_ui.dart';

ui.FragmentProgram? _program;
Future<void>? _loading;

/// 加载投影 shader。没加载好之前照旧用 BoxShadow 画。
Future<void> loadCoverShadow() =>
    _loading ??= ui.FragmentProgram.fromAsset('shaders/cover_shadow.frag')
        .then((p) => _program = p);

/// 封面的圆角投影。BoxShadow 的透明度是一级一级的（安卓上最明显），
/// 铺在暗色的播放页背景上能看到一圈圈条纹，这里用 shader 按浮点算并抖动。
/// 可以放进 AnimatedContainer，投影会跟着插值。
class CoverShadowDecoration extends Decoration {
  const CoverShadowDecoration({required this.radius, required this.shadow});

  final double radius;
  final BoxShadow shadow;

  static CoverShadowDecoration lerp(
    CoverShadowDecoration a,
    CoverShadowDecoration b,
    double t,
  ) => CoverShadowDecoration(
    radius: ui.lerpDouble(a.radius, b.radius, t)!,
    shadow: BoxShadow.lerp(a.shadow, b.shadow, t)!,
  );

  @override
  Decoration? lerpFrom(Decoration? a, double t) =>
      a is CoverShadowDecoration ? lerp(a, this, t) : super.lerpFrom(a, t);

  @override
  Decoration? lerpTo(Decoration? b, double t) =>
      b is CoverShadowDecoration ? lerp(this, b, t) : super.lerpTo(b, t);

  @override
  BoxPainter createBoxPainter([VoidCallback? onChanged]) =>
      _CoverShadowPainter(this);

  @override
  bool operator ==(Object other) =>
      other is CoverShadowDecoration &&
      other.radius == radius &&
      other.shadow == shadow;

  @override
  int get hashCode => Object.hash(radius, shadow);
}

class _CoverShadowPainter extends BoxPainter {
  _CoverShadowPainter(this.d);

  final CoverShadowDecoration d;
  ui.FragmentShader? _shader;
  final _paint = Paint();

  @override
  void paint(Canvas canvas, Offset offset, ImageConfiguration configuration) {
    final s = d.shadow;
    final rect = (offset & configuration.size!)
        .shift(s.offset)
        .inflate(s.spreadRadius);
    final program = _program;
    if (program == null) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, Radius.circular(d.radius)),
        s.toPaint(),
      );
      return;
    }
    final sigma = s.blurSigma;
    final shader = (_shader ??= program.fragmentShader())
      ..setFloat(0, rect.left)
      ..setFloat(1, rect.top)
      ..setFloat(2, rect.right)
      ..setFloat(3, rect.bottom)
      ..setFloat(4, d.radius)
      ..setFloat(5, sigma)
      ..setFloat(6, s.color.r)
      ..setFloat(7, s.color.g)
      ..setFloat(8, s.color.b)
      ..setFloat(9, s.color.a);
    canvas.drawRect(rect.inflate(3 * sigma), _paint..shader = shader);
  }

  @override
  void dispose() {
    _shader?.dispose();
    super.dispose();
  }
}
