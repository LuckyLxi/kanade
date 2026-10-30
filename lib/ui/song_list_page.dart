import 'dart:math';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/app_localizations.dart';
import '../library/library_controller.dart';
import '../player/player_controller.dart';
import '../src/rust/api/music.dart' as api;
import '../src/rust/api/types.dart';
import 'glass.dart';
import 'playlist_actions.dart';
import 'smooth_scroll.dart';
import 'song_actions.dart';
import 'widgets.dart';

/// period 只有榜单有，用来显示“更新于 …”。owned 是自己的歌单时才有，可以删歌。
typedef ListData = ({
  String title,
  String cover,
  String period,
  String description,
  List<Song> songs,
  MyPlaylist? owned,
});

/// 歌单详情 / 榜单详情共用的页面。
class SongListPage extends StatelessWidget {
  const SongListPage({
    super.key,
    required this.title,
    required this.load,
    this.ranked = false,
    this.searchable = false,
  });

  final String title;
  final Future<ListData> Function() load;

  /// 显示名次。
  final bool ranked;

  /// 头部下面有搜索框，按歌名、歌手筛选。
  final bool searchable;

  static Route<void> playlist(String id, String title) => MaterialPageRoute(
    builder: (context) => SongListPage(
      title: title,
      searchable: true,
      load: () async {
        final owned = context.read<LibraryController>().ownPlaylist(id);
        final d = await api.getPlaylistDetail(id: id);
        return (
          title: d.title,
          cover: d.coverUrl,
          period: '',
          description: d.description,
          songs: d.songs,
          owned: await owned,
        );
      },
    ),
  );

  /// 已经拿到的歌曲列表，比如推荐页某个区块的“查看全部”。
  static Route<void> songs(String title, List<Song> songs) => MaterialPageRoute(
    builder: (_) => SongListPage(
      title: title,
      load: () async => (
        title: title,
        cover: songs.isEmpty ? '' : songs.first.coverUrl,
        period: '',
        description: '',
        songs: songs,
        owned: null,
      ),
    ),
  );

  /// 云端最近播放，从新到旧。
  static Route<void> recent(String title) => MaterialPageRoute(
    builder: (_) => SongListPage(
      title: title,
      searchable: true,
      load: () async {
        final songs = await api.getRecentPlays();
        return (
          title: title,
          cover: songs.isEmpty ? '' : songs.first.coverUrl,
          period: '',
          description: '',
          songs: songs,
          owned: null,
        );
      },
    ),
  );

  static Route<void> toplist(int topId, String period, String title) => MaterialPageRoute(
    builder: (_) => SongListPage(
      title: title,
      ranked: true,
      load: () async {
        final d = await api.getToplistDetail(topId: topId, period: period);
        return (
          title: d.title,
          cover: d.coverUrl,
          period: d.period,
          description: d.description,
          songs: d.songs,
          owned: null,
        );
      },
    ),
  );

  @override
  Widget build(BuildContext context) {
    // 标题放在下面的大封面头部里，左上角只浮一颗返回钮
    return GlassBackScaffold(
      body: AsyncView<ListData>(
        load: load,
        builder: (context, d) => _Body(d, ranked: ranked, searchable: searchable),
      ),
    );
  }
}

class _Body extends StatefulWidget {
  const _Body(this.d, {required this.ranked, required this.searchable});

  final ListData d;
  final bool ranked;
  final bool searchable;

  @override
  State<_Body> createState() => _BodyState();
}

class _BodyState extends State<_Body> {
  /// 删歌成功后从这里去掉，不用重新加载整个歌单。
  late final List<Song> _songs = List.of(widget.d.songs);

  /// 改名后就地更新，不重新加载。
  late MyPlaylist? _owned = widget.d.owned;
  late String _title = widget.d.title;

  Future<void> _remove(Song song) async {
    if (await removeFromPlaylist(context, _owned!, song) && mounted) {
      setState(() => _songs.remove(song));
    }
  }

  Future<void> _edit() async {
    final owned = _owned!;
    switch (await showPlaylistActions(context, owned)) {
      case PlaylistRenamed(:final name):
        if (!mounted) return;
        setState(() {
          _title = name;
          _owned = MyPlaylist(
            dirId: owned.dirId,
            tid: owned.tid,
            name: name,
            coverUrl: owned.coverUrl,
            songCount: owned.songCount,
          );
        });
      case PlaylistDeleted():
        if (mounted) Navigator.of(context).pop();
      case null:
    }
  }

  final _query = TextEditingController();
  final _scroll = SmoothScrollController();

  @override
  void dispose() {
    _query.dispose();
    _scroll.dispose();
    super.dispose();
  }

  /// 按歌名或歌手筛选，不区分大小写。点歌时只播筛出来的这些。
  List<Song> get _shown {
    final q = _query.text.trim().toLowerCase();
    if (q.isEmpty) return _songs;
    return [
      for (final s in _songs)
        if (s.name.toLowerCase().contains(q) || s.singers.any((e) => e.name.toLowerCase().contains(q))) s,
    ];
  }

  @override
  Widget build(BuildContext context) {
    final d = widget.d;
    final searchable = widget.searchable;
    final shown = searchable ? _shown : _songs;
    // 列表前面固定的行：头部，可搜索时再加搜索框
    final lead = searchable ? 2 : 1;
    return ListView.builder(
      controller: _scroll,
      // 拖动列表时收起键盘
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      itemCount: lead + (shown.isEmpty && searchable ? 1 : shown.length),
      itemBuilder: (context, i) {
        if (i == 0) return _Head(d, _songs, title: _title, onEdit: canEditPlaylist(_owned) ? _edit : null);
        if (searchable && i == 1) return _FilterField(_query, onChanged: () => setState(() {}));
        if (shown.isEmpty) {
          return Padding(
            padding: const EdgeInsets.all(32),
            child: Center(child: Text(AppLocalizations.of(context).searchNoResults)),
          );
        }
        final song = shown[i - lead];
        return SongTile(
          songs: shown,
          index: i - lead,
          // 筛选后仍显示原来的名次
          rank: widget.ranked ? _songs.indexOf(song) + 1 : null,
          // “我喜欢”里不给删，取消喜欢就行
          onRemove: canEditPlaylist(_owned) ? () => _remove(song) : null,
        );
      },
    );
  }
}

class _FilterField extends StatelessWidget {
  const _FilterField(this.controller, {required this.onChanged});

  final TextEditingController controller;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: SearchBar(
        controller: controller,
        hintText: AppLocalizations.of(context).filterSongsHint,
        leading: const Icon(Icons.search),
        elevation: const WidgetStatePropertyAll(0),
        constraints: const BoxConstraints(minHeight: 44),
        onChanged: (_) => onChanged(),
        trailing: [
          if (controller.text.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.clear),
              onPressed: () {
                controller.clear();
                onChanged();
              },
            ),
        ],
      ),
    );
  }
}

class _Head extends StatelessWidget {
  const _Head(this.d, this.songs, {required this.title, this.onEdit});

  final ListData d;
  final List<Song> songs;
  final String title;

  /// 自己的歌单（“我喜欢”除外）才有：改名、删除。
  final VoidCallback? onEdit;

  void _shuffle(BuildContext context) {
    final p = context.read<PlayerController>();
    p.setMode(PlayMode.shuffle);
    p.playList(songs, Random().nextInt(songs.length));
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final meta = [l.songCount(songs.length), if (d.period.isNotEmpty) l.updatedAt(d.period)].join(' · ');
    final description = d.description.replaceAll(RegExp(r'<[^>]+>'), '').trim();
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, GlassBackScaffold.topInset, 24, 12),
      child: Column(
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              boxShadow: const [BoxShadow(color: Colors.black54, blurRadius: 40, offset: Offset(0, 20))],
            ),
            child: Cover(d.cover, size: 196, radius: 20),
          ),
          const SizedBox(height: 18),
          Text(
            title,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 6),
          Text(meta, style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant)),
          if (description.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              description,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12, height: 1.5, color: scheme.onSurfaceVariant),
            ),
          ],
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(minimumSize: const Size(0, 46)),
                  onPressed: songs.isEmpty ? null : () => context.read<PlayerController>().playList(songs, 0),
                  icon: const Icon(Icons.play_arrow_rounded),
                  label: Text(l.playAll(songs.length)),
                ),
              ),
              const SizedBox(width: 10),
              IconButton(
                tooltip: l.shufflePlay,
                style: IconButton.styleFrom(
                  fixedSize: const Size(46, 46),
                  backgroundColor: scheme.surfaceContainerHigh,
                  side: BorderSide(color: scheme.outlineVariant),
                ),
                onPressed: songs.isEmpty ? null : () => _shuffle(context),
                icon: const Icon(Icons.shuffle_rounded),
              ),
              if (onEdit != null) ...[
                const SizedBox(width: 10),
                IconButton(
                  tooltip: l.more,
                  style: IconButton.styleFrom(
                    fixedSize: const Size(46, 46),
                    backgroundColor: scheme.surfaceContainerHigh,
                    side: BorderSide(color: scheme.outlineVariant),
                  ),
                  onPressed: onEdit,
                  icon: const Icon(Icons.more_horiz_rounded),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}
