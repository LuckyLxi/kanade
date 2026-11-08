import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:provider/provider.dart';

import '../l10n/app_localizations.dart';
import '../settings/theme_controller.dart';
import 'theme.dart';

/// 浅色时显示月亮（点了变深色），深色时显示太阳。
IconData _glyph(bool dark) =>
    dark ? Icons.light_mode_outlined : Icons.dark_mode_outlined;

/// 手动切换浅色/深色的圆形过渡。先把旧画面截下来盖在最上面，底下直接换成新主题：
/// 切到深色时旧画面从图标处挖开一个越来越大的圆洞，切回浅色时旧的深色画面缩成圆收回图标。
/// 截图前先把真正的图标藏起来，图标的切换动画画在最上面，免得被旧画面挡住。
class ThemeReveal extends StatefulWidget {
  const ThemeReveal({super.key, required this.builder});

  /// [revealing] 为 true 时正在播圆形过渡。
  final Widget Function(BuildContext context, bool revealing) builder;

  @override
  State<ThemeReveal> createState() => _ThemeRevealState();
}

class _ThemeRevealState extends State<ThemeReveal>
    with SingleTickerProviderStateMixin {
  final _boundary = GlobalKey();
  late final _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 500),
  );
  late final _curve = CurvedAnimation(
    parent: _controller,
    curve: Curves.easeInOutCubic,
  );

  /// 为 true 时真正的图标藏起来，由最上面那份代替。
  final _busy = ValueNotifier(false);
  ui.Image? _image;
  Rect _icon = Rect.zero;
  bool _toDark = true;
  double _maxRadius = 0;

  @override
  void dispose() {
    _curve.dispose();
    _controller.dispose();
    _busy.dispose();
    _image?.dispose();
    super.dispose();
  }

  double get _radius =>
      _maxRadius * (_toDark ? _curve.value : 1 - _curve.value);

  Future<void> _toggle(Rect icon, Brightness current) async {
    if (_busy.value) return;
    _busy.value = true;
    // 等图标藏起来的这一帧画完再截图
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted) return;
    final boundary =
        _boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = boundary.toImageSync(
      pixelRatio: View.of(context).devicePixelRatio,
    );
    final rect = boundary.globalToLocal(icon.topLeft) & icon.size;
    final size = boundary.size;
    final c = rect.center;
    final toDark = current == Brightness.light;
    context.read<ThemeController>().setMode(
      toDark ? ThemeMode.dark : ThemeMode.light,
    );
    setState(() {
      _image = image;
      _icon = rect;
      _toDark = toDark;
      // 圆心到最远的角
      _maxRadius = Offset(
        math.max(c.dx, size.width - c.dx),
        math.max(c.dy, size.height - c.dy),
      ).distance;
    });
    await _controller.forward(from: 0);
    if (!mounted) return;
    setState(() => _image = null);
    _busy.value = false;
    WidgetsBinding.instance.addPostFrameCallback((_) => image.dispose());
  }

  @override
  Widget build(BuildContext context) {
    final image = _image;
    return Stack(
      fit: StackFit.expand,
      textDirection: TextDirection.ltr,
      children: [
        RepaintBoundary(
          key: _boundary,
          child: widget.builder(context, image != null),
        ),
        if (image != null) ...[
          // 不透明的截图挡住过渡中的点击
          CustomPaint(
            painter: _RevealPainter(
              image,
              _icon.center,
              _toDark,
              () => _radius,
              _controller,
            ),
          ),
          Positioned.fromRect(
            rect: _icon,
            child: IgnorePointer(
              child: _FlyingGlyph(
                progress: _controller,
                toDark: _toDark,
                radius: () => _radius,
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _RevealPainter extends CustomPainter {
  _RevealPainter(
    this.image,
    this.center,
    this.toDark,
    this.radius,
    Listenable repaint,
  ) : super(repaint: repaint);

  final ui.Image image;
  final Offset center;
  final bool toDark;
  final double Function() radius;

  @override
  void paint(Canvas canvas, Size size) {
    final dst = Offset.zero & size;
    final circle = Rect.fromCircle(center: center, radius: radius());
    canvas.save();
    canvas.clipPath(
      toDark
          ? (Path()
              ..fillType = PathFillType.evenOdd
              ..addRect(dst)
              ..addOval(circle))
          : (Path()..addOval(circle)),
    );
    canvas.drawImageRect(
      image,
      Offset.zero & Size(image.width.toDouble(), image.height.toDouble()),
      dst,
      Paint(),
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_RevealPainter old) =>
      old.image != image || old.center != center || old.toDark != toDark;
}

/// 盖在最上面的图标：旧图标转着缩小淡出，新图标转着弹出来。
/// 颜色跟着它所在的区域走：被深色圆圈盖住时用深色主题的颜色，露在外面时用浅色主题的。
class _FlyingGlyph extends StatelessWidget {
  const _FlyingGlyph({
    required this.progress,
    required this.toDark,
    required this.radius,
  });

  final Animation<double> progress;
  final bool toDark;
  final double Function() radius;

  static final _lightColor = buildTheme(Brightness.light).colorScheme.onSurface;
  static final _darkColor = buildTheme(Brightness.dark).colorScheme.onSurface;

  @override
  Widget build(BuildContext context) {
    final spin = toDark ? math.pi / 2 : -math.pi / 2;
    return Directionality(
      textDirection: TextDirection.ltr,
      child: AnimatedBuilder(
        animation: progress,
        builder: (context, _) {
          final t = progress.value;
          final out = Curves.easeIn.transform((t / 0.45).clamp(0, 1));
          final inn = Curves.easeOutBack.transform(
            ((t - 0.25) / 0.6).clamp(0, 1),
          );
          final color = Color.lerp(
            _lightColor,
            _darkColor,
            ((radius() - 6) / 12).clamp(0, 1),
          );
          Widget glyph(bool dark, double angle, double scale, double opacity) =>
              Opacity(
                opacity: opacity.clamp(0, 1),
                child: Transform.rotate(
                  angle: angle,
                  child: Transform.scale(
                    scale: scale,
                    child: Icon(_glyph(dark), size: 24, color: color),
                  ),
                ),
              );
          return Stack(
            alignment: Alignment.center,
            children: [
              glyph(!toDark, -spin * out, 1 - 0.5 * out, 1 - out),
              glyph(toDark, spin * (1 - inn), 0.5 + 0.5 * inn, inn),
            ],
          );
        },
      ),
    );
  }
}

/// 设置页右上角的浅色/深色切换按钮。
class ThemeToggleButton extends StatelessWidget {
  const ThemeToggleButton({super.key});

  @override
  Widget build(BuildContext context) {
    final reveal = context.findAncestorStateOfType<_ThemeRevealState>()!;
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    return IconButton(
      onPressed: () {
        final box = context.findRenderObject()! as RenderBox;
        reveal._toggle(
          box.localToGlobal(Offset.zero) & box.size,
          theme.brightness,
        );
      },
      icon: ValueListenableBuilder(
        valueListenable: reveal._busy,
        builder: (context, busy, _) => Opacity(
          opacity: busy ? 0 : 1,
          child: Icon(
            _glyph(dark),
            size: 24,
            color: theme.colorScheme.onSurface,
            semanticLabel: dark ? l.themeToLight : l.themeToDark,
          ),
        ),
      ),
    );
  }
}
