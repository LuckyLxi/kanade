import 'package:material_ui/material_ui.dart';

import '../src/rust/api/music.dart' as api;

/// 歌词显示：逐字点亮、罗马音。歌曲没有对应的数据时开着也不显示。
class LyricSettings extends ChangeNotifier {
  LyricSettings()
    : wordByWord = api.getPref(key: _wordByWordKey) != 'false',
      romaji = api.getPref(key: _romajiKey) != 'false';

  static const _wordByWordKey = 'lyric_word_by_word';
  static const _romajiKey = 'lyric_romaji';

  bool wordByWord;
  bool romaji;

  void setWordByWord(bool v) {
    wordByWord = v;
    api.setPref(key: _wordByWordKey, value: '$v');
    notifyListeners();
  }

  void setRomaji(bool v) {
    romaji = v;
    api.setPref(key: _romajiKey, value: '$v');
    notifyListeners();
  }
}
