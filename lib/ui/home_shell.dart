import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import 'discover_page.dart';
import 'mine_page.dart';
import 'search_page.dart';
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

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 720;
    final destinations = _destinations(AppLocalizations.of(context));
    final body = IndexedStack(
      index: _tab,
      children: [
        _tabNavigator(0, const DiscoverPage()),
        _tabNavigator(1, const SearchPage()),
        _tabNavigator(2, const MinePage()),
      ],
    );

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
      child: Scaffold(
        body: wide
            ? Row(
                children: [
                  NavigationRail(
                    selectedIndex: _tab,
                    onDestinationSelected: _select,
                    labelType: NavigationRailLabelType.all,
                    leading: const Padding(
                      padding: EdgeInsets.symmetric(vertical: 12),
                      child: Text('Kanade', style: TextStyle(fontWeight: FontWeight.bold)),
                    ),
                    destinations: [
                      for (final d in destinations)
                        NavigationRailDestination(icon: Icon(d.$1), selectedIcon: Icon(d.$2), label: Text(d.$3)),
                    ],
                  ),
                  const VerticalDivider(width: 1),
                  Expanded(child: body),
                ],
              )
            : body,
        bottomNavigationBar: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const MiniPlayer(),
            if (!wide)
              NavigationBar(
                selectedIndex: _tab,
                onDestinationSelected: _select,
                destinations: [
                  for (final d in destinations)
                    NavigationDestination(icon: Icon(d.$1), selectedIcon: Icon(d.$2), label: d.$3),
                ],
              ),
          ],
        ),
      ),
    );
  }
}
