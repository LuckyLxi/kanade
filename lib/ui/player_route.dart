import 'dart:math' as math;
import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'package:provider/provider.dart';

import '../data/data_ext.dart';
import '../player/player_controller.dart';
import 'glass.dart';
import 'player_page.dart';
import 'title_bar.dart';
import 'widgets.dart';

/// 播放条在屏幕上的锚点：播放页从它变形出来，关闭时再变回它。
/// 播放条把 [barKey] / [coverKey] 挂在自己和封面上，并提供一份不带封面的 [face]，
/// 变形开头由转场层画这份副本，播放条本身藏起来（[hidden]）。
class PlayerBarAnchor {
  PlayerBarAnchor({required this.face, required this.coverRadius});

  final barKey = GlobalKey(debugLabel: 'player bar');
  final coverKey = GlobalKey(debugLabel: 'player bar cover');

  /// 播放条上除封面以外的内容（歌名、按钮），按播放条的尺寸排版。
  final WidgetBuilder face;

  /// 播放条上封面的圆角，飞行封面从它过渡到大封面的圆角。
  final double coverRadius;

  /// 播放页盖在上面（包括转场途中）时为 true。
  final hidden = ValueNotifier(false);

  Rect? get rect => _globalRect(barKey);
  Rect? get coverRect => _globalRect(coverKey);

  /// 挂着 [key] 的组件在屏幕上的位置。还没布局时返回 null。
  static Rect? _globalRect(GlobalKey key) {
    final box = key.currentContext?.findRenderObject();
    if (box is! RenderBox || !box.hasSize) return null;
    return box.localToGlobal(Offset.zero) & box.size;
  }
}

/// 驱动"播放条 ⇄ 播放页"变形的一方：播放页的路由，或者手指从播放条往上拖、还没松手时的预览。
/// 播放页通过 [PlayerMorph.maybeOf] 拿到它，把大封面挂到 [artKey] 上。
mixin PlayerMorph {
  PlayerBarAnchor? get anchor;

  /// 播放页里大封面的 key，飞行封面的终点。
  final artKey = GlobalKey(debugLabel: 'player art');

  /// 封面还在飞的时候，播放页自己的封面先藏起来。
  late final artInFlight = ValueNotifier(anchor != null);

  /// 上一次量到的大封面位置（相对播放页）。预览交接给路由时带过去，路由第一帧还没排版也能用。
  Rect? lastArt;

  /// 形状顶边从播放条走到屏幕顶的距离，把手指位移换算成进度。
  double travel = 600;

  /// 变形进度变化时通知重建。
  Listenable get motion;

  /// 当前看到的变形进度，0 是播放条，1 是全屏播放页。
  double get progress;

  static PlayerMorph? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_MorphScope>()?.morph;
}

class _MorphScope extends InheritedWidget {
  const _MorphScope({required this.morph, required super.child});

  final PlayerMorph morph;

  @override
  bool updateShouldNotify(_MorphScope old) => morph != old.morph;
}

Duration _settle(double distance) => Duration(milliseconds: (160 + 300 * distance).round());

/// 播放条上"按住往上拖打开播放页"的手势。
///
/// 拖动途中不能推路由：Navigator 推页面时会取消屏幕上正在进行的触摸，手势就断了。
/// 所以拖的时候先在最上层画一份一模一样的变形预览跟手，松手要打开时再推真正的路由，
/// 从同一个进度接着展开，同一帧撤掉预览。
class PlayerBarDrag {
  PlayerBarDrag(this.anchor, this.vsync);

  final PlayerBarAnchor anchor;
  final TickerProvider vsync;
  _DragPreview? _preview;

  void update(BuildContext context, DragUpdateDetails d) {
    if (_preview == null) {
      if (d.delta.dy >= 0) return;
      _preview = _DragPreview(anchor, vsync)..show(context);
    }
    _preview!.dragUpdate(d.delta.dy);
  }

  void end(BuildContext context, double velocityY) {
    _preview?.release(context, velocityY);
    _preview = null;
  }
}

class _DragPreview with PlayerMorph {
  _DragPreview(this.anchor, TickerProvider vsync) : _controller = AnimationController(vsync: vsync);

  @override
  final PlayerBarAnchor anchor;
  final AnimationController _controller;
  OverlayEntry? _entry;

  @override
  Listenable get motion => _controller;

  @override
  double get progress => _controller.value;

  void show(BuildContext context) {
    anchor.hidden.value = true;
    // 手指一直按在播放条上，预览不接收点击
    _entry = OverlayEntry(builder: (_) => IgnorePointer(child: _BarMorph(morph: this, child: const PlayerPage())));
    Overlay.of(context, rootOverlay: true).insert(_entry!);
  }

  void dragUpdate(double dy) => _controller.value -= dy / travel;

  void release(BuildContext context, double velocityY) {
    final v = -velocityY / travel;
    final open = v.abs() > 1 ? v > 0 : _controller.value > 0.5;
    if (open) {
      Navigator.of(context, rootNavigator: true).push(
        PlayerRoute(anchor: anchor, startAt: _controller.value, artHint: lastArt),
      );
      _dispose();
    } else {
      _controller.animateBack(0, duration: _settle(_controller.value), curve: Curves.easeOutCubic).whenComplete(() {
        anchor.hidden.value = false;
        _dispose();
      });
    }
  }

  void _dispose() {
    _entry
      ?..remove()
      ..dispose();
    _entry = null;
    // 预览下一帧才真正卸载，卸载时还要从这两个上面摘监听
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _controller.dispose();
      artInFlight.dispose();
    });
  }
}

/// 播放页的路由。打开时播放条本身变形成播放页：形状从胶囊长到全屏，全程保持大圆角；
/// 页面内容按全屏排好，只跟着形状的顶边平移，所以底部的控制区是从下面滑上来的；
/// 封面单独从播放条飞到大封面的位置。播放页里上下拖可以直接拖动这个过程（[dragStart] 那一组）。
///
/// 用 ModalRoute 而不是 PageRoute：PageRoute 推上来的第一帧会被 Hero 机制挂成 offstage、
/// 动画临时接到"已完成"；下面的页面也不会跟着做页面切换的动画。
class PlayerRoute extends ModalRoute<void> with PlayerMorph {
  PlayerRoute({this.anchor, this.showQueue = false, this.startAt, Rect? artHint}) {
    lastArt = artHint;
  }

  @override
  final PlayerBarAnchor? anchor;

  final bool showQueue;

  /// 从拖动预览接手时的起始进度。
  final double? startAt;

  /// 手指或自己给曲线的动画在驱动时，变形直接用控制器的线性值。
  bool _manual = false;
  bool _dragging = false;

  late final CurvedAnimation _curved = CurvedAnimation(
    parent: controller!,
    curve: Curves.easeInOutCubicEmphasized,
    reverseCurve: Curves.easeInOutCubic,
  );

  @override
  Listenable get motion => controller!;

  @override
  double get progress => _manual ? controller!.value : _curved.value;

  @override
  Color? get barrierColor => null;

  @override
  bool get barrierDismissible => false;

  @override
  String? get barrierLabel => null;

  @override
  bool get opaque => false;

  @override
  bool get maintainState => true;

  @override
  Duration get transitionDuration => const Duration(milliseconds: 560);

  @override
  Duration get reverseTransitionDuration => const Duration(milliseconds: 460);

  @override
  void install() {
    super.install();
    controller!
      ..addListener(_onTick)
      ..addStatusListener(_onStatus);
  }

  @override
  TickerFuture didPush() {
    anchor?.hidden.value = true;
    final start = startAt;
    if (start == null) return super.didPush();
    // 接着拖动预览的进度往下展开
    controller!.value = start;
    super.didPush();
    _manual = true;
    return controller!.animateTo(1, duration: _settle(1 - start), curve: Curves.easeOutCubic);
  }

  void _onTick() => artInFlight.value = anchor != null && controller!.value < 1;

  void _onStatus(AnimationStatus status) {
    // 手指拖回起点也会是 dismissed，那时页面还在，不算结束
    if (_dragging) return;
    if (status.isCompleted || status.isDismissed) _manual = false;
    if (status.isDismissed && !isActive) anchor?.hidden.value = false;
  }

  @override
  void dispose() {
    anchor?.hidden.value = false;
    _curved.dispose();
    artInFlight.dispose();
    super.dispose();
  }

  /// 从播放条点开。
  static void open(BuildContext context, {PlayerBarAnchor? anchor, bool showQueue = false}) =>
      Navigator.of(context, rootNavigator: true).push(PlayerRoute(anchor: anchor, showQueue: showQueue));

  /// 手指按下：从当前看到的位置接管，曲线值和线性值之间不会跳。
  void dragStart() {
    final t = progress;
    _manual = true;
    _dragging = true;
    controller!
      ..stop()
      ..value = t;
  }

  /// 竖直方向的手指位移，往下为正。
  void dragUpdate(double dy) => controller!.value -= dy / travel;

  /// 松手：按速度或位置决定展开还是收回。
  void dragEnd(double velocityY) {
    final c = controller!;
    final v = -velocityY / travel;
    final open = v.abs() > 1 ? v > 0 : c.value > 0.5;
    _manual = true;
    _dragging = false;
    if (open) {
      c.animateTo(1, duration: _settle(1 - c.value), curve: Curves.easeOutCubic);
    } else {
      // pop 会先开一段线性的反向动画，紧接着换成带曲线的
      if (isCurrent) navigator!.pop();
      c.animateBack(0, duration: _settle(c.value), curve: Curves.easeOutCubic);
    }
  }

  @override
  Widget buildPage(BuildContext context, Animation<double> animation, Animation<double> secondaryAnimation) =>
      // 全屏沉浸：窗口按钮平时隐藏，鼠标移到顶部才出现
      ImmersiveTitleBar(child: PlayerPage(showQueue: showQueue));

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) => _BarMorph(morph: this, child: child);
}

class _BarMorph extends StatefulWidget {
  const _BarMorph({required this.morph, required this.child});

  final PlayerMorph morph;
  final Widget child;

  @override
  State<_BarMorph> createState() => _BarMorphState();
}

class _BarMorphState extends State<_BarMorph> {
  /// 包住整个播放页，大封面的位置相对它来量，不受变形时的平移影响。
  final _pageKey = GlobalKey();
  Rect? _start;

  /// 展开途中的圆角。
  static const _radius = 38.0;

  /// 大封面在播放页里的位置。播放页第一帧还没排版，就用上一次量到的。
  Rect? _artRect() {
    final morph = widget.morph;
    final art = morph.artKey.currentContext?.findRenderObject();
    final page = _pageKey.currentContext?.findRenderObject();
    if (art is RenderBox && page is RenderBox && art.hasSize && art.attached) {
      morph.lastArt = MatrixUtils.transformRect(art.getTransformTo(page), Offset.zero & art.size);
    }
    return morph.lastArt;
  }

  @override
  Widget build(BuildContext context) {
    final morph = widget.morph;
    final anchor = morph.anchor;
    return AnimatedBuilder(
      animation: morph.motion,
      child: _MorphScope(
        morph: morph,
        child: KeyedSubtree(key: _pageKey, child: widget.child),
      ),
      builder: (context, page) {
        final size = MediaQuery.sizeOf(context);
        final full = Offset.zero & size;
        // 没有播放条（测试、其他入口）时从屏幕底边升上来
        final start = _start = anchor?.rect ?? _start ?? Rect.fromLTWH(16, size.height, size.width - 32, 64);
        morph.travel = math.max(160, start.top);
        final t = morph.progress;
        final rect = Rect.lerp(start, full, t)!;
        // 全程大圆角，到全屏前的最后一小段才收成直角
        final radius = lerpDouble(start.shortestSide / 2, _radius, t)! * ((1 - t) / 0.06).clamp(0.0, 1.0);
        // 播放页在前 30% 里显出来，之后它不透明，底下的玻璃就不用画了
        final pageOpacity = anchor == null ? 1.0 : (t / 0.3).clamp(0.0, 1.0);
        final from = anchor != null && t < 1 ? anchor.coverRect : null;
        final art = from == null ? null : _artRect();
        return Stack(
          fit: StackFit.expand,
          children: [
            // 和播放条同一块玻璃，开头看起来就是播放条在长大
            if (anchor != null && t < 0.3)
              Positioned.fromRect(
                rect: rect,
                child: GlassContainer(
                  useOwnLayer: true,
                  settings: KanadeGlass.navigationSettings(context),
                  quality: KanadeGlass.navigationQuality,
                  shape: LiquidRoundedRectangle(borderRadius: radius),
                  child: const SizedBox.expand(),
                ),
              ),
            // 页面按全屏排好，只跟着形状的顶边平移、被形状裁剪；不缩放，每帧不用重新排版
            Transform.translate(
              // 前面的玻璃会增删，靠 key 对上，页面不被重建
              key: const ValueKey('page'),
              offset: Offset(0, rect.top),
              child: ClipRRect(
                clipper: _RRectClipper(
                  RRect.fromRectAndRadius(rect.translate(0, -rect.top), Radius.circular(radius)),
                ),
                clipBehavior: t >= 1 ? Clip.none : Clip.antiAlias,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Opacity(opacity: pageOpacity, child: page),
                    // 封面在屏幕上直接从播放条朝大封面的最终位置走（一路往上），再换算到页面里；
                    // 它始终在形状里面，也被形状裁住
                    if (from != null)
                      Positioned.fromRect(
                        rect: Rect.lerp(from, art ?? from, t)!.translate(0, -rect.top),
                        child: IgnorePointer(
                          child: _FlyingCover(radius: lerpDouble(anchor!.coverRadius, 14, t)!, t: t),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            // 播放条上的歌名和按钮跟着顶边走，很快淡掉
            if (anchor != null && t < 0.18)
              Positioned(
                left: rect.left,
                top: rect.top,
                width: start.width,
                height: start.height,
                child: IgnorePointer(
                  child: Opacity(opacity: 1 - t / 0.18, child: anchor.face(context)),
                ),
              ),
          ],
        );
      },
    );
  }
}

/// 飞行中的封面：小图一定已经缓存，大图到了就盖上去。
/// 投影随进度 [t] 从无长到大封面那样，落地换成真封面时不会突然冒出阴影。
class _FlyingCover extends StatelessWidget {
  const _FlyingCover({required this.radius, required this.t});

  final double radius;
  final double t;

  @override
  Widget build(BuildContext context) {
    final song = context.read<PlayerController>().current;
    if (song == null) return const SizedBox.shrink();
    final shadow = albumArtShadow(lifted: context.select<PlayerController, bool>((p) => p.playing));
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        boxShadow: [
          BoxShadow(
            color: shadow.color.withValues(alpha: shadow.color.a * t),
            offset: shadow.offset * t,
            blurRadius: shadow.blurRadius * t,
            spreadRadius: shadow.spreadRadius * t,
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: Stack(
          fit: StackFit.expand,
          children: [
            Cover(song.coverUrl, radius: 0),
            Cover(bigCoverUrl(song), radius: 0),
          ],
        ),
      ),
    );
  }
}

class _RRectClipper extends CustomClipper<RRect> {
  const _RRectClipper(this.rrect);

  final RRect rrect;

  @override
  RRect getClip(Size size) => rrect;

  @override
  bool shouldReclip(_RRectClipper old) => old.rrect != rrect;
}
