import 'dart:math' as math;
import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'package:provider/provider.dart';

import '../l10n/app_localizations.dart';
import '../player/player_controller.dart';
import '../src/rust/api/types.dart';
import 'desktop_shell.dart';
import 'discover_page.dart';
import 'glass.dart';
import 'mine_page.dart';
import 'mini_player.dart';
import 'overlay_layout_state.dart';
import 'search_page.dart';
import 'song_list_page.dart';
import 'widgets.dart';

/// 底部（窄屏）或侧边（宽屏）导航。每个标签页有自己的 Navigator，
/// 这样进入歌单详情时迷你播放条仍然保留。
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> with TickerProviderStateMixin {
  int _tab = 0;
  final _keys = List.generate(3, (_) => GlobalKey<NavigatorState>());
  late final _depths = List.generate(3, (_) => _DepthObserver(_onDepthChanged));

  /// 当前标签页进了二级页面（歌单、设置……）时收起底部导航。
  bool get _nested => _depths[_tab].depth > 1;

  // 观察者的回调可能发生在构建期间，推到这一帧结束后再刷新
  void _onDepthChanged() => WidgetsBinding.instance.addPostFrameCallback((_) {
    if (mounted) setState(() {});
  });

  static List<(IconData, IconData, String)> _destinations(AppLocalizations l) => [
    (Icons.explore_outlined, Icons.explore, l.tabDiscover),
    (Icons.search, Icons.search, l.tabSearch),
    (Icons.person_outline, Icons.person, l.tabMine),
  ];

  Widget _tabNavigator(int i, Widget root) => Navigator(
    key: _keys[i],
    observers: [_depths[i]],
    onGenerateRoute: (_) => MaterialPageRoute(builder: (_) => root),
  );

  void _select(int i) {
    if (i == _tab) {
      _keys[i].currentState?.popUntil((r) => r.isFirst);
    } else {
      setState(() => _tab = i);
    }
  }

  /// 侧栏点开的歌单，用来判断是不是又点了正在看的那个。
  (String, Route<void>)? _sidebarPlaylist;

  /// 侧栏点歌单：替换掉当前标签里已经打开的页面，不往上叠，返回时直接回到发现/搜索/我的。
  void _openSidebarPlaylist(PlaylistBrief p) {
    final nav = _keys[_tab].currentState;
    if (nav == null) return;
    final open = _sidebarPlaylist;
    if (open != null && open.$1 == p.id && open.$2.isCurrent) return;
    final route = SongListPage.playlist(p.id, p.title);
    _sidebarPlaylist = (p.id, route);
    nav.pushAndRemoveUntil(route, (r) => r.isFirst);
  }

  /// 手机上滚动页面时播放条收成导航栏右边的圆球，只有点圆球才恢复。
  bool _collapsed = false;
  bool _hadSong = false;
  double _scrolled = 0;

  /// 播放条的形状：0 胶囊，1 圆球。用弹簧驱动，会稍微冲过头再回来。
  late final _shape = AnimationController.unbounded(vsync: this);

  /// 进二级页面的第一段：导航栏和播放条融成一整块（0 分开，1 融合成导航栏那么大的一块）。
  late final _fuse = AnimationController(vsync: this, duration: const Duration(milliseconds: 300));

  /// 第二段：融合后的那一块弹成底部的胶囊（0 导航栏的形状，1 底部胶囊）。
  late final _drop = AnimationController.unbounded(vsync: this);

  /// 播放条第一次出现：从导航栏右端分裂出来。
  late final _appear = AnimationController(vsync: this, duration: const Duration(milliseconds: 640), value: 1);
  double _shapeTarget = 0;
  bool _nestedShown = false;
  int _nestedRun = 0;

  static final _spring = SpringDescription.withDampingRatio(mass: 1, stiffness: 420, ratio: 0.72);
  static final _springBack = SpringDescription.withDampingRatio(mass: 1, stiffness: 520, ratio: 0.95);

  /// 收成圆球慢一点，展开回胶囊还是用快的。
  static final _springCollapse = SpringDescription.withDampingRatio(mass: 1, stiffness: 190, ratio: 0.8);

  @override
  void initState() {
    super.initState();
    MiniPlayer.anchor.hidden.addListener(_reportPlayerVisibility);
    DesktopPlayerBar.anchor.hidden.addListener(_reportPlayerVisibility);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _reportPlayerVisibility();
    });
  }

  void _reportPlayerVisibility() {
    OverlayLayoutState.instance.playerVisible.value =
        MiniPlayer.anchor.hidden.value || DesktopPlayerBar.anchor.hidden.value;
  }

  @override
  void dispose() {
    MiniPlayer.anchor.hidden.removeListener(_reportPlayerVisibility);
    DesktopPlayerBar.anchor.hidden.removeListener(_reportPlayerVisibility);
    _shape.dispose();
    _fuse.dispose();
    _drop.dispose();
    _appear.dispose();
    super.dispose();
  }

  TickerFuture _springTo(AnimationController c, double target, SpringDescription spring) =>
      c.animateWith(SpringSimulation(spring, c.value, target, c.velocity));

  void _syncChrome(bool hasSong) {
    if (hasSong && !_hadSong) {
      _collapsed = touchPlatform;
      _shapeTarget = _collapsed ? 1 : 0;
      _shape.value = _shapeTarget;
      _nestedShown = _nested;
      _fuse.value = _drop.value = _nested ? 1 : 0;
      _appear.forward(from: 0);
    }
    _hadSong = hasSong;
    final shape = _collapsed ? 1.0 : 0.0;
    if (shape != _shapeTarget) {
      _shapeTarget = shape;
      _springTo(_shape, shape, shape == 1 ? _springCollapse : _spring);
    }
    if (_nested != _nestedShown) {
      _nestedShown = _nested;
      _runNested(_nested);
    }
  }

  /// 进二级页面：先融合（圆球滑进导航栏连成一块，封面快速挪到左端），再弹成底部的胶囊。
  /// 退出来倒着走：胶囊缩回导航栏的形状，再从右端分裂出圆球。
  Future<void> _runNested(bool nested) async {
    final run = ++_nestedRun;
    try {
      if (nested) {
        if (_fuse.value < 1) {
          await _fuse.animateTo(1, curve: Curves.easeInOutCubic).orCancel;
        }
        if (run == _nestedRun) await _springTo(_drop, 1, _spring).orCancel;
      } else {
        if (_drop.value.abs() > 0.001) await _springTo(_drop, 0, _springBack).orCancel;
        _drop.value = 0;
        if (run == _nestedRun) await _fuse.animateBack(0, curve: Curves.easeInOutCubic).orCancel;
      }
    } on TickerCanceled {
      // 半路又切回去了，新的那一轮接着当前的位置走
    }
  }

  /// 上下滑页面（手指拖动的）超过一点距离就收起播放条。
  bool _onScroll(ScrollNotification n) {
    if (!touchPlatform || _collapsed || _nested || !_hadSong || n.metrics.axis != Axis.vertical) return false;
    if (n is ScrollStartNotification) _scrolled = 0;
    final delta = switch (n) {
      ScrollUpdateNotification(dragDetails: != null, :final scrollDelta) => scrollDelta ?? 0,
      OverscrollNotification(dragDetails: != null, :final overscroll) => overscroll,
      _ => 0.0,
    };
    _scrolled += delta.abs();
    if (_scrolled > 24) setState(() => _collapsed = true);
    return false;
  }

  /// 告诉提示浮在哪：在导航栏和播放条之外。构建期间不能通知监听者，推到这一帧之后。
  void _reportChrome(EdgeInsets insets) {
    if (OverlayLayoutState.instance.chrome.value == insets) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) OverlayLayoutState.instance.chrome.value = insets;
    });
  }

  /// 玻璃条浮在内容上方，内容本身铺满全屏；把被遮住的高度加进 padding，
  /// 列表滚到底时最后一项才不会藏在玻璃条下面。
  Widget _insetBottom(BuildContext context, double inset, Widget child) {
    final mq = MediaQuery.of(context);
    return MediaQuery(
      data: mq.copyWith(padding: mq.padding.copyWith(bottom: mq.padding.bottom + inset)),
      child: child,
    );
  }

  @override
  Widget build(BuildContext context) {
    // 桌面播放栏两侧是固定宽度，太窄放不下，窄于 960 用手机布局
    final wide = MediaQuery.sizeOf(context).width >= 960;
    final hasSong = context.select<PlayerController, bool>((p) => p.current != null);
    _syncChrome(hasSong);
    final scheme = Theme.of(context).colorScheme;
    final destinations = _destinations(AppLocalizations.of(context));
    final body = _TabSwitcher(
      index: _tab,
      children: [
        _tabNavigator(0, const DiscoverPage()),
        _tabNavigator(1, const SearchPage()),
        _tabNavigator(2, const MinePage()),
      ],
    );

    final Widget content;
    if (wide) {
      // 左侧实心侧栏 + 底部整宽玻璃播放栏，侧栏底部让出播放栏的位置
      const gap = 12.0;
      final mq = MediaQuery.of(context);
      // 桌面播放栏常驻，还没放过歌时显示空状态
      const barSpace = DesktopPlayerBar.height + gap * 2;
      // 播放栏和窗口一样宽，提示在整个窗口居中，正好对着中间的播放键
      _reportChrome(EdgeInsets.only(bottom: mq.padding.bottom + barSpace));
      content = Material(
        color: scheme.surface,
        child: KanadeGlass.backdropScope(
          child: Stack(
            children: [
              Positioned.fill(
                child: KanadeGlass.backdropSource(
                  captureBounds: (size) => Rect.fromLTRB(0, size.height - barSpace - 32, size.width, size.height),
                  child: ColoredBox(
                    color: scheme.surface,
                    child: Row(
                      children: [
                        Padding(
                          padding: EdgeInsets.fromLTRB(gap, mq.padding.top + 8, 0, mq.padding.bottom + barSpace),
                          child: SizedBox(
                            width: DesktopSidebar.width,
                            child: DesktopSidebar(
                              destinations: destinations,
                              selected: _tab,
                              onSelect: _select,
                              onOpenPlaylist: _openSidebarPlaylist,
                            ),
                          ),
                        ),
                        Expanded(
                          child: _insetBottom(context, barSpace, body),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              Positioned(
                left: gap,
                right: gap,
                bottom: gap + mq.padding.bottom,
                child: const DesktopPlayerBar(),
              ),
            ],
          ),
        ),
      );
    } else {
      const navPad = 6.0;
      const navHeight = KanadeGlass.navigationControlHeight + navPad * 2;
      const miniGap = 2.0;
      // 导航栏的玻璃胶囊在组件里左右各缩进 12
      const pillInset = 12.0;
      const circleSize = KanadeGlass.navigationControlHeight;
      const circleGap = 8.0;
      final safeBottom = MediaQuery.paddingOf(context).bottom;
      final screenWidth = MediaQuery.sizeOf(context).width;
      final screenHeight = MediaQuery.sizeOf(context).height;
      // 三个标签的胶囊不需要铺满整行，收窄后居中；手机上还要给右边的圆球留位置
      final navWidth = (screenWidth - 32 - (touchPlatform ? circleSize + circleGap : 0)).clamp(0.0, 300.0);
      final isDark = Theme.of(context).brightness == Brightness.dark;
      final foreground = isDark ? Colors.white : Colors.black87;
      final shadows = [Shadow(color: isDark ? Colors.black54 : Colors.white54, blurRadius: 1.5)];
      final labelStyle = TextStyle(decoration: TextDecoration.none, shadows: shadows);
      final tabBar = MediaQuery(
        data: MediaQuery.of(context).copyWith(platformBrightness: Theme.of(context).brightness),
        child: GlassTabBar.bottom(
          selectedIndex: _tab,
          onTabSelected: _select,
          tabs: [
            for (final d in destinations)
              GlassTab(
                icon: Icon(d.$1, shadows: shadows),
                activeIcon: Icon(d.$2, shadows: shadows),
                label: d.$3,
                semanticLabel: d.$3,
              ),
          ],
          quality: KanadeGlass.navigationQuality,
          settings: KanadeGlass.navigationSettings(context),
          indicatorSettings: KanadeGlass.indicatorSettings,
          // 指示器是一颗透明透镜，选中态靠抗色图标区分
          indicatorColor: foreground.withValues(alpha: 0.1),
          selectedIconColor: scheme.primary,
          selectedLabelColor: scheme.primary,
          unselectedIconColor: foreground,
          unselectedLabelColor: foreground,
          selectedLabelStyle: labelStyle,
          unselectedLabelStyle: labelStyle,
          adaptiveBrightness: false,
          magnification: 1.2,
          horizontalPadding: 12,
          verticalPadding: navPad,
          barHeight: KanadeGlass.navigationControlHeight,
          tabWidth: (navWidth - 24) / destinations.length,
          barBorderRadius: GlassDefaults.capsuleRadius,
          indicatorBorderRadius: GlassDefaults.capsuleRadius,
        ),
      );
      // 二级页面里导航栏和播放条融成一块，落到底部变成胶囊
      final navSpace = _nested ? 8.0 : navHeight;
      final inset = navSpace + (hasSong ? MiniPlayer.height + miniGap : 0) + 8;
      // 播放条收成导航栏旁边的圆球时，提示只要躲开导航栏
      _reportChrome(
        EdgeInsets.only(bottom: safeBottom + (hasSong && _collapsed && !_nested ? navHeight + 6 : inset + 4)),
      );
      final chrome = AnimatedBuilder(
        animation: Listenable.merge([_shape, _fuse, _drop, _appear]),
        builder: (context, _) {
          final s = _shape.value;
          final f = _fuse.value;
          final d = _drop.value;
          final a = _appear.value;
          final round = s.clamp(0.0, 1.0);
          // 收成圆球时导航栏往左让，和圆球一起居中；圆球和导航栏的玻璃胶囊一样高、对齐
          final shift = s * Curves.easeOutCubic.transform(a);
          final navCentered = (screenWidth - navWidth) / 2;
          final navGrouped = (screenWidth - (navWidth - pillInset * 2 + circleGap + circleSize)) / 2 - pillInset;
          final navLeft = lerpDouble(navCentered, navGrouped, shift)!;
          final navTop = screenHeight - safeBottom - navHeight;
          // 导航栏里那块玻璃胶囊本身的位置
          final pill = Rect.fromLTWH(navLeft + pillInset, navTop + navPad, navWidth - pillInset * 2, circleSize);
          final circle = Rect.fromLTWH(pill.right + circleGap, pill.top, circleSize, circleSize);
          final capsule = Rect.fromLTWH(
            16,
            navTop - miniGap - MiniPlayer.height,
            screenWidth - 32,
            MiniPlayer.height,
          );
          final bottom = Rect.fromLTWH(16, screenHeight - safeBottom - 8 - MiniPlayer.height, screenWidth - 32, MiniPlayer.height);
          // 一级页面里的样子（胶囊 / 圆球）→ 融成导航栏那块 → 弹成底部胶囊
          var bar = f < 1 ? Rect.lerp(Rect.lerp(capsule, circle, s), pill, f)! : Rect.lerp(pill, bottom, d)!;
          // 歌名和按钮：收成圆、融合时淡掉，落到底部时再出来
          final face = math.max(
            (1 - round / 0.4).clamp(0.0, 1.0) * (1 - f / 0.3).clamp(0.0, 1.0),
            f < 1 ? 0.0 : ((d - 0.3) / 0.5).clamp(0.0, 1.0),
          );
          // 从圆球融进去时封面先待在右端，导航栏淡掉后快速挪到左端
          final coverShift = round * (1 - const Interval(0.5, 0.85, curve: Curves.easeInOut).transform(f));
          // 有播放条时导航栏淡掉、被它吸进去；没有播放条就像原来一样整条往下滑走
          final navOpacity = hasSong ? 1 - const Interval(0.3, 0.7).transform(f) : 1.0;
          final navSlide = hasSong ? 0.0 : f * navHeight * 1.6;
          var opacity = 1.0;
          if (a < 1) {
            // 第一次出现：一颗小圆从导航栏胶囊的右端分裂出来，长大挪到位（二级页面里从胶囊右端长出来）
            final seed = Rect.fromCircle(
              center: f >= 1
                  ? bottom.centerRight - const Offset(MiniPlayer.height / 2, 0)
                  : s > 0.5
                  ? Offset(pill.right - circleSize / 2, pill.center.dy)
                  : capsule.centerRight - const Offset(MiniPlayer.height / 2, 0),
              radius: 12,
            );
            bar = Rect.lerp(seed, bar, Curves.easeOutBack.transform(a))!;
            opacity = (a / 0.2).clamp(0.0, 1.0);
          }
          return Stack(
            children: [
              if (hasSong)
                Positioned.fromRect(
                  rect: bar,
                  child: Opacity(
                    opacity: opacity,
                    child: MiniPlayer(
                      round: s > 0.5 && f < 0.5,
                      faceOpacity: face,
                      coverShift: coverShift,
                      capsuleWidth: capsule.width,
                      onExpand: () => setState(() => _collapsed = false),
                    ),
                  ),
                ),
              // 融合时导航栏盖在播放条上面淡掉，看起来是被吸进去
              Positioned(
                left: navLeft,
                top: navTop + navSlide,
                width: navWidth,
                height: navHeight,
                child: IgnorePointer(
                  ignoring: _nested,
                  child: Opacity(opacity: navOpacity, child: tabBar),
                ),
              ),
            ],
          );
        },
      );
      content = Material(
        color: scheme.surface,
        child: KanadeGlass.backdropScope(
          child: Stack(
            children: [
              Positioned.fill(
                child: KanadeGlass.backdropSource(
                  child: ColoredBox(
                    color: scheme.surface,
                    child: NotificationListener<ScrollNotification>(
                      onNotification: _onScroll,
                      child: _insetBottom(context, inset, body),
                    ),
                  ),
                ),
              ),
              // 空白处点不中，手势会落到下面的页面
              Positioned.fill(child: chrome),
            ],
          ),
        ),
      );
    }

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final nav = _keys[_tab].currentState;
        if (nav != null && nav.canPop()) {
          // maybePop 让二级页面自己的 PopScope 先处理（比如歌单页先退出搜索）
          nav.maybePop();
        } else if (_tab != 0) {
          setState(() => _tab = 0);
        }
      },
      child: content,
    );
  }
}

/// 切换标签时页面横着滑过去：往右边的标签切，新页面从右边推进来，反过来从左边。
/// 三个页面一直留着（滚动位置、二级页面都在），不在显示的不绘制、停掉动画。
class _TabSwitcher extends StatefulWidget {
  const _TabSwitcher({required this.index, required this.children});

  final int index;
  final List<Widget> children;

  @override
  State<_TabSwitcher> createState() => _TabSwitcherState();
}

class _TabSwitcherState extends State<_TabSwitcher> with SingleTickerProviderStateMixin {
  late final _slide = AnimationController(vsync: this, duration: const Duration(milliseconds: 300), value: 1)
    // 滑完把旧页面藏起来
    ..addStatusListener((s) {
      if (s == AnimationStatus.completed) setState(() {});
    });
  late int _from = widget.index;

  @override
  void didUpdateWidget(_TabSwitcher old) {
    super.didUpdateWidget(old);
    if (widget.index != old.index) {
      _from = old.index;
      _slide.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _slide.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final to = widget.index;
    return ClipRect(
      child: AnimatedBuilder(
        animation: _slide,
        builder: (context, _) {
          final moving = _slide.isAnimating;
          final t = Curves.easeOutCubic.transform(_slide.value);
          final dir = to > _from ? 1.0 : -1.0;
          return Stack(
            fit: StackFit.expand,
            children: [
              for (final (i, child) in widget.children.indexed)
                // 每一层的结构保持不变，页面的状态才不会丢
                Offstage(
                  offstage: i != to && !(moving && i == _from),
                  child: TickerMode(
                    enabled: i == to || (moving && i == _from),
                    child: FractionalTranslation(
                      translation: Offset(i == to ? dir * (1 - t) : -dir * t, 0),
                      child: IgnorePointer(
                        ignoring: i != to,
                        // 滑动时只挪图层，不重绘页面内容
                        child: RepaintBoundary(child: child),
                      ),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

/// 记录一个标签页 Navigator 里有几层页面。
class _DepthObserver extends NavigatorObserver {
  _DepthObserver(this.onChanged);

  final VoidCallback onChanged;
  int depth = 0;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    depth++;
    onChanged();
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    depth--;
    onChanged();
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    depth--;
    onChanged();
  }
}
