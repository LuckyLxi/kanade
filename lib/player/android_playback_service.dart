import 'dart:async';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:media_kit/media_kit.dart';
import 'package:path_provider/path_provider.dart';

import '../auth/auth_controller.dart';
import '../data/song_json.dart';
import '../library/library_controller.dart';
import '../settings/locale_controller.dart';
import '../src/rust/api/music.dart' as api;
import '../src/rust/api/types.dart';
import '../src/rust/frb_generated.dart';
import 'android_playback_connection.dart';
import 'media_session.dart';
import 'playback_messages.dart';
import 'player_controller.dart';

Future<void> runAndroidPlayback() async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  await RustLib.init();
  final directory = (await getApplicationSupportDirectory()).path;
  await api.initCore(dataDir: directory);

  final auth = AuthController(watchSession: false);
  final library = LibraryController(auth);
  final locale = LocaleController();
  final player = PlayerController(auth, loadDisplayMetadata: false);
  await MediaSession.attach(player, library, locale);
  await _PlaybackServer(player, auth, library, locale).listen(directory);
}

class _PlaybackServer {
  _PlaybackServer(this.player, this.auth, this.library, this.locale);

  final PlayerController player;
  final AuthController auth;
  final LibraryController library;
  final LocaleController locale;
  final _clients = <Socket>{};
  final _watching = <Socket>{};
  List<Song>? _sentQueue;

  Future<void> listen(String directory) async {
    final address = playbackAddress(directory);
    final file = File(address.address);
    if (await FileSystemEntity.type(file.path) !=
        FileSystemEntityType.notFound) {
      await file.delete();
    }
    final server = await ServerSocket.bind(address, 0);
    server.listen(_attach);
    player.addListener(_publish);
    library.addListener(_publish);
    player.position.addListener(_publishPosition);
    // 下载在这个进程里跑；界面从共用的数据库读记录，这里只告诉它哪首变了
    api.watchDownloads().listen((e) {
      final mid = switch (e) {
        DownloadEvent_Changed(field0: final d) => d.song.mid,
        DownloadEvent_Removed(:final mid) => mid,
      };
      for (final socket in _clients) {
        sendPlaybackMessage(socket, {'download': mid});
      }
    });
  }

  void _attach(Socket socket) {
    _clients.add(socket);
    socket.done.ignore();
    playbackMessages(socket).listen(
      (request) {
        if (request['watch'] case final bool watching) {
          if (watching) {
            _watching.add(socket);
            sendPlaybackMessage(socket, _snapshot(includeQueue: true));
            sendPlaybackMessage(socket, _position);
          } else {
            _watching.remove(socket);
          }
        } else {
          unawaited(_reply(socket, request));
        }
      },
      onError: (Object _) => _remove(socket),
      onDone: () => _remove(socket),
      cancelOnError: true,
    );
  }

  void _remove(Socket socket) {
    _clients.remove(socket);
    _watching.remove(socket);
    socket.destroy();
  }

  PlaybackMessage get _position => {
    'position': player.position.value.inMilliseconds,
  };

  PlaybackMessage _snapshot({required bool includeQueue}) {
    final song = player.current;
    return {
      ...encodePlayerState(player, includeQueue: includeQueue),
      if (song != null && library.canLike) 'liked': library.isLiked(song),
    };
  }

  void _publish() {
    if (_watching.isEmpty) return;
    final snapshot = _snapshot(
      includeQueue: !identical(_sentQueue, player.queue),
    );
    _sentQueue = player.queue;
    for (final socket in _watching) {
      sendPlaybackMessage(socket, snapshot);
    }
  }

  void _publishPosition() {
    for (final socket in _watching) {
      sendPlaybackMessage(socket, _position);
    }
  }

  Future<void> _reply(Socket socket, PlaybackMessage request) async {
    final id = request['id'];
    final PlaybackMessage response;
    try {
      final value = await _command(
        request['method'] as String,
        request['argument'],
      );
      response = {'id': id, 'value': value};
    } catch (error) {
      if (_clients.contains(socket)) {
        sendPlaybackMessage(socket, {
          'id': id,
          'error': encodePlaybackException(error),
        });
      }
      return;
    }
    if (_clients.contains(socket)) sendPlaybackMessage(socket, response);
  }

  static List<Song> _songs(Object? value) => (value as List<Object?>)
      .cast<Map<String, dynamic>>()
      .map(songFromJson)
      .toList();

  Future<Object?> _command(String method, Object? argument) async {
    switch (PlaybackOp.values.byName(method)) {
      case PlaybackOp.playList:
        final args = argument as List<Object?>;
        await player.playList(_songs(args[0]), args[1] as int);
      case PlaybackOp.playRadio:
        final args = argument as List<Object?>;
        await player.playRadio(
          RadioSource.fromMessage(
            args[0] as String,
            (args[1] as List<Object?>).cast<int>(),
            args[2] as int?,
          ),
          first: args[3] == null ? null : _songs(args[3]),
        );
      case PlaybackOp.playNext:
        player.playNext(songFromJson(argument as Map<String, dynamic>));
      case PlaybackOp.playAt:
        await player.playAt(argument as int);
      case PlaybackOp.removeAt:
        await player.removeAt(argument as int);
      case PlaybackOp.moveQueue:
        final args = argument as List<Object?>;
        player.moveQueue(args[0] as int, args[1] as int);
      case PlaybackOp.next:
        await player.next();
      case PlaybackOp.previous:
        await player.previous();
      case PlaybackOp.play:
        await player.play();
      case PlaybackOp.pause:
        await player.pause();
      case PlaybackOp.toggle:
        await player.toggle();
      case PlaybackOp.seek:
        await player.seek(Duration(milliseconds: argument as int));
      case PlaybackOp.restorePosition:
        await player.restorePosition(Duration(milliseconds: argument as int));
      case PlaybackOp.mode:
        player.setMode(PlayMode.values.byName(argument as String));
      case PlaybackOp.defaultQuality:
        player.setDefaultQuality(Quality.values.byName(argument as String));
      case PlaybackOp.fade:
        player.setFade(Duration(seconds: argument as int));
      case PlaybackOp.sleep:
        player.setSleepTimer(
          argument == null ? null : Duration(seconds: argument as int),
        );
      case PlaybackOp.sleepAfterSong:
        player.setSleepAfterSong(argument as bool);
      case PlaybackOp.volume:
        await player.setVolume((argument as num).toDouble());
      case PlaybackOp.quality:
        await player.setQuality(Quality.values.byName(argument as String));
      case PlaybackOp.auth:
        auth.reloadSession();
      case PlaybackOp.locale:
        locale.reloadLocale();
      case PlaybackOp.like:
        final args = argument as List<Object?>;
        library.updateLiked(
          songFromJson(args[0] as Map<String, dynamic>),
          args[1] as bool,
        );
      case PlaybackOp.cacheInfo:
        final info = await player.audioCacheInfo();
        return [info.limitMb, info.bytes];
      case PlaybackOp.cacheLimit:
        await player.setAudioCacheLimit(argument as int);
      case PlaybackOp.clearAudioCache:
        await player.clearAudioCache();
      case PlaybackOp.download:
        final args = argument as List<Object?>;
        await api.downloadSongs(
          songs: _songs(args[0]),
          quality: Quality.values.byName(args[1] as String),
        );
      case PlaybackOp.pauseDownloads:
        await api.pauseDownloads(mids: (argument as List<Object?>).cast());
      case PlaybackOp.resumeDownloads:
        await api.resumeDownloads(mids: (argument as List<Object?>).cast());
      case PlaybackOp.removeDownload:
        await api.removeDownload(mid: argument as String);
      case PlaybackOp.downloadConcurrency:
        await api.setDownloadConcurrency(n: argument as int);
      case PlaybackOp.downloadWifiOnly:
        await api.setDownloadWifiOnly(enabled: argument as bool);
    }
    return null;
  }
}
