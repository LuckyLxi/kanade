import 'dart:async';

import 'package:material_ui/material_ui.dart';

import '../src/rust/api/music.dart' as api;
import '../src/rust/api/types.dart';

/// 下载列表和进度。记录在 Rust 的数据库里，这里只是一份跟着事件更新的副本。
class DownloadController extends ChangeNotifier {
  DownloadController() {
    for (final d in api.getDownloads()) {
      _items[d.song.mid] = d;
    }
    _sub = api.watchDownloads().listen(_onEvent);
  }

  final _items = <String, DownloadItem>{};
  StreamSubscription<DownloadEvent>? _sub;

  DownloadItem? item(String mid) => _items[mid];

  /// 先加入的在前。
  Iterable<DownloadItem> get items => _items.values;

  void _onEvent(DownloadEvent e) {
    switch (e) {
      case DownloadEvent_Changed(field0: final d):
        _items[d.song.mid] = d;
      case DownloadEvent_Removed(:final mid):
        _items.remove(mid);
    }
    notifyListeners();
  }

  Future<void> download(List<Song> songs, Quality quality) =>
      api.downloadSongs(songs: songs, quality: quality);

  Future<void> remove(String mid) => api.removeDownload(mid: mid);

  @override
  void dispose() {
    unawaited(_sub?.cancel());
    super.dispose();
  }
}

/// 需要整首解码的音质下载下来是 WAV。
bool savesAsWav(Quality q) =>
    q == Quality.dts || q == Quality.ra360 || q == Quality.aicodec;
