import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../l10n/l10n_ext.dart';
import '../library/library_controller.dart';
import '../player/player_controller.dart';
import '../src/rust/api/types.dart';
import 'comments_page.dart';
import 'player_background.dart';
import 'player_lyrics.dart';
import 'player_route.dart';
import 'song_actions.dart';
import 'widgets.dart';

enum _Panel { none, lyrics, queue }


const _motion = Duration(milliseconds: 550);
const _curve = Curves.easeInOutCubicEmphasized;

/// 播放页用的大封面地址。
String bigCoverUrl(Song s) => s.coverUrl.replaceFirst('300x300', '500x500');

String? _prefetched;

/// 切歌时就把播放页要用的大封面和背景素材准备好，
/// 打开播放页时不用在转场动画期间临时下载、取色、模糊。
void prefetchPlayerArt(BuildContext context, Song song) {
  final url = bigCoverUrl(song);
  if (url.isEmpty || url == _prefetched) return;
  _prefetched = url;
  WidgetsBinding.instance.addPostFrameCallback((_) {
    if (!context.mounted) return;
    unawaited(precacheImage(NetworkImage(url.replaceFirst('http://', 'https://')), context));
    unawaited(loadCoverArt(url).then<void>((_) {}, onError: (_) {}));
  });
}

final _fallbackTheme = ThemeData(
  useMaterial3: true,
  colorScheme: ColorScheme.fromSeed(seedColor: fallbackPalette[1], brightness: Brightness.dark),
);

/// Apple Music 风格的全屏播放页：封面取色流动背景、下拉关闭，
/// 窄屏下封面会收进左上角，给歌词 / 播放队列腾地方。
class PlayerPage extends StatefulWidget {
  const PlayerPage({super.key, this.showQueue = false});

  /// 打开时直接显示播放队列（桌面底栏的队列按钮用）。
  final bool showQueue;

  /// 给了 [anchor] 时播放页从那个播放条变形出来，关闭时变回去；不给就从屏幕底边升上来。
  static Route<void> route({PlayerBarAnchor? anchor, bool showQueue = false}) =>
      PlayerRoute(anchor: anchor, showQueue: showQueue);

  @override
  State<PlayerPage> createState() => _PlayerPageState();
}

class _PlayerPageState extends State<PlayerPage> {
  late _Panel _panel = widget.showQueue ? _Panel.queue : _Panel.none;
  CoverArt? _art;
  String? _artUrl;

  List<Color> get _palette => _art?.palette ?? fallbackPalette;

  void _loadArt(String url) {
    if (url == _artUrl) return;
    _artUrl = url;
    if (url.isEmpty) return;
    // 迷你播放器一般已经预取好了，第一帧直接用
    final cached = cachedCoverArt(url);
    if (cached != null) {
      _art = cached;
      return;
    }
    loadCoverArt(url).then(
      (art) {
        if (mounted && _artUrl == url) setState(() => _art = art);
      },
      onError: (_) {},
    );
  }

  void _togglePanel(_Panel panel) => setState(() => _panel = _panel == panel ? _Panel.none : panel);

  @override
  Widget build(BuildContext context) {
    final p = context.watch<PlayerController>();
    final song = p.current;
    if (song == null) return const Scaffold();
    final cover = bigCoverUrl(song);
    _loadArt(cover);
    final wide = MediaQuery.sizeOf(context).width >= 800;
    final route = ModalRoute.of(context);

    final page = Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          PlayerBackground(art: _art, animate: p.playing),
          // 背景每帧都在动，前景单独一层，避免跟着重绘
          RepaintBoundary(
            child: SafeArea(
              child: Column(
                children: [
                  _Grabber(onTap: () => Navigator.pop(context)),
                  Expanded(child: wide ? _wide(p, song, cover) : _narrow(p, song, cover)),
                ],
              ),
            ),
          ),
        ],
      ),
    );

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Theme(
        data: _art?.theme ?? _fallbackTheme,
        // 下拉时整页沿着变形的路径缩回播放条，手指松开再决定关还是弹回
        child: route is PlayerRoute
            ? GestureDetector(
                onVerticalDragStart: (_) => route.dragStart(),
                onVerticalDragUpdate: (d) => route.dragUpdate(d.delta.dy),
                onVerticalDragEnd: (d) => route.dragEnd(d.velocity.pixelsPerSecond.dy),
                onVerticalDragCancel: () => route.dragEnd(0),
                child: page,
              )
            : page,
      ),
    );
  }

  Widget _narrow(PlayerController p, Song song, String cover) {
    final open = _panel != _Panel.none;
    return Column(
      children: [
        Expanded(
          child: LayoutBuilder(
            builder: (context, c) {
              const pad = 28.0, titleH = 64.0, small = 60.0;
              final size = min(c.maxWidth - pad * 2, c.maxHeight - titleH - 28).clamp(80.0, 560.0);
              final top = max(0.0, (c.maxHeight - size - titleH - 24) / 2);
              final coverRect = open
                  ? const Rect.fromLTWH(24, 4, small, small)
                  : Rect.fromLTWH((c.maxWidth - size) / 2, top, size, size);
              final titleRect = open
                  ? Rect.fromLTWH(24 + small + 14, 4, c.maxWidth - 24 - small - 14 - 20, small)
                  : Rect.fromLTWH(pad, top + size + 24, c.maxWidth - pad * 2, titleH);
              return Stack(
                children: [
                  Positioned.fill(
                    top: small + 16,
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 400),
                      switchInCurve: Curves.easeOutCubic,
                      transitionBuilder: (child, a) => FadeTransition(
                        opacity: a,
                        child: SlideTransition(
                          position: Tween(begin: const Offset(0, 0.06), end: Offset.zero).animate(a),
                          child: child,
                        ),
                      ),
                      child: switch (_panel) {
                        _Panel.lyrics => const LyricView(key: ValueKey('lyrics')),
                        _Panel.queue => const _QueuePanel(key: ValueKey('queue')),
                        _Panel.none => const SizedBox.shrink(),
                      },
                    ),
                  ),
                  AnimatedPositioned.fromRect(
                    rect: coverRect,
                    duration: _motion,
                    curve: _curve,
                    child: _AlbumArt(url: cover, playing: p.playing, expanded: !open),
                  ),
                  AnimatedPositioned.fromRect(
                    rect: titleRect,
                    duration: _motion,
                    curve: _curve,
                    child: _TitleRow(song: song, compact: open),
                  ),
                ],
              );
            },
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(28, 8, 28, 8),
          child: _ControlsArea(panel: _panel, accent: _palette.first, onPanel: _togglePanel),
        ),
      ],
    );
  }

  Widget _wide(PlayerController p, Song song, String cover) {
    // 宽屏右侧始终有内容：默认歌词，点队列切换
    final panel = _panel == _Panel.queue ? _Panel.queue : _Panel.lyrics;
    return Row(
      children: [
        Expanded(
          flex: 5,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(56, 8, 40, 24),
            child: Column(
              children: [
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, c) {
                      final size = min(min(c.maxWidth, c.maxHeight), 520.0);
                      return Center(
                        child: SizedBox.square(
                          dimension: size,
                          child: _AlbumArt(url: cover, playing: p.playing, expanded: true),
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 28),
                SizedBox(height: 64, child: _TitleRow(song: song, compact: false)),
                const SizedBox(height: 12),
                _ControlsArea(
                  panel: panel,
                  accent: _palette.first,
                  onPanel: (x) => setState(() => _panel = x == _Panel.queue && _panel != _Panel.queue ? x : _Panel.lyrics),
                ),
              ],
            ),
          ),
        ),
        Expanded(
          flex: 6,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(0, 8, 40, 8),
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 400),
              child: panel == _Panel.queue
                  ? const _QueuePanel(key: ValueKey('queue'))
                  : const LyricView(key: ValueKey('lyrics'), fontSize: 36),
            ),
          ),
        ),
      ],
    );
  }
}

class _Grabber extends StatelessWidget {
  const _Grabber({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(0, 8, 0, 14),
        child: Center(
          child: Container(
            width: 40,
            height: 5,
            decoration: BoxDecoration(color: Colors.white38, borderRadius: BorderRadius.circular(3)),
          ),
        ),
      ),
    );
  }
}

/// 大封面的投影：播放时浮起来、阴影更深。飞行中的封面也用它，落地时阴影不会突然冒出来。
BoxShadow albumArtShadow({required bool lifted}) => BoxShadow(
  color: Colors.black.withValues(alpha: lifted ? 0.5 : 0.28),
  blurRadius: lifted ? 60 : 18,
  spreadRadius: lifted ? 2 : 0,
  offset: Offset(0, lifted ? 28 : 8),
);

/// 封面：暂停时缩小、播放时弹回并加深投影；大图状态下左右滑动切歌。
class _AlbumArt extends StatelessWidget {
  const _AlbumArt({required this.url, required this.playing, required this.expanded});

  final String url;
  final bool playing;
  final bool expanded;

  @override
  Widget build(BuildContext context) {
    final p = context.read<PlayerController>();
    final lifted = expanded && playing;
    final radius = expanded ? 14.0 : 8.0;
    final morph = PlayerMorph.maybeOf(context);
    final art = GestureDetector(
      onHorizontalDragEnd: !expanded
          ? null
          : (d) {
              final v = d.velocity.pixelsPerSecond.dx;
              if (v < -300) unawaited(p.next());
              if (v > 300) unawaited(p.previous());
            },
      child: AnimatedScale(
        scale: expanded && !playing ? 0.8 : 1,
        duration: const Duration(milliseconds: 650),
        curve: playing ? Curves.easeOutBack : Curves.easeOutCubic,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 650),
          curve: Curves.easeOutCubic,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(radius),
            boxShadow: [albumArtShadow(lifted: lifted)],
          ),
          // 打开播放页时封面从播放条飞过来，落点量的就是这里
          child: KeyedSubtree(
            key: morph?.artKey,
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 450),
              transitionBuilder: (child, a) => FadeTransition(
                opacity: a,
                child: ScaleTransition(scale: Tween(begin: 0.94, end: 1.0).animate(a), child: child),
              ),
              child: SizedBox.expand(key: ValueKey(url), child: Cover(url, radius: radius)),
            ),
          ),
        ),
      ),
    );
    if (morph == null) return art;
    // 封面还在飞的时候这里先藏起来，落地再接上
    return ValueListenableBuilder(
      valueListenable: morph.artInFlight,
      child: art,
      builder: (_, flying, art) => Opacity(opacity: flying ? 0 : 1, child: art),
    );
  }
}

class _TitleRow extends StatelessWidget {
  const _TitleRow({required this.song, required this.compact});

  final Song song;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final p = context.watch<PlayerController>();
    final l = AppLocalizations.of(context);
    final error = p.error;
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              AnimatedDefaultTextStyle(
                duration: _motion,
                curve: _curve,
                style: TextStyle(fontSize: compact ? 17 : 22, fontWeight: FontWeight.w800, color: Colors.white),
                child: _Marquee(song.name),
              ),
              const SizedBox(height: 2),
              GestureDetector(
                onTap: () => openSinger(context, song),
                child: AnimatedDefaultTextStyle(
                  duration: _motion,
                  curve: _curve,
                  style: TextStyle(
                    fontSize: compact ? 14 : 18,
                    fontWeight: FontWeight.w500,
                    color: error != null ? const Color(0xFFFF9A9A) : Colors.white60,
                  ),
                  child: Text(
                    error != null ? playerErrorText(l, error) : singerNames(song),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        _LikeButton(song),
        const SizedBox(width: 10),
        _GlassButton(
          tooltip: l.more,
          onTap: () => showSongActions(context, song),
          child: const Icon(Icons.more_horiz_rounded, color: Colors.white, size: 22),
        ),
      ],
    );
  }
}

/// 文字超宽时来回滚动，两端渐隐。
class _Marquee extends StatefulWidget {
  const _Marquee(this.text);

  final String text;

  @override
  State<_Marquee> createState() => _MarqueeState();
}

class _MarqueeState extends State<_Marquee> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this);
  static const _gap = 48.0;

  @override
  void didUpdateWidget(_Marquee old) {
    super.didUpdateWidget(old);
    if (old.text != widget.text) _c.reset();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final style = DefaultTextStyle.of(context).style;
    return LayoutBuilder(
      builder: (context, c) {
        final tp = TextPainter(
          text: TextSpan(text: widget.text, style: style),
          maxLines: 1,
          textDirection: Directionality.of(context),
        )..layout();
        final w = tp.width, h = tp.height;
        tp.dispose();
        if (w <= c.maxWidth) {
          if (_c.isAnimating) _c.stop();
          return Text(widget.text, maxLines: 1, softWrap: false);
        }
        // 前 3 秒停住，然后匀速滚过一整段
        final travel = w + _gap;
        final scroll = Duration(milliseconds: (travel / 40 * 1000).round());
        final total = scroll + const Duration(seconds: 3);
        if (_c.duration != total || !_c.isAnimating) {
          _c.duration = total;
          _c.repeat();
        }
        final hold = 3000 / total.inMilliseconds;
        return ShaderMask(
          blendMode: BlendMode.dstIn,
          shaderCallback: (r) => const LinearGradient(
            colors: [Colors.black, Colors.black, Colors.transparent],
            stops: [0, 0.88, 1],
          ).createShader(r),
          child: ClipRect(
            child: SizedBox(
              height: h,
              child: AnimatedBuilder(
                animation: _c,
                builder: (_, child) {
                  final t = _c.value < hold ? 0.0 : (_c.value - hold) / (1 - hold);
                  return Transform.translate(offset: Offset(-t * travel, 0), child: child);
                },
                child: OverflowBox(
                  alignment: Alignment.centerLeft,
                  maxWidth: double.infinity,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [Text(widget.text, maxLines: 1), const SizedBox(width: _gap), Text(widget.text, maxLines: 1)],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _GlassButton extends StatelessWidget {
  const _GlassButton({required this.child, required this.onTap, this.tooltip});

  final Widget child;
  final VoidCallback onTap;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final button = Material(
      color: Colors.white.withValues(alpha: 0.14),
      shape: const CircleBorder(),
      clipBehavior: Clip.antiAlias,
      child: InkWell(onTap: onTap, child: SizedBox.square(dimension: 36, child: Center(child: child))),
    );
    return tooltip == null ? button : Tooltip(message: tooltip!, child: button);
  }
}

class _LikeButton extends StatelessWidget {
  const _LikeButton(this.song);

  final Song song;

  @override
  Widget build(BuildContext context) {
    final liked = context.watch<LibraryController>().isLiked(song);
    final l = AppLocalizations.of(context);
    return _GlassButton(
      tooltip: liked ? l.unlike : l.like,
      onTap: () => toggleLike(context, song),
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 450),
        switchInCurve: Curves.elasticOut,
        transitionBuilder: (child, a) => ScaleTransition(scale: a, child: child),
        child: Icon(
          liked ? Icons.favorite_rounded : Icons.favorite_border_rounded,
          key: ValueKey(liked),
          size: 20,
          color: liked ? const Color(0xFFFF4D6D) : Colors.white,
        ),
      ),
    );
  }
}

/// 进度条 + 播放按钮 + 音量 + 底部切换栏。
class _ControlsArea extends StatelessWidget {
  const _ControlsArea({required this.panel, required this.accent, required this.onPanel});

  final _Panel panel;
  final Color accent;
  final ValueChanged<_Panel> onPanel;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final song = context.select<PlayerController, Song?>((p) => p.current);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const _ProgressBar(),
        const SizedBox(height: 4),
        const _Transport(),
        const SizedBox(height: 6),
        const _VolumeBar(),
        const SizedBox(height: 14),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            _ToggleIcon(
              icon: Icons.lyrics_outlined,
              tooltip: l.lyrics,
              selected: panel == _Panel.lyrics,
              accent: accent,
              onTap: () => onPanel(_Panel.lyrics),
            ),
            _ToggleIcon(
              icon: Icons.mode_comment_outlined,
              tooltip: l.comments,
              selected: false,
              accent: accent,
              onTap: song == null ? () {} : () => Navigator.of(context).push(CommentsPage.song(song)),
            ),
            _ToggleIcon(
              icon: Icons.format_list_bulleted_rounded,
              tooltip: l.queue,
              selected: panel == _Panel.queue,
              accent: accent,
              onTap: () => onPanel(_Panel.queue),
            ),
          ],
        ),
      ],
    );
  }
}

class _ToggleIcon extends StatelessWidget {
  const _ToggleIcon({
    required this.icon,
    required this.tooltip,
    required this.selected,
    required this.accent,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final bool selected;
  final Color accent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final dark = HSLColor.fromColor(accent).withLightness(0.18).toColor();
    return Tooltip(
      message: tooltip,
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
          width: 44,
          height: 36,
          decoration: BoxDecoration(
            color: selected ? Colors.white.withValues(alpha: 0.9) : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, size: 22, color: selected ? dark : Colors.white70),
        ),
      ),
    );
  }
}

/// 细进度条：按住时变粗、时间变亮，松手才跳转。
class _ThinSlider extends StatelessWidget {
  const _ThinSlider({
    required this.value,
    required this.active,
    required this.onStart,
    required this.onChanged,
    required this.onEnd,
    this.height = 7,
  });

  final double value;
  final bool active;
  final ValueChanged<double> onStart;
  final ValueChanged<double> onChanged;
  final VoidCallback onEnd;
  final double height;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        double at(Offset o) => (o.dx / c.maxWidth).clamp(0.0, 1.0);
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onHorizontalDragStart: (d) => onStart(at(d.localPosition)),
          onHorizontalDragUpdate: (d) => onChanged(at(d.localPosition)),
          onHorizontalDragEnd: (_) => onEnd(),
          onHorizontalDragCancel: onEnd,
          onTapUp: (d) {
            onStart(at(d.localPosition));
            onEnd();
          },
          child: SizedBox(
            height: 28,
            child: Center(
              child: AnimatedPadding(
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeOutBack,
                padding: EdgeInsets.symmetric(horizontal: active ? 0 : 3),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 220),
                  curve: Curves.easeOutBack,
                  height: active ? height * 1.9 : height,
                  clipBehavior: Clip.antiAlias,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.22),
                    borderRadius: BorderRadius.circular(height),
                  ),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: FractionallySizedBox(
                      widthFactor: value.clamp(0.0, 1.0),
                      heightFactor: 1,
                      child: ColoredBox(color: active ? Colors.white : Colors.white.withValues(alpha: 0.75)),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _ProgressBar extends StatefulWidget {
  const _ProgressBar();

  @override
  State<_ProgressBar> createState() => _ProgressBarState();
}

class _ProgressBarState extends State<_ProgressBar> {
  double? _drag;

  @override
  Widget build(BuildContext context) {
    final p = context.watch<PlayerController>();
    final total = p.duration.inMilliseconds;
    final timeStyle = TextStyle(
      fontSize: 12,
      fontWeight: FontWeight.w600,
      color: _drag != null ? Colors.white : Colors.white54,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    return ValueListenableBuilder(
      valueListenable: p.position,
      builder: (_, pos, _) {
        final v = _drag ?? (total == 0 ? 0.0 : pos.inMilliseconds / total);
        final shown = Duration(milliseconds: (v * total).round());
        return Column(
          children: [
            _ThinSlider(
              value: v,
              active: _drag != null,
              onStart: (x) => setState(() => _drag = x),
              onChanged: (x) => setState(() => _drag = x),
              onEnd: () {
                final d = _drag;
                setState(() => _drag = null);
                if (d != null && total > 0) unawaited(p.seek(Duration(milliseconds: (d * total).round())));
              },
            ),
            Row(
              children: [
                SizedBox(width: 56, child: Text(formatDuration(shown), style: timeStyle)),
                const Expanded(child: Center(child: QualityMenu())),
                SizedBox(
                  width: 56,
                  child: Text(
                    '-${formatDuration(Duration(milliseconds: max(0, total - shown.inMilliseconds)))}',
                    textAlign: TextAlign.end,
                    style: timeStyle,
                  ),
                ),
              ],
            ),
          ],
        );
      },
    );
  }
}

class _VolumeBar extends StatefulWidget {
  const _VolumeBar();

  @override
  State<_VolumeBar> createState() => _VolumeBarState();
}

class _VolumeBarState extends State<_VolumeBar> {
  bool _active = false;

  @override
  Widget build(BuildContext context) {
    final p = context.watch<PlayerController>();
    final l = AppLocalizations.of(context);
    void set(double v) => unawaited(p.setVolume(v * 100));
    return Semantics(
      label: l.volume,
      child: Row(
        children: [
          GestureDetector(
            onTap: () => set(0),
            child: AnimatedScale(
              scale: _active ? 1.15 : 1,
              duration: const Duration(milliseconds: 200),
              child: const Icon(Icons.volume_mute_rounded, size: 18, color: Colors.white54),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _ThinSlider(
              value: p.volume / 100,
              active: _active,
              height: 6,
              onStart: (v) {
                setState(() => _active = true);
                set(v);
              },
              onChanged: set,
              onEnd: () => setState(() => _active = false),
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: () => set(1),
            child: AnimatedScale(
              scale: _active ? 1.15 : 1,
              duration: const Duration(milliseconds: 200),
              child: const Icon(Icons.volume_up_rounded, size: 20, color: Colors.white54),
            ),
          ),
        ],
      ),
    );
  }
}

class _Transport extends StatelessWidget {
  const _Transport();

  @override
  Widget build(BuildContext context) {
    final p = context.watch<PlayerController>();
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        _PressButton(
          size: 44,
          nudge: -1,
          onTap: p.previous,
          child: const Icon(Icons.fast_rewind_rounded, size: 44, color: Colors.white),
        ),
        _PressButton(
          size: 60,
          onTap: p.toggle,
          child: Stack(
            alignment: Alignment.center,
            children: [
              _PlayPauseIcon(playing: p.playing),
              if (p.loading || p.buffering)
                const SizedBox.square(
                  dimension: 74,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white54),
                ),
            ],
          ),
        ),
        _PressButton(
          size: 44,
          nudge: 1,
          onTap: p.next,
          child: const Icon(Icons.fast_forward_rounded, size: 44, color: Colors.white),
        ),
      ],
    );
  }
}

/// 按下时缩小并亮起圆形底；上一首 / 下一首额外往对应方向轻推一下。
class _PressButton extends StatefulWidget {
  const _PressButton({required this.size, required this.onTap, required this.child, this.nudge = 0});

  final double size;
  final VoidCallback onTap;
  final Widget child;
  final double nudge;

  @override
  State<_PressButton> createState() => _PressButtonState();
}

class _PressButtonState extends State<_PressButton> with TickerProviderStateMixin {
  late final AnimationController _press = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 90),
    reverseDuration: const Duration(milliseconds: 350),
  );
  late final AnimationController _nudge = AnimationController(vsync: this, duration: const Duration(milliseconds: 380));

  @override
  void dispose() {
    _press.dispose();
    _nudge.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final box = widget.size * 1.7;
    return GestureDetector(
      onTapDown: (_) => _press.forward(),
      onTapCancel: _press.reverse,
      onTapUp: (_) {
        _press.reverse();
        _nudge.forward(from: 0);
        HapticFeedback.lightImpact();
        widget.onTap();
      },
      child: AnimatedBuilder(
        animation: Listenable.merge([_press, _nudge]),
        builder: (_, child) => Container(
          width: box,
          height: box,
          decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.white.withValues(alpha: 0.16 * _press.value)),
          child: Transform.translate(
            offset: Offset(widget.nudge * 12 * sin(Curves.easeOut.transform(_nudge.value) * pi), 0),
            child: Transform.scale(scale: 1 - 0.14 * _press.value, child: child),
          ),
        ),
        child: Center(child: widget.child),
      ),
    );
  }
}

class _PlayPauseIcon extends StatefulWidget {
  const _PlayPauseIcon({required this.playing});

  final bool playing;

  @override
  State<_PlayPauseIcon> createState() => _PlayPauseIconState();
}

class _PlayPauseIconState extends State<_PlayPauseIcon> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 320),
    value: widget.playing ? 1 : 0,
  );

  @override
  void didUpdateWidget(_PlayPauseIcon old) {
    super.didUpdateWidget(old);
    if (old.playing != widget.playing) widget.playing ? _c.forward() : _c.reverse();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedIcon(
      icon: AnimatedIcons.play_pause,
      progress: CurvedAnimation(parent: _c, curve: Curves.easeInOutCubic),
      size: 60,
      color: Colors.white,
    );
  }
}

/// 音质切换：只列出当前歌曲实际可播放的档位。
class QualityMenu extends StatelessWidget {
  const QualityMenu({super.key});

  @override
  Widget build(BuildContext context) {
    final p = context.watch<PlayerController>();
    final l = AppLocalizations.of(context);
    final options = p.qualityOptions.where((option) => option.available).toList();
    final actual = p.actualQuality;
    final label = actual == null
        ? l.quality
        : actual == p.quality
            ? qualityLabel(l, actual)
            // 请求的音质没有权限，Rust 层已自动降级
            : l.qualityDowngraded(qualityLabel(l, actual), qualityLabel(l, p.quality));
    return PopupMenuButton<Quality>(
      tooltip: p.qualitiesLoading
          ? l.qualityLoading
          : p.qualitiesError != null
              ? l.qualityFailed(errorText(l, p.qualitiesError!))
              : options.isEmpty
                  ? l.qualityNoneForSong
                  : l.quality,
      enabled: !p.qualitiesLoading,
      initialValue: actual,
      position: PopupMenuPosition.over,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      onSelected: (q) => unawaited(p.setQuality(q)),
      itemBuilder: (_) => [
        if (p.qualitiesError != null)
          PopupMenuItem<Quality>(
            onTap: () => unawaited(p.refreshQualities()),
            child: Text(l.qualityFailedRetry),
          )
        else if (options.isEmpty)
          PopupMenuItem<Quality>(enabled: false, child: Text(l.qualityNone))
        else
          for (final option in options)
            PopupMenuItem(
              value: option.quality,
              child: Text(qualityLabel(l, option.quality)),
            ),
      ],
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.graphic_eq_rounded, size: 13, color: Colors.white70),
            const SizedBox(width: 4),
            Flexible(
              child: Text(
                label,
                style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Colors.white70),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (p.qualitiesLoading)
              const Padding(
                padding: EdgeInsets.only(left: 5),
                child: SizedBox.square(dimension: 10, child: CircularProgressIndicator(strokeWidth: 1.5, color: Colors.white70)),
              ),
          ],
        ),
      ),
    );
  }
}

class _QueuePanel extends StatefulWidget {
  const _QueuePanel({super.key});

  @override
  State<_QueuePanel> createState() => _QueuePanelState();
}

class _QueuePanelState extends State<_QueuePanel> {
  static const _extent = 64.0;
  late final ScrollController _scroll = ScrollController(
    initialScrollOffset: max(0, (context.read<PlayerController>().index - 1) * _extent),
  );

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.watch<PlayerController>();
    final l = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 4, 20, 8),
          child: Row(
            children: [
              Expanded(
                child: Text(l.upNext, style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800, color: Colors.white)),
              ),
              _ModeChip(
                icon: Icons.shuffle_rounded,
                tooltip: l.modeShuffle,
                selected: p.mode == PlayMode.shuffle,
                onTap: () => p.setMode(p.mode == PlayMode.shuffle ? PlayMode.sequence : PlayMode.shuffle),
              ),
              const SizedBox(width: 8),
              _ModeChip(
                icon: p.mode == PlayMode.repeatOne ? Icons.repeat_one_rounded : Icons.repeat_rounded,
                tooltip: p.mode == PlayMode.repeatOne ? l.modeRepeatOne : l.modeSequence,
                selected: p.mode == PlayMode.repeatOne,
                onTap: () => p.setMode(p.mode == PlayMode.repeatOne ? PlayMode.sequence : PlayMode.repeatOne),
              ),
            ],
          ),
        ),
        Expanded(
          child: ShaderMask(
            blendMode: BlendMode.dstIn,
            shaderCallback: (r) => const LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Colors.transparent, Colors.black, Colors.black, Colors.transparent],
              stops: [0, 0.04, 0.9, 1],
            ).createShader(r),
            child: ListView.builder(
              controller: _scroll,
              itemExtent: _extent,
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 40),
              itemCount: p.queue.length,
              itemBuilder: (_, i) => _QueueTile(
                song: p.queue[i],
                current: i == p.index,
                played: i < p.index,
                playing: p.playing,
                onTap: () => p.playAt(i),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _ModeChip extends StatelessWidget {
  const _ModeChip({required this.icon, required this.tooltip, required this.selected, required this.onTap});

  final IconData icon;
  final String tooltip;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          width: 40,
          height: 32,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: selected ? 0.9 : 0.14),
            borderRadius: BorderRadius.circular(9),
          ),
          child: Icon(icon, size: 19, color: selected ? Colors.black87 : Colors.white),
        ),
      ),
    );
  }
}

class _QueueTile extends StatelessWidget {
  const _QueueTile({
    required this.song,
    required this.current,
    required this.played,
    required this.playing,
    required this.onTap,
  });

  final Song song;
  final bool current;
  final bool played;
  final bool playing;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    // 已播放的歌用颜色变淡，不用 Opacity 图层
    final fg = played ? 0.45 : 1.0;
    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        hoverColor: Colors.white10,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: current ? Colors.white.withValues(alpha: 0.12) : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              Stack(
                children: [
                  // 队列封面只有 46px，按显示尺寸解码，不用解出整张 300px 原图
                  SizedBox.square(
                    dimension: 46,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: Image.network(
                        song.coverUrl.replaceFirst('http://', 'https://'),
                        cacheWidth: (46 * MediaQuery.devicePixelRatioOf(context)).round(),
                        fit: BoxFit.cover,
                        color: played ? const Color(0x73FFFFFF) : null,
                        colorBlendMode: BlendMode.modulate,
                        errorBuilder: (_, _, _) => const ColoredBox(color: Colors.white12),
                      ),
                    ),
                  ),
                  if (current)
                    Positioned.fill(
                      child: DecoratedBox(
                        decoration: BoxDecoration(color: Colors.black45, borderRadius: BorderRadius.circular(6)),
                        child: Center(child: _NowPlayingBars(playing: playing)),
                      ),
                    ),
                ],
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      song.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: current ? FontWeight.w800 : FontWeight.w600,
                        color: Colors.white.withValues(alpha: fg),
                      ),
                    ),
                    Text(
                      singerNames(song),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 13, color: Colors.white.withValues(alpha: 0.6 * fg)),
                    ),
                  ],
                ),
              ),
              Text(
                formatDuration(Duration(seconds: song.durationSecs)),
                style: TextStyle(fontSize: 12, color: Colors.white.withValues(alpha: 0.38 * fg)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 正在播放的跳动音柱。
class _NowPlayingBars extends StatefulWidget {
  const _NowPlayingBars({required this.playing});

  final bool playing;

  @override
  State<_NowPlayingBars> createState() => _NowPlayingBarsState();
}

class _NowPlayingBarsState extends State<_NowPlayingBars> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1200));

  @override
  void initState() {
    super.initState();
    if (widget.playing) _c.repeat();
  }

  @override
  void didUpdateWidget(_NowPlayingBars old) {
    super.didUpdateWidget(old);
    if (widget.playing && !_c.isAnimating) _c.repeat();
    if (!widget.playing) _c.stop();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (_, _) => Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (var i = 0; i < 4; i++)
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 1.2),
              width: 3,
              height: widget.playing ? 5 + 11 * (0.5 + 0.5 * sin(_c.value * 2 * pi * (i.isEven ? 2 : 3) + i * 1.3)) : 4,
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(2)),
            ),
        ],
      ),
    );
  }
}
