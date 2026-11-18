import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../l10n/l10n_ext.dart';
import '../player/player_controller.dart';
import 'sheet.dart';

const _maxMinutes = 120;

/// 定时关闭：滑块选时长、播完整首再停的开关、开始按钮。
Future<void> showSleepTimer(BuildContext context) => showKanadeSheet<void>(
  context: context,
  padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
  builder: (_) => const _SleepTimerSheet(),
);

class _SleepTimerSheet extends StatefulWidget {
  const _SleepTimerSheet();

  @override
  State<_SleepTimerSheet> createState() => _SleepTimerSheetState();
}

class _SleepTimerSheetState extends State<_SleepTimerSheet> {
  // 开着定时的话从剩余时间开始
  // 滑块用连续值：带 divisions 的滑块每跳一格都要动画过去，拖起来跟不上手指
  late double _value = switch (context
      .read<PlayerController>()
      .sleepAt
      ?.difference(DateTime.now())) {
    final left? when left > Duration.zero =>
      ((left.inSeconds + 59) ~/ 60).clamp(1, _maxMinutes).toDouble(),
    _ => 30,
  };

  int get _minutes => _value.round();

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final (_, fill) = sheetColors(scheme);
    final player = context.watch<PlayerController>();
    final at = player.sleepAt;
    final navigator = Navigator.of(context);
    final card = BoxDecoration(
      color: fill,
      borderRadius: BorderRadius.circular(20),
    );
    return SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SheetHeader(
            title: l.sleepTimer,
            subtitle: at == null
                ? null
                : at.isAfter(DateTime.now())
                ? l.sleepTimerUntil(
                    MaterialLocalizations.of(context)
                        .formatTimeOfDay(TimeOfDay.fromDateTime(at)),
                  )
                : l.sleepTimerWaiting,
            trailing: IconButton.filled(
              tooltip: l.close,
              style: IconButton.styleFrom(
                backgroundColor: fill,
                foregroundColor: scheme.onSurface,
                fixedSize: const Size.square(44),
              ),
              onPressed: navigator.pop,
              icon: const Icon(Icons.close_rounded),
            ),
          ),
          Container(
            decoration: card,
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        l.sleepTimerDuration,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: scheme.onSurface,
                        ),
                      ),
                    ),
                    Text(
                      l.durationMinutes(_minutes),
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: scheme.onSurface,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                SliderTheme(
                  data: SliderThemeData(
                    trackHeight: 18,
                    activeTrackColor: scheme.primary,
                    inactiveTrackColor: scheme.surfaceContainerHighest,
                    thumbColor: Colors.white,
                    overlayShape: SliderComponentShape.noOverlay,
                    thumbShape: const RoundSliderThumbShape(
                      enabledThumbRadius: 13,
                      elevation: 2,
                    ),
                    trackShape: const RoundedRectSliderTrackShape(),
                  ),
                  child: Slider(
                    value: _value,
                    min: 1,
                    max: _maxMinutes.toDouble(),
                    padding: const EdgeInsets.symmetric(horizontal: 13),
                    semanticFormatterCallback: (v) =>
                        l.durationMinutes(v.round()),
                    onChanged: (v) => setState(() => _value = v),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Material(
            color: fill,
            borderRadius: BorderRadius.circular(20),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: () => player.setSleepAfterSong(!player.sleepAfterSong),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(18, 14, 14, 14),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            l.sleepAfterSong,
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: scheme.onSurface,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            l.sleepAfterSongHint,
                            style: TextStyle(
                              fontSize: 13,
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Switch(
                      value: player.sleepAfterSong,
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      onChanged: player.setSleepAfterSong,
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              if (at != null) ...[
                Expanded(
                  child: _PillButton(
                    label: l.sleepTimerOff,
                    background: fill,
                    foreground: scheme.onSurface,
                    onTap: () {
                      player.setSleepTimer(null);
                      navigator.pop();
                    },
                  ),
                ),
                const SizedBox(width: 10),
              ],
              Expanded(
                child: _PillButton(
                  label: l.sleepTimerStart,
                  background: scheme.primary,
                  foreground: scheme.onPrimary,
                  onTap: () {
                    player.setSleepTimer(Duration(minutes: _minutes));
                    navigator.pop();
                  },
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PillButton extends StatelessWidget {
  const _PillButton({
    required this.label,
    required this.background,
    required this.foreground,
    required this.onTap,
  });

  final String label;
  final Color background;
  final Color foreground;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => FilledButton(
    style: FilledButton.styleFrom(
      backgroundColor: background,
      foregroundColor: foreground,
      minimumSize: const Size.fromHeight(52),
      shape: const StadiumBorder(),
      textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
    ),
    onPressed: onTap,
    child: Text(label),
  );
}
