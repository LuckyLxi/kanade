import 'dart:async';
import 'dart:typed_data';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show SynchronousFuture, visibleForTesting;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

const fallbackPalette = [Color(0xFF3A2A4A), Color(0xFF5B3FA8), Color(0xFFB0476A), Color(0xFF2A3F6B)];

/// 背景用的封面素材：4 个主色、一张预先模糊好的小图、4 张主色光斑小图。
/// 模糊和渐变都只在取图时画一次，之后每帧只是把这些小图放大、移动、旋转着画出来。
/// 不能每帧新建渐变 shader：Impeller 会给每个新渐变分配纹理，
/// 实测打开播放页时内存从 200MB 冲到 5GB 以上。
class CoverArt {
  CoverArt(this.palette, this.blurred) : blobs = _renderBlobs(palette);

  final List<Color> palette;
  final ui.Image blurred;
  final List<ui.Image> blobs;

  /// 按主色生成的深色主题（弹出菜单、底部面板用）。fromSeed 要算色调，生成一次就留着。
  late final ThemeData theme = ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(seedColor: palette[1], brightness: Brightness.dark),
  );
}

/// 解码封面用的尺寸（取色也用它）和预模糊图的尺寸。
/// 预模糊图要够大，放大到全屏时才不会出现颗粒和色块。
const _srcSize = 128;
const _artSize = 256;

/// 最近用过的封面素材，每张约 256 KB。
final _artCache = <String, CoverArt>{};

/// 正在生成的素材，同一张封面同时被预取和播放页请求时只算一次。
final _artLoading = <String, Future<CoverArt>>{};

const _blobSize = 128;

/// 每个主色画一张径向渐变光斑：中心半透明，边缘全透明。
List<ui.Image> _renderBlobs(List<Color> palette) => [
      for (final c in palette)
        () {
          final rec = ui.PictureRecorder();
          const center = Offset(_blobSize / 2, _blobSize / 2);
          Canvas(rec).drawCircle(
            center,
            _blobSize / 2,
            Paint()
              ..shader = ui.Gradient.radial(center, _blobSize / 2, [c.withValues(alpha: 0.5), c.withValues(alpha: 0)]),
          );
          return rec.endRecording().toImageSync(_blobSize, _blobSize);
        }(),
    ];

/// 还没取到封面时用的默认光斑，第一次用到时才生成。
final _fallbackBlobs = _renderBlobs(fallbackPalette);

/// 已经生成好的素材，播放页第一帧就能直接用，不用等异步。
CoverArt? cachedCoverArt(String url) => _artCache[_normalize(url)];

String _normalize(String url) => url.replaceFirst('http://', 'https://');

Future<CoverArt> loadCoverArt(String url) {
  url = _normalize(url);
  final cached = _artCache.remove(url);
  if (cached != null) return SynchronousFuture(_artCache[url] = cached);
  return _artLoading[url] ??= _build(url).whenComplete(() => _artLoading.remove(url));
}

Future<CoverArt> _build(String url) async {
  final src = await _loadSmall(NetworkImage(url));
  try {
    final data = await src.toByteData(format: ui.ImageByteFormat.rawRgba);
    final palette = data == null ? fallbackPalette : _pick(data);
    final rec = ui.PictureRecorder();
    Canvas(rec).drawImageRect(
      src,
      Rect.fromLTWH(0, 0, src.width.toDouble(), src.height.toDouble()),
      const Rect.fromLTWH(0, 0, _artSize + 0.0, _artSize + 0.0),
      Paint()
        ..filterQuality = FilterQuality.high
        ..imageFilter = ui.ImageFilter.blur(sigmaX: 26, sigmaY: 26, tileMode: TileMode.mirror),
    );
    final blurred = await rec.endRecording().toImage(_artSize, _artSize);
    final art = CoverArt(palette, blurred);
    _artCache[url] = art;
    // 只留最近 12 张；被挤掉的图可能还在画，交给 GC 回收，不手动 dispose
    while (_artCache.length > 12) {
      _artCache.remove(_artCache.keys.first);
    }
    return art;
  } finally {
    src.dispose();
  }
}

Future<ui.Image> _loadSmall(ImageProvider provider) {
  final completer = Completer<ui.Image>();
  final stream = ResizeImage(provider, width: _srcSize, height: _srcSize).resolve(ImageConfiguration.empty);
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

/// 按色相分 12 个桶，饱和度高、像素多的桶优先，取前 4 个。
/// 亮度压到中低区间，保证上面的白字看得清。
List<Color> _pick(ByteData data) {
  final sums = List.generate(13, (_) => [0.0, 0.0, 0.0, 0.0, 0.0]); // r g b count score
  // 隔一个像素采样就够了
  for (var i = 0; i + 3 < data.lengthInBytes; i += 8) {
    if (data.getUint8(i + 3) < 128) continue;
    final c = Color.fromARGB(255, data.getUint8(i), data.getUint8(i + 1), data.getUint8(i + 2));
    final hsv = HSVColor.fromColor(c);
    // 灰色单独放最后一个桶
    final bucket = hsv.saturation < 0.15 || hsv.value < 0.12 ? 12 : (hsv.hue / 30).floor() % 12;
    final s = sums[bucket];
    s[0] += c.r;
    s[1] += c.g;
    s[2] += c.b;
    s[3] += 1;
    s[4] += 0.25 + hsv.saturation * hsv.value;
  }
  final ranked = [for (var b = 0; b < 13; b++) if (sums[b][3] > 0) b]
    ..sort((a, b) => sums[b][4].compareTo(sums[a][4]));
  final colors = [
    for (final b in ranked.take(4))
      Color.from(alpha: 1, red: sums[b][0] / sums[b][3], green: sums[b][1] / sums[b][3], blue: sums[b][2] / sums[b][3]),
  ];
  if (colors.isEmpty) return fallbackPalette;
  // 颜色不够时用主色的深浅变体补齐
  while (colors.length < 4) {
    final hsl = HSLColor.fromColor(colors.first);
    colors.add(hsl.withLightness((hsl.lightness + 0.18 * colors.length) % 0.7).toColor());
  }
  return [
    for (final c in colors)
      () {
        final hsl = HSLColor.fromColor(c);
        return hsl
            .withLightness(hsl.lightness.clamp(0.22, 0.55))
            .withSaturation(min(1, hsl.saturation * 1.25))
            .toColor();
      }(),
  ];
}

/// Apple Music 式的流动背景：模糊封面两层反向缓慢旋转，再叠几团漂移的主色光斑。
/// 全部在一个 CustomPainter 里画，30fps 刷新；暂停播放时停止流动。
class PlayerBackground extends StatefulWidget {
  const PlayerBackground({super.key, required this.art, required this.animate});

  final CoverArt? art;
  final bool animate;

  @override
  State<PlayerBackground> createState() => _PlayerBackgroundState();
}

class _PlayerBackgroundState extends State<PlayerBackground> with TickerProviderStateMixin {
  /// 流动相位 0–1，一圈 60 秒。
  final _phase = ValueNotifier<double>(0);
  late final Ticker _ticker = createTicker(_onTick);
  Duration _last = Duration.zero;

  late final AnimationController _fade = AnimationController(vsync: this, duration: const Duration(milliseconds: 1400))
    ..value = 1;
  late CoverArt? _from = widget.art;
  late CoverArt? _to = widget.art;

  @override
  void initState() {
    super.initState();
    if (widget.animate) _ticker.start();
  }

  void _onTick(Duration elapsed) {
    final dt = elapsed - _last;
    if (dt < const Duration(milliseconds: 33)) return;
    _last = elapsed;
    _phase.value = (_phase.value + dt.inMicroseconds / 60e6) % 1;
  }

  @override
  void didUpdateWidget(PlayerBackground old) {
    super.didUpdateWidget(old);
    if (!identical(old.art, widget.art)) {
      _from = _fade.value < 0.5 ? _from : _to;
      _to = widget.art;
      _fade.forward(from: 0);
    }
    if (widget.animate && !_ticker.isActive) {
      _last = Duration.zero;
      _ticker.start();
    } else if (!widget.animate && _ticker.isActive) {
      _ticker.stop();
    }
  }

  @override
  void dispose() {
    _ticker.dispose();
    _fade.dispose();
    _phase.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: CustomPaint(
        size: Size.infinite,
        painter: _BackgroundPainter(this),
        // 每帧都变，告诉引擎别尝试光栅缓存
        willChange: true,
      ),
    );
  }
}

/// 性能测试用：按位开关背景各层（1 封面、2 光斑、4 压暗）。
@visibleForTesting
var debugBackgroundParts = 7;

class _BackgroundPainter extends CustomPainter {
  _BackgroundPainter(this.s) : super(repaint: Listenable.merge([s._phase, s._fade]));

  final _PlayerBackgroundState s;

  // 放大绘制用双三次插值，比双线性平滑得多，不会出现网格状颗粒
  static final _imagePaint = Paint()..filterQuality = FilterQuality.high;

  /// 压暗层只依赖高度，窗口大小不变就复用同一个渐变。
  static Paint? _scrim;
  static double _scrimHeight = -1;

  @override
  void paint(Canvas canvas, Size size) {
    final t = Curves.easeInOut.transform(s._fade.value);
    final from = s._from?.palette ?? fallbackPalette;
    final to = s._to?.palette ?? fallbackPalette;
    final a = s._phase.value * 2 * pi;
    final full = Offset.zero & size;

    final base = HSLColor.fromColor(Color.lerp(from.first, to.first, t)!);
    canvas.drawRect(full, Paint()..color = base.withLightness(base.lightness * 0.45).toColor());

    // 封面：旧图淡出、新图淡入
    if (debugBackgroundParts & 1 != 0) {
      if (t < 1 && s._from != null) _cover(canvas, size, s._from!.blurred, a, 1 - t);
      if (s._to != null) _cover(canvas, size, s._to!.blurred, a, t);
    }

    // 主色光斑沿不同频率的李萨如曲线漂移，同样旧的淡出、新的淡入
    if (debugBackgroundParts & 2 != 0) {
      if (t < 1) _blobs(canvas, size, s._from?.blobs ?? _fallbackBlobs, a, 1 - t);
      _blobs(canvas, size, s._to?.blobs ?? _fallbackBlobs, a, t);
    }

    // 压暗一层，保证白字可读
    if (debugBackgroundParts & 4 == 0) return;
    if (_scrimHeight != size.height) {
      _scrimHeight = size.height;
      _scrim = Paint()
        ..shader = ui.Gradient.linear(
          Offset.zero,
          Offset(0, size.height),
          const [Color(0x33000000), Color(0x22000000), Color(0x77000000)],
          const [0, 0.5, 1],
        );
    }
    canvas.drawRect(full, _scrim!);
  }

  void _blobs(Canvas canvas, Size size, List<ui.Image> blobs, double a, double opacity) {
    if (opacity <= 0.01) return;
    final r = max(size.width, size.height) * 0.7;
    final centers = [
      Offset(0.25 + 0.2 * sin(a * 3), 0.2 + 0.15 * cos(a * 2)),
      Offset(0.8 + 0.15 * cos(a * 2), 0.35 + 0.2 * sin(a * 3)),
      Offset(0.3 + 0.2 * cos(a * 4), 0.85 + 0.1 * sin(a * 2)),
      Offset(0.7 + 0.2 * sin(a * 2), 0.7 + 0.2 * cos(a * 5)),
    ];
    const src = Rect.fromLTWH(0, 0, _blobSize + 0.0, _blobSize + 0.0);
    _imagePaint.color = Color.fromRGBO(0, 0, 0, opacity);
    for (var i = 0; i < 4; i++) {
      final c = Offset(centers[i].dx * size.width, centers[i].dy * size.height);
      canvas.drawImageRect(blobs[i], src, Rect.fromCircle(center: c, radius: r), _imagePaint);
    }
  }

  /// 两层反向旋转的模糊封面。
  void _cover(Canvas canvas, Size size, ui.Image img, double a, double opacity) {
    if (opacity <= 0.01) return;
    final side = max(size.width, size.height) * 1.6;
    final src = Rect.fromLTWH(0, 0, img.width.toDouble(), img.height.toDouble());
    final dst = Rect.fromCenter(center: Offset.zero, width: side, height: side);
    for (final (speed, dx, dy, alpha) in [(1.0, 0.15, 0.1, 0.9), (-2.0, 0.2, 0.15, 0.5)]) {
      canvas
        ..save()
        ..translate(size.width / 2 + cos(a * speed) * size.width * dx, size.height / 2 + sin(a * speed) * size.height * dy)
        ..rotate(a * speed);
      _imagePaint.color = Color.fromRGBO(0, 0, 0, alpha * opacity);
      canvas
        ..drawImageRect(img, src, dst, _imagePaint)
        ..restore();
    }
  }

  @override
  bool shouldRepaint(_BackgroundPainter old) => old.s != s;
}
