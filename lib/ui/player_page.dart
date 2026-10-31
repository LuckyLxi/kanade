import 'dart:async';
import 'dart:math';
import 'dart:ui' show ImageFilter, lerpDouble;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../data/data_ext.dart';
import '../l10n/l10n_ext.dart';
import '../library/library_controller.dart';
import '../player/player_controller.dart';
import '../src/rust/api/types.dart';
import 'comments_page.dart';
import 'player_background.dart';
import 'player_lyrics.dart';
import 'player_route.dart';
import 'smooth_scroll.dart';
import 'song_actions.dart';
import 'toast.dart';
import 'widgets.dart';

enum _Panel { lyrics, queue }

enum _Drag { none, route, page }

const _motion = Duration(milliseconds: 550);
const _curve = Curves.easeInOutCubicEmphasized;

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

class _PlayerPageState extends State<PlayerPage> with SingleTickerProviderStateMixin {
  CoverArt? _art;
  String? _artUrl;

  /// 宽屏右侧显示队列还是歌词。
  late bool _wideQueue = widget.showQueue;

  /// 窄屏翻页的进度：0 是主页面，1 是 [_side] 那一页（队列在下面、歌词在右边）。
  /// 拖动时手指直接改它，封面、歌名、控件、面板的位置都由它算出来。
  late final AnimationController _page = AnimationController(vsync: this, value: widget.showQueue ? 1 : 0)
    ..addStatusListener((_) => setState(() {}));
  late _Panel _side = widget.showQueue ? _Panel.queue : _Panel.lyrics;

  /// 窄屏内容区的大小，翻页时手指位移按它换算成进度。
  Size _area = Size.zero;

  /// 窄屏封面歌名那一块的高度，也就是控件顶边的位置。
  double _headerHeight = 0;

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

  @override
  void dispose() {
    _page.dispose();
    super.dispose();
  }

  // ---- 窄屏翻页 ----

  /// 松手后接着手指的速度弹到位，临界阻尼不回弹。
  static final _pageSpring = SpringDescription.withDampingRatio(mass: 1, stiffness: 520);

  double get _extent => _side == _Panel.queue ? _area.height : _area.width;

  void _pageDragStart(_Panel side) {
    _page.stop();
    _side = side;
  }

  /// [delta] 是手指沿翻页方向的位移（队列看竖直、歌词看水平），往主页面那边为正。
  void _pageDragUpdate(double delta) {
    if (_extent > 0) _page.value -= delta / _extent;
  }

  /// 甩得够快按方向翻，否则过了一半就翻过去、不到一半弹回来。
  void _pageDragEnd(double velocity) {
    final v = _extent > 0 ? -velocity / _extent : 0.0;
    final open = v.abs() > 1.2 ? v > 0 : _page.value > 0.5;
    // 落点要正好是 0 / 1，往回翻要用 animateBackWith，停下时才算回到主页面
    final spring = SpringSimulation(_pageSpring, _page.value, open ? 1 : 0, v, snapToEnd: true);
    open ? _page.animateWith(spring) : _page.animateBackWith(spring);
  }

  /// 这次拖动交给谁：路由（拖动关闭播放页）还是翻页；第一次移动时按方向定下来。
  _Drag? _drag;
  Axis? _dragAxis;

  /// 队列列表在顶上被往下拉，由列表自己接管了这次拖动。
  bool _listPull = false;

  _Drag _decideVertical(bool narrow, PlayerRoute? r, double dy) {
    if (!narrow) {
      r?.dragStart();
      return r == null ? _Drag.none : _Drag.route;
    }
    if (_page.value == 0) {
      // 主页面往下拖、或者打开动画还没走完，是拖动播放页本身；往上翻到队列
      if (r != null && (dy >= 0 || r.progress < 1)) {
        r.dragStart();
        return _Drag.route;
      }
      if (dy >= 0) return _Drag.none;
      _pageDragStart(_Panel.queue);
      return _Drag.page;
    }
    // 队列页顶上往下拉回主页面；歌词页不管竖直方向
    if (_side != _Panel.queue) return _Drag.none;
    _pageDragStart(_Panel.queue);
    return _Drag.page;
  }

  _Drag _decideHorizontal(double dx) {
    final t = _page.value;
    if ((t == 0 && dx < 0) || (t > 0 && _side == _Panel.lyrics)) {
      _pageDragStart(_Panel.lyrics);
      return _Drag.page;
    }
    return _Drag.none;
  }

  Widget _gestures({required bool narrow, required Widget child}) {
    final route = ModalRoute.of(context);
    final r = route is PlayerRoute ? route : null;
    void start(Axis axis) {
      _drag = null;
      _dragAxis = axis;
    }
    void update(Axis axis, double delta) {
      if (_listPull || _dragAxis != axis) return;
      _drag ??= axis == Axis.vertical ? _decideVertical(narrow, r, delta) : _decideHorizontal(delta);
      if (_drag == _Drag.route) r!.dragUpdate(delta);
      if (_drag == _Drag.page) _pageDragUpdate(delta);
    }
    // 点按钮时拖动手势没真正开始也会收到取消，这时 _drag 还是空的
    void end(Axis axis, double velocity) {
      if (_dragAxis != axis) return;
      if (_drag == _Drag.route) r!.dragEnd(velocity);
      if (_drag == _Drag.page) _pageDragEnd(velocity);
      _drag = null;
      _dragAxis = null;
    }
    return GestureDetector(
      onVerticalDragStart: (_) => start(Axis.vertical),
      onVerticalDragUpdate: (d) => update(Axis.vertical, d.delta.dy),
      onVerticalDragEnd: (d) => end(Axis.vertical, d.velocity.pixelsPerSecond.dy),
      onVerticalDragCancel: () => end(Axis.vertical, 0),
      onHorizontalDragStart: narrow ? (_) => start(Axis.horizontal) : null,
      onHorizontalDragUpdate: narrow ? (d) => update(Axis.horizontal, d.delta.dx) : null,
      onHorizontalDragEnd: narrow ? (d) => end(Axis.horizontal, d.velocity.pixelsPerSecond.dx) : null,
      onHorizontalDragCancel: narrow ? () => end(Axis.horizontal, 0) : null,
      child: child,
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = context.watch<PlayerController>();
    final song = p.current;
    if (song == null) return const Scaffold();
    final cover = bigCoverUrl(song);
    _loadArt(cover);
    final wide = MediaQuery.sizeOf(context).width >= 800;

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

    // 窄屏翻到队列时，返回键先翻回主页面；歌词页按返回直接关掉播放页
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Theme(
        data: _art?.theme ?? _fallbackTheme,
        child: PopScope(
          canPop: wide || _page.isDismissed || _side == _Panel.lyrics,
          onPopInvokedWithResult: (didPop, _) {
            if (!didPop) _page.animateBack(0, duration: _motion, curve: _curve);
          },
          // 下拉时整页沿着变形的路径缩回播放条，手指松开再决定关还是弹回
          child: _gestures(narrow: !wide, child: page),
        ),
      ),
    );
  }

  /// 主页面和队列 / 歌词像两页纸：控件跟着主页面翻走，面板从下面或右边跟进来，
  /// 封面和歌名按进度缩进左上角。
  Widget _narrow(PlayerController p, Song song, String cover) {
    const small = 60.0;
    // 主页面停稳时不建面板；从队列列表往下拉回来、手指还没松开时要留着，松手要靠它
    final panel = _page.isDismissed && !_listPull
        ? null
        : RepaintBoundary(
            child: switch (_side) {
              _Panel.lyrics => const LyricView(key: ValueKey('lyrics')),
              _Panel.queue => _QueuePanel(
                key: const ValueKey('queue'),
                onPullStart: () {
                  _listPull = true;
                  _pageDragStart(_Panel.queue);
                },
                onPull: _pageDragUpdate,
                onPullEnd: (v) {
                  setState(() => _listPull = false);
                  _pageDragEnd(v);
                },
              ),
            },
          );
    final controls = RepaintBoundary(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(28, 8, 28, 8),
        child: _ControlsArea(accent: _palette.first),
      ),
    );
    return LayoutBuilder(
      builder: (context, area) {
        _area = area.biggest;
        return AnimatedBuilder(
          animation: _page,
          builder: (context, _) {
            final t = _page.value;
            // 整页翻走的距离：队列竖着翻一屏，歌词横着翻一屏
            final shift = _side == _Panel.queue ? Offset(0, area.maxHeight) : Offset(area.maxWidth, 0);
            return Stack(
              children: [
                if (panel != null)
                  Positioned.fill(
                    top: small + 16,
                    child: Transform.translate(offset: shift * (1 - t), child: panel),
                  ),
                // 从下往上排：控件先画，封面歌名盖在上面
                Column(
                  verticalDirection: VerticalDirection.up,
                  children: [
                    // 控件翻走时从顶上那条封面歌名下面钻过去，和面板一样在那条线以上看不见
                    ClipRect(
                      clipper: _ClipAbove(() => small + 16 - _headerHeight),
                      child: Transform.translate(offset: -shift * t, child: controls),
                    ),
                    Expanded(
                      child: LayoutBuilder(
                        builder: (context, c) {
                          _headerHeight = c.maxHeight;
                          const pad = 28.0, titleH = 64.0;
                          final size = min(c.maxWidth - pad * 2, c.maxHeight - titleH - 28).clamp(80.0, 560.0);
                          final top = max(0.0, (c.maxHeight - size - titleH - 24) / 2);
                          final coverRect = Rect.lerp(
                            Rect.fromLTWH((c.maxWidth - size) / 2, top, size, size),
                            const Rect.fromLTWH(24, 4, small, small),
                            t,
                          )!;
                          final titleRect = Rect.lerp(
                            Rect.fromLTWH(pad, top + size + 24, c.maxWidth - pad * 2, titleH),
                            Rect.fromLTWH(24 + small + 14, 4, c.maxWidth - 24 - small - 14 - 20, small),
                            t,
                          )!;
                          return Stack(
                            children: [
                              Positioned.fromRect(
                                rect: coverRect,
                                child: _AlbumArt(url: cover, playing: p.playing, expanded: t < 0.5),
                              ),
                              Positioned.fromRect(rect: titleRect, child: _TitleRow(song: song, t: t)),
                            ],
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _wide(PlayerController p, Song song, String cover) {
    // 宽屏右侧始终有内容：默认歌词，队列按钮在歌词和队列之间切换
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
                SizedBox(height: 64, child: _TitleRow(song: song, t: 0)),
                const SizedBox(height: 12),
                _ControlsArea(
                  accent: _palette.first,
                  queueOpen: _wideQueue,
                  onQueue: () => setState(() => _wideQueue = !_wideQueue),
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
              child: _wideQueue
                  ? const _QueuePanel(key: ValueKey('queue'))
                  : const LyricView(key: ValueKey('lyrics'), fontSize: 36),
            ),
          ),
        ),
      ],
    );
  }
}

/// 只露出 [top] 以下的部分，[top] 用本地坐标、每次画的时候现取（要等排版完才知道）。
class _ClipAbove extends CustomClipper<Rect> {
  _ClipAbove(this.top);

  final double Function() top;

  @override
  Rect getClip(Size size) => Rect.fromLTRB(-1e5, top(), 1e5, 1e5);

  @override
  bool shouldReclip(_ClipAbove old) => true;
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

/// 封面：暂停时缩小、播放时弹回并加深投影。
class _AlbumArt extends StatelessWidget {
  const _AlbumArt({required this.url, required this.playing, required this.expanded});

  final String url;
  final bool playing;
  final bool expanded;

  @override
  Widget build(BuildContext context) {
    final lifted = expanded && playing;
    final radius = expanded ? 14.0 : 8.0;
    final morph = PlayerMorph.maybeOf(context);
    final art = AnimatedScale(
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

/// 歌名、歌手和按钮。[t] 是翻页进度：0 是主页面的大字，1 是缩在左上角封面旁边的小字。
class _TitleRow extends StatelessWidget {
  const _TitleRow({required this.song, required this.t});

  final Song song;
  final double t;

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
              DefaultTextStyle(
                style: TextStyle(fontSize: lerpDouble(22, 17, t), fontWeight: FontWeight.w800, color: Colors.white),
                child: _Marquee(song.name),
              ),
              const SizedBox(height: 2),
              GestureDetector(
                onTap: () => openSinger(context, song),
                child: DefaultTextStyle(
                  style: TextStyle(
                    fontSize: lerpDouble(18, 14, t),
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

/// 进度条 + 播放按钮一排 + 底部按钮。
class _ControlsArea extends StatelessWidget {
  const _ControlsArea({required this.accent, this.queueOpen = false, this.onQueue});

  final Color accent;
  final bool queueOpen;

  /// 宽屏才有队列按钮；窄屏上滑打开队列、左滑打开歌词，底下只留评论。
  final VoidCallback? onQueue;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final song = context.select<PlayerController, Song?>((p) => p.current);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const _ProgressBar(),
        const SizedBox(height: 6),
        const _Transport(),
        const SizedBox(height: 14),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            _ToggleIcon(
              icon: Icons.mode_comment_outlined,
              tooltip: l.comments,
              selected: false,
              accent: accent,
              onTap: song == null ? () {} : () => Navigator.of(context).push(CommentsPage.song(song)),
            ),
            if (onQueue != null)
              _ToggleIcon(
                icon: Icons.format_list_bulleted_rounded,
                tooltip: l.queue,
                selected: queueOpen,
                accent: accent,
                onTap: onQueue!,
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
  });

  final double value;
  final bool active;
  final ValueChanged<double> onStart;
  final ValueChanged<double> onChanged;
  final VoidCallback onEnd;
  static const height = 7.0;

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

/// 播放模式 · 上一首 · 播放 / 暂停 · 下一首 · 音量。
class _Transport extends StatelessWidget {
  const _Transport();

  @override
  Widget build(BuildContext context) {
    final p = context.watch<PlayerController>();
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        const _ModeButton(),
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
        const _VolumeButton(),
      ],
    );
  }
}

/// 按下时缩小并亮起圆形底；上一首 / 下一首额外往对应方向轻推一下。
/// 圆形底比按钮本身大，画在布局范围外面，不把一排按钮撑宽。
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
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => _press.forward(),
      onTapCancel: _press.reverse,
      onTapUp: (_) {
        _press.reverse();
        _nudge.forward(from: 0);
        HapticFeedback.lightImpact();
        widget.onTap();
      },
      child: SizedBox.square(
        dimension: widget.size * 1.25,
        child: OverflowBox(
          maxWidth: box,
          maxHeight: box,
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
        ),
      ),
    );
  }
}

String _modeLabel(AppLocalizations l, PlayMode mode) => switch (mode) {
  PlayMode.sequence => l.modeSequence,
  PlayMode.repeatOne => l.modeRepeatOne,
  PlayMode.shuffle => l.modeShuffle,
};

/// 播放模式：点一下换下一种（列表循环 → 单曲循环 → 随机），换完弹个提示。
class _ModeButton extends StatelessWidget {
  const _ModeButton();

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final mode = context.select<PlayerController, PlayMode>((p) => p.mode);
    return Tooltip(
      message: _modeLabel(l, mode),
      child: _PressButton(
        size: 32,
        onTap: () {
          final p = context.read<PlayerController>()..cycleMode();
          showToast(context, _modeLabel(l, p.mode));
        },
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 300),
          switchInCurve: Curves.easeOutBack,
          transitionBuilder: (child, a) => FadeTransition(
            opacity: a,
            child: ScaleTransition(scale: Tween(begin: 0.5, end: 1.0).animate(a), child: child),
          ),
          child: Icon(
            switch (mode) {
              PlayMode.sequence => Icons.repeat_rounded,
              PlayMode.repeatOne => Icons.repeat_one_rounded,
              PlayMode.shuffle => Icons.shuffle_rounded,
            },
            key: ValueKey(mode),
            size: 24,
            color: Colors.white70,
          ),
        ),
      ),
    );
  }
}

IconData _volumeIcon(double volume) => volume == 0
    ? Icons.volume_off_rounded
    : volume < 50
        ? Icons.volume_down_rounded
        : Icons.volume_up_rounded;

/// 音量按钮：点开时按钮本身长成一条竖着的音量条，点外面再缩回按钮。
class _VolumeButton extends StatefulWidget {
  const _VolumeButton();

  @override
  State<_VolumeButton> createState() => _VolumeButtonState();
}

class _VolumeButtonState extends State<_VolumeButton> {
  bool _open = false;

  void _openPanel() {
    final box = context.findRenderObject()! as RenderBox;
    final route = _VolumeRoute(
      anchor: box.localToGlobal(Offset.zero) & box.size,
      player: context.read<PlayerController>(),
      barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
    );
    // 展开期间按钮藏起来，看起来就是它自己变成了音量条；缩回去落地了再露出来
    setState(() => _open = true);
    unawaited(Navigator.of(context, rootNavigator: true).push(route));
    unawaited(route.completed.then((_) {
      if (mounted) setState(() => _open = false);
    }));
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final volume = context.select<PlayerController, double>((p) => p.volume);
    return Tooltip(
      message: l.volume,
      child: Opacity(
        opacity: _open ? 0 : 1,
        child: _PressButton(
          size: 32,
          onTap: _openPanel,
          child: Icon(_volumeIcon(volume), size: 24, color: Colors.white70),
        ),
      ),
    );
  }
}

class _VolumeRoute extends PopupRoute<void> {
  _VolumeRoute({required this.anchor, required this.player, required this.barrierLabel});

  /// 音量按钮在屏幕上的位置，音量条从这里长出来、缩回这里。
  final Rect anchor;
  final PlayerController player;

  @override
  final String barrierLabel;

  @override
  Color? get barrierColor => null;

  @override
  bool get barrierDismissible => true;

  @override
  Duration get transitionDuration => const Duration(milliseconds: 380);

  @override
  Duration get reverseTransitionDuration => const Duration(milliseconds: 260);

  late final CurvedAnimation _curved = CurvedAnimation(
    parent: animation!,
    curve: Curves.easeOutCubic,
    reverseCurve: Curves.easeInCubic,
  );

  @override
  void dispose() {
    _curved.dispose();
    super.dispose();
  }

  @override
  Widget buildPage(BuildContext context, Animation<double> animation, Animation<double> secondaryAnimation) =>
      _VolumePanel(anchor: anchor, player: player, animation: _curved, route: animation);
}

class _VolumePanel extends StatelessWidget {
  const _VolumePanel({required this.anchor, required this.player, required this.animation, required this.route});

  final Rect anchor;
  final PlayerController player;

  /// 加了曲线的进度：0 是按钮，1 是展开的音量条。
  final Animation<double> animation;

  /// 路由本身的动画，只用来判断是在展开还是在收起。
  final Animation<double> route;

  static const _width = 56.0, _height = 220.0;

  void _set(double v) => unawaited(player.setVolume(v * 100));

  @override
  Widget build(BuildContext context) {
    final screen = MediaQuery.sizeOf(context);
    final top = MediaQuery.paddingOf(context).top;
    final c = anchor.center;
    // 底部那一格放图标，正好盖在按钮原来的位置上
    final left = (c.dx - _width / 2).clamp(8.0, screen.width - _width - 8);
    final bottom = c.dy + _width / 2;
    final panel = Rect.fromLTRB(left, max(top + 8, bottom - _height), left + _width, bottom);
    return Material(
      type: MaterialType.transparency,
      child: AnimatedBuilder(
        animation: animation,
        builder: (context, _) {
          final t = animation.value;
          final rect = Rect.lerp(anchor, panel, t)!;
          final radius = lerpDouble(anchor.shortestSide / 2, _width / 2, t)!;
          final content = ((t - 0.35) / 0.65).clamp(0.0, 1.0);
          return Stack(
            children: [
              Positioned.fromRect(
                rect: rect,
                child: IgnorePointer(
                  // 收起途中不再接受拖动
                  ignoring: route.status == AnimationStatus.reverse,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(radius),
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 24 * t, sigmaY: 24 * t),
                      child: ColoredBox(
                        color: Colors.white.withValues(alpha: 0.16 * t),
                        child: LayoutBuilder(
                          builder: (context, box) {
                            double at(Offset o) => (1 - o.dy / box.maxHeight).clamp(0.0, 1.0);
                            return Listener(
                              onPointerSignal: (e) {
                                if (e is PointerScrollEvent) _set((player.volume - e.scrollDelta.dy / 8) / 100);
                              },
                              child: GestureDetector(
                                behavior: HitTestBehavior.opaque,
                                onVerticalDragStart: (d) => _set(at(d.localPosition)),
                                onVerticalDragUpdate: (d) => _set(at(d.localPosition)),
                                onTapUp: (d) => _set(at(d.localPosition)),
                                child: ListenableBuilder(
                                  listenable: player,
                                  builder: (context, _) =>
                                      _VolumeFill(volume: player.volume, content: content, iconBox: lerpDouble(anchor.height, _width, t)!),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// 音量条里面：从下往上的填充、顶上的数值、底部的图标。图标被填充盖住时换成深色。
class _VolumeFill extends StatelessWidget {
  const _VolumeFill({required this.volume, required this.content, required this.iconBox});

  final double volume;
  final double content;
  final double iconBox;

  @override
  Widget build(BuildContext context) {
    final v = volume / 100;
    return LayoutBuilder(
      builder: (context, box) {
        final filled = v * box.maxHeight;
        Color on(bool covered) => Color.lerp(Colors.white70, Colors.black87, covered ? content : 0)!;
        return Stack(
          fit: StackFit.expand,
          children: [
            Align(
              alignment: Alignment.bottomCenter,
              child: SizedBox(
                height: filled,
                width: double.infinity,
                child: ColoredBox(color: Colors.white.withValues(alpha: 0.9 * content)),
              ),
            ),
            Positioned(
              top: 12,
              left: 0,
              right: 0,
              child: Opacity(
                opacity: content,
                child: Text(
                  '${volume.round()}',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: on(filled > box.maxHeight - 22),
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              height: iconBox,
              child: Center(child: Icon(_volumeIcon(volume), size: 24, color: on(filled > iconBox / 2))),
            ),
          ],
        );
      },
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
  const _QueuePanel({super.key, this.onPullStart, this.onPull, this.onPullEnd});

  /// 窄屏：列表已经在最顶上还往下拉时，这次拖动改成翻回主页面，跟着手指走。
  /// [onPull] 给竖直位移，[onPullEnd] 给松手时的竖直速度。
  final VoidCallback? onPullStart;
  final ValueChanged<double>? onPull;
  final ValueChanged<double>? onPullEnd;

  @override
  State<_QueuePanel> createState() => _QueuePanelState();
}

class _QueuePanelState extends State<_QueuePanel> {
  static const _extent = 64.0;
  late final ScrollController _scroll = SmoothScrollController(
    initialScrollOffset: max(0, (context.read<PlayerController>().index - 1) * _extent),
  );

  /// 直接看手指，不进手势竞争：比列表的滚动手势先一步判断是不是在顶上往下拉。
  VelocityTracker? _tracker;
  double _moved = 0;
  bool _decided = false;
  bool _pulling = false;

  void _onDown(PointerDownEvent e) {
    if (widget.onPull == null) return;
    _tracker = VelocityTracker.withKind(e.kind)..addPosition(e.timeStamp, e.position);
    _moved = 0;
    _decided = false;
  }

  void _onMove(PointerMoveEvent e) {
    final tracker = _tracker;
    if (tracker == null) return;
    tracker.addPosition(e.timeStamp, e.position);
    if (_pulling) {
      widget.onPull!(e.delta.dy);
      return;
    }
    if (_decided) return;
    _moved += e.delta.dy;
    // 比列表滚动的判定距离小，列表还没开始滚就决定好
    if (_moved.abs() < 8) return;
    _decided = true;
    final atTop = _scroll.hasClients && _scroll.position.pixels <= _scroll.position.minScrollExtent;
    if (_moved < 0 || !atTop) return;
    // 拉的时候列表本身不能滚，换掉滚动物理也会结束列表已经开始的那次滚动
    setState(() => _pulling = true);
    widget.onPullStart!();
    widget.onPull!(_moved);
  }

  void _onUp(PointerEvent e, {required bool cancel}) {
    final tracker = _tracker;
    _tracker = null;
    if (!_pulling) return;
    setState(() => _pulling = false);
    widget.onPullEnd!(cancel || tracker == null ? 0 : tracker.getVelocity().pixelsPerSecond.dy);
  }

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
          padding: const EdgeInsets.fromLTRB(24, 8, 20, 12),
          child: Text(l.upNext, style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800, color: Colors.white)),
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
            child: Listener(
              onPointerDown: _onDown,
              onPointerMove: _onMove,
              onPointerUp: (e) => _onUp(e, cancel: false),
              onPointerCancel: (e) => _onUp(e, cancel: true),
              child: ListView.builder(
                controller: _scroll,
                physics: _pulling ? const NeverScrollableScrollPhysics() : null,
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
        ),
      ],
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
                        httpsUrl(song.coverUrl),
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
