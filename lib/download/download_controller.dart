import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../data/song_json.dart';
import '../player/android_playback_connection.dart';
import '../player/playback_messages.dart';
import '../src/rust/api/music.dart' as api;
import '../src/rust/api/types.dart';

/// 下载列表和进度。记录在 Rust 的数据库里，这里只是一份跟着改动更新的副本。
/// Android 上下载在播放进程里跑：命令经 [_remote] 发过去，改了哪首从它的推送里回来。
class DownloadController extends ChangeNotifier {
  DownloadController([this._remote]) {
    _reload();
    _subs = switch (_remote) {
      final remote? => [
        remote.downloads.listen(_onRemote),
        // 播放进程重启过，可能都变了
        remote.restarts.listen((_) => _onRemote(null)),
      ],
      null => [api.watchDownloads().listen(_onEvent)],
    };
  }

  final AndroidPlaybackConnection? _remote;
  final _items = <String, DownloadItem>{};
  late final List<StreamSubscription<Object?>> _subs;
  late int concurrency = api.getDownloadConcurrency();
  late bool wifiOnly = api.getDownloadWifiOnly();

  /// 桌面的下载文件夹；Android 固定存到 MediaStore。
  late String dir = api.getDownloadDir();
  late bool embedLyrics = api.getDownloadEmbedLyrics();

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
    final r? => r.call(PlaybackOp.download, [
      songs.map(songToJson).toList(),
      quality.name,
    ]),
    null => api.downloadSongs(songs: songs, quality: quality),
  };

  Future<void> pause(List<String> mids) => switch (_remote) {
    final r? => r.call(PlaybackOp.pauseDownloads, mids),
    null => api.pauseDownloads(mids: mids),
  };

  /// 继续暂停的、重试失败的。
  Future<void> resume(List<String> mids) => switch (_remote) {
    final r? => r.call(PlaybackOp.resumeDownloads, mids),
    null => api.resumeDownloads(mids: mids),
  };

  /// 按下载文件夹里的文件补回记录（重装后用），返回补回的首数。
  /// Android 上要先授权读文件夹，用户拒绝时返回 null。
  /// 两个进程共用数据库，在这边做完直接重读。
  Future<int?> restore() async {
    if (Platform.isAndroid &&
        await const MethodChannel('kanade/downloads')
                .invokeMethod<bool>('pickFolder') !=
            true) {
      return null;
    }
    final n = await api.restoreDownloads();
    _reload();
    notifyListeners();
    return n;
  }

  Future<void> remove(String mid) => switch (_remote) {
    final r? => r.call(PlaybackOp.removeDownload, mid),
    null => api.removeDownload(mid: mid),
  };

  Future<void> setConcurrency(int n) {
    concurrency = n;
    notifyListeners();
    return switch (_remote) {
      final r? => r.call(PlaybackOp.downloadConcurrency, n),
      null => api.setDownloadConcurrency(n: n),
    };
  }

  Future<void> setWifiOnly(bool on) {
    wifiOnly = on;
    notifyListeners();
    return switch (_remote) {
      final r? => r.call(PlaybackOp.downloadWifiOnly, on),
      null => api.setDownloadWifiOnly(enabled: on),
    };
  }

  void setDir(String path) {
    api.setDownloadDir(dir: path);
    dir = api.getDownloadDir();
    notifyListeners();
  }

  void setEmbedLyrics(bool on) {
    api.setDownloadEmbedLyrics(enabled: on);
    embedLyrics = on;
    notifyListeners();
  }

  @override
  void dispose() {
    for (final sub in _subs) {
      unawaited(sub.cancel());
    }
    super.dispose();
  }
}

/// 需要整首解码的音质下载下来是 WAV。
bool savesAsWav(Quality q) =>
    q == Quality.dts || q == Quality.ra360 || q == Quality.aicodec;
