import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

/// Shares a content texture between glass surfaces on renderers without shader
/// image filters. Keep the surfaces outside [GlassBackdropSource].
class GlassBackdropScope extends StatefulWidget {
  /// Creates a scope for a background source and its floating controls.
  const GlassBackdropScope({required this.child, this.blurSigma = 0, super.key});

  /// The content and the controls which sample it.
  final Widget child;

  /// Gaussian blur, in logical pixels, applied once to each capture. Matches
  /// the backdrop blur of the shader-filter renderer; surfaces sampling a
  /// pre-blurred texture skip their own approximate blur.
  final double blurSigma;

  /// The nearest shared backdrop, if any.
  static GlassBackdropData? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_BackdropTheme>()?.data;

  @override
  State<GlassBackdropScope> createState() => _GlassBackdropScopeState();
}

class _GlassBackdropScopeState extends State<GlassBackdropScope> {
  late final GlassBackdropData _data = GlassBackdropData()
    ..blurSigma = widget.blurSigma;

  @override
  void didUpdateWidget(GlassBackdropScope oldWidget) {
    super.didUpdateWidget(oldWidget);
    _data.blurSigma = widget.blurSigma;
  }

  @override
  void dispose() {
    _data.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      _BackdropTheme(data: _data, child: widget.child);
}

class _BackdropTheme extends InheritedTheme {
  const _BackdropTheme({required this.data, required super.child});

  final GlassBackdropData data;

  @override
  bool updateShouldNotify(_BackdropTheme oldWidget) => data != oldWidget.data;

  @override
  Widget wrap(BuildContext context, Widget child) =>
      _BackdropTheme(data: data, child: child);
}

/// Marks content behind the glass, excluding the glass itself from the capture.
class GlassBackdropSource extends StatelessWidget {
  /// Creates a repaint-driven backdrop source. No continuous ticker is used.
  const GlassBackdropSource({required this.child, this.captureBounds, super.key});

  /// Scrolling or animated content behind the floating controls.
  final Widget child;

  /// Optional sampling region in source-local logical pixels. Include the
  /// surfaces' refraction and blur margins. Resolution is unchanged.
  final Rect Function(Size size)? captureBounds;

  @override
  Widget build(BuildContext context) {
    final data = GlassBackdropScope.maybeOf(context);
    if (data == null) return child;
    return _BackdropBoundary(
      data: data,
      pixelRatio: View.of(context).devicePixelRatio,
      captureBounds: captureBounds,
      child: child,
    );
  }
}

/// Shared GPU texture. Changes repaint consumers without rebuilding their child.
class GlassBackdropData extends ChangeNotifier {
  /// Creates an initially empty backdrop.
  GlassBackdropData();

  _RenderBackdropBoundary? _source;
  ui.Image? _image;
  Rect _imageBounds = Rect.zero;
  bool _pending = false;
  bool _capturing = false;
  bool _dirty = false;
  bool _disposed = false;

  /// Blur applied to captures, in logical pixels.
  double blurSigma = 0;

  /// Latest content image, at the source's device pixel ratio.
  ui.Image? get image => _image;

  /// Source-local logical bounds represented by [image].
  Rect get imageBounds => _imageBounds;

  /// Source used to map controls into the captured content's local coordinates.
  RenderBox? get source => _source;

  @override
  void addListener(VoidCallback listener) {
    super.addListener(listener);
    _scheduleCapture();
  }

  @override
  void removeListener(VoidCallback listener) {
    super.removeListener(listener);
    if (!hasListeners) {
      _image?.dispose();
      _image = null;
    }
  }

  void _scheduleCapture() {
    if (_disposed || !hasListeners) return;
    _dirty = true;
    if (_pending || _capturing) return;
    _pending = true;
    SchedulerBinding.instance.addPostFrameCallback((_) async {
      _pending = false;
      final source = _source;
      if (_disposed || !hasListeners || source == null || !source.canCapture) {
        return;
      }
      _dirty = false;
      _capturing = true;
      final pixelRatio = source.pixelRatio;
      final sigma = blurSigma * pixelRatio;
      final bounds = source.captureRect;
      if (bounds.isEmpty) {
        _capturing = false;
        return;
      }
      ui.Image? next;
      try {
        // Wait for rasterization, not just submission of GPU work. Synchronous
        // captures let scrolling queue full-resolution textures faster than
        // the raster thread can consume them, especially in fullscreen.
        next = await source.capture(bounds, pixelRatio);
        if (_disposed || !hasListeners || _source != source) return;
        if (sigma > 0) {
          final unblurred = next;
          next = null;
          next = await _blur(unblurred, sigma);
        }
        if (_disposed || !hasListeners || _source != source) return;
        final previous = _image;
        _image = next;
        _imageBounds = bounds;
        next = null;
        notifyListeners();
        previous?.dispose();
      } catch (error) {
        // The live backdrop path remains usable if the GPU cannot allocate a
        // capture (for example, while its window surface is being recreated).
        if (!_disposed) {
          _image?.dispose();
          _image = null;
          notifyListeners();
        }
        debugPrint('[GlassBackdrop] Capture failed: $error');
      } finally {
        next?.dispose();
        _capturing = false;
        // Coalesce changes received while awaiting the GPU into one capture.
        if (_dirty && !_disposed && hasListeners) _scheduleCapture();
      }
    });
    SchedulerBinding.instance.ensureVisualUpdate();
  }

  static Future<ui.Image> _blur(ui.Image image, double sigma) async {
    final recorder = ui.PictureRecorder();
    ui.Canvas(recorder).drawImage(
      image,
      Offset.zero,
      ui.Paint()
        ..imageFilter = ui.ImageFilter.blur(
            sigmaX: sigma, sigmaY: sigma, tileMode: ui.TileMode.clamp),
    );
    final picture = recorder.endRecording();
    try {
      return await picture.toImage(image.width, image.height);
    } finally {
      picture.dispose();
      image.dispose();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _source = null;
    _image?.dispose();
    _image = null;
    super.dispose();
  }
}

class _BackdropBoundary extends SingleChildRenderObjectWidget {
  const _BackdropBoundary({
    required this.data,
    required this.pixelRatio,
    required this.captureBounds,
    required super.child,
  });

  final GlassBackdropData data;
  final double pixelRatio;
  final Rect Function(Size size)? captureBounds;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderBackdropBoundary(data, pixelRatio, captureBounds);

  @override
  void updateRenderObject(
      BuildContext context, _RenderBackdropBoundary object) {
    if (object.pixelRatio != pixelRatio) {
      object.pixelRatio = pixelRatio;
      object.markNeedsPaint();
    }
    if (object.captureBounds != captureBounds) {
      object.captureBounds = captureBounds;
      data._scheduleCapture();
    }
  }
}

class _RenderBackdropBoundary extends RenderRepaintBoundary {
  _RenderBackdropBoundary(this.data, this.pixelRatio, this.captureBounds) {
    data._source = this;
  }

  final GlassBackdropData data;
  double pixelRatio;
  Rect Function(Size size)? captureBounds;

  Rect get captureRect => (captureBounds?.call(size) ?? Offset.zero & size)
      .intersect(Offset.zero & size);

  Future<ui.Image> capture(Rect bounds, double ratio) =>
      (layer! as OffsetLayer).toImage(bounds, pixelRatio: ratio);

  bool get canCapture => attached && hasSize && !size.isEmpty && layer != null;

  @override
  OffsetLayer updateCompositedLayer({covariant _BackdropLayer? oldLayer}) =>
      oldLayer ?? _BackdropLayer(data._scheduleCapture);

  @override
  void dispose() {
    if (data._source == this) data._source = null;
    super.dispose();
  }
}

class _BackdropLayer extends OffsetLayer {
  _BackdropLayer(this.onContentChanged);

  final VoidCallback onContentChanged;
  int? _lastContentHash;

  @override
  void addToScene(ui.SceneBuilder builder) {
    super.addToScene(builder);
    // Glass transform trackers request composition even when they paint
    // nothing new. Only actual display lists, transforms or effects invalidate
    // the texture, including changes inside nested repaint boundaries.
    final contentHash = Object.hashAll(_contentProperties(this));
    if (_lastContentHash != contentHash) {
      _lastContentHash = contentHash;
      onContentChanged();
    }
  }

  Iterable<Object?> _contentProperties(Layer layer) sync* {
    yield layer;
    if (layer is PictureLayer) yield layer.picture;
    if (layer is OffsetLayer) yield layer.offset;
    if (layer is TransformLayer) {
      yield Object.hashAll(layer.transform?.storage ?? const <double>[]);
    }
    if (layer is OpacityLayer) yield layer.alpha;
    if (layer is ClipRectLayer) {
      yield layer.clipRect;
      yield layer.clipBehavior;
    }
    if (layer is ClipRRectLayer) {
      yield layer.clipRRect;
      yield layer.clipBehavior;
    }
    if (layer is ClipRSuperellipseLayer) {
      yield layer.clipRSuperellipse;
      yield layer.clipBehavior;
    }
    if (layer is ClipPathLayer) {
      yield layer.clipPath;
      yield layer.clipBehavior;
    }
    if (layer is ColorFilterLayer) yield layer.colorFilter;
    if (layer is ImageFilterLayer) yield layer.imageFilter;
    if (layer is BackdropFilterLayer) {
      yield layer.filter;
      yield layer.blendMode;
    }
    if (layer is ShaderMaskLayer) {
      yield layer.shader;
      yield layer.maskRect;
      yield layer.blendMode;
    }
    if (layer is ContainerLayer) {
      var child = layer.firstChild;
      while (child != null) {
        yield* _contentProperties(child);
        child = child.nextSibling;
      }
    }
  }
}
