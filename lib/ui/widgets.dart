import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/l10n_ext.dart';
import '../player/player_controller.dart';
import '../src/rust/api/types.dart';
import 'player_page.dart';
import 'song_actions.dart';

String formatDuration(Duration d) {
  final m = d.inMinutes;
  final s = d.inSeconds % 60;
  return '$m:${s.toString().padLeft(2, '0')}';
}

String singerNames(Song s) => s.singers.map((e) => e.name).join(' / ');

class Cover extends StatelessWidget {
  const Cover(this.url, {super.key, this.size, this.radius = 8});

  final String url;
  final double? size;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final placeholder = Container(
      width: size,
      height: size,
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: const Icon(Icons.music_note),
    );
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: url.isEmpty
          ? placeholder
          : Image.network(
              url.replaceFirst('http://', 'https://'),
              width: size,
              height: size,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => placeholder,
            ),
    );
  }
}

/// 带加载 / 出错重试的 FutureBuilder。
class AsyncView<T> extends StatefulWidget {
  const AsyncView({super.key, required this.load, required this.builder});

  final Future<T> Function() load;
  final Widget Function(BuildContext, T) builder;

  @override
  State<AsyncView<T>> createState() => _AsyncViewState<T>();
}

class _AsyncViewState<T> extends State<AsyncView<T>> {
  late Future<T> _future = widget.load();

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<T>(
      future: _future,
      builder: (context, snap) {
        if (snap.hasError) {
          final l = AppLocalizations.of(context);
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(l.loadFailed(errorText(l, snap.error!)), textAlign: TextAlign.center),
                const SizedBox(height: 12),
                FilledButton.tonal(
                  onPressed: () => setState(() => _future = widget.load()),
                  child: Text(l.retry),
                ),
              ],
            ),
          );
        }
        if (!snap.hasData) return const Center(child: CircularProgressIndicator());
        return widget.builder(context, snap.data as T);
      },
    );
  }
}

class SongTile extends StatelessWidget {
  const SongTile({super.key, required this.songs, required this.index, this.rank});

  final List<Song> songs;
  final int index;
  final int? rank;

  @override
  Widget build(BuildContext context) {
    final song = songs[index];
    final player = context.watch<PlayerController>();
    final isCurrent = player.current?.mid == song.mid;
    final scheme = Theme.of(context).colorScheme;
    return ListTile(
      leading: rank != null
          ? SizedBox(
              width: 32,
              child: Center(
                child: Text(
                  '$rank',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: rank! <= 3 ? scheme.primary : scheme.onSurfaceVariant,
                  ),
                ),
              ),
            )
          : Cover(song.coverUrl, size: 44, radius: 6),
      title: Text(
        song.name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(color: isCurrent ? scheme.primary : null),
      ),
      subtitle: Row(
        children: [
          if (song.vip) const _Badge('VIP'),
          if (song.hasFlac) const _Badge('SQ') else if (song.hasHq) const _Badge('HQ'),
          Expanded(
            child: Text(
              [singerNames(song), if (song.albumName.isNotEmpty) song.albumName].join(' · '),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(formatDuration(Duration(seconds: song.durationSecs))),
          IconButton(
            tooltip: AppLocalizations.of(context).more,
            icon: const Icon(Icons.more_vert),
            onPressed: () => showSongActions(context, song),
          ),
        ],
      ),
      contentPadding: const EdgeInsetsDirectional.only(start: 16, end: 4),
      onTap: () => player.playList(songs, index),
      onLongPress: () => showSongActions(context, song),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme.primary;
    return Container(
      margin: const EdgeInsets.only(right: 4),
      padding: const EdgeInsets.symmetric(horizontal: 3),
      decoration: BoxDecoration(border: Border.all(color: c), borderRadius: BorderRadius.circular(3)),
      child: Text(text, style: TextStyle(fontSize: 9, color: c, height: 1.3)),
    );
  }
}

class MiniPlayer extends StatelessWidget {
  const MiniPlayer({super.key});

  @override
  Widget build(BuildContext context) {
    final p = context.watch<PlayerController>();
    final song = p.current;
    if (song == null) return const SizedBox.shrink();
    prefetchPlayerArt(context, song);
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surfaceContainer,
      child: InkWell(
        onTap: () => Navigator.of(context, rootNavigator: true).push(PlayerPage.route()),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ValueListenableBuilder(
              valueListenable: p.position,
              builder: (_, pos, _) => LinearProgressIndicator(
                minHeight: 2,
                value: p.duration.inMilliseconds == 0
                    ? 0
                    : (pos.inMilliseconds / p.duration.inMilliseconds).clamp(0.0, 1.0),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                children: [
                  Hero(tag: 'cover', child: Cover(song.coverUrl, size: 44, radius: 6)),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(song.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                        Text(
                          p.error == null ? singerNames(song) : playerErrorText(AppLocalizations.of(context), p.error!),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12,
                            color: p.error != null ? scheme.error : scheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(onPressed: p.previous, icon: const Icon(Icons.skip_previous)),
                  p.loading || p.buffering
                      ? const SizedBox(
                          width: 48,
                          height: 48,
                          child: Padding(padding: EdgeInsets.all(14), child: CircularProgressIndicator(strokeWidth: 2)),
                        )
                      : IconButton(
                          onPressed: p.toggle,
                          icon: Icon(p.playing ? Icons.pause : Icons.play_arrow),
                        ),
                  IconButton(onPressed: p.next, icon: const Icon(Icons.skip_next)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
