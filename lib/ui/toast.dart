import 'dart:async';
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import 'desktop_shell.dart';
import 'mini_player.dart';

enum ToastKind { info, success, liked, error }

/// 提示。页面已经关掉、找不到 Overlay 时什么都不做。
void showToast(BuildContext context, String text, {ToastKind kind = ToastKind.info}) {
  final overlay = Overlay.maybeOf(context, rootOverlay: true);
  if (overlay != null) Toast.show(overlay, text, kind: kind);
}

/// 毛玻璃胶囊提示：居中浮在导航栏和播放条上方，播放页打开时挪到顶上。
/// 同一时间只有一条，新的来了旧的就淡出。
abstract final class Toast {
  /// 浮在内容上的玻璃（导航栏、播放条）占掉的地方，由 HomeShell 报上来，含底部安全区。
  static final chrome = ValueNotifier(EdgeInsets.zero);

  static ValueNotifier<bool>? _leaving;

  /// 异步回来后 context 可能已经没了，先拿好 Overlay 再调这个。
  static void show(OverlayState overlay, String text, {ToastKind kind = ToastKind.info}) {
    _leaving?.value = true;
    final leaving = _leaving = ValueNotifier(false);
    late final OverlayEntry entry;
    entry = OverlayEntry(
      builder: (_) => _Toast(
        text: text,
        kind: kind,
        leaving: leaving,
        onGone: () {
          entry.remove();
          entry.dispose();
          leaving.dispose();
          if (_leaving == leaving) _leaving = null;
        },
      ),
    );
    overlay.insert(entry);
  }
}

class _Toast extends StatefulWidget {
  const _Toast({required this.text, required this.kind, required this.leaving, required this.onGone});

  final String text;
  final ToastKind kind;
  final ValueNotifier<bool> leaving;
  final VoidCallback onGone;

  @override
  State<_Toast> createState() => _ToastState();
}

class _ToastState extends State<_Toast> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 240),
    reverseDuration: const Duration(milliseconds: 160),
  )..forward();
  late final _t = CurvedAnimation(parent: _c, curve: Curves.easeOutCubic, reverseCurve: Curves.easeInCubic);
  late final Timer _timer;
  bool _left = false;

  static final _placement = Listenable.merge([Toast.chrome, MiniPlayer.anchor.hidden, DesktopPlayerBar.anchor.hidden]);

  @override
  void initState() {
    super.initState();
    // 出错的多留一会儿，方便看清原因
    _timer = Timer(Duration(milliseconds: widget.kind == ToastKind.error ? 3600 : 2400), _leave);
    widget.leaving.addListener(_leave);
  }

  void _leave() {
    if (_left) return;
    _left = true;
    _timer.cancel();
    _c.reverse().whenComplete(widget.onGone);
  }

  @override
  void dispose() {
    _timer.cancel();
    widget.leaving.removeListener(_leave);
    _t.dispose();
    _c.dispose();
    super.dispose();
  }

  (IconData, Color) get _icon => switch (widget.kind) {
    ToastKind.info => (Icons.info_outline_rounded, Colors.white),
    ToastKind.success => (Icons.check_rounded, Colors.white),
    ToastKind.liked => (Icons.favorite_rounded, Theme.of(context).colorScheme.primary),
    ToastKind.error => (Icons.error_outline_rounded, const Color(0xFFFF6B5E)),
  };

  @override
  Widget build(BuildContext context) {
    final (icon, iconColor) = _icon;
    const radius = BorderRadius.all(Radius.circular(22));
    final capsule = GestureDetector(
      onTap: _leave,
      child: DecoratedBox(
        decoration: const BoxDecoration(
          borderRadius: radius,
          boxShadow: [BoxShadow(color: Color(0x80000000), blurRadius: 24, offset: Offset(0, 8))],
        ),
        child: ClipRRect(
          borderRadius: radius,
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: const Color(0xB8222222),
                borderRadius: radius,
                border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
              ),
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 44, maxWidth: 420),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(14, 11, 18, 11),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(icon, size: 18, color: iconColor),
                      const SizedBox(width: 10),
                      Flexible(
                        child: Text(
                          widget.text,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            height: 1.3,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    return ListenableBuilder(
      listenable: _placement,
      builder: (context, child) {
        // 播放页底下是播放控制，提示放到顶上
        final onPlayer = MiniPlayer.anchor.hidden.value || DesktopPlayerBar.anchor.hidden.value;
        final chrome = onPlayer ? EdgeInsets.zero : Toast.chrome.value;
        final from = onPlayer ? -1.0 : 1.0;
        return Positioned(
          left: chrome.left + 16,
          right: chrome.right + 16,
          top: onPlayer ? MediaQuery.paddingOf(context).top + 28 : null,
          bottom: onPlayer ? null : chrome.bottom,
          child: Align(
            alignment: onPlayer ? Alignment.topCenter : Alignment.bottomCenter,
            child: AnimatedBuilder(
              animation: _t,
              builder: (context, child) => Opacity(
                opacity: _t.value.clamp(0.0, 1.0),
                child: Transform.translate(
                  offset: Offset(0, from * 12 * (1 - _t.value)),
                  child: Transform.scale(scale: 0.94 + 0.06 * _t.value, child: child),
                ),
              ),
              child: child,
            ),
          ),
        );
      },
      child: Material(
        type: MaterialType.transparency,
        child: Semantics(liveRegion: true, child: capsule),
      ),
    );
  }
}
