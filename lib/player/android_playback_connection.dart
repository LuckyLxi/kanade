import 'dart:async';
import 'dart:convert';
import 'dart:io';

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
  AndroidPlaybackConnection(String directory, this.onUpdate)
    : _address = playbackAddress(directory);

  final InternetAddress _address;
  final void Function(PlaybackMessage) onUpdate;
  final _pending = <int, Completer<Object?>>{};
  Socket? _socket;
  Future<Socket>? _connecting;
  int _nextId = 0;
  bool _watching = true;
  bool _disposed = false;

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
        return socket;
      } on SocketException {
        if (wait.elapsed >= const Duration(seconds: 8)) rethrow;
        await Future<void>.delayed(const Duration(milliseconds: 150));
      }
    }
  }

  Future<Object?> call(String method, [Object? argument]) async {
    final socket = await connect();
    final id = _nextId++;
    final response = Completer<Object?>();
    _pending[id] = response;
    try {
      sendPlaybackMessage(socket, {
        'id': id,
        'method': method,
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
      onUpdate(message);
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
  }
}
