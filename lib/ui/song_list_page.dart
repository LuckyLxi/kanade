import 'dart:math';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/app_localizations.dart';
import '../library/library_controller.dart';
import '../player/player_controller.dart';
import '../src/rust/api/music.dart' as api;
import '../src/rust/api/types.dart';
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
  const SongListPage({super.key, required this.title, required this.load, this.ranked = false});

  final String title;
  final Future<ListData> Function() load;
  final bool ranked;

  static Route<void> playlist(String id, String title) => MaterialPageRoute(
    builder: (context) => SongListPage(
      title: title,
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
    // 标题放在下面的大封面头部里，顶栏只留返回
    return Scaffold(
      appBar: AppBar(),
      body: AsyncView<ListData>(
        load: load,
        builder: (context, d) => _Body(d, ranked: ranked),
      ),
    );
  }
}

class _Body extends StatefulWidget {
  const _Body(this.d, {required this.ranked});

  final ListData d;
  final bool ranked;

  @override
  State<_Body> createState() => _BodyState();
}

class _BodyState extends State<_Body> {
  /// 删歌成功后从这里去掉，不用重新加载整个歌单。
  late final List<Song> _songs = List.of(widget.d.songs);

  Future<void> _remove(Song song) async {
    if (await removeFromPlaylist(context, widget.d.owned!, song) && mounted) {
      setState(() => _songs.remove(song));
    }
  }

  @override
  Widget build(BuildContext context) {
    final d = widget.d;
    return ListView.builder(
      itemCount: _songs.length + 1,
      itemBuilder: (context, i) {
        if (i == 0) return _Head(d, _songs);
        final song = _songs[i - 1];
        return SongTile(
          songs: _songs,
          index: i - 1,
          rank: widget.ranked ? i : null,
          onRemove: d.owned == null ? null : () => _remove(song),
        );
      },
    );
  }
}

class _Head extends StatelessWidget {
  const _Head(this.d, this.songs);

  final ListData d;
  final List<Song> songs;

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
      padding: const EdgeInsets.fromLTRB(24, 4, 24, 12),
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
            d.title,
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
            ],
          ),
        ],
      ),
    );
  }
}
