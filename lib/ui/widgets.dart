import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show lerpDouble;

import 'package:flutter/foundation.dart' show defaultTargetPlatform;
import 'package:flutter/material.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'package:provider/provider.dart';

import '../l10n/l10n_ext.dart';
import '../player/player_controller.dart';
import '../src/rust/api/types.dart';
import 'glass.dart';
import 'player_page.dart';
import 'player_route.dart';
import 'song_actions.dart';

String formatDuration(Duration d) {
  final m = d.inMinutes;
  final s = d.inSeconds % 60;
  return '$m:${s.toString().padLeft(2, '0')}';
}

String singerNames(Song s) => s.singers.map((e) => e.name).join(' / ');

/// 这个组件在屏幕上的位置，播放页从这里展开。还没布局时返回 null。
Rect? globalRectOf(BuildContext context) {
  final box = context.findRenderObject();
  if (box is! RenderBox || !box.hasSize) return null;
  return box.localToGlobal(Offset.zero) & box.size;
}

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

/// 手机上才有的交互：左右滑切歌、滚动时收成圆球。
/// 跟着 defaultTargetPlatform 走，测试里可以在桌面上模拟手机。
bool get touchPlatform => const {TargetPlatform.android, TargetPlatform.iOS}.contains(defaultTargetPlatform);

/// 浮在底部导航上方的玻璃胶囊播放条。外壳用 Positioned 给它当前的矩形，
/// 形状的过渡由外壳驱动：[faceOpacity] 是歌名和按钮的显示程度，[coverShift] 把封面从左端挪到右端；
/// [round] 时是导航栏旁边的圆球，只剩封面，点一下 [onExpand] 恢复。
/// 胶囊上点一下或按住往上拖打开播放页，手机上左右滑切歌。
/// 里面的按钮都是普通按钮：玻璃里再套玻璃会双重折射，还费 GPU。
class MiniPlayer extends StatefulWidget {
  const MiniPlayer({
    super.key,
    this.round = false,
    this.faceOpacity = 1,
    this.coverShift = 0,
    this.capsuleWidth,
    this.onExpand,
  });

  static const height = 64.0;
  static const _coverSize = 44.0;
  static const _circleCover = 46.0;

  /// 播放页从这里变形出来。
  static final anchor = PlayerBarAnchor(
    coverRadius: _coverSize / 2,
    face: (_) => const Material(type: MaterialType.transparency, child: _MiniFace()),
  );

  final bool round;
  final double faceOpacity;
  final double coverShift;

  /// 胶囊状态的宽度。歌名按它排版，收成圆的途中只被裁掉，不会重新换行。
  final double? capsuleWidth;

  final VoidCallback? onExpand;

  @override
  State<MiniPlayer> createState() => _MiniPlayerState();
}

class _MiniPlayerState extends State<MiniPlayer> with TickerProviderStateMixin {
  /// 左右滑时歌名跟着手指的位移。
  late final _swipe = AnimationController.unbounded(vsync: this);
  late final _drag = PlayerBarDrag(MiniPlayer.anchor, this);

  @override
  void dispose() {
    _swipe.dispose();
    super.dispose();
  }

  /// 松手才切：歌名滑出去，换成下一首从另一边滑进来；不够远就弹回。
  Future<void> _onSwipeEnd(DragEndDetails d) async {
    final p = context.read<PlayerController>();
    final v = d.velocity.pixelsPerSecond.dx;
    final dx = _swipe.value;
    final next = dx < -56 || v < -500;
    final previous = !next && (dx > 56 || v > 500);
    if (!next && !previous) {
      await _swipe.animateTo(0, duration: const Duration(milliseconds: 260), curve: Curves.easeOutCubic);
      return;
    }
    unawaited(next ? p.next() : p.previous());
    const out = 140.0;
    await _swipe.animateTo(next ? -out : out, duration: const Duration(milliseconds: 140), curve: Curves.easeIn);
    if (!mounted) return;
    _swipe.value = next ? out : -out;
    await _swipe.animateTo(0, duration: const Duration(milliseconds: 280), curve: Curves.easeOutCubic);
  }

  @override
  Widget build(BuildContext context) {
    final song = context.select<PlayerController, Song?>((p) => p.current);
    if (song == null) return const SizedBox.shrink();
    prefetchPlayerArt(context, song);
    final round = widget.round;
    final swipe = touchPlatform && !round;
    final bar = GestureDetector(
      key: MiniPlayer.anchor.barKey,
      behavior: HitTestBehavior.opaque,
      onTap: round ? widget.onExpand : () => PlayerRoute.open(context, anchor: MiniPlayer.anchor),
      onVerticalDragUpdate: round ? null : (d) => _drag.update(context, d),
      onVerticalDragEnd: round ? null : (d) => _drag.end(context, d.velocity.pixelsPerSecond.dy),
      onVerticalDragCancel: round ? null : () => _drag.end(context, 0),
      onHorizontalDragStart: swipe ? (_) => _swipe.stop() : null,
      onHorizontalDragUpdate: swipe ? (d) => _swipe.value += d.delta.dx : null,
      onHorizontalDragEnd: swipe ? _onSwipeEnd : null,
      child: LayoutBuilder(
        builder: (context, box) {
          final w = box.maxWidth, h = box.maxHeight;
          // 胶囊里 44，圆球和导航栏那么高时 46
          final d = lerpDouble(MiniPlayer._coverSize, MiniPlayer._circleCover, ((MiniPlayer.height - h) / 6).clamp(0.0, 1.0))!;
          return GlassContainer(
            useOwnLayer: true,
            settings: KanadeGlass.navigationSettings(context),
            quality: KanadeGlass.navigationQuality,
            shape: LiquidRoundedRectangle(borderRadius: math.min(w, h) / 2),
            clipBehavior: Clip.antiAlias,
            child: Material(
              type: MaterialType.transparency,
              child: Stack(
                children: [
                  if (widget.faceOpacity > 0)
                    Positioned(
                      left: 0,
                      top: (h - MiniPlayer.height) / 2,
                      width: widget.capsuleWidth ?? w,
                      height: MiniPlayer.height,
                      child: Opacity(opacity: widget.faceOpacity.clamp(0.0, 1.0), child: _MiniFace(swipe: _swipe)),
                    ),
                  Positioned(
                    // 封面平时待在左端的半圆里，收成圆时是右边缩进来
                    left: lerpDouble((h - d) / 2, w - (h + d) / 2, widget.coverShift),
                    top: (h - d) / 2,
                    width: d,
                    height: d,
                    child: KeyedSubtree(
                      key: MiniPlayer.anchor.coverKey,
                      child: Cover(song.coverUrl, size: d, radius: d / 2),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
    // 播放页盖在上面时由转场层画它，这里藏起来
    return ValueListenableBuilder(
      valueListenable: MiniPlayer.anchor.hidden,
      child: bar,
      builder: (_, hidden, bar) => Opacity(opacity: hidden ? 0 : 1, child: bar),
    );
  }
}

/// 胶囊上除封面以外的部分：歌名、播放键（桌面没有手势，再加上一首 / 下一首）、进度线。
class _MiniFace extends StatelessWidget {
  const _MiniFace({this.swipe});

  final Animation<double>? swipe;

  @override
  Widget build(BuildContext context) {
    final p = context.watch<PlayerController>();
    final song = p.current;
    if (song == null) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    Widget title = Column(
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
          p.error == null ? singerNames(song) : playerErrorText(AppLocalizations.of(context), p.error!),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(fontSize: 12, color: p.error != null ? scheme.error : scheme.onSurfaceVariant),
        ),
      ],
    );
    final swipe = this.swipe;
    if (swipe != null) {
      title = ClipRect(
        child: AnimatedBuilder(
          animation: swipe,
          child: title,
          builder: (_, title) => Transform.translate(
            offset: Offset(swipe.value, 0),
            child: Opacity(opacity: (1 - swipe.value.abs() / 140).clamp(0.0, 1.0), child: title),
          ),
        ),
      );
    }
    return Stack(
      children: [
        Row(
          children: [
            const SizedBox(width: 10 + MiniPlayer._coverSize + 12),
            Expanded(child: title),
            if (!touchPlatform)
              IconButton(
                onPressed: p.previous,
                icon: Icon(Icons.skip_previous_rounded, color: scheme.onSurface),
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
                      icon: Icon(p.playing ? Icons.pause_rounded : Icons.play_arrow_rounded, color: scheme.onPrimary),
                    ),
            ),
            if (!touchPlatform)
              IconButton(
                onPressed: p.next,
                icon: Icon(Icons.skip_next_rounded, color: scheme.onSurface),
              ),
            // 手机上播放键和胶囊右端的半圆同心
            SizedBox(width: touchPlatform ? 12 : 8),
          ],
        ),
        // 进度线只画在胶囊的直边上
        Positioned(
          left: MiniPlayer.height / 2,
          right: MiniPlayer.height / 2,
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
    );
  }
}
