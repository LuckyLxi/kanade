import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';

/// 下拉刷新：内容跟着手指往下移，顶上露出一个圆环，拉得越多画得越满。
/// 松手过线后圆环转圈；刷新成功时减速停在正上方、补满一圈，轻弹一下画出对勾，再收起。
/// [onRefresh] 返回 false（失败）时不画对勾，直接收起。
class RingRefresh extends StatefulWidget {
  const RingRefresh({super.key, required this.onRefresh, required this.child});

  final Future<bool> Function() onRefresh;
  final Widget child;

  @override
  State<RingRefresh> createState() => _RingRefreshState();
}

enum _Mode { idle, drag, refreshing, finishing, settling }

class _RingRefreshState extends State<RingRefresh>
    with TickerProviderStateMixin {
  /// 拉过这么多松手才刷新，正好是刷新时内容停的位置。
  static const _threshold = 64.0;
  static const _maxPull = 130.0;

  /// 手指移动多少，内容跟着移动几成。
  static const _resistance = 0.7;

  /// 刷新期间内容停在这么低，给圆环留位置。
  static const _holdAt = 64.0;

  /// 刷新中圆环露出的弧长。
  static const _spinSweep = 0.28;

  static const _settle = Duration(milliseconds: 380);
  static const _settleCurve = Cubic(0.2, 0.8, 0.2, 1);
  static const _stopCurve = Cubic(0.25, 0.6, 0.35, 1);

  /// 补满一圈后：弹大 180ms、缩回 220ms，同时画对勾 300ms；再停 250ms 才收起。
  static const _popMs = 180.0;
  static const _shrinkMs = 220.0;
  static const _checkMs = 300.0;
  static const _holdMs = 250.0;

  /// 内容往下移了多少像素。
  late final _offset = AnimationController.unbounded(vsync: this);

  /// 刷新中转圈，值是圈数（0~1）。
  late final _spin = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 650),
  );

  /// 刷新中的弧长：从松手时的长度缩到 [_spinSweep]。
  late final _sweep = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 300),
  );

  /// 成功后的收尾，值 0~1 对应 [_finishMs] 毫秒。
  late final _finish = AnimationController(vsync: this);

  var _mode = _Mode.idle;
  var _succeeded = false;

  /// 收尾开始时圆环转到的角度（圈数）和弧长。
  var _stopFrom = 0.0;
  var _sweepFrom = _spinSweep;

  /// 收尾里减速停住那段的时长：离正上方越远越长。
  var _stopMs = 0.0;
  double get _finishMs => _stopMs + _popMs + _shrinkMs + _holdMs;

  @override
  void dispose() {
    _offset.dispose();
    _spin.dispose();
    _sweep.dispose();
    _finish.dispose();
    super.dispose();
  }

  void _setMode(_Mode mode) {
    if (_mode != mode) setState(() => _mode = mode);
  }

  /// 列表的滚动规则：拉下来后又往上推时，先收回拉出来的距离，列表本身不动，收完了才轮到列表滚。
  late final _behavior = ScrollConfiguration.of(context).copyWith(
    physics: _RetractPhysics(
      this,
      parent: ScrollConfiguration.of(context).getScrollPhysics(context),
    ),
  );

  /// 手指往上推了 [delta]（负数），返回收完拉出距离后还剩多少给列表。
  double _retract(double delta) {
    final pulled = _offset.value;
    if (_mode != _Mode.drag || pulled <= 0) return delta;
    final want = -delta * _resistance;
    if (want <= pulled) {
      _offset.value = pulled - want;
      return 0;
    }
    _offset.value = 0;
    return delta + pulled / _resistance;
  }

  bool _onScroll(ScrollNotification n) {
    if (n.depth != 0 || n.metrics.axis != Axis.vertical) return false;
    final canDrag = _mode == _Mode.idle || _mode == _Mode.drag;
    if (n is OverscrollNotification &&
        n.dragDetails != null &&
        n.overscroll < 0 &&
        canDrag) {
      _offset.stop();
      _setMode(_Mode.drag);
      final before = _offset.value;
      _offset.value = (before - n.overscroll * _resistance).clamp(
        0.0,
        _maxPull,
      );
      // 拉过线的那一下震一下，告诉用户松手就会刷新
      if (before < _threshold && _offset.value >= _threshold) {
        HapticFeedback.lightImpact();
      }
    } else if (n is ScrollEndNotification && _mode == _Mode.drag) {
      _release();
    }
    return false;
  }

  bool _onIndicator(OverscrollIndicatorNotification n) {
    // 顶部的拉伸效果换成这里的圆环
    if (n.depth != 0 || !n.leading) return false;
    n.disallowIndicator();
    return true;
  }

  Future<void> _release() async {
    if (_offset.value < _threshold) {
      _setMode(_Mode.idle);
      await _offset.animateTo(0, duration: _settle, curve: _settleCurve);
      return;
    }
    // 从松手时的角度和弧长接着转，不跳
    _spin.value = _dragTurns(_offset.value) % 1;
    _spin.repeat();
    _sweep.value = _dragSweep(_offset.value);
    _sweep.animateTo(_spinSweep, curve: Curves.easeOut);
    _setMode(_Mode.refreshing);
    _offset.animateTo(_holdAt, duration: _settle, curve: _settleCurve);

    _succeeded = await widget.onRefresh();
    if (!mounted) return;
    if (_succeeded) {
      _stopFrom = _spin.value;
      _sweepFrom = _sweep.value;
      _spin.stop();
      _stopMs = 260 + (1 - _stopFrom) * 220;
      _finish.duration = Duration(milliseconds: _finishMs.round());
      _setMode(_Mode.finishing);
      final finished = _finish.forward(from: 0);
      // 圆环补满、开始画对勾时震一下
      await Future<void>.delayed(Duration(milliseconds: _stopMs.round()));
      if (!mounted) return;
      HapticFeedback.mediumImpact();
      await finished;
      if (!mounted) return;
    }
    _setMode(_Mode.settling);
    await _offset.animateTo(0, duration: _settle, curve: _settleCurve);
    if (!mounted) return;
    _spin.stop();
    _setMode(_Mode.idle);
  }

  static double _dragSweep(double p) => math.min(p / _threshold, 1) * 0.92;

  /// 拉过线后继续往下拉，圆环跟着转。
  static double _dragTurns(double p) =>
      p > _threshold ? (p - _threshold) * 3 / 360 : 0;

  /// 当前这一帧圆环的样子。
  ({double sweep, double turns, double check, double scale, double opacity})
  _ring() {
    final p = _offset.value;
    switch (_mode) {
      case _Mode.idle || _Mode.drag:
        return (
          sweep: _dragSweep(p),
          turns: _dragTurns(p),
          check: 0,
          scale: 1,
          opacity: math.min(p / 36, 1),
        );
      case _Mode.refreshing:
        return (
          sweep: _sweep.value,
          turns: _spin.value,
          check: 0,
          scale: 1,
          opacity: 1,
        );
      case _Mode.finishing:
        final ms = _finish.value * _finishMs;
        final stop = _stopCurve.transform((ms / _stopMs).clamp(0.0, 1.0));
        final after = ms - _stopMs;
        final scale = after <= 0
            ? 1.0
            : after < _popMs
            ? 1 + 0.1 * const Cubic(0.3, 1.6, 0.5, 1).transform(after / _popMs)
            : 1.1 -
                  0.1 *
                      Curves.easeOut.transform(
                        ((after - _popMs) / _shrinkMs).clamp(0.0, 1.0),
                      );
        return (
          sweep: _sweepFrom + (1 - _sweepFrom) * stop,
          turns: _stopFrom + (1 - _stopFrom) * stop,
          check: const Cubic(
            0.4,
            0,
            0.2,
            1,
          ).transform((after / _checkMs).clamp(0.0, 1.0)),
          scale: scale,
          opacity: 1,
        );
      case _Mode.settling:
        return (
          sweep: _succeeded ? 1 : _sweep.value,
          turns: _succeeded ? 0 : _spin.value,
          check: _succeeded ? 1 : 0,
          scale: 1,
          opacity: (p / _holdAt).clamp(0.0, 1.0),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return NotificationListener<OverscrollIndicatorNotification>(
      onNotification: _onIndicator,
      child: NotificationListener<ScrollNotification>(
        onNotification: _onScroll,
        child: Stack(
          children: [
            AnimatedBuilder(
              animation: _offset,
              builder: (context, child) => Transform.translate(
                offset: Offset(0, _offset.value),
                child: child,
              ),
              // 刷新开始到收起之前列表不能滑也不能点
              child: AbsorbPointer(
                absorbing: _mode != _Mode.idle && _mode != _Mode.drag,
                child: ScrollConfiguration(
                  behavior: _behavior,
                  child: widget.child,
                ),
              ),
            ),
            if (_mode != _Mode.idle || _offset.value > 0)
              AnimatedBuilder(
                animation: Listenable.merge([_offset, _spin, _sweep, _finish]),
                builder: (context, _) {
                  final ring = _ring();
                  return Positioned(
                    top: math.max(_offset.value / 2 - 20, -44),
                    left: 0,
                    right: 0,
                    child: IgnorePointer(
                      child: Center(
                        child: Opacity(
                          opacity: ring.opacity,
                          child: Transform.scale(
                            scale: ring.scale,
                            child: Transform.rotate(
                              angle: ring.turns * 2 * math.pi,
                              child: CustomPaint(
                                size: const Size.square(40),
                                painter: _RingPainter(
                                  sweep: ring.sweep,
                                  check: ring.check,
                                  background: scheme.surfaceContainerHigh,
                                  track: scheme.surfaceContainerHighest,
                                  color: scheme.primary,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
          ],
        ),
      ),
    );
  }
}

/// 在原有滚动规则外面套一层：竖向往上推时先交给 [_RingRefreshState._retract]。
class _RetractPhysics extends ScrollPhysics {
  const _RetractPhysics(this.state, {super.parent});

  final _RingRefreshState state;

  @override
  _RetractPhysics applyTo(ScrollPhysics? ancestor) =>
      _RetractPhysics(state, parent: buildParent(ancestor));

  @override
  double applyPhysicsToUserOffset(ScrollMetrics position, double offset) {
    if (position.axis == Axis.vertical && offset < 0) {
      offset = state._retract(offset);
    }
    return super.applyPhysicsToUserOffset(position, offset);
  }
}

/// 40×40 的圆底，半径 14 的圆环从正上方顺时针画 [sweep] 圈，中间按 [check] 画出对勾。
class _RingPainter extends CustomPainter {
  _RingPainter({
    required this.sweep,
    required this.check,
    required this.background,
    required this.track,
    required this.color,
  });

  final double sweep;
  final double check;
  final Color background;
  final Color track;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width / 40;
    canvas.scale(s);
    const center = Offset(20, 20);
    canvas.drawCircle(center, 20, Paint()..color = background);
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas.drawCircle(center, 14, stroke..color = track);
    stroke.color = color;
    if (sweep > 0) {
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: 14),
        -math.pi / 2,
        sweep * 2 * math.pi,
        false,
        stroke,
      );
    }
    if (check > 0) {
      final path = Path()
        ..moveTo(13.5, 20.5)
        ..relativeLineTo(4.5, 4.5)
        ..relativeLineTo(8.5, -9);
      final metric = path.computeMetrics().single;
      canvas.drawPath(metric.extractPath(0, metric.length * check), stroke);
    }
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.sweep != sweep ||
      old.check != check ||
      old.background != background ||
      old.track != track ||
      old.color != color;
}
