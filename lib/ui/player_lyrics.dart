import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/l10n_ext.dart';
import '../player/player_controller.dart';
import '../src/rust/api/types.dart';

/// Apple Music 式歌词：大号粗体左对齐，当前行从左到右逐渐点亮，
/// 离当前行越远越暗越模糊。用户手动滚动时取消模糊，3 秒后恢复自动跟随。
class LyricView extends StatefulWidget {
  const LyricView({super.key, this.fontSize = 28});

  final double fontSize;

  @override
  State<LyricView> createState() => _LyricViewState();
}

class _LyricViewState extends State<LyricView> {
  late final PlayerController _player = context.read<PlayerController>();
  List<GlobalKey> _keys = [];
  Lyric? _lyric;
  int _current = -1;
  bool _userScrolling = false;
  DateTime _userScrolledAt = DateTime(0);

  @override
  void initState() {
    super.initState();
    _player.position.addListener(_onPosition);
  }

  @override
  void dispose() {
    _player.position.removeListener(_onPosition);
    super.dispose();
  }

  void _onPosition() {
    final free = DateTime.now().difference(_userScrolledAt) < const Duration(seconds: 3);
    final i = _player.lyricIndexAt(_player.position.value);
    if (_userScrolling != free) {
      setState(() => _userScrolling = free);
      // 手动滚动结束，回到当前行
      if (!free) _follow(i);
    }
    if (i == _current) return;
    setState(() => _current = i);
    if (free) return;
    _follow(i);
  }

  void _follow(int i) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = i >= 0 && i < _keys.length ? _keys[i].currentContext : null;
      if (ctx != null) {
        Scrollable.ensureVisible(
          ctx,
          alignment: 0.3,
          duration: const Duration(milliseconds: 700),
          curve: Curves.easeOutCubic,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final lyric = context.select<PlayerController, Lyric?>((p) => p.lyric);
    if (!identical(lyric, _lyric)) {
      _lyric = lyric;
      _keys = List.generate(lyric?.lines.length ?? 0, (_) => GlobalKey());
      _current = -1;
    }
    final l = AppLocalizations.of(context);
    final big = TextStyle(fontSize: widget.fontSize, fontWeight: FontWeight.w800, height: 1.25);
    if (lyric == null || (lyric.lines.isEmpty && lyric.plain.isEmpty)) {
      return Center(child: Text(l.noLyrics, style: big.copyWith(color: Colors.white54, fontSize: 20)));
    }
    if (lyric.lines.isEmpty) {
      return SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 120),
        child: Text(lyric.plain, style: big.copyWith(fontSize: widget.fontSize * 0.7, color: Colors.white70)),
      );
    }

    return NotificationListener<UserScrollNotification>(
      onNotification: (_) {
        _userScrolledAt = DateTime.now();
        if (!_userScrolling) setState(() => _userScrolling = true);
        return false;
      },
      child: ShaderMask(
        shaderCallback: (r) => const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.transparent, Colors.black, Colors.black, Colors.transparent],
          stops: [0, 0.1, 0.85, 1],
        ).createShader(r),
        blendMode: BlendMode.dstIn,
        child: LayoutBuilder(
          builder: (context, c) => SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(12, c.maxHeight * 0.3, 12, c.maxHeight * 0.6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final (i, line) in lyric.lines.indexed)
                  _Line(
                    key: _keys[i],
                    line: line,
                    nextMs: i + 1 < lyric.lines.length ? lyric.lines[i + 1].timeMs : null,
                    distance: _current < 0 ? i + 1 : (i - _current).abs(),
                    active: i == _current,
                    free: _userScrolling,
                    style: big,
                    onTap: () {
                      _userScrolledAt = DateTime(0);
                      _player.seek(Duration(milliseconds: line.timeMs));
                    },
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 只用文字颜色的透明度区分远近。
/// 不做逐行模糊（每帧都要新建模糊纹理）也不做缩放动画
/// （每个中间尺寸都会把字形重新栅格化进缓存，中日文字多时显存暴涨）。
class _Line extends StatelessWidget {
  const _Line({
    super.key,
    required this.line,
    required this.nextMs,
    required this.distance,
    required this.active,
    required this.free,
    required this.style,
    required this.onTap,
  });

  final LyricLine line;
  final int? nextMs;
  final int distance;
  final bool active;
  final bool free;
  final TextStyle style;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final opacity = active ? 1.0 : free ? 0.55 : (0.4 - distance * 0.05).clamp(0.12, 0.4);
    final empty = line.text.trim().isEmpty;
    final transStyle = style.copyWith(fontSize: style.fontSize! * 0.6, fontWeight: FontWeight.w600);

    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        hoverColor: Colors.white10,
        splashColor: Colors.white12,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: empty
              ? (active ? _InterludeDots(size: style.fontSize! * 0.35) : SizedBox(height: style.fontSize! * 0.4))
              : TweenAnimationBuilder<double>(
                  tween: Tween(end: opacity),
                  duration: const Duration(milliseconds: 450),
                  curve: Curves.easeOut,
                  builder: (_, o, _) => Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      active
                          ? _Sweep(line: line, nextMs: nextMs, style: style)
                          : Text(line.text, style: style.copyWith(color: Colors.white.withValues(alpha: o))),
                      if (line.trans.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(line.trans, style: transStyle.copyWith(color: Colors.white.withValues(alpha: o * 0.7))),
                        ),
                    ],
                  ),
                ),
        ),
      ),
    );
  }
}

/// 当前行从左往右点亮：按本行到下一行的时间比例移动渐变分界。
/// 渐变直接作为文字画笔的 shader，按文字实际宽度铺开。
class _Sweep extends StatelessWidget {
  const _Sweep({required this.line, required this.nextMs, required this.style});

  final LyricLine line;
  final int? nextMs;
  final TextStyle style;

  @override
  Widget build(BuildContext context) {
    final player = context.read<PlayerController>();
    // 行间隔太长（间奏）时只按 6 秒算，避免长时间半亮
    final span = ((nextMs ?? line.timeMs + 5000) - line.timeMs).clamp(800, 6000);
    return LayoutBuilder(
      builder: (context, c) {
        final tp = TextPainter(text: TextSpan(text: line.text, style: style), textDirection: TextDirection.ltr)
          ..layout(maxWidth: c.maxWidth);
        final width = tp.width;
        tp.dispose();
        return ValueListenableBuilder(
          valueListenable: player.position,
          builder: (_, pos, _) => TweenAnimationBuilder<double>(
            tween: Tween(end: ((pos.inMilliseconds - line.timeMs) / span).clamp(0.0, 1.0)),
            duration: const Duration(milliseconds: 250),
            builder: (_, v, _) => Text(
              line.text,
              style: style.copyWith(
                foreground: Paint()
                  ..shader = ui.Gradient.linear(
                    Offset.zero,
                    Offset(width, 0),
                    const [Colors.white, Colors.white, Color(0x88FFFFFF), Color(0x88FFFFFF)],
                    [0, v, (v + 0.15).clamp(0, 1), 1],
                  ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// 间奏时的三个呼吸圆点。
class _InterludeDots extends StatefulWidget {
  const _InterludeDots({required this.size});

  final double size;

  @override
  State<_InterludeDots> createState() => _InterludeDotsState();
}

class _InterludeDotsState extends State<_InterludeDots> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1600))
    ..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: widget.size * 2.4,
      child: AnimatedBuilder(
        animation: _c,
        builder: (_, _) => Row(
          children: [
            for (var i = 0; i < 3; i++)
              Padding(
                padding: EdgeInsets.only(right: widget.size * 0.6),
                child: Transform.scale(
                  scale: 0.7 + 0.5 * Curves.easeInOut.transform(((_c.value * 3 - i) % 3 / 3 - 0.5).abs() * 2),
                  child: Container(
                    width: widget.size,
                    height: widget.size,
                    decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
