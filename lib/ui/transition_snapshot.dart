import 'package:material_ui/material_ui.dart';

/// [animation] 处在 [when] 认的状态时，[child] 先画成一张图，转场里只贴这张图，不再每帧重画。
/// 每次重新进入这个状态都重截一张，中间这段时间里 [child] 可能已经变了。
class TransitionSnapshot extends StatefulWidget {
  const TransitionSnapshot({
    super.key,
    required this.animation,
    required this.when,
    required this.child,
  });

  final Animation<double>? animation;
  final bool Function(AnimationStatus status) when;
  final Widget child;

  @override
  State<TransitionSnapshot> createState() => _TransitionSnapshotState();
}

class _TransitionSnapshotState extends State<TransitionSnapshot> {
  final _snapshot = SnapshotController();

  @override
  void initState() {
    super.initState();
    _watch(widget.animation);
  }

  @override
  void didUpdateWidget(TransitionSnapshot oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.animation == widget.animation) return;
    oldWidget.animation?.removeStatusListener(_onStatus);
    _watch(widget.animation);
  }

  void _watch(Animation<double>? animation) {
    animation?.addStatusListener(_onStatus);
    _onStatus(animation?.status ?? AnimationStatus.dismissed);
  }

  void _onStatus(AnimationStatus status) {
    final snap = widget.when(status);
    if (snap && !_snapshot.allowSnapshotting) _snapshot.clear();
    _snapshot.allowSnapshotting = snap;
  }

  @override
  void dispose() {
    widget.animation?.removeStatusListener(_onStatus);
    _snapshot.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SnapshotWidget(
    controller: _snapshot,
    mode: SnapshotMode.permissive,
    child: widget.child,
  );
}
