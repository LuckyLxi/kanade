import 'package:material_ui/material_ui.dart';

/// 一条轨道里放几个选项，选中的那块白底会滑过去。
/// 放得下时各段按文字宽度平分多出来的空间，放不下就横向滚动，切换时把选中的滚进视野。
class SlidingSegments extends StatefulWidget {
  const SlidingSegments({
    super.key,
    required this.labels,
    required this.selected,
    required this.onSelect,
  });

  final List<String> labels;
  final int selected;
  final ValueChanged<int> onSelect;

  @override
  State<SlidingSegments> createState() => _SlidingSegmentsState();
}

class _SlidingSegmentsState extends State<SlidingSegments> {
  static const _height = 38.0;
  static const _inset = 3.0;
  static const _textPadding = 28.0;
  static const _duration = Duration(milliseconds: 320);
  static const _curve = Curves.easeOutBack;
  static const _style = TextStyle(fontSize: 13, fontWeight: FontWeight.w600);

  final _scroll = ScrollController();
  List<double> _widths = const [];

  @override
  void didUpdateWidget(SlidingSegments old) {
    super.didUpdateWidget(old);
    if (old.selected != widget.selected) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _reveal());
    }
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  double _left(int i) {
    var x = _inset;
    for (var j = 0; j < i; j++) {
      x += _widths[j];
    }
    return x;
  }

  /// 选中的一段滚到轨道中间（滚不到就贴边）。
  void _reveal() {
    if (!mounted || !_scroll.hasClients) return;
    final i = widget.selected;
    if (i < 0 || i >= _widths.length) return;
    final p = _scroll.position;
    final target = _left(i) + _widths[i] / 2 - p.viewportDimension / 2;
    _scroll.animateTo(
      target.clamp(p.minScrollExtent, p.maxScrollExtent),
      duration: _duration,
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final scaler = MediaQuery.textScalerOf(context);
    final dir = Directionality.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final natural = [
          for (final label in widget.labels)
            (TextPainter(
                  text: TextSpan(text: label, style: _style),
                  textDirection: dir,
                  textScaler: scaler,
                  maxLines: 1,
                )..layout()).width.ceilToDouble() +
                _textPadding,
        ];
        final inner = constraints.maxWidth - _inset * 2;
        final total = natural.fold(0.0, (a, b) => a + b);
        final extra = total < inner ? (inner - total) / natural.length : 0.0;
        _widths = [for (final w in natural) w + extra];
        final i = widget.selected.clamp(0, widget.labels.length - 1);
        final track = Stack(
          children: [
            AnimatedPositioned(
              duration: _duration,
              curve: _curve,
              left: _left(i),
              top: _inset,
              width: _widths[i],
              height: _height - _inset * 2,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: scheme.onSurface,
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(_inset),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final (j, label) in widget.labels.indexed)
                    SizedBox(
                      width: _widths[j],
                      height: _height - _inset * 2,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(99),
                        onTap: () => widget.onSelect(j),
                        child: Center(
                          child: AnimatedDefaultTextStyle(
                            duration: const Duration(milliseconds: 200),
                            style: _style.copyWith(
                              color: j == i
                                  ? scheme.surface
                                  : scheme.onSurfaceVariant,
                            ),
                            child: Text(label, maxLines: 1),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        );
        return Container(
          height: _height,
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: scheme.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(99),
          ),
          child: SingleChildScrollView(
            controller: _scroll,
            scrollDirection: Axis.horizontal,
            child: track,
          ),
        );
      },
    );
  }
}
