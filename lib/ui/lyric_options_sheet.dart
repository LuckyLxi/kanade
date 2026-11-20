import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../l10n/l10n_ext.dart';
import '../settings/lyric_settings.dart';
import 'sheet.dart';

/// 播放页「更多」里的歌词显示开关，和设置页里的是同一份。
Future<void> showLyricOptions(BuildContext context) => showKanadeSheet<void>(
  context: context,
  builder: (sheet) {
    final l = AppLocalizations.of(sheet);
    final s = sheet.watch<LyricSettings>();
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SheetHeader(title: l.lyricOptions),
        SheetGroup(
          children: [
            SheetRow(
              leading: const Icon(Icons.lyrics_outlined),
              title: l.lyricWordByWord,
              subtitle: l.lyricWordByWordHint,
              trailing: Switch(
                value: s.wordByWord,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                onChanged: s.setWordByWord,
              ),
              onTap: () => s.setWordByWord(!s.wordByWord),
            ),
            SheetRow(
              leading: const Icon(Icons.abc_rounded),
              title: l.lyricRomaji,
              subtitle: l.lyricRomajiHint,
              trailing: Switch(
                value: s.romaji,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                onChanged: s.setRomaji,
              ),
              onTap: () => s.setRomaji(!s.romaji),
            ),
            SheetRow(
              leading: const Icon(Icons.translate_rounded),
              title: l.lyricTranslation,
              subtitle: l.lyricTranslationHint,
              trailing: Switch(
                value: s.translation,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                onChanged: s.setTranslation,
              ),
              onTap: () => s.setTranslation(!s.translation),
            ),
          ],
        ),
      ],
    );
  },
);
