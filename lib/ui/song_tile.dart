import 'package:flutter/foundation.dart' show defaultTargetPlatform;
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../data/data_ext.dart';
import '../l10n/l10n_ext.dart';
import '../player/player_controller.dart';
import '../src/rust/api/types.dart';
import 'song_action_sheet.dart';
import 'widgets.dart';

class SongTile extends StatelessWidget {
  const SongTile({
    super.key,
    required this.songs,
    required this.index,
    this.rank,
    this.onRemove,
    this.tags = const [],
  });

  final List<Song> songs;
  final int index;
  final int? rank;

  /// 自己的歌单里才有，更多菜单里会出现“从歌单中删除”。
  final VoidCallback? onRemove;

  /// 搜索结果里的“飙升榜No.18”、一句热评这类标签，显示在歌手名下面一行。
  final List<String> tags;

  static const _coverSize = 48.0;

  @override
  Widget build(BuildContext context) {
    final song = songs[index];
    // 只订阅和这一行有关的状态，切歌时其它行不用重建
    final isCurrent = context.select<PlayerController, bool>(
      (p) => p.current?.mid == song.mid,
    );
    final playing =
        isCurrent && context.select<PlayerController, bool>((p) => p.playing);
    final scheme = Theme.of(context).colorScheme;
    return ListTile(
      leading: rank != null
          ? SizedBox(
              width: 32,
              child: Center(
                child: isCurrent
                    ? PlayingBars(animate: playing)
                    : Text(
                        '$rank',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                          color: rank! <= 3
                              ? scheme.primary
                              : scheme.onSurfaceVariant,
                        ),
                      ),
              ),
            )
          : Stack(
              children: [
                Cover(
                  song.coverUrl,
                  size: _coverSize,
                  // QQ 的 300px 方形封面按列表实际需要的物理像素解码。
                  cacheWidth:
                      defaultTargetPlatform == TargetPlatform.android &&
                          song.coverUrl.contains('R300x300M000')
                      ? (_coverSize * MediaQuery.devicePixelRatioOf(context))
                            .ceil()
                      : null,
                ),
                if (isCurrent)
                  Positioned.fill(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: Colors.black45,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Center(child: PlayingBars(animate: playing)),
                    ),
                  ),
              ],
            ),
      title: Text(
        song.name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w600,
          color: isCurrent ? scheme.primary : null,
        ),
      ),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 3),
        child: _withTags(
          Row(
            children: [
              if (song.vip) const QualityBadge('VIP', filled: true),
              if (song.hasFlac)
                const QualityBadge('SQ')
              else if (song.hasHq)
                const QualityBadge('HQ'),
              Expanded(
                child: Text(
                  [
                    singerNames(song),
                    if (song.albumName.isNotEmpty) song.albumName,
                  ].join(' · '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          scheme,
        ),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            formatDuration(Duration(seconds: song.durationSecs)),
            style: TextStyle(
              fontSize: 13,
              color: scheme.onSurfaceVariant,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          IconButton(
            tooltip: AppLocalizations.of(context).more,
            color: scheme.onSurfaceVariant,
            icon: const Icon(Icons.more_vert),
            onPressed: () => showSongActions(context, song, onRemove: onRemove),
          ),
        ],
      ),
      contentPadding: const EdgeInsetsDirectional.only(start: 16, end: 4),
      onTap: () => context.read<PlayerController>().playList(songs, index),
      onLongPress: () => showSongActions(context, song, onRemove: onRemove),
    );
  }

  Widget _withTags(Widget subtitle, ColorScheme scheme) {
    if (tags.isEmpty) return subtitle;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        subtitle,
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Text(
            tags.join("  "),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 12, color: scheme.primary),
          ),
        ),
      ],
    );
  }
}
