import 'package:flutter/material.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'package:provider/provider.dart';

import '../l10n/app_localizations.dart';
import '../player/player_controller.dart';
import 'desktop_shell.dart';
import 'discover_page.dart';
import 'glass.dart';
import 'mine_page.dart';
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

class _HomeShellState extends State<HomeShell> {
  int _tab = 0;
  final _keys = List.generate(3, (_) => GlobalKey<NavigatorState>());

  static List<(IconData, IconData, String)> _destinations(AppLocalizations l) => [
    (Icons.explore_outlined, Icons.explore, l.tabDiscover),
    (Icons.search, Icons.search, l.tabSearch),
    (Icons.person_outline, Icons.person, l.tabMine),
  ];

  Widget _tabNavigator(int i, Widget root) => Navigator(
    key: _keys[i],
    onGenerateRoute: (_) => MaterialPageRoute(builder: (_) => root),
  );

  void _select(int i) {
    if (i == _tab) {
      _keys[i].currentState?.popUntil((r) => r.isFirst);
    } else {
      setState(() => _tab = i);
    }
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
    final scheme = Theme.of(context).colorScheme;
    final destinations = _destinations(AppLocalizations.of(context));
    final body = IndexedStack(
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
      final barSpace = hasSong ? DesktopPlayerBar.height + gap * 2 : gap;
      content = Material(
        color: scheme.surface,
        child: KanadeGlass.backdropScope(
          child: Stack(
            children: [
              Positioned.fill(
                child: KanadeGlass.backdropSource(
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
                              onOpenPlaylist: (p) =>
                                  _keys[_tab].currentState?.push(SongListPage.playlist(p.id, p.title)),
                            ),
                          ),
                        ),
                        Expanded(
                          child: _insetBottom(context, hasSong ? DesktopPlayerBar.height + gap * 2 : 0, body),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              if (hasSong)
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
      final safeBottom = MediaQuery.paddingOf(context).bottom;
      final screenWidth = MediaQuery.sizeOf(context).width;
      // 三个标签的胶囊不需要铺满整行，收窄后居中
      final navWidth = (screenWidth - 32).clamp(0.0, 300.0);
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
      final inset = navHeight + (hasSong ? MiniPlayer.height + miniGap : 0) + 8;
      content = Material(
        color: scheme.surface,
        child: KanadeGlass.backdropScope(
          child: Stack(
            children: [
              Positioned.fill(
                child: KanadeGlass.backdropSource(
                  child: ColoredBox(color: scheme.surface, child: _insetBottom(context, inset, body)),
                ),
              ),
              if (hasSong)
                Positioned(left: 16, right: 16, bottom: safeBottom + navHeight + miniGap, child: const MiniPlayer()),
              Positioned(
                left: (screenWidth - navWidth) / 2,
                width: navWidth,
                bottom: safeBottom,
                height: navHeight,
                child: tabBar,
              ),
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
          nav.pop();
        } else if (_tab != 0) {
          setState(() => _tab = 0);
        }
      },
      child: content,
    );
  }
}
