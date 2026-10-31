import 'package:flutter/material.dart';

import '../l10n/l10n_ext.dart';
import '../src/rust/api/music.dart' as api;
import '../src/rust/api/types.dart';
import 'smooth_scroll.dart';
import 'song_list_page.dart';
import 'widgets.dart';

/// 其他用户的主页：头像、粉丝数和公开歌单，滚到底加载下一页。
/// 歌手账号和只发动态的账号没有歌单标签，只显示资料。
class UserPage extends StatelessWidget {
  const UserPage({super.key, required this.euin, required this.name});

  final String euin;
  final String name;

  static Route<void> route(String euin, String name) => MaterialPageRoute(builder: (_) => UserPage(euin: euin, name: name));

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(name)),
      body: AsyncView<UserProfile>(
        load: () => api.getUserProfile(euin: euin),
        builder: (context, p) => _Playlists(p),
      ),
    );
  }
}

class _Playlists extends StatefulWidget {
  const _Playlists(this.profile);

  final UserProfile profile;

  @override
  State<_Playlists> createState() => _PlaylistsState();
}

class _PlaylistsState extends State<_Playlists> {
  static const _pageSize = 30;

  final _scroll = SmoothScrollController();
  final _items = <PlaylistBrief>[];
  int _page = 0;
  late bool _hasMore = widget.profile.playlistCount > 0;
  bool _loading = false;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _more();
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _more() async {
    if (_loading || !_hasMore || _error != null) return;
    final p = widget.profile;
    setState(() => _loading = true);
    try {
      final r = await api.getUserPublicPlaylists(euin: p.euin, creator: p.name, page: _page, pageSize: _pageSize);
      if (!mounted) return;
      setState(() {
        _page++;
        _items.addAll(r.playlists);
        _hasMore = r.hasMore;
      });
    } catch (e) {
      if (mounted) setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return NotificationListener<ScrollNotification>(
      onNotification: (n) {
        if (n.metrics.extentAfter < 300) _more();
        return false;
      },
      child: ListView.builder(
        controller: _scroll,
        itemCount: _items.length + 2,
        itemBuilder: (context, i) {
          if (i == 0) return _Head(widget.profile);
          final j = i - 1;
          if (j < _items.length) {
            final p = _items[j];
            return ListTile(
              leading: Cover(p.coverUrl, size: 52, radius: 12),
              title: Text(p.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
              subtitle: p.songCount > 0 ? Text(l.songCount(p.songCount)) : null,
              onTap: () => Navigator.of(context).push(SongListPage.playlist(p.id, p.title)),
            );
          }
          if (_error != null) {
            return ListTile(
              title: Text(l.loadFailed(errorText(l, _error!)), textAlign: TextAlign.center),
              onTap: () {
                setState(() => _error = null);
                _more();
              },
            );
          }
          if (_loading) return const Padding(padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator()));
          if (_items.isEmpty) {
            return Padding(padding: const EdgeInsets.all(32), child: Center(child: Text(l.userNoPlaylists)));
          }
          return const BottomSpacer();
        },
      ),
    );
  }
}

class _Head extends StatelessWidget {
  const _Head(this.p);

  final UserProfile p;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    // 和歌手页同一种居中头部
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 12),
      child: Column(
        children: [
          DecoratedBox(
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              boxShadow: [BoxShadow(color: Colors.black54, blurRadius: 40, offset: Offset(0, 20))],
            ),
            child: ClipOval(child: Cover(p.avatarUrl, size: 120, radius: 0)),
          ),
          const SizedBox(height: 16),
          Text(p.name, textAlign: TextAlign.center, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
          const SizedBox(height: 8),
          Text(
            l.userFansFollows(formatCount(l, p.fansCount.toInt()), formatCount(l, p.followCount.toInt())),
            style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
          ),
          if (p.playlistCount > 0) ...[
            const SizedBox(height: 16),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: Text(l.userPlaylists(p.playlistCount), style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
            ),
          ],
        ],
      ),
    );
  }
}
