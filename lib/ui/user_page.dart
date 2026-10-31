import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../auth/auth_controller.dart';
import '../l10n/l10n_ext.dart';
import '../src/rust/api/music.dart' as api;
import '../src/rust/api/types.dart';
import 'follow_button.dart';
import 'singer_page.dart' show AlbumTile;
import 'smooth_scroll.dart';
import 'song_list_page.dart';
import 'video_tile.dart';
import 'widgets.dart';

/// 用户主页：创建的歌单、我喜欢（歌曲 / 歌单 / 专辑 / 视频）。
class UserPage extends StatelessWidget {
  const UserPage({super.key, required this.euin, required this.name});

  final String euin;
  final String name;

  static Route<void> route(String euin, String name) => MaterialPageRoute(
    builder: (_) => UserPage(euin: euin, name: name),
  );

  @override
  Widget build(BuildContext context) {
    final account = context.select<AuthController, String?>((a) => a.user?.uin);
    return Scaffold(
      appBar: AppBar(title: Text(name)),
      body: AsyncView<UserProfile>(
        key: ValueKey((euin, account)),
        load: () => api.getUserProfile(euin: euin),
        builder: (context, p) => _ProfileBody(p),
      ),
    );
  }
}

class _ProfileBody extends StatefulWidget {
  const _ProfileBody(this.profile);

  final UserProfile profile;

  @override
  State<_ProfileBody> createState() => _ProfileBodyState();
}

class _ProfileBodyState extends State<_ProfileBody> {
  bool _likes = false;
  UserAssetKind _kind = UserAssetKind.song;
  late bool _followed = widget.profile.followed;

  @override
  Widget build(BuildContext context) {
    final p = widget.profile;
    final l = AppLocalizations.of(context);
    final header = _Head(
      p,
      showPlaylistCount: !_likes,
      followed: _followed,
      onFollow: (value) async {
        await api.setUserFollowed(euin: p.euin, followed: value);
        if (mounted) setState(() => _followed = value);
      },
    );
    return Column(
      children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Pill(label: l.playlistsCreated, selected: !_likes, onTap: () => setState(() => _likes = false)),
              const SizedBox(width: 6),
              Pill(label: l.userLikes, selected: _likes, onTap: () => setState(() => _likes = true)),
            ],
          ),
        ),
        if (_likes)
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            child: Row(
              children: [
                for (final (kind, label) in [
                  (UserAssetKind.song, l.tabSongs),
                  (UserAssetKind.playlist, l.searchKindPlaylist),
                  (UserAssetKind.album, l.tabAlbums),
                  (UserAssetKind.video, l.searchKindVideo),
                ])
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: Pill(label: label, selected: _kind == kind, onTap: () => setState(() => _kind = kind)),
                  ),
              ],
            ),
          ),
        Expanded(
          child: !_likes
              ? _Playlists(p, header: header)
              : _Assets(key: ValueKey(_kind), profile: p, kind: _kind, header: header),
        ),
      ],
    );
  }
}

class _Playlists extends StatefulWidget {
  const _Playlists(this.profile, {required this.header});

  final UserProfile profile;
  final Widget header;

  @override
  State<_Playlists> createState() => _PlaylistsState();
}

class _PlaylistsState extends State<_Playlists> {
  static const _pageSize = 30;

  final _scroll = SmoothScrollController();
  final _items = <PlaylistBrief>[];
  int _page = 0;
  late bool _hasMore = widget.profile.playlistCount > 0 && !widget.profile.playlistsHidden;
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
          if (i == 0) return widget.header;
          final j = i - 1;
          if (j < _items.length) {
            final p = _items[j];
            return ListTile(
              leading: Cover(p.coverUrl, size: 52, radius: 12),
              title: Text(
                p.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
              ),
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
          if (_loading) {
            return const Padding(
              padding: EdgeInsets.all(16),
              child: Center(child: CircularProgressIndicator()),
            );
          }
          if (_items.isEmpty) {
            return Padding(
              padding: const EdgeInsets.all(32),
              child: Center(child: Text(widget.profile.playlistsHidden ? l.userPrivate : l.userNoPlaylists)),
            );
          }
          return const BottomSpacer();
        },
      ),
    );
  }
}

class _Assets extends StatefulWidget {
  const _Assets({super.key, required this.profile, required this.kind, required this.header});

  final UserProfile profile;
  final UserAssetKind kind;
  final Widget header;

  @override
  State<_Assets> createState() => _AssetsState();
}

class _AssetsState extends State<_Assets> {
  final _scroll = SmoothScrollController();
  final _playlists = <PlaylistBrief>[];
  final _albums = <AlbumBrief>[];
  final _songs = <Song>[];
  final _videos = <VideoBrief>[];
  int _page = 0;
  bool _hasMore = true;
  bool _loading = false;
  bool _hidden = false;
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
    setState(() => _loading = true);
    try {
      final result = await api.getUserAssets(euin: widget.profile.euin, kind: widget.kind, page: _page, pageSize: 30);
      if (!mounted) return;
      setState(() {
        _playlists.addAll(result.playlists);
        _albums.addAll(result.albums);
        _songs.addAll(result.songs);
        _videos.addAll(result.videos);
        _page++;
        _hasMore = result.hasMore;
        _hidden = result.hidden;
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
    final count = _songs.length + _playlists.length + _albums.length + _videos.length;
    return NotificationListener<ScrollNotification>(
      onNotification: (n) {
        if (n.metrics.extentAfter < 300) _more();
        return false;
      },
      child: ListView.builder(
        controller: _scroll,
        itemCount: count + 2,
        itemBuilder: (context, i) {
          if (i == 0) return widget.header;
          final index = i - 1;
          if (index < count) {
            if (widget.kind == UserAssetKind.song) return SongTile(songs: _songs, index: index);
            if (widget.kind == UserAssetKind.video) return VideoTile(_videos[index]);
            if (widget.kind == UserAssetKind.album) return AlbumTile(_albums[index]);
            final p = _playlists[index];
            return ListTile(
              leading: Cover(p.coverUrl, size: 52, radius: 12),
              title: Text(p.title, maxLines: 1, overflow: TextOverflow.ellipsis),
              subtitle: Text(l.songCount(p.songCount)),
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
          if (_loading) {
            return const Padding(
              padding: EdgeInsets.all(16),
              child: Center(child: CircularProgressIndicator()),
            );
          }
          if (count == 0) {
            return Padding(
              padding: const EdgeInsets.all(32),
              child: Center(child: Text(_hidden ? l.userPrivate : l.noItems)),
            );
          }
          return const BottomSpacer();
        },
      ),
    );
  }
}

class _Head extends StatelessWidget {
  const _Head(this.p, {required this.followed, required this.onFollow, required this.showPlaylistCount});

  final UserProfile p;
  final bool followed;
  final Future<void> Function(bool) onFollow;
  final bool showPlaylistCount;

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
          Text(
            p.name,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 8),
          Text(
            l.userFansFollows(formatCount(l, p.fansCount.toInt()), formatCount(l, p.followCount.toInt())),
            style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
          ),
          if (!p.isSelf) ...[const SizedBox(height: 8), FollowButton(followed: followed, onChanged: onFollow)],
          if (showPlaylistCount && p.playlistCount > 0) ...[
            const SizedBox(height: 16),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: Text(
                l.userPlaylists(p.playlistCount),
                style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
