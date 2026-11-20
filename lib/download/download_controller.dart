import 'dart:async';

import 'package:material_ui/material_ui.dart';

import '../data/song_json.dart';
import '../player/playback_messages.dart';
import '../src/rust/api/music.dart' as api;
import '../src/rust/api/types.dart';

/// 下载在另一个进程里跑（Android 播放进程）：命令发过去，改动从 [changes] 回来。
class RemoteDownloads {
  RemoteDownloads(this.send, this.changes);

  final Future<void> Function(PlaybackOp op, [Object? argument]) send;

  /// 改了的那首的 mid；null 表示可能都变了（播放进程重启过）。
  final Stream<String?> changes;
}

/// 下载列表和进度。记录在 Rust 的数据库里，这里只是一份跟着改动更新的副本。
class DownloadController extends ChangeNotifier {
  DownloadController([this._remote]) {
    _reload();
    _sub = switch (_remote) {
      final remote? => remote.changes.listen(_onRemote),
      null => api.watchDownloads().listen(_onEvent),
    };
  }

  final RemoteDownloads? _remote;
  final _items = <String, DownloadItem>{};
  StreamSubscription<Object?>? _sub;
  late int concurrency = api.getDownloadConcurrency();
  late bool wifiOnly = api.getDownloadWifiOnly();

  DownloadItem? item(String mid) => _items[mid];

  /// 先加入的在前。
  Iterable<DownloadItem> get items => _items.values;

  bool get waitingForWifi => api.downloadWaitingForWifi();

  void _reload() {
    _items.clear();
    for (final d in api.getDownloads()) {
      _items[d.song.mid] = d;
    }
  }

  void _onEvent(DownloadEvent e) {
    switch (e) {
      case DownloadEvent_Changed(field0: final d):
        _items[d.song.mid] = d;
      case DownloadEvent_Removed(:final mid):
        _items.remove(mid);
    }
    notifyListeners();
  }

  // 两个进程共用一个数据库，播放进程写完记录才通知，这边直接读
  void _onRemote(String? mid) {
    if (mid == null) {
      _reload();
    } else if (api.getDownload(mid: mid) case final d?) {
      _items[mid] = d;
    } else {
      _items.remove(mid);
    }
    notifyListeners();
  }

  Future<void> download(List<Song> songs, Quality quality) => switch (_remote) {
    final r? => r.send(PlaybackOp.download, [
      songs.map(songToJson).toList(),
      quality.name,
    ]),
    null => api.downloadSongs(songs: songs, quality: quality),
  };

  Future<void> pause(List<String> mids) => switch (_remote) {
    final r? => r.send(PlaybackOp.pauseDownloads, mids),
    null => api.pauseDownloads(mids: mids),
  };

  /// 继续暂停的、重试失败的。
  Future<void> resume(List<String> mids) => switch (_remote) {
    final r? => r.send(PlaybackOp.resumeDownloads, mids),
    null => api.resumeDownloads(mids: mids),
  };

  /// 按下载文件夹里的文件补回记录（重装后用），返回补回的首数。
  /// Android 上两个进程共用数据库，在这边做完直接重读。
  Future<int> restore() async {
    final n = await api.restoreDownloads();
    _reload();
    notifyListeners();
    return n;
  }

  Future<void> remove(String mid) => switch (_remote) {
    final r? => r.send(PlaybackOp.removeDownload, mid),
    null => api.removeDownload(mid: mid),
  };

  Future<void> setConcurrency(int n) {
    concurrency = n;
    notifyListeners();
    return switch (_remote) {
      final r? => r.send(PlaybackOp.downloadConcurrency, n),
      null => api.setDownloadConcurrency(n: n),
    };
  }

  Future<void> setWifiOnly(bool on) {
    wifiOnly = on;
    notifyListeners();
    return switch (_remote) {
      final r? => r.send(PlaybackOp.downloadWifiOnly, on),
      null => api.setDownloadWifiOnly(enabled: on),
    };
  }

  @override
  void dispose() {
    unawaited(_sub?.cancel());
    super.dispose();
  }
}

/// 需要整首解码的音质下载下来是 WAV。
bool savesAsWav(Quality q) =>
    q == Quality.dts || q == Quality.ra360 || q == Quality.aicodec;
