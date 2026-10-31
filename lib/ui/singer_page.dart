import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../auth/auth_controller.dart';
import '../l10n/l10n_ext.dart';
import '../player/player_controller.dart';
import '../src/rust/api/music.dart' as api;
import '../src/rust/api/types.dart';
import 'album_page.dart';
import 'follow_button.dart';
import 'smooth_scroll.dart';
import 'video_tile.dart';
import 'widgets.dart';

/// 歌手页：精选、歌曲、专辑和视频，复用现有列表与 MV 播放页。
class SingerPage extends StatelessWidget {
  const SingerPage({super.key, required this.mid, required this.name});

  final String mid;
  final String name;

  static Route<void> route(String mid, String name) => MaterialPageRoute(
    builder: (_) => SingerPage(mid: mid, name: name),
  );

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return DefaultTabController(
      length: 4,
      child: Scaffold(
        appBar: AppBar(
          title: Text(name),
          bottom: TabBar(
            tabs: [
              Tab(text: l.singerFeatured),
              Tab(text: l.tabSongs),
              Tab(text: l.tabAlbums),
              Tab(text: l.searchKindVideo),
            ],
          ),
        ),
        body: AsyncView<SingerDetail>(
          load: () => api.getSingerDetail(mid: mid),
          builder: (context, d) => TabBarView(
            children: [
              ListView(
                children: [
                  _Head(d),
                  _Social(mid),
                  if (d.selectedAlbums.isNotEmpty) ...[
                    _SectionTitle(l.singerSelectedAlbums),
                    for (final album in d.selectedAlbums) AlbumTile(album),
                  ],
                  _SectionTitle(l.tabSongs),
                  for (var i = 0; i < d.songs.length && i < 10; i++) SongTile(songs: d.songs, index: i),
                  const BottomSpacer(),
                ],
              ),
              _PagedList<Song>(
                initial: d.songs,
                total: d.songTotal,
                loadMore: (begin) => api.getSingerSongs(mid: mid, begin: begin, num: 30),
                itemBuilder: (context, items, i) => SongTile(songs: items, index: i),
              ),
              _PagedList<AlbumBrief>(
                initial: d.albums,
                total: d.albumTotal,
                loadMore: (begin) => api.getSingerAlbums(mid: mid, begin: begin, num: 30),
                itemBuilder: (context, items, i) => AlbumTile(items[i]),
              ),
              _Videos(d),
            ],
          ),
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.title);

  final String title;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
    child: Text(title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
  );
}

class _Social extends StatelessWidget {
  const _Social(this.mid);

  final String mid;

  @override
  Widget build(BuildContext context) {
    final account = context.select<AuthController, String?>((a) => a.user?.uin);
    return AsyncView<SingerSocial>(
      key: ValueKey((mid, account)),
      load: () => api.getSingerSocial(mid: mid),
      builder: (_, data) => _SocialInfo(mid, data),
    );
  }
}

class _SocialInfo extends StatefulWidget {
  const _SocialInfo(this.mid, this.data);

  final String mid;
  final SingerSocial data;

  @override
  State<_SocialInfo> createState() => _SocialInfoState();
}

class _SocialInfoState extends State<_SocialInfo> {
  late bool _followed = widget.data.followed;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        children: [
          Text(l.userFans(formatCount(l, widget.data.fansCount.toInt()))),
          if (widget.data.guardTitle.isNotEmpty) Text(widget.data.guardTitle),
          const SizedBox(height: 8),
          FollowButton(
            followed: _followed,
            onChanged: (value) async {
              await api.setSingerFollowed(mid: widget.mid, followed: value);
              if (mounted) setState(() => _followed = value);
            },
          ),
        ],
      ),
    );
  }
}

class _Videos extends StatefulWidget {
  const _Videos(this.singer);

  final SingerDetail singer;

  @override
  State<_Videos> createState() => _VideosState();
}

class _VideosState extends State<_Videos> with AutomaticKeepAliveClientMixin {
  VideoTag? _tag;
  int _order = 0;

  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final d = widget.singer;
    return AsyncView<List<VideoTag>>(
      load: () => api.getSingerVideoTags(mid: d.mid),
      builder: (context, tags) {
        if (tags.isEmpty) return Center(child: Text(AppLocalizations.of(context).noItems));
        final tag = (_tag ?? tags.first).id;
        final order = _order;
        final l = AppLocalizations.of(context);
        return Column(
          children: [
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  for (final t in tags)
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: Pill(label: t.name, selected: tag == t.id, onTap: () => setState(() => _tag = t)),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Pill(label: l.newest, selected: order == 0, onTap: () => setState(() => _order = 0)),
                  const SizedBox(width: 6),
                  Pill(label: l.hottest, selected: order == 1, onTap: () => setState(() => _order = 1)),
                ],
              ),
            ),
            Expanded(
              child: AsyncView<SingerVideoPage>(
                key: ValueKey((tag, order)),
                load: () => api.getSingerVideos(mid: d.mid, name: d.name, tag: tag, order: order, begin: 0, num: 40),
                builder: (_, page) => _PagedList<VideoBrief>(
                  initial: page.videos,
                  total: page.total,
                  loadMore: (begin) async => (await api.getSingerVideos(
                    mid: d.mid,
                    name: d.name,
                    tag: tag,
                    order: order,
                    begin: begin,
                    num: 40,
                  )).videos,
                  itemBuilder: (_, items, i) => VideoTile(items[i]),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _Head extends StatelessWidget {
  const _Head(this.d);

  final SingerDetail d;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    // 和歌单 / 专辑同一种居中头部，头像是圆的
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 12),
      child: Column(
        children: [
          DecoratedBox(
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              boxShadow: [BoxShadow(color: Colors.black54, blurRadius: 40, offset: Offset(0, 20))],
            ),
            child: ClipOval(child: Cover(d.avatarUrl, size: 140, radius: 0)),
          ),
          const SizedBox(height: 16),
          Text(
            d.name,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900),
          ),
          if (d.description.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              d.description,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12, height: 1.5, color: scheme.onSurfaceVariant),
            ),
          ],
          const SizedBox(height: 18),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              style: FilledButton.styleFrom(minimumSize: const Size(0, 46)),
              onPressed: d.songs.isEmpty ? null : () => context.read<PlayerController>().playList(d.songs, 0),
              icon: const Icon(Icons.play_arrow_rounded),
              label: Text(l.playAll(d.songs.length)),
            ),
          ),
        ],
      ),
    );
  }
}

class AlbumTile extends StatelessWidget {
  const AlbumTile(this.album, {super.key});

  final AlbumBrief album;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Cover(album.coverUrl, size: 52, radius: 12),
      title: Text(
        album.name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
      ),
      subtitle: Text([album.singerName, album.publishDate].where((s) => s.isNotEmpty).join(' · ')),
      onTap: () => Navigator.of(context).push(AlbumPage.route(album.mid, album.name)),
    );
  }
}

/// 按 begin 偏移翻页的列表。
class _PagedList<T> extends StatefulWidget {
  const _PagedList({
    super.key,
    required this.initial,
    required this.total,
    required this.loadMore,
    required this.itemBuilder,
    this.header,
  });

  final List<T> initial;
  final int total;
  final Future<List<T>> Function(int begin) loadMore;
  final Widget Function(BuildContext, List<T>, int) itemBuilder;
  final Widget? header;

  @override
  State<_PagedList<T>> createState() => _PagedListState<T>();
}

class _PagedListState<T> extends State<_PagedList<T>> with AutomaticKeepAliveClientMixin {
  late final List<T> _items = [...widget.initial];
  late bool _hasMore = _items.length < widget.total;
  bool _loading = false;
  Object? _error;
  final _scroll = SmoothScrollController();

  @override
  bool get wantKeepAlive => true;

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _more() async {
    if (_loading || !_hasMore) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final next = await widget.loadMore(_items.length);
      if (!mounted) return;
      setState(() {
        _items.addAll(next);
        _hasMore = next.isNotEmpty && _items.length < widget.total;
      });
    } catch (e) {
      if (mounted) setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final l = AppLocalizations.of(context);
    final head = widget.header == null ? 0 : 1;
    return NotificationListener<ScrollNotification>(
      onNotification: (n) {
        if (n.metrics.extentAfter < 300 && _error == null) _more();
        return false;
      },
      child: ListView.builder(
        controller: _scroll,
        itemCount: head + _items.length + 1,
        itemBuilder: (context, i) {
          if (i < head) return widget.header!;
          final j = i - head;
          if (j < _items.length) return widget.itemBuilder(context, _items, j);
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
              padding: const EdgeInsets.all(24),
              child: Center(child: Text(l.noItems)),
            );
          }
          return const SizedBox(height: 16);
        },
      ),
    );
  }
}
