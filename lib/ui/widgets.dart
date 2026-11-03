import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show defaultTargetPlatform;
import 'package:flutter/material.dart';

import '../data/data_ext.dart';
import '../l10n/l10n_ext.dart';

String formatDuration(Duration d) {
  final m = d.inMinutes;
  final s = d.inSeconds % 60;
  return '$m:${s.toString().padLeft(2, '0')}';
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
              httpsUrl(url),
              width: size,
              height: size,
              fit: BoxFit.cover,
              // 网络加载完才淡入；内存缓存里同步拿到的直接显示，滚回来不会再闪一次
              frameBuilder: (_, child, frame, sync) {
                if (sync) return child;
                return ColoredBox(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  child: AnimatedOpacity(
                    opacity: frame == null ? 0 : 1,
                    duration: const Duration(milliseconds: 280),
                    curve: Curves.easeOut,
                    child: child,
                  ),
                );
              },
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

  /// 加载动画出现过（等了超过 [PageLoading.delay]）才让内容淡入，很快加载完的直接显示。
  final _since = Stopwatch()..start();

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
                FilledButton.tonal(onPressed: () => setState(() { _future = widget.load(); _since.reset(); }), child: Text(l.retry)),
              ],
            ),
          );
        }
        if (!snap.hasData) return const PageLoading();
        return _FadeIn(enabled: _since.elapsed > PageLoading.delay, child: widget.builder(context, snap.data as T));
      },
    );
  }
}

/// 页面加载中：五根抗色律动条 + “加载中”，和列表里正在播放的小律动条同一个样子。
/// 先等 [delay] 再淡入，加载很快时不闪一下；没出现之前不跑动画。
class PageLoading extends StatefulWidget {
  const PageLoading({super.key});

  static const delay = Duration(milliseconds: 300);

  @override
  State<PageLoading> createState() => _PageLoadingState();
}

class _PageLoadingState extends State<PageLoading> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 900));
  late final Timer _timer;
  bool _shown = false;

  @override
  void initState() {
    super.initState();
    _timer = Timer(PageLoading.delay, () {
      _c.repeat();
      setState(() => _shown = true);
    });
  }

  @override
  void dispose() {
    _timer.cancel();
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: AnimatedOpacity(
        opacity: _shown ? 1 : 0,
        duration: const Duration(milliseconds: 200),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              height: 30,
              child: AnimatedBuilder(
                animation: _c,
                builder: (_, _) => Row(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    for (var i = 0; i < 5; i++) ...[
                      if (i > 0) const SizedBox(width: 5),
                      Container(
                        width: 5,
                        // 五根依次错开五分之一个周期，像一道波
                        height: 6 + 24 * (0.5 - 0.5 * math.cos((_c.value - i / 5) * 2 * math.pi)),
                        decoration: BoxDecoration(color: scheme.primary, borderRadius: BorderRadius.circular(3)),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 14),
            Text(
              AppLocalizations.of(context).loading,
              style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}

/// 加载完的内容淡入一次。[enabled] 只在第一次建出来时看，之后重建不会再淡入。
class _FadeIn extends StatefulWidget {
  const _FadeIn({required this.enabled, required this.child});

  final bool enabled;
  final Widget child;

  @override
  State<_FadeIn> createState() => _FadeInState();
}

class _FadeInState extends State<_FadeIn> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 220),
    value: widget.enabled ? 0 : 1,
  )..forward();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FadeTransition(opacity: _c, child: widget.child);
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
