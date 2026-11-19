import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show lerpDouble;

import 'package:flutter/physics.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'package:provider/provider.dart';

import '../data/data_ext.dart';
import '../l10n/l10n_ext.dart';
import '../player/player_controller.dart';
import '../src/rust/api/types.dart';
import 'glass.dart';
import 'play_pause_button.dart';
import 'player_background.dart';
import 'player_route.dart';
import 'widgets.dart';

/// 浮在底部导航上方的玻璃胶囊播放条。外壳用 Positioned 给它当前的矩形，
/// 形状的过渡由外壳驱动：[faceOpacity] 是歌名和按钮的显示程度，[coverShift] 把封面从左端挪到右端；
/// [round] 时是导航栏旁边的圆球，只剩封面，点一下 [onExpand] 恢复。
/// 胶囊上点一下或按住往上拖打开播放页，手机上左右滑切歌。
/// 里面的按钮都是普通按钮：玻璃里再套玻璃会双重折射，还费 GPU。
class MiniPlayer extends StatefulWidget {
  const MiniPlayer({
    super.key,
    this.round = false,
    this.faceOpacity = 1,
    this.coverShift = 0,
    this.capsuleWidth,
    this.onExpand,
    this.barAnchor,
    this.grouped = false,
    this.faceStagger = false,
  });

  static const height = 64.0;
  static const _coverSize = 44.0;
  static const _circleCover = 46.0;

  /// 底部导航上方那条播放条的锚点，播放页从这里变形出来。
  static final anchor = newAnchor();

  /// 另外摆一条播放条时（比如从播放页进的歌手页）给它自己的锚点。
  static PlayerBarAnchor newAnchor() => PlayerBarAnchor(
    coverRadius: _coverSize / 2,
    face: (_) =>
        const Material(type: MaterialType.transparency, child: _MiniFace()),
  );

  /// 不给就是 [MiniPlayer.anchor]。
  final PlayerBarAnchor? barAnchor;

  final bool round;
  final double faceOpacity;
  final double coverShift;

  /// 胶囊状态的宽度。歌名按它排版，收成圆的途中只被裁掉，不会重新换行。
  final double? capsuleWidth;

  final VoidCallback? onExpand;

  /// 玻璃不自己建一层，加入外面的 [AdaptiveLiquidGlassLayer]，和导航栏融成一块。
  final bool grouped;

  /// 歌名和按钮按 [faceOpacity] 错开出现，而不是整块一起淡入淡出。
  final bool faceStagger;

  @override
  State<MiniPlayer> createState() => _MiniPlayerState();
}

class _MiniPlayerState extends State<MiniPlayer> with TickerProviderStateMixin {
  /// 左右滑时歌名跟着手指的位移。
  late final _swipe = AnimationController.unbounded(vsync: this);

  /// 歌名拖过这么远，松手就切歌。
  static const _switchDistance = 56.0;

  /// 拖着时已经够切歌的方向：-1 下一首（往左），1 上一首，0 不够远。
  final _armed = ValueNotifier(0);

  void _updateArmed() {
    final dx = _swipe.value;
    final armed = dx <= -_switchDistance
        ? -1
        : dx >= _switchDistance
        ? 1
        : 0;
    if (armed == _armed.value) return;
    if (armed != 0) HapticFeedback.lightImpact();
    _armed.value = armed;
  }

  /// 左右滑时手指离起点的位移，上下也算；整条带阻尼地跟着挪一点。
  /// 松手时 [_nudge] 从 1 弹到 0 把它收回。
  /// 不用 [_swipe]，它切歌时会从一边跳到另一边。
  final _finger = ValueNotifier(Offset.zero);
  Offset _fingerOrigin = Offset.zero;
  late final _nudge = AnimationController.unbounded(vsync: this);

  /// 橡皮筋：开头跟手指的 0.3，越拖越拖不动，慢慢逼近 10 但碰不到；
  /// 手指拖 56 时挪 6，拖 120 时挪 8。
  static double _damp(double d) {
    const limit = 10.0, c = 0.3;
    final x = d.abs() * c;
    return d.sign * limit * x / (x + limit);
  }

  late final _anchor = widget.barAnchor ?? MiniPlayer.anchor;
  late final _drag = PlayerBarDrag(_anchor, this);
  late final _visibility = Listenable.merge([_anchor.hidden, _anchor.growing]);

  /// 按住时整条轻微放大，松手回弹；值就是缩放，弹簧接着当前速度走。
  late final AnimationController _press = AnimationController.unbounded(
    vsync: this,
    value: 1,
  )..addListener(() => _anchor.pressScale.value = _press.value);
  static const _pressedScale = 1.03;
  static final _pressSpring = SpringDescription.withDampingRatio(
    mass: 1,
    stiffness: 420,
    ratio: 0.75,
  );
  static final _releaseSpring = SpringDescription.withDampingRatio(
    mass: 1,
    stiffness: 260,
    ratio: 0.5,
  );

  void _springTo(double target, SpringDescription spring) => _press.animateWith(
    // 停下时正好落在目标上，松手后回到 1 才不留一点点缩放
    SpringSimulation(
      spring,
      _press.value,
      target,
      _press.velocity,
      snapToEnd: true,
    ),
  );

  @override
  void dispose() {
    _swipe.dispose();
    _nudge.dispose();
    _finger.dispose();
    _armed.dispose();
    _press.dispose();
    _anchor.pressScale.value = 1;
    super.dispose();
  }

  void _onPointerDown(PointerDownEvent _) =>
      _springTo(_pressedScale, _pressSpring);

  void _release() => _springTo(1, _releaseSpring);

  void _settleNudge() {
    _armed.value = 0;
    _nudge.animateWith(
      SpringSimulation(_releaseSpring, _nudge.value, 0, 0, snapToEnd: true),
    );
  }

  /// 松手才切：歌名滑出去，换成下一首从另一边滑进来；不够远就弹回。
  Future<void> _onSwipeEnd(DragEndDetails d) async {
    _settleNudge();
    final p = context.read<PlayerController>();
    final v = d.velocity.pixelsPerSecond.dx;
    final dx = _swipe.value;
    final next = dx < -_switchDistance || v < -500;
    final previous = !next && (dx > _switchDistance || v > 500);
    if (!next && !previous) {
      await _swipe.animateTo(
        0,
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOutCubic,
      );
      return;
    }
    unawaited(next ? p.next() : p.previous());
    const out = 140.0;
    await _swipe.animateTo(
      next ? -out : out,
      duration: const Duration(milliseconds: 140),
      curve: Curves.easeIn,
    );
    if (!mounted) return;
    _swipe.value = next ? out : -out;
    await _swipe.animateTo(
      0,
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    final song = context.select<PlayerController, Song?>((p) => p.current);
    if (song == null) return const SizedBox.shrink();
    prefetchPlayerArt(context, song);
    final round = widget.round;
    final swipe = touchPlatform && !round;
    final bar = GestureDetector(
      key: _anchor.barKey,
      behavior: HitTestBehavior.opaque,
      onTap: round
          ? widget.onExpand
          : () => PlayerRoute.open(context, anchor: _anchor),
      onVerticalDragUpdate: round ? null : (d) => _drag.update(context, d),
      onVerticalDragEnd: round
          ? null
          : (d) => _drag.end(context, d.velocity.pixelsPerSecond.dy),
      onVerticalDragCancel: round ? null : () => _drag.end(context, 0),
      // 横向拖动赢下手势后竖直方向的拖不再打开播放页，只让整条跟着挪
      onHorizontalDragStart: swipe
          ? (d) {
              _swipe.stop();
              _nudge.stop();
              // 还在弹回时接着当前的位置拖
              _finger.value *= _nudge.value;
              _nudge.value = 1;
              _fingerOrigin = d.globalPosition - _finger.value;
            }
          : null,
      onHorizontalDragUpdate: swipe
          ? (d) {
              _swipe.value += d.delta.dx;
              _finger.value = d.globalPosition - _fingerOrigin;
              _updateArmed();
            }
          : null,
      onHorizontalDragEnd: swipe ? _onSwipeEnd : null,
      onHorizontalDragCancel: swipe ? _settleNudge : null,
      child: Listener(
        behavior: HitTestBehavior.opaque,
        onPointerDown: _onPointerDown,
        onPointerUp: (_) => _release(),
        onPointerCancel: (_) => _release(),
        child: LayoutBuilder(
          builder: (context, box) {
            final w = box.maxWidth, h = box.maxHeight;
            // 胶囊里 44，圆球和导航栏那么高时 46
            final d = lerpDouble(
              MiniPlayer._coverSize,
              MiniPlayer._circleCover,
              ((MiniPlayer.height - h) / 6).clamp(0.0, 1.0),
            )!;
            final face = widget.faceOpacity.clamp(0.0, 1.0);
            final content = _PressScale(
              anchor: _anchor,
              child: Material(
                type: MaterialType.transparency,
                child: Stack(
                  children: [
                    if (widget.faceOpacity > 0)
                      Positioned(
                        left: 0,
                        top: (h - MiniPlayer.height) / 2,
                        width: widget.capsuleWidth ?? w,
                        height: MiniPlayer.height,
                        child: widget.faceStagger
                            ? _MiniFace(
                                swipe: _swipe,
                                armed: _armed,
                                reveal: face,
                              )
                            : Opacity(
                                opacity: face,
                                child: _MiniFace(swipe: _swipe, armed: _armed),
                              ),
                      ),
                    Positioned(
                      // 封面平时待在左端的半圆里，收成圆时是右边缩进来
                      left: lerpDouble(
                        (h - d) / 2,
                        w - (h + d) / 2,
                        widget.coverShift,
                      ),
                      top: (h - d) / 2,
                      width: d,
                      height: d,
                      child: KeyedSubtree(
                        key: _anchor.coverKey,
                        child: Cover(
                          song.coverUrl,
                          size: d,
                          radius: d / 2,
                          keepPrevious: true,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
            // 变形开头玻璃跟着长成播放页的形状，歌名和封面这时由转场层画
            return PlayerBarGrowth(
              anchor: _anchor,
              builder: (growing, shapeT) {
                final shape = LiquidRoundedRectangle(
                  borderRadius: PlayerMorph.radiusAt(
                    math.min(w, h) * _anchor.pressScale.value,
                    shapeT,
                  ),
                );
                final inner = Opacity(
                  opacity: growing ? 0 : 1,
                  child: PlayerBarGrowth.pin(content),
                );
                if (!widget.grouped) {
                  return GlassContainer(
                    useOwnLayer: true,
                    settings: KanadeGlass.navigationSettings(context),
                    quality: KanadeGlass.navigationQuality,
                    shape: shape,
                    clipBehavior: Clip.antiAlias,
                    child: inner,
                  );
                }
                // 分组的玻璃连同里面的内容都由外面的玻璃层来画，外面套 Opacity 藏不住；
                // 播放页盖上来时干脆不挂玻璃，只留透明的内容占位
                return ValueListenableBuilder(
                  valueListenable: _anchor.hidden,
                  child: inner,
                  builder: (_, hidden, inner) => hidden && !growing
                      ? inner!
                      : GlassContainer(
                          quality: KanadeGlass.navigationQuality,
                          shape: shape,
                          clipBehavior: Clip.antiAlias,
                          child: inner,
                        ),
                );
              },
            );
          },
        ),
      ),
    );
    // 播放页盖在上面时由转场层画它，这里藏起来；变形开头只留长大的玻璃
    return ListenableBuilder(
      listenable: _visibility,
      child: AnimatedBuilder(
        animation: Listenable.merge([_nudge, _finger]),
        child: bar,
        builder: (_, bar) {
          final f = _finger.value * _nudge.value;
          return Transform.translate(
            offset: Offset(_damp(f.dx), _damp(f.dy)),
            child: bar,
          );
        },
      ),
      builder: (_, bar) => Opacity(
        opacity: _anchor.hidden.value && _anchor.growing.value == null ? 0 : 1,
        child: bar,
      ),
    );
  }
}

/// 按下时里面的内容跟着放大；玻璃本身由 [PlayerBarGrowth] 按 [PlayerBarAnchor.pressScale] 排大。
/// 一直跟着 [PlayerBarAnchor.pressScale]，不在变形途中切换：飞行封面从这里量起点，中途变了就会跳。
class _PressScale extends StatelessWidget {
  const _PressScale({required this.anchor, required this.child});

  final PlayerBarAnchor anchor;
  final Widget child;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder(
    valueListenable: anchor.pressScale,
    child: child,
    builder: (_, scale, child) => Transform.scale(scale: scale, child: child),
  );
}

/// 胶囊上除封面以外的部分：歌名、播放键（桌面没有手势，再加上一首 / 下一首）、进度线。
class _MiniFace extends StatelessWidget {
  const _MiniFace({this.swipe, this.armed, this.reveal});

  final Animation<double>? swipe;

  /// 见 [_MiniPlayerState._armed]，够切歌时在歌名让开的地方提示上一首 / 下一首。
  final ValueNotifier<int>? armed;

  /// 给了就错开出现：歌名先从左边滑进来，按钮晚一点弹出来；不给就是整块一起显示。
  final double? reveal;

  @override
  Widget build(BuildContext context) {
    final p = context.watch<PlayerController>();
    final song = p.current;
    if (song == null) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    final reveal = this.reveal;
    final titleIn = reveal == null
        ? 1.0
        : const Interval(0, 0.7).transform(reveal.clamp(0.0, 1.0));
    final buttonsIn = reveal == null
        ? 1.0
        : const Interval(0.3, 1).transform(reveal.clamp(0.0, 1.0));
    Widget pop(Widget button) {
      return buttonsIn >= 1
          ? button
          : Opacity(
              opacity: buttonsIn,
              child: Transform.scale(
                scale: 0.6 + 0.4 * Curves.easeOutBack.transform(buttonsIn),
                child: button,
              ),
            );
    }

    Widget title = Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          song.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
        ),
        Text(
          p.error == null
              ? singerNames(song)
              : playerErrorText(AppLocalizations.of(context), p.error!),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 12,
            color: p.error != null ? scheme.error : scheme.onSurfaceVariant,
          ),
        ),
      ],
    );
    final swipe = this.swipe;
    if (swipe != null) {
      title = AnimatedBuilder(
        animation: swipe,
        child: title,
        builder: (_, title) => Transform.translate(
          offset: Offset(swipe.value, 0),
          child: Opacity(
            opacity: (1 - swipe.value.abs() / 140).clamp(0.0, 1.0),
            child: title,
          ),
        ),
      );
      final armed = this.armed;
      if (armed != null) {
        final l10n = AppLocalizations.of(context);
        // 出现在歌名让开的那一边
        Widget hint(int side, String text) => Positioned.fill(
          child: Align(
            alignment: side < 0 ? Alignment.centerRight : Alignment.centerLeft,
            child: ValueListenableBuilder(
              valueListenable: armed,
              child: Text(
                text,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: scheme.onSurfaceVariant,
                ),
              ),
              builder: (_, a, child) => AnimatedOpacity(
                opacity: a == side ? 1 : 0,
                duration: const Duration(milliseconds: 150),
                child: AnimatedScale(
                  scale: a == side ? 1 : 0.85,
                  duration: const Duration(milliseconds: 150),
                  curve: Curves.easeOutBack,
                  child: child,
                ),
              ),
            ),
          ),
        );
        title = Stack(
          children: [
            title,
            hint(-1, l10n.nextSong),
            hint(1, l10n.previousSong),
          ],
        );
      }
      title = ClipRect(child: title);
    }
    if (titleIn < 1) {
      title = Opacity(
        opacity: titleIn,
        child: Transform.translate(
          offset: Offset((1 - titleIn) * -10, 0),
          child: title,
        ),
      );
    }
    return Stack(
      children: [
        Row(
          children: [
            const SizedBox(width: 10 + MiniPlayer._coverSize + 12),
            Expanded(child: title),
            if (!touchPlatform)
              pop(
                IconButton(
                  onPressed: p.previous,
                  icon: Icon(
                    Icons.skip_previous_rounded,
                    color: scheme.onSurface,
                  ),
                ),
              ),
            pop(
              PlayPauseButton(
                dimension: 40,
                playing: p.playing,
                loading: p.loading || p.buffering,
                onPressed: p.toggle,
              ),
            ),
            if (!touchPlatform)
              pop(
                IconButton(
                  onPressed: p.next,
                  icon: Icon(Icons.skip_next_rounded, color: scheme.onSurface),
                ),
              ),
            // 手机上播放键和胶囊右端的半圆同心
            SizedBox(width: touchPlatform ? 12 : 8),
          ],
        ),
        // 进度线只画在胶囊的直边上；手机上不画
        if (!touchPlatform)
          Positioned(
            left: MiniPlayer.height / 2,
            right: MiniPlayer.height / 2,
            bottom: 0,
            child: Opacity(
              opacity: titleIn,
              child: ValueListenableBuilder(
                valueListenable: p.position,
                builder: (_, pos, _) => LinearProgressIndicator(
                  minHeight: 2,
                  backgroundColor: scheme.onSurface.withValues(alpha: 0.12),
                  value: p.duration.inMilliseconds == 0
                      ? 0
                      : (pos.inMilliseconds / p.duration.inMilliseconds).clamp(
                          0.0,
                          1.0,
                        ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
