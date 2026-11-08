import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../l10n/l10n_ext.dart';
import '../player/player_controller.dart';
import 'sheet.dart';

const _presets = [15, 30, 45, 60, 90];

/// 定时关闭：几个常用时长、自定义分钟数、播完整首再停的开关。
Future<void> showSleepTimer(BuildContext context) => showKanadeSheet<void>(
  context: context,
  builder: (_) => const _SleepTimerSheet(),
);

class _SleepTimerSheet extends StatefulWidget {
  const _SleepTimerSheet();

  @override
  State<_SleepTimerSheet> createState() => _SleepTimerSheetState();
}

class _SleepTimerSheetState extends State<_SleepTimerSheet> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _start(int minutes) {
    context.read<PlayerController>().setSleepTimer(Duration(minutes: minutes));
    Navigator.of(context).pop();
  }

  int? get _custom => switch (int.tryParse(_controller.text)) {
    final m? when m > 0 => m,
    _ => null,
  };

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final (_, fill) = sheetColors(scheme);
    final player = context.watch<PlayerController>();
    final at = player.sleepAt;
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide(color: scheme.outline),
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
          ),
          SheetGroup(
            children: [
              for (final m in _presets)
                SheetRow(
                  leading: const Icon(Icons.timer_outlined),
                  title: l.durationMinutes(m),
                  onTap: () => _start(m),
                ),
            ],
          ),
          const SizedBox(height: 8),
          ValueListenableBuilder(
            valueListenable: _controller,
            builder: (_, _, _) => Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _controller,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    maxLength: 3,
                    onSubmitted: (_) {
                      if (_custom case final m?) _start(m);
                    },
                    decoration: InputDecoration(
                      hintText: l.sleepTimerCustomHint,
                      filled: true,
                      fillColor: fill,
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 12,
                      ),
                      counterText: '',
                      suffixText: l.sleepTimerMinutes,
                      suffixStyle: TextStyle(
                        fontSize: 13,
                        color: scheme.onSurfaceVariant,
                      ),
                      border: border,
                      enabledBorder: border,
                      focusedBorder: border.copyWith(
                        borderSide: BorderSide(color: scheme.onSurfaceVariant),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  // 和歌单命名弹窗的按钮一样：白底黑字
                  style: FilledButton.styleFrom(
                    backgroundColor: scheme.onSurface,
                    foregroundColor: scheme.surface,
                    minimumSize: const Size(64, 46),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  onPressed: switch (_custom) {
                    final m? => () => _start(m),
                    null => null,
                  },
                  child: Text(l.sleepTimerStart),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          SheetGroup(
            children: [
              SheetRow(
                leading: const Icon(Icons.music_note_outlined),
                title: l.sleepAfterSong,
                onTap: () => player.setSleepAfterSong(!player.sleepAfterSong),
                trailing: Switch(
                  value: player.sleepAfterSong,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  onChanged: player.setSleepAfterSong,
                ),
              ),
              if (at != null)
                SheetRow(
                  leading: const Icon(Icons.timer_off_outlined),
                  title: l.sleepTimerOff,
                  destructive: true,
                  onTap: () {
                    player.setSleepTimer(null);
                    Navigator.of(context).pop();
                  },
                ),
            ],
          ),
        ],
      ),
    );
  }
}
