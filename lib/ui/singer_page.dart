import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/l10n_ext.dart';
import '../player/player_controller.dart';
import '../src/rust/api/music.dart' as api;
import '../src/rust/api/types.dart';
import 'album_page.dart';
import 'smooth_scroll.dart';
import 'widgets.dart';

/// 歌手页：简介 + 歌曲 / 专辑两个标签，滚到底自动加载下一页。
class SingerPage extends StatelessWidget {
  const SingerPage({super.key, required this.mid, required this.name});

  final String mid;
  final String name;

  static Route<void> route(String mid, String name) =>
      MaterialPageRoute(builder: (_) => SingerPage(mid: mid, name: name));

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: Text(name),
          bottom: TabBar(tabs: [Tab(text: l.tabSongs), Tab(text: l.tabAlbums)]),
        ),
        body: AsyncView<SingerDetail>(
          load: () => api.getSingerDetail(mid: mid),
          builder: (context, d) => TabBarView(
            children: [
              _PagedList<Song>(
                initial: d.songs,
                total: d.songTotal,
                header: _Head(d),
                loadMore: (begin) => api.getSingerSongs(mid: mid, begin: begin, num: 30),
                itemBuilder: (context, items, i) => SongTile(songs: items, index: i),
              ),
              _PagedList<AlbumBrief>(
                initial: d.albums,
                total: d.albumTotal,
                loadMore: (begin) => api.getSingerAlbums(mid: mid, begin: begin, num: 30),
                itemBuilder: (context, items, i) => AlbumTile(items[i]),
              ),
            ],
          ),
        ),
      ),
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
          if (_loading) return const Padding(padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator()));
          return const SizedBox(height: 16);
        },
      ),
    );
  }
}
