import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

/// 给 [child] 里的文字（图标也是字）加模糊阴影，阴影先画成图缓存起来。
///
/// Impeller 只有在缩放和上一帧一样时才复用文字阴影。导航栏按下会整体放大，
/// 选中的标签也会放大，动画的每一帧都要给每个字重新做一遍模糊，光栅线程大半时间花在这上面。
/// 这里按缩放把阴影画成图：缩放在变时借用缩放最接近的那张，停下来后按准确的缩放画一张，
/// 所以静止时和直接给文字加阴影画出来的一样。[child] 里的文字本身不要带阴影。
class BakedTextShadow extends SingleChildRenderObjectWidget {
  const BakedTextShadow({
    super.key,
    required this.shadows,
    required super.child,
  });

  final List<Shadow> shadows;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      RenderBakedTextShadow(shadows);

  @override
  void updateRenderObject(
    BuildContext context,
    RenderBakedTextShadow renderObject,
  ) {
    renderObject.shadows = shadows;
  }
}

/// [BakedTextShadow] 的渲染对象。
class RenderBakedTextShadow extends RenderProxyBox {
  RenderBakedTextShadow(this._shadows);

  List<Shadow> _shadows;
  set shadows(List<Shadow> value) {
    if (listEquals(value, _shadows)) return;
    _shadows = value;
    markNeedsPaint();
  }

  // 上一次画的时候每段文字所在的缩放，连续两次一样说明动画停了
  final _lastScales = Expando<double>();
  bool _settleScheduled = false;

  @override
  void paint(PaintingContext context, Offset offset) {
    if (_shadows.isNotEmpty && child != null) {
      // 一路乘到根（含 devicePixelRatio），图层上的变换也算在里面
      final toDevice = getTransformTo(null);
      final paragraphs = <RenderParagraph>[];
      void collect(RenderObject node) {
        if (node is RenderParagraph) {
          paragraphs.add(node);
        } else {
          node.visitChildren(collect);
        }
      }

      collect(child!);
      var needsSettle = false;
      for (final p in paragraphs) {
        if (!p.hasSize) continue;
        final local = p.getTransformTo(this);
        final scale = _scaleOf(toDevice.clone()..multiply(local));
        final key = _ShadowKey.of(p, _shadows);
        if (key == null || scale <= 0) continue;
        final stable = _lastScales[p] == scale;
        _lastScales[p] = scale;
        final baked = _ShadowCache.instance.lookup(key, scale, exact: stable);
        if (baked.scale != scale) needsSettle = true;
        final canvas = context.canvas;
        canvas
          ..save()
          ..translate(offset.dx, offset.dy)
          ..transform(local.storage)
          ..translate(-baked.margin, -baked.margin)
          ..scale(1 / baked.scale)
          ..drawImage(
            baked.image,
            Offset.zero,
            Paint()..filterQuality = FilterQuality.low,
          )
          ..restore();
      }
      if (needsSettle) _scheduleSettle();
    }
    super.paint(context, offset);
  }

  // 借用了别的缩放的阴影：下一帧再画一次，缩放没再变就按准确的缩放画
  void _scheduleSettle() {
    if (_settleScheduled) return;
    _settleScheduled = true;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      _settleScheduled = false;
      if (attached) markNeedsPaint();
    });
  }

  static double _scaleOf(Matrix4 m) {
    final s = m.storage;
    final x = math.sqrt(s[0] * s[0] + s[1] * s[1] + s[2] * s[2]);
    final y = math.sqrt(s[4] * s[4] + s[5] * s[5] + s[6] * s[6]);
    // 去掉矩阵连乘带来的末位误差，不然静止时也会被当成缩放变了
    return (math.max(x, y) * 1e4).roundToDouble() / 1e4;
  }
}

/// 一段文字的阴影要画成什么样：文字、排版参数和阴影，不含文字颜色。
@immutable
class _ShadowKey {
  const _ShadowKey(
    this.span,
    this.minWidth,
    this.maxWidth,
    this.textAlign,
    this.textDirection,
    this.textScaler,
    this.maxLines,
    this.ellipsis,
    this.locale,
    this.strutStyle,
    this.textWidthBasis,
    this.textHeightBehavior,
  );

  static _ShadowKey? of(RenderParagraph p, List<Shadow> shadows) {
    final span = _withShadows(p.text, shadows);
    if (span == null) return null;
    final ellipsis = p.overflow == TextOverflow.ellipsis;
    final widthMatters = p.softWrap || ellipsis;
    return _ShadowKey(
      span,
      p.constraints.minWidth,
      widthMatters ? p.constraints.maxWidth : double.infinity,
      p.textAlign,
      p.textDirection,
      p.textScaler,
      p.maxLines,
      ellipsis,
      p.locale,
      p.strutStyle,
      p.textWidthBasis,
      p.textHeightBehavior,
    );
  }

  /// 文字改成透明、加上阴影，画出来就只剩阴影。只认纯文字。
  static TextSpan? _withShadows(InlineSpan span, List<Shadow> shadows) {
    if (span is! TextSpan) return null;
    final children = <InlineSpan>[];
    for (final c in span.children ?? const <InlineSpan>[]) {
      final s = _withShadows(c, shadows);
      if (s == null) return null;
      children.add(s);
    }
    final style = span.style;
    if (style?.foreground != null) return null;
    return TextSpan(
      text: span.text,
      style: (style ?? const TextStyle()).copyWith(
        color: const Color(0x00000000),
        shadows: shadows,
      ),
      children: span.children == null ? null : children,
    );
  }

  final TextSpan span;
  final double minWidth;
  final double maxWidth;
  final TextAlign textAlign;
  final TextDirection textDirection;
  final TextScaler textScaler;
  final int? maxLines;
  final bool ellipsis;
  final Locale? locale;
  final StrutStyle? strutStyle;
  final TextWidthBasis textWidthBasis;
  final ui.TextHeightBehavior? textHeightBehavior;

  @override
  bool operator ==(Object other) =>
      other is _ShadowKey &&
      other.span == span &&
      other.minWidth == minWidth &&
      other.maxWidth == maxWidth &&
      other.textAlign == textAlign &&
      other.textDirection == textDirection &&
      other.textScaler == textScaler &&
      other.maxLines == maxLines &&
      other.ellipsis == ellipsis &&
      other.locale == locale &&
      other.strutStyle == strutStyle &&
      other.textWidthBasis == textWidthBasis &&
      other.textHeightBehavior == textHeightBehavior;

  @override
  int get hashCode => Object.hash(
    span,
    minWidth,
    maxWidth,
    textAlign,
    textDirection,
    textScaler,
    maxLines,
    ellipsis,
    locale,
    strutStyle,
    textWidthBasis,
    textHeightBehavior,
  );

  _BakedShadow bake(double scale) {
    final painter = TextPainter(
      text: span,
      textAlign: textAlign,
      textDirection: textDirection,
      textScaler: textScaler,
      maxLines: maxLines,
      ellipsis: ellipsis ? '…' : null,
      locale: locale,
      strutStyle: strutStyle,
      textWidthBasis: textWidthBasis,
      textHeightBehavior: textHeightBehavior,
    )..layout(minWidth: minWidth, maxWidth: maxWidth);
    var margin = 1.0;
    for (final s in span.style!.shadows!) {
      margin = math.max(margin, s.blurSigma * 3 + s.offset.distance + 1);
    }
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder)
      ..scale(scale)
      ..translate(margin, margin);
    painter.paint(canvas, Offset.zero);
    final picture = recorder.endRecording();
    final image = picture.toImageSync(
      math.max(1, ((painter.width + margin * 2) * scale).ceil()),
      math.max(1, ((painter.height + margin * 2) * scale).ceil()),
    );
    picture.dispose();
    painter.dispose();
    return _BakedShadow(image, scale, margin);
  }
}

class _BakedShadow {
  _BakedShadow(this.image, this.scale, this.margin);

  final ui.Image image;
  final double scale;
  final double margin;
}

/// 全局共用：导航栏选中项的部件会随着高亮移动反复创建，不能存在部件自己身上。
class _ShadowCache {
  _ShadowCache._();

  static final instance = _ShadowCache._();

  // 每段文字最多留几种缩放，总共最多留几段文字
  static const _scalesPerKey = 4;
  static const _maxKeys = 48;

  // 借用别的缩放的阴影时，缩放最多差多少（导航栏按下放大 × 选中项放大不到 1.25）
  static const _maxBorrowRatio = 1.3;

  final _entries = <_ShadowKey, List<_BakedShadow>>{};

  _BakedShadow lookup(_ShadowKey key, double scale, {required bool exact}) {
    final list = _entries.remove(key) ?? [];
    // 最近用过的放到最后，超出时从最前面丢
    _entries[key] = list;
    _BakedShadow? nearest;
    var nearestRatio = double.infinity;
    for (final b in list) {
      final ratio = b.scale > scale ? b.scale / scale : scale / b.scale;
      if (ratio < nearestRatio) {
        nearest = b;
        nearestRatio = ratio;
      }
    }
    if (nearest != null &&
        (nearestRatio == 1 || (!exact && nearestRatio <= _maxBorrowRatio))) {
      return nearest;
    }
    final baked = key.bake(scale);
    if (list.length >= _scalesPerKey) {
      // 丢掉和这次缩放差得最远的那张
      list.sort(
        (a, b) =>
            _distance(a.scale, scale).compareTo(_distance(b.scale, scale)),
      );
      list.removeLast().image.dispose();
    }
    list.add(baked);
    while (_entries.length > _maxKeys) {
      final oldest = _entries.keys.first;
      for (final b in _entries.remove(oldest)!) {
        b.image.dispose();
      }
    }
    return baked;
  }

  static double _distance(double a, double b) => (math.log(a / b)).abs();
}
