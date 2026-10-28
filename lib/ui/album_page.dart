import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/l10n_ext.dart';
import '../player/player_controller.dart';
import '../src/rust/api/music.dart' as api;
import '../src/rust/api/types.dart';
import 'comments_page.dart';
import 'singer_page.dart';
import 'widgets.dart';

class AlbumPage extends StatelessWidget {
  const AlbumPage({super.key, required this.mid, required this.name});

  final String mid;
  final String name;

  static Route<void> route(String mid, String name) => MaterialPageRoute(builder: (_) => AlbumPage(mid: mid, name: name));

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(name)),
      body: AsyncView<AlbumDetail>(
        load: () => api.getAlbumDetail(mid: mid),
        builder: (context, d) => ListView.builder(
          itemCount: d.songs.length + 1,
          itemBuilder: (context, i) => i == 0 ? _Head(d) : SongTile(songs: d.songs, index: i - 1),
        ),
      ),
    );
  }
}

class _Head extends StatelessWidget {
  const _Head(this.d);

  final AlbumDetail d;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final l = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Cover(d.coverUrl, size: 120),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(d.name, style: text.titleLarge),
                const SizedBox(height: 4),
                Wrap(
                  spacing: 4,
                  children: [
                    for (final s in d.singers)
                      InkWell(
                        onTap: s.mid.isEmpty ? null : () => Navigator.of(context).push(SingerPage.route(s.mid, s.name)),
                        child: Text(s.name, style: text.bodyMedium?.copyWith(color: Theme.of(context).colorScheme.primary)),
                      ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  [if (d.publishDate.isNotEmpty) l.publishedOn(d.publishDate), d.company].where((s) => s.isNotEmpty).join(' · '),
                  style: text.bodySmall,
                ),
                if (d.description.isNotEmpty)
                  Text(d.description, maxLines: 3, overflow: TextOverflow.ellipsis, style: text.bodySmall),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    FilledButton.icon(
                      onPressed: d.songs.isEmpty ? null : () => context.read<PlayerController>().playList(d.songs, 0),
                      icon: const Icon(Icons.play_arrow),
                      label: Text(l.playAll(d.songs.length)),
                    ),
                    OutlinedButton.icon(
                      onPressed: d.id == 0 ? null : () => Navigator.of(context).push(CommentsPage.album(d)),
                      icon: const Icon(Icons.comment_outlined),
                      label: Text(l.comments),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
