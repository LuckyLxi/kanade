import 'dart:async';
import 'dart:math';
import 'dart:ui' show ImageFilter, lerpDouble;

import 'package:material_ui/material_ui.dart';
import 'package:flutter/physics.dart';
import 'package:provider/provider.dart';

import '../l10n/l10n_ext.dart';
import '../player/player_controller.dart';
import '../src/rust/api/types.dart';

/// 音质切换：只列出当前歌曲实际可播放的档位。
/// 点一下按钮本身会用弹簧动画长成毛玻璃菜单，和音量条同一套质感；选完再缩回按钮。
class QualityMenu extends StatefulWidget {
  const QualityMenu({super.key});

  @override
  State<QualityMenu> createState() => _QualityMenuState();
}

class _QualityMenuState extends State<QualityMenu>
    with SingleTickerProviderStateMixin {
  static const _headerHeight = 34.0;
  static const _rowHeight = 44.0;
  static const _pad = 6.0;
  static const _menuWidth = 200.0;
  static const _menuRadius = 22.0;

  // 展开带一点回弹，收起不回弹、干脆利落
  static final _openSpring = SpringDescription.withDampingRatio(
    mass: 1,
    stiffness: 380,
    ratio: 0.68,
  );
  static final _closeSpring = SpringDescription.withDampingRatio(
    mass: 1,
    stiffness: 560,
    ratio: 1,
  );

  final _link = LayerLink();
  final _chipKey = GlobalKey();
  final _portal = OverlayPortalController();

  // 0 是按钮，1 是菜单；弹簧会冲过 1 一点，所以不设上下界
  late final _c = AnimationController.unbounded(vsync: this);
  Size _chipSize = Size.zero;
  bool _expanded = false;

  /// 刚点中、还没收起的那一档，白色选中块先滑过去再收。
  Quality? _picked;

  Animation<double>? _route;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context)?.animation;
    if (route == _route) return;
    _route?.removeStatusListener(_onRouteStatus);
    _route = route?..addStatusListener(_onRouteStatus);
  }

  /// 播放页开始收起时菜单跟着缩回按钮，不留在最上层。
  void _onRouteStatus(AnimationStatus status) {
    if (status == AnimationStatus.reverse) unawaited(_close());
  }

  @override
  void dispose() {
    _route?.removeStatusListener(_onRouteStatus);
    _c.dispose();
    super.dispose();
  }

  void _open() {
    final box = _chipKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return;
    setState(() {
      _chipSize = box.size;
      _expanded = true;
      _picked = null;
    });
    _portal.show();
    unawaited(
      _c.animateWith(SpringSimulation(_openSpring, _c.value, 1, _c.velocity)),
    );
  }

  Future<void> _close() async {
    if (!_expanded) return;
    _expanded = false;
    await _c.animateBackWith(
      SpringSimulation(_closeSpring, _c.value, 0, _c.velocity, snapToEnd: true),
    );
    if (!mounted || _expanded) return;
    _portal.hide();
    setState(() => _picked = null);
  }

  Future<void> _pick(PlayerController p, Quality q) async {
    setState(() => _picked = q);
    unawaited(p.setQuality(q));
    await Future<void>.delayed(const Duration(milliseconds: 220));
    if (mounted) await _close();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.watch<PlayerController>();
    final l = AppLocalizations.of(context);
    final actual = p.actualQuality;
    // 请求的音质没权限时 Rust 层会自动降级，按钮上只显示实际在播的档位
    final label = actual == null ? l.quality : qualityLabel(l, actual);
    final options = p.qualityOptions
        .where((option) => option.available)
        .toList();
    return OverlayPortal(
      controller: _portal,
      overlayChildBuilder: (_) => _buildMenu(p, l, label, options),
      child: CompositedTransformTarget(
        link: _link,
        // 展开期间按钮本体让给菜单，原位置留空
        child: Opacity(
          opacity: _portal.isShowing ? 0 : 1,
          child: Tooltip(
            message: p.qualitiesLoading
                ? l.qualityLoading
                : p.qualitiesError != null
                ? l.qualityFailed(errorText(l, p.qualitiesError!))
                : options.isEmpty
                ? l.qualityNoneForSong
                : l.quality,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: p.qualitiesLoading ? null : _open,
              child: Container(
                key: _chipKey,
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                decoration: const ShapeDecoration(
                  color: Color(0x1FFFFFFF),
                  shape: StadiumBorder(),
                ),
                child: _chipContent(label, loading: p.qualitiesLoading),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _chipContent(String label, {bool loading = false}) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.graphic_eq_rounded, size: 13, color: Colors.white70),
        const SizedBox(width: 4),
        Flexible(
          child: Text(
            label,
            maxLines: 1,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: Colors.white70,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
        if (loading)
          const Padding(
            padding: EdgeInsets.only(left: 5),
            child: SizedBox.square(
              dimension: 10,
              child: CircularProgressIndicator(
                strokeWidth: 1.5,
                color: Colors.white70,
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildMenu(
    PlayerController p,
    AppLocalizations l,
    String label,
    List<QualityOption> options,
  ) {
    final error = p.qualitiesError != null;
    final count = error || options.isEmpty ? 1 : options.length;
    final selected = _picked ?? p.actualQuality;
    final selectedIndex = error
        ? -1
        : options.indexWhere((o) => o.quality == selected);
    final menuSize = Size(
      max(_menuWidth, _chipSize.width),
      _headerHeight + count * _rowHeight + _pad * 2,
    );

    return Stack(
      children: [
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => unawaited(_close()),
          ),
        ),
        CompositedTransformFollower(
          link: _link,
          // 播放页收起时按钮不再绘制，菜单别跑到左上角去
          showWhenUnlinked: false,
          // 以按钮底边中点为锚，菜单从按钮所在位置往上长出来
          targetAnchor: Alignment.bottomCenter,
          followerAnchor: Alignment.bottomCenter,
          child: AnimatedBuilder(
            animation: _c,
            builder: (_, _) {
              final v = _c.value;
              final t = v.clamp(0.0, 1.0);
              double fade(double from, double to) =>
                  ((v - from) / (to - from)).clamp(0.0, 1.0);
              // 选项一行接一行浮上来，行多的时候间隔压缩，保证在弹簧到位前都出来
              final step = min(0.06, 0.3 / count);
              final chipFade = 1 - fade(0, 0.3);

              Widget appear(int i, Widget child) {
                final a = Curves.easeOut.transform(
                  fade(0.3 + i * step, 0.7 + i * step),
                );
                return Opacity(
                  opacity: a,
                  child: Transform.translate(
                    offset: Offset(0, 10 * (1 - a)),
                    child: child,
                  ),
                );
              }

              final rows = <Widget>[
                if (error)
                  _row(
                    l.qualityFailedRetry,
                    onTap: () {
                      unawaited(p.refreshQualities());
                      unawaited(_close());
                    },
                  )
                else if (options.isEmpty)
                  _row(l.qualityNone)
                else
                  for (final option in options)
                    _row(
                      qualityLabel(l, option.quality),
                      selected: option.quality == selected,
                      onTap: () => unawaited(_pick(p, option.quality)),
                    ),
              ];

              final menu = Padding(
                padding: const EdgeInsets.all(_pad),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Opacity(
                      opacity: fade(0.25, 0.65),
                      child: SizedBox(
                        height: _headerHeight,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          child: Row(
                            children: [
                              const Icon(
                                Icons.graphic_eq_rounded,
                                size: 15,
                                color: Colors.white54,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                l.quality,
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.white54,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    Stack(
                      children: [
                        // 白底选中块：换档时滑到新的一行
                        if (selectedIndex >= 0)
                          AnimatedPositioned(
                            duration: const Duration(milliseconds: 260),
                            curve: Curves.easeOutCubic,
                            left: 0,
                            right: 0,
                            top: selectedIndex * _rowHeight,
                            height: _rowHeight,
                            child: Opacity(
                              opacity: fade(0.35, 0.75),
                              child: const DecoratedBox(
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.all(
                                    Radius.circular(_menuRadius - _pad),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            for (var i = 0; i < rows.length; i++)
                              appear(i, rows[i]),
                          ],
                        ),
                      ],
                    ),
                  ],
                ),
              );

              final w = lerpDouble(_chipSize.width, menuSize.width, v)!;
              final h = lerpDouble(_chipSize.height, menuSize.height, v)!;
              return SizedBox(
                width: w,
                height: h,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(_menuRadius),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.28 * t),
                        blurRadius: 30 * t,
                        offset: Offset(0, 10 * t),
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(
                      lerpDouble(_chipSize.height / 2, _menuRadius, t)!,
                    ),
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 24 * t, sigmaY: 24 * t),
                      child: ColoredBox(
                        color: Colors.white.withValues(
                          alpha: lerpDouble(0.12, 0.16, t)!,
                        ),
                        child: Stack(
                          children: [
                            if (chipFade > 0)
                              Positioned.fill(
                                child: Opacity(
                                  opacity: chipFade,
                                  child: Center(child: _chipContent(label)),
                                ),
                              ),
                            if (v > 0.25)
                              Positioned.fill(
                                child: OverflowBox(
                                  alignment: Alignment.bottomCenter,
                                  minWidth: menuSize.width,
                                  maxWidth: menuSize.width,
                                  minHeight: menuSize.height,
                                  maxHeight: menuSize.height,
                                  child: menu,
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  /// 「高品质 320k」拆成名字和规格两段，规格靠右用小字。
  Widget _row(String text, {bool selected = false, VoidCallback? onTap}) {
    final split = text.lastIndexOf(' ');
    final name = split > 0 ? text.substring(0, split) : text;
    final spec = split > 0 ? text.substring(split + 1) : null;
    final color = onTap == null
        ? Colors.white38
        : selected
        ? Colors.black
        : Colors.white;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: SizedBox(
        height: _rowHeight,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            children: [
              Expanded(
                child: AnimatedDefaultTextStyle(
                  duration: const Duration(milliseconds: 200),
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                    color: color,
                  ),
                  child: Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
              if (spec != null)
                AnimatedDefaultTextStyle(
                  duration: const Duration(milliseconds: 200),
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: color.withValues(alpha: selected ? 0.55 : 0.5),
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                  child: Text(spec),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
