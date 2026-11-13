import 'dart:async';
import 'dart:ui' as ui;

import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';

import '../data/data_ext.dart';
import '../settings/locale_controller.dart';
import '../src/rust/api/types.dart';
import 'player_controller.dart';

/// Windows 任务栏图标悬停时的预览，原生部分在 windows/runner/taskbar_thumbnail.cpp。
/// 有歌时预览显示封面，标题是「歌名 - 歌手」，下面是上一首 / 播放暂停 / 下一首。
/// 没歌或封面加载失败时恢复系统默认的窗口缩略图。
class TaskbarThumbnail {
  TaskbarThumbnail(this._p, this._locale) {
    _channel.setMethodCallHandler(_onCall);
    _locale.addListener(_push);
    unawaited(_loadIcons());
  }

  static const _channel = MethodChannel('kanade/taskbar');

  final PlayerController _p;
  final LocaleController _locale;
  Song? _song;
  bool _playing = false;

  void dispose() {
    _locale.removeListener(_push);
    _channel.setMethodCallHandler(null);
  }

  void song(Song? s) {
    _song = s;
    _push();
    unawaited(_loadCover(s));
  }

  void state({required bool playing}) {
    if (playing == _playing) return;
    _playing = playing;
    _push();
  }

  void _push() {
    final s = _song;
    final l = _locale.strings;
    unawaited(
      _channel.invokeMethod('update', {
        'visible': s != null,
        'playing': _playing,
        'title': s == null ? l.appTitle : '${s.name} - ${singerNames(s)}',
        'tips': [l.previousSong, l.play, l.pause, l.nextSong],
      }),
    );
  }

  Future<void> _onCall(MethodCall call) async {
    switch (call.method) {
      case 'button':
        switch (call.arguments) {
          case 'previous':
            await _p.previous();
          case 'toggle':
            await _p.toggle();
          case 'next':
            await _p.next();
        }
      case 'iconSpecChanged':
        await _loadIcons();
    }
  }

  /// 换歌时旧封面先留着，新封面到了再换，免得预览在封面和窗口截图之间闪一下。
  Future<void> _loadCover(Song? s) async {
    Map<String, Object>? cover;
    if (s != null && s.coverUrl.isNotEmpty) {
      try {
        // 和迷你播放器的 Cover 同一个地址，通常直接命中图片缓存
        final image = await _resolve(NetworkImage(httpsUrl(s.coverUrl)));
        try {
          final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
          if (data != null) {
            cover = {'width': image.width, 'height': image.height, 'rgba': data.buffer.asUint8List()};
          }
        } finally {
          image.dispose();
        }
      } catch (e) {
        debugPrint('taskbar cover failed: $e');
      }
    }
    if (_song?.mid != s?.mid) return;
    await _channel.invokeMethod('setCover', cover);
  }

  /// 图标按任务栏当前的小图标尺寸和深浅色画，主题或缩放变了原生那边会通知重画。
  Future<void> _loadIcons() async {
    try {
      final spec = (await _channel.invokeMapMethod<String, Object?>('iconSpec'))!;
      final size = spec['size']! as int;
      final color = spec['light']! as bool ? const Color(0xFF1A1A1A) : Colors.white;
      await _channel.invokeMethod('setIcons', {
        'size': size,
        'previous': await _drawIcon(Icons.skip_previous_rounded, size, color),
        'play': await _drawIcon(Icons.play_arrow_rounded, size, color),
        'pause': await _drawIcon(Icons.pause_rounded, size, color),
        'next': await _drawIcon(Icons.skip_next_rounded, size, color),
      });
    } catch (e) {
      debugPrint('taskbar icons failed: $e');
    }
  }
}

Future<Uint8List> _drawIcon(IconData icon, int size, Color color) async {
  final painter = TextPainter(
    text: TextSpan(
      text: String.fromCharCode(icon.codePoint),
      style: TextStyle(
        fontFamily: icon.fontFamily,
        package: icon.fontPackage,
        fontSize: size.toDouble(),
        height: 1,
        color: color,
      ),
    ),
    textDirection: TextDirection.ltr,
  )..layout();
  final recorder = ui.PictureRecorder();
  painter.paint(Canvas(recorder), Offset((size - painter.width) / 2, (size - painter.height) / 2));
  painter.dispose();
  final picture = recorder.endRecording();
  final image = await picture.toImage(size, size);
  picture.dispose();
  try {
    // 原生那边做 32 位图标，要不预乘透明度的像素
    final data = await image.toByteData(format: ui.ImageByteFormat.rawStraightRgba);
    return data!.buffer.asUint8List();
  } finally {
    image.dispose();
  }
}

Future<ui.Image> _resolve(ImageProvider provider) {
  final completer = Completer<ui.Image>();
  final stream = provider.resolve(ImageConfiguration.empty);
  late final ImageStreamListener listener;
  listener = ImageStreamListener(
    (info, _) {
      stream.removeListener(listener);
      completer.complete(info.image.clone());
      info.dispose();
    },
    onError: (e, s) {
      stream.removeListener(listener);
      completer.completeError(e, s);
    },
  );
  stream.addListener(listener);
  return completer.future;
}
