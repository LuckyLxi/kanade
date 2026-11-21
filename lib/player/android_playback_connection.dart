import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';

import 'playback_messages.dart';

typedef PlaybackMessage = Map<String, Object?>;

InternetAddress playbackAddress(String directory) =>
    InternetAddress('$directory/playback.sock', type: InternetAddressType.unix);

Stream<PlaybackMessage> playbackMessages(Socket socket) => socket
    .cast<List<int>>()
    .transform(utf8.decoder)
    .transform(const LineSplitter())
    .map((line) => jsonDecode(line) as PlaybackMessage);

void sendPlaybackMessage(Socket socket, PlaybackMessage message) {
  socket.write('${jsonEncode(message)}\n');
}

class AndroidPlaybackConnection {
  AndroidPlaybackConnection(String directory)
    : _address = playbackAddress(directory);

  final InternetAddress _address;
  final _state = StreamController<PlaybackMessage>.broadcast(sync: true);
  final _downloads = StreamController<String>.broadcast(sync: true);
  final _floatingLyrics = StreamController<void>.broadcast(sync: true);
  final _restarts = StreamController<void>.broadcast(sync: true);

  /// 播放进程推来的播放状态快照和进度。
  Stream<PlaybackMessage> get state => _state.stream;

  /// 播放进程里下载记录变了的歌曲 mid，记录本身从共用的数据库读。
  Stream<String> get downloads => _downloads.stream;

  /// 悬浮窗上改了歌词设置，从共用的数据库重读。
  Stream<void> get floatingLyrics => _floatingLyrics.stream;

  /// 断开后重新连上：原来的播放进程已经没了，连上的是新拉起的。
  Stream<void> get restarts => _restarts.stream;
  final _pending = <int, Completer<Object?>>{};
  Socket? _socket;
  Future<Socket>? _connecting;
  int _nextId = 0;
  bool _watching = true;
  bool _disposed = false;
  bool _lost = false;

  static const _service = MethodChannel('kanade/playback');

  void setWatching(bool watching) {
    if (_watching == watching) return;
    _watching = watching;
    if (_socket case final socket?) {
      sendPlaybackMessage(socket, {'watch': watching});
    }
  }

  Future<Socket> connect() async {
    if (_disposed) throw StateError('Playback connection has closed');
    if (_socket case final socket?) return socket;
    if (_connecting case final attempt?) return attempt;
    final attempt = _open();
    _connecting = attempt;
    try {
      return await attempt;
    } finally {
      _connecting = null;
    }
  }

  Future<Socket> _open() async {
    final wait = Stopwatch()..start();
    var started = false;
    while (true) {
      if (_disposed) throw StateError('Playback connection has closed');
      try {
        final socket = await Socket.connect(_address, 0);
        if (_disposed) {
          socket.destroy();
          throw StateError('Playback connection has closed');
        }
        _socket = socket;
        socket.done.ignore();
        playbackMessages(socket).listen(
          _receive,
          onError: (Object error) => _disconnect(socket, error),
          onDone: () =>
              _disconnect(socket, StateError('Playback service disconnected')),
          cancelOnError: true,
        );
        if (_watching) sendPlaybackMessage(socket, {'watch': true});
        if (_lost) {
          _lost = false;
          _restarts.add(null);
        }
        return socket;
      } on SocketException {
        if (wait.elapsed >= const Duration(seconds: 8)) rethrow;
        // 播放进程被系统杀掉后不会自己回来，要界面重新拉起；首次启动由 audio_service 绑定拉起
        if (_lost && !started) {
          started = true;
          _service.invokeMethod<bool>('start').ignore();
        }
        await Future<void>.delayed(const Duration(milliseconds: 150));
      }
    }
  }

  Future<Object?> call(PlaybackOp op, [Object? argument]) async {
    final socket = await connect();
    final id = _nextId++;
    final response = Completer<Object?>();
    _pending[id] = response;
    try {
      sendPlaybackMessage(socket, {
        'id': id,
        'method': op.name,
        'argument': argument,
      });
      return await response.future;
    } finally {
      _pending.remove(id);
    }
  }

  void _receive(PlaybackMessage message) {
    final id = message['id'];
    if (id is! int) {
      if (_disposed) return;
      if (message['download'] case final String mid) {
        _downloads.add(mid);
      } else if (message['floatingLyrics'] == true) {
        _floatingLyrics.add(null);
      } else {
        _state.add(message);
      }
      return;
    }
    final pending = _pending.remove(id);
    if (message['error'] case final error?) {
      pending?.completeError(decodePlaybackException(error));
    } else {
      pending?.complete(message['value']);
    }
  }

  void _disconnect(Socket socket, Object error) {
    if (!identical(_socket, socket)) return;
    _socket = null;
    _lost = true;
    socket.destroy();
    for (final pending in _pending.values) {
      pending.completeError(error);
    }
    _pending.clear();
  }

  void dispose() {
    _disposed = true;
    if (_socket case final socket?) {
      _disconnect(socket, StateError('Playback connection has closed'));
    }
    unawaited(_state.close());
    unawaited(_downloads.close());
    unawaited(_floatingLyrics.close());
    unawaited(_restarts.close());
  }
}
