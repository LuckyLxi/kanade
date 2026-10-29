import 'dart:math' as math;

import 'package:flutter/foundation.dart' show defaultTargetPlatform;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/data_ext.dart';
import '../l10n/l10n_ext.dart';
import '../player/player_controller.dart';
import '../src/rust/api/types.dart';
import 'song_actions.dart';

String formatDuration(Duration d) {
  final m = d.inMinutes;
  final s = d.inSeconds % 60;
  return '$m:${s.toString().padLeft(2, '0')}';
}

/// 提示条。页面已经关掉、找不到 ScaffoldMessenger 时什么都不做。
void showToast(BuildContext context, String text) =>
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text(text)));

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
              httpsUrl(url),
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
                FilledButton.tonal(onPressed: () => setState(() => _future = widget.load()), child: Text(l.retry)),
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
  const SongTile({super.key, required this.songs, required this.index, this.rank, this.onRemove});

  final List<Song> songs;
  final int index;
  final int? rank;

  /// 自己的歌单里才有，更多菜单里会出现“从歌单中删除”。
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final song = songs[index];
    // 只订阅和这一行有关的状态，切歌时其它行不用重建
    final isCurrent = context.select<PlayerController, bool>((p) => p.current?.mid == song.mid);
    final playing = isCurrent && context.select<PlayerController, bool>((p) => p.playing);
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
                          color: rank! <= 3 ? scheme.primary : scheme.onSurfaceVariant,
                        ),
                      ),
              ),
            )
          : Stack(
              children: [
                Cover(song.coverUrl, size: 48, radius: 8),
                if (isCurrent)
                  Positioned.fill(
                    child: DecoratedBox(
                      decoration: BoxDecoration(color: Colors.black45, borderRadius: BorderRadius.circular(8)),
                      child: Center(child: PlayingBars(animate: playing)),
                    ),
                  ),
              ],
            ),
      title: Text(
        song.name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: isCurrent ? scheme.primary : null),
      ),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 3),
        child: Row(
          children: [
            if (song.vip) const QualityBadge('VIP', filled: true),
            if (song.hasFlac) const QualityBadge('SQ') else if (song.hasHq) const QualityBadge('HQ'),
            Expanded(
              child: Text(
                [singerNames(song), if (song.albumName.isNotEmpty) song.albumName].join(' · '),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
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
}

/// 页面里的区块标题，右侧可选一个“全部”。
class SectionHeader extends StatelessWidget {
  const SectionHeader(this.text, {super.key, this.onMore, this.padding = const EdgeInsets.fromLTRB(16, 24, 8, 8)});

  final String text;
  final VoidCallback? onMore;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: padding,
      child: Row(
        children: [
          Expanded(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w700),
            ),
          ),
          if (onMore != null)
            TextButton(
              onPressed: onMore,
              style: TextButton.styleFrom(foregroundColor: scheme.onSurfaceVariant),
              child: Text(AppLocalizations.of(context).seeAll),
            ),
        ],
      ),
    );
  }
}

/// 列表末尾的留白：玻璃导航栏和播放条浮在内容上，盖住的高度在 MediaQuery 的底部 padding 里。
class BottomSpacer extends StatelessWidget {
  const BottomSpacer({super.key});

  @override
  Widget build(BuildContext context) => SizedBox(height: MediaQuery.paddingOf(context).bottom + 16);
}

/// 切换用的小胶囊：选中是白底黑字，没选中是描边。
class Pill extends StatelessWidget {
  const Pill({super.key, required this.label, required this.selected, required this.onTap, this.large = false});

  final String label;
  final bool selected;
  final VoidCallback onTap;

  /// 页面顶上那种大一号的。
  final bool large;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: selected ? scheme.secondaryContainer : Colors.transparent,
      shape: StadiumBorder(side: selected ? BorderSide.none : BorderSide(color: scheme.outlineVariant)),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: large
              ? const EdgeInsets.symmetric(horizontal: 18, vertical: 8)
              : const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
          child: Text(
            label,
            style: TextStyle(
              fontSize: large ? 15 : 13,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
              color: selected ? scheme.onSecondaryContainer : scheme.onSurfaceVariant,
            ),
          ),
        ),
      ),
    );
  }
}

/// 方形封面 + 标题的歌单卡片，播放量放在左上角的小胶囊里。
class PlaylistCard extends StatelessWidget {
  const PlaylistCard({super.key, required this.title, required this.coverUrl, this.badge, required this.onTap});

  final String title;
  final String coverUrl;
  final String? badge;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AspectRatio(
            aspectRatio: 1,
            child: Stack(
              fit: StackFit.expand,
              children: [
                Cover(coverUrl, radius: 14),
                if (badge != null)
                  Positioned(
                    left: 8,
                    top: 8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                      decoration: BoxDecoration(color: Colors.black45, borderRadius: BorderRadius.circular(99)),
                      child: Text(
                        badge!,
                        style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, height: 1.35),
          ),
        ],
      ),
    );
  }
}

/// 音质 / 会员标签。VIP 用抗色实底，音质用灰色描边。
class QualityBadge extends StatelessWidget {
  const QualityBadge(this.text, {super.key, this.filled = false});

  final String text;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(right: 5),
      padding: const EdgeInsets.symmetric(horizontal: 4),
      decoration: BoxDecoration(
        color: filled ? scheme.primary : null,
        border: filled ? null : Border.all(color: scheme.onSurfaceVariant.withValues(alpha: 0.6)),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 9,
          fontWeight: FontWeight.w800,
          height: 1.4,
          color: filled ? scheme.onPrimary : scheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

/// 正在播放的三根跳动音柱。暂停时停在中间高度。
class PlayingBars extends StatefulWidget {
  const PlayingBars({super.key, required this.animate, this.color});

  final bool animate;
  final Color? color;

  @override
  State<PlayingBars> createState() => _PlayingBarsState();
}

class _PlayingBarsState extends State<PlayingBars> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 900));

  @override
  void initState() {
    super.initState();
    if (widget.animate) _c.repeat();
  }

  @override
  void didUpdateWidget(PlayingBars old) {
    super.didUpdateWidget(old);
    if (widget.animate && !_c.isAnimating) {
      _c.repeat();
    } else if (!widget.animate && _c.isAnimating) {
      _c.stop();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.color ?? Theme.of(context).colorScheme.primary;
    return SizedBox(
      width: 16,
      height: 15,
      child: AnimatedBuilder(
        animation: _c,
        builder: (_, _) => Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            for (var i = 0; i < 3; i++)
              Container(
                width: 3,
                // 三根错开三分之一个周期
                height: 4 + 11 * (0.5 + 0.5 * math.sin((_c.value + i / 3) * 2 * math.pi)),
                decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(2)),
              ),
          ],
        ),
      ),
    );
  }
}

/// 手机上才有的交互：左右滑切歌、滚动时收成圆球。
/// 跟着 defaultTargetPlatform 走，测试里可以在桌面上模拟手机。
bool get touchPlatform => const {TargetPlatform.android, TargetPlatform.iOS}.contains(defaultTargetPlatform);
