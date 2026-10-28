import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/app_localizations.dart';
import '../player/player_controller.dart';
import '../src/rust/api/music.dart' as api;
import '../src/rust/api/types.dart';
import 'widgets.dart';

/// period 只有榜单有，用来显示“更新于 …”。
typedef ListData = ({String title, String cover, String period, String description, List<Song> songs});

/// 歌单详情 / 榜单详情共用的页面。
class SongListPage extends StatelessWidget {
  const SongListPage({super.key, required this.title, required this.load, this.ranked = false});

  final String title;
  final Future<ListData> Function() load;
  final bool ranked;

  static Route<void> playlist(String id, String title) => MaterialPageRoute(
        builder: (_) => SongListPage(
          title: title,
          load: () async {
            final d = await api.getPlaylistDetail(id: id);
            return (title: d.title, cover: d.coverUrl, period: '', description: d.description, songs: d.songs);
          },
        ),
      );

  /// 已经拿到的歌曲列表，比如推荐页某个区块的“查看全部”。
  static Route<void> songs(String title, List<Song> songs) => MaterialPageRoute(
        builder: (_) => SongListPage(
          title: title,
          load: () async =>
              (title: title, cover: songs.isEmpty ? '' : songs.first.coverUrl, period: '', description: '', songs: songs),
        ),
      );

  static Route<void> toplist(int topId, String period, String title) => MaterialPageRoute(
        builder: (_) => SongListPage(
          title: title,
          ranked: true,
          load: () async {
            final d = await api.getToplistDetail(topId: topId, period: period);
            return (title: d.title, cover: d.coverUrl, period: d.period, description: d.description, songs: d.songs);
          },
        ),
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: AsyncView<ListData>(
        load: load,
        builder: (context, d) => ListView.builder(
          itemCount: d.songs.length + 1,
          itemBuilder: (context, i) {
            if (i == 0) return _Head(d);
            return SongTile(songs: d.songs, index: i - 1, rank: ranked ? i : null);
          },
        ),
      ),
    );
  }
}

class _Head extends StatelessWidget {
  const _Head(this.d);

  final ListData d;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final l = AppLocalizations.of(context);
    final description = [if (d.period.isNotEmpty) l.updatedAt(d.period), d.description].join('\n');
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Cover(d.cover, size: 120),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(d.title, style: text.titleLarge),
                const SizedBox(height: 6),
                Text(
                  description.replaceAll(RegExp(r'<[^>]+>'), ''),
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: text.bodySmall,
                ),
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
