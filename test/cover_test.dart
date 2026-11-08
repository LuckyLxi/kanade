import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanade/ui/widgets.dart';

ui.Image _solidImage(Color color) {
  final recorder = ui.PictureRecorder();
  ui.Canvas(recorder).drawColor(color, BlendMode.src);
  final picture = recorder.endRecording();
  final image = picture.toImageSync(4, 4);
  picture.dispose();
  return image;
}

Future<int?> _centerPixel(WidgetTester tester, GlobalKey coverKey) {
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(coverKey),
  );
  return tester.runAsync(() async {
    final image = await boundary.toImage();
    try {
      final bytes = (await image.toByteData())!;
      return bytes.getUint32((16 * image.width + 16) * 4);
    } finally {
      image.dispose();
    }
  });
}

void main() {
  testWidgets(
    'keeps the cached thumbnail visible as the large cover fades in',
    (tester) async {
      const thumbnail = NetworkImage('https://example.com/300x300.jpg');
      const largeCover = NetworkImage('https://example.com/500x500.jpg');
      final largeImage = Completer<ImageInfo>();
      final cache = PaintingBinding.instance.imageCache;
      cache.putIfAbsent(
        thumbnail,
        () => OneFrameImageStreamCompleter(
          SynchronousFuture(
            ImageInfo(image: _solidImage(const Color(0xFFFF0000))),
          ),
        ),
      );
      cache.putIfAbsent(
        largeCover,
        () => OneFrameImageStreamCompleter(largeImage.future),
      );
      addTearDown(() {
        cache.evict(thumbnail);
        cache.evict(largeCover);
      });

      final coverKey = GlobalKey();
      await tester.pumpWidget(
        MaterialApp(
          home: Center(
            child: RepaintBoundary(
              key: coverKey,
              child: Cover(
                largeCover.url,
                placeholderUrl: thumbnail.url,
                size: 32,
              ),
            ),
          ),
        ),
      );

      expect(await _centerPixel(tester, coverKey), 0xFF0000FF);

      largeImage.complete(
        ImageInfo(image: _solidImage(const Color(0xFF00FF00))),
      );
      await tester.pump();
      expect(await _centerPixel(tester, coverKey), 0xFF0000FF);

      await tester.pump(const Duration(milliseconds: 140));
      final blended = (await _centerPixel(tester, coverKey))!;
      expect(blended >> 24, greaterThan(0));
      expect((blended >> 16) & 0xFF, greaterThan(0));
      expect(blended & 0xFF, 0xFF);

      await tester.pump(const Duration(milliseconds: 140));
      expect(await _centerPixel(tester, coverKey), 0x00FF00FF);
    },
  );

  testWidgets('keeps the displayed cover through a delayed song change', (
    tester,
  ) async {
    const previous = NetworkImage('https://example.com/previous.jpg');
    const next = NetworkImage('https://example.com/next.jpg');
    final nextImage = Completer<ImageInfo>();
    final cache = PaintingBinding.instance.imageCache;
    cache.putIfAbsent(
      previous,
      () => OneFrameImageStreamCompleter(
        SynchronousFuture(
          ImageInfo(image: _solidImage(const Color(0xFFFF0000))),
        ),
      ),
    );
    cache.putIfAbsent(
      next,
      () => OneFrameImageStreamCompleter(nextImage.future),
    );
    addTearDown(() {
      cache.evict(previous);
      cache.evict(next);
    });

    final coverKey = GlobalKey();
    Future<void> show(String url) => tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: RepaintBoundary(
            key: coverKey,
            child: Cover(url, size: 32, keepPrevious: true),
          ),
        ),
      ),
    );

    await show(previous.url);
    expect(await _centerPixel(tester, coverKey), 0xFF0000FF);
    final previousImage = find.byKey(ValueKey(previous.url));
    final displayed = tester.element(previousImage);
    cache.evict(previous, includeLive: false);

    await show(next.url);
    await tester.pump(const Duration(seconds: 1));
    expect(tester.element(previousImage), same(displayed));
    expect(await _centerPixel(tester, coverKey), 0xFF0000FF);

    nextImage.complete(ImageInfo(image: _solidImage(const Color(0xFF00FF00))));
    await tester.pump();
    await tester.pump();
    expect(await _centerPixel(tester, coverKey), 0xFF0000FF);
    await tester.pump(const Duration(milliseconds: 140));
    final blended = (await _centerPixel(tester, coverKey))!;
    expect(blended >> 24, greaterThan(0));
    expect((blended >> 16) & 0xFF, greaterThan(0));
    expect(blended & 0xFF, 0xFF);

    await tester.pumpAndSettle();
    expect(previousImage, findsNothing);
    expect(await _centerPixel(tester, coverKey), 0x00FF00FF);
  });
}
