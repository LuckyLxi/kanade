import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/l10n_ext.dart';
import '../player/player_controller.dart';
import '../src/rust/api/music.dart' as api;
import '../src/rust/api/types.dart';
import 'album_page.dart';
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
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipOval(child: Cover(d.avatarUrl, size: 96, radius: 0)),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(d.name, style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 6),
                if (d.description.isNotEmpty)
                  Text(d.description, maxLines: 3, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.bodySmall),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: d.songs.isEmpty ? null : () => context.read<PlayerController>().playList(d.songs, 0),
                  icon: const Icon(Icons.play_arrow),
                  label: Text(l.playAll(d.songs.length)),
                ),
              ],
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
      leading: Cover(album.coverUrl, size: 48),
      title: Text(album.name, maxLines: 1, overflow: TextOverflow.ellipsis),
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

  @override
  bool get wantKeepAlive => true;

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
