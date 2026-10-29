import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'package:provider/provider.dart';

import '../l10n/l10n_ext.dart';
import '../player/player_controller.dart';
import '../src/rust/api/types.dart';
import 'glass.dart';
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

/// 浮在底部导航上方的玻璃播放条。里面的按钮都是普通按钮：玻璃里再套玻璃会双重折射，还费 GPU。
class MiniPlayer extends StatelessWidget {
  const MiniPlayer({super.key});

  static const height = 64.0;

  @override
  Widget build(BuildContext context) {
    final p = context.watch<PlayerController>();
    final song = p.current;
    if (song == null) return const SizedBox.shrink();
    prefetchPlayerArt(context, song);
    final scheme = Theme.of(context).colorScheme;
    return GlassContainer(
      useOwnLayer: true,
      settings: KanadeGlass.playerBarSettings(context),
      quality: KanadeGlass.navigationQuality,
      height: height,
      shape: const LiquidRoundedSuperellipse(borderRadius: 22),
      clipBehavior: Clip.antiAlias,
      child: Material(
        color: KanadeGlass.playerBarScrim(context),
        child: InkWell(
          onTap: () => Navigator.of(context, rootNavigator: true).push(PlayerPage.route()),
          child: Stack(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: Row(
                  children: [
                    Hero(tag: 'cover', child: Cover(song.coverUrl, size: 44, radius: 10)),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            song.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                          ),
                          Text(
                            p.error == null
                                ? singerNames(song)
                                : playerErrorText(AppLocalizations.of(context), p.error!),
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
                    SizedBox.square(
                      dimension: 40,
                      child: p.loading || p.buffering
                          ? Padding(
                              padding: const EdgeInsets.all(10),
                              child: CircularProgressIndicator(strokeWidth: 2, color: scheme.primary),
                            )
                          : IconButton.filled(
                              padding: EdgeInsets.zero,
                              onPressed: p.toggle,
                              // 玻璃层会改写继承的图标颜色，这里显式指定
                              icon: Icon(
                                p.playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                                color: scheme.onPrimary,
                              ),
                            ),
                    ),
                    IconButton(
                      onPressed: p.next,
                      icon: Icon(Icons.skip_next_rounded, color: scheme.onSurface),
                    ),
                  ],
                ),
              ),
              Positioned(
                left: 22,
                right: 22,
                bottom: 0,
                child: ValueListenableBuilder(
                  valueListenable: p.position,
                  builder: (_, pos, _) => LinearProgressIndicator(
                    minHeight: 2,
                    backgroundColor: scheme.onSurface.withValues(alpha: 0.12),
                    value: p.duration.inMilliseconds == 0
                        ? 0
                        : (pos.inMilliseconds / p.duration.inMilliseconds).clamp(0.0, 1.0),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
