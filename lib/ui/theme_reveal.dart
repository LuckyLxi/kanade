import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:material_ui/material_ui.dart';
import 'package:flutter/rendering.dart';
import 'package:provider/provider.dart';

import '../l10n/app_localizations.dart';
import '../settings/theme_controller.dart';
import 'theme.dart';

/// 浅色时显示月亮（点了变深色），深色时显示太阳。
IconData _glyph(bool dark) =>
    dark ? Icons.light_mode_outlined : Icons.dark_mode_outlined;

final _lightColor = buildTheme(Brightness.light).colorScheme.onSurface;
final _darkColor = buildTheme(Brightness.dark).colorScheme.onSurface;

/// 盖在最上面那份图标怎么飞：[from] 转着缩小淡出（没有就不画），[to] 转着弹出来。
class _Flight {
  const _Flight(this.from, this.to, this.size, this.color);

  final IconData? from;
  final IconData to;
  final double size;

  /// 参数是切换的方向和圆当前的半径。
  final Color Function(bool toDark, double radius) color;
}

/// 手动切换浅色/深色的圆形过渡。先把旧画面截下来盖在最上面，底下直接换成新主题：
/// 切到深色时旧画面从图标处挖开一个越来越大的圆洞，切回浅色时旧的深色画面缩成圆收回图标。
/// 截图前先把真正的图标藏起来，图标的切换动画画在最上面，免得被旧画面挡住。
/// 深浅没变时（比如系统本来就是深色，从深色切到跟随系统）不画圆，只让图标转出来。
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

  /// 正在最上面飞的图标；真正的那个藏起来，由最上面那份代替。
  final _flying = ValueNotifier<IconData?>(null);
  ui.Image? _image;
  _Flight? _flight;
  Rect _icon = Rect.zero;
  bool _toDark = true;
  double _maxRadius = 0;

  @override
  void dispose() {
    _curve.dispose();
    _controller.dispose();
    _flying.dispose();
    _image?.dispose();
    super.dispose();
  }

  double get _radius =>
      _maxRadius * (_toDark ? _curve.value : 1 - _curve.value);

  /// 从 [icon] 处切到 [mode]。
  Future<void> _switch(
    Rect icon,
    Brightness current,
    ThemeMode mode,
    _Flight flight,
  ) async {
    if (_flying.value != null) return;
    final target = switch (mode) {
      ThemeMode.light => Brightness.light,
      ThemeMode.dark => Brightness.dark,
      ThemeMode.system =>
        WidgetsBinding.instance.platformDispatcher.platformBrightness,
    };
    _flying.value = flight.to;
    // 等图标藏起来的这一帧画完再截图
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted) return;
    final boundary =
        _boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = target == current
        ? null
        : boundary.toImageSync(pixelRatio: View.of(context).devicePixelRatio);
    final rect = boundary.globalToLocal(icon.topLeft) & icon.size;
    final size = boundary.size;
    final c = rect.center;
    context.read<ThemeController>().setMode(mode);
    setState(() {
      _image = image;
      _flight = flight;
      _icon = rect;
      _toDark = target == Brightness.dark;
      // 圆心到最远的角
      _maxRadius = Offset(
        math.max(c.dx, size.width - c.dx),
        math.max(c.dy, size.height - c.dy),
      ).distance;
    });
    await _controller.forward(from: 0);
    if (!mounted) return;
    setState(() {
      _image = null;
      _flight = null;
    });
    _flying.value = null;
    if (image != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => image.dispose());
    }
  }

  @override
  Widget build(BuildContext context) {
    final image = _image;
    final flight = _flight;
    return Stack(
      fit: StackFit.expand,
      textDirection: TextDirection.ltr,
      children: [
        RepaintBoundary(
          key: _boundary,
          child: widget.builder(context, image != null),
        ),
        // 不透明的截图挡住过渡中的点击
        if (image != null)
          CustomPaint(
            painter: _RevealPainter(
              image,
              _icon.center,
              _toDark,
              () => _radius,
              _controller,
            ),
          ),
        if (flight != null)
          Positioned.fromRect(
            rect: _icon,
            child: IgnorePointer(
              child: _FlyingGlyph(
                progress: _controller,
                toDark: _toDark,
                flight: flight,
                radius: () => _radius,
              ),
            ),
          ),
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
class _FlyingGlyph extends StatelessWidget {
  const _FlyingGlyph({
    required this.progress,
    required this.toDark,
    required this.flight,
    required this.radius,
  });

  final Animation<double> progress;
  final bool toDark;
  final _Flight flight;
  final double Function() radius;

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
          final color = flight.color(toDark, radius());
          Widget glyph(
            IconData icon,
            double angle,
            double scale,
            double opacity,
          ) => Opacity(
            opacity: opacity.clamp(0, 1),
            child: Transform.rotate(
              angle: angle,
              child: Transform.scale(
                scale: scale,
                child: Icon(icon, size: flight.size, color: color),
              ),
            ),
          );
          final from = flight.from;
          return Stack(
            alignment: Alignment.center,
            children: [
              if (from != null)
                glyph(from, -spin * out, 1 - 0.5 * out, 1 - out),
              glyph(flight.to, spin * (1 - inn), 0.5 + 0.5 * inn, inn),
            ],
          );
        },
      ),
    );
  }
}

/// 浅色/深色切换按钮：旧图标转走，新图标转出来，颜色跟着它所在的区域走
/// （被深色圆圈盖住时用深色主题的颜色，露在外面时用浅色主题的）。
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
        reveal._switch(
          box.localToGlobal(Offset.zero) & box.size,
          theme.brightness,
          dark ? ThemeMode.light : ThemeMode.dark,
          _Flight(
            _glyph(dark),
            _glyph(!dark),
            24,
            (_, radius) => Color.lerp(
              _lightColor,
              _darkColor,
              ((radius - 6) / 12).clamp(0, 1),
            )!,
          ),
        );
      },
      icon: ValueListenableBuilder(
        valueListenable: reveal._flying,
        builder: (context, flying, _) => Opacity(
          opacity: flying != null ? 0 : 1,
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

/// 设置页主题选项前面的图标。点选项时用这个图标的 context 调 [ThemeModeIcon.select]：
/// 深浅变了就从图标处画圆，图标转着弹出来；飞的时候真正的图标藏起来。
class ThemeModeIcon extends StatelessWidget {
  const ThemeModeIcon(this.icon, {super.key, required this.size, this.color});

  final IconData icon;
  final double size;
  final Color? color;

  /// 切到 [mode]。弹出来的图标用新主题选中态的颜色，和切完后的选项一致。
  static void select(BuildContext iconContext, ThemeMode mode, IconData icon) {
    final reveal = iconContext.findAncestorStateOfType<_ThemeRevealState>()!;
    final box = iconContext.findRenderObject()! as RenderBox;
    reveal._switch(
      box.localToGlobal(Offset.zero) & box.size,
      Theme.of(iconContext).brightness,
      mode,
      _Flight(
        null,
        icon,
        box.size.shortestSide,
        (toDark, _) => toDark ? _darkSelected : _lightSelected,
      ),
    );
  }

  static final _lightSelected = buildTheme(Brightness.light)
      .colorScheme
      .onSecondaryContainer;
  static final _darkSelected = buildTheme(Brightness.dark)
      .colorScheme
      .onSecondaryContainer;

  @override
  Widget build(BuildContext context) {
    final reveal = context.findAncestorStateOfType<_ThemeRevealState>()!;
    return ValueListenableBuilder(
      valueListenable: reveal._flying,
      builder: (context, flying, child) =>
          Opacity(opacity: flying == icon ? 0 : 1, child: child),
      child: Icon(icon, size: size, color: color),
    );
  }
}
