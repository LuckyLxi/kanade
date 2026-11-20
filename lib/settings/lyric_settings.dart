import 'dart:io';

import 'package:material_ui/material_ui.dart';

import '../src/rust/api/music.dart' as api;

/// 歌词显示：逐字点亮、罗马音、翻译。歌曲没有对应的数据时开着也不显示。
class LyricSettings extends ChangeNotifier {
  LyricSettings()
    : wordByWord = api.getPref(key: _wordByWordKey) != 'false',
      romaji = api.getPref(key: _romajiKey) != 'false',
      translation = api.getPref(key: _translationKey) != 'false',
      keepScreenOn =
          Platform.isAndroid && api.getPref(key: _keepScreenOnKey) == 'true';

  static const _wordByWordKey = 'lyric_word_by_word';
  static const _romajiKey = 'lyric_romaji';
  static const _translationKey = 'lyric_translation';
  static const _keepScreenOnKey = 'lyric_keep_screen_on';

  bool wordByWord;
  bool romaji;
  bool translation;

  /// 停在歌词页时屏幕不自动熄灭。只在 Android 上有。
  bool keepScreenOn;

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

  void setTranslation(bool v) {
    translation = v;
    api.setPref(key: _translationKey, value: '$v');
    notifyListeners();
  }

  void setKeepScreenOn(bool v) {
    keepScreenOn = v;
    api.setPref(key: _keepScreenOnKey, value: '$v');
    notifyListeners();
  }
}
