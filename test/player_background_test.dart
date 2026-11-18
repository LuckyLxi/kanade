import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanade/ui/player_background.dart';

void main() {
  testWidgets(
    'paused background keeps the same pixels when moved and returned',
    (tester) async {
      tester.view.physicalSize = const Size(96, 96);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final motion = ValueNotifier(Offset.zero);
      addTearDown(motion.dispose);
      final key = GlobalKey();
      await tester.runAsync(warmUpPlayerBackground);
      await tester.pumpWidget(
        RepaintBoundary(
          key: key,
          child: ValueListenableBuilder(
            valueListenable: motion,
            builder: (_, offset, child) =>
                Transform.translate(offset: offset, child: child),
            child: const PlayerBackground(art: null, animate: false),
          ),
        ),
      );
      await tester.pumpAndSettle();
      Future<Uint8List> pixels() async {
        final boundary =
            key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
        final image = await boundary.toImage();
        try {
          final data = await image.toByteData(
            format: ui.ImageByteFormat.rawRgba,
          );
          return Uint8List.fromList(data!.buffer.asUint8List());
        } finally {
          image.dispose();
        }
      }

      final initial = (await tester.runAsync(pixels))!;
      expect(
        initial.sublist(0, 3),
        isNot(orderedEquals(initial.sublist(96 * 48 * 4, 96 * 48 * 4 + 3))),
        reason: 'warm-up must make the shader available on the first frame',
      );
      motion.value = const Offset(0, 12);
      await tester.pumpAndSettle();
      final moved = (await tester.runAsync(pixels))!;
      for (var channel = 0; channel < 4; channel++) {
        expect(
          moved[(32 * 96 + 30) * 4 + channel],
          closeTo(initial[(20 * 96 + 30) * 4 + channel], 1),
        );
      }
      motion.value = Offset.zero;
      await tester.pumpAndSettle();
      expect(await tester.runAsync(pixels), orderedEquals(initial));
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'background animates, settles when paused, and survives resizing',
    (tester) async {
      final key = GlobalKey();
      Future<void> show({
        required bool animate,
        Size size = const Size(80, 60),
      }) async {
        await tester.pumpWidget(
          Center(
            child: RepaintBoundary(
              key: key,
              child: SizedBox.fromSize(
                size: size,
                child: PlayerBackground(art: null, animate: animate),
              ),
            ),
          ),
        );
      }

      Future<Uint8List> pixels() async {
        final boundary =
            key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
        final image = await boundary.toImage();
        try {
          final data = await image.toByteData(
            format: ui.ImageByteFormat.rawRgba,
          );
          return Uint8List.fromList(data!.buffer.asUint8List());
        } finally {
          image.dispose();
        }
      }

      await show(animate: false);
      // Let FragmentProgram.fromAsset finish before checking the paused image.
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pumpAndSettle();
      final paused = await tester.runAsync(pixels);
      expect(
        paused!.sublist(0, 3),
        isNot(orderedEquals(paused.sublist(80 * 30 * 4, 80 * 30 * 4 + 3))),
        reason: 'the loaded shader must replace the flat loading color while paused',
      );
      await tester.pump(const Duration(seconds: 1));
      expect(await tester.runAsync(pixels), orderedEquals(paused));

      await show(animate: true);
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      await tester.pump();
      expect(await tester.runAsync(pixels), isNot(orderedEquals(paused)));

      await show(animate: false, size: const Size(96, 72));
      await tester.pumpAndSettle();
      final resized = await tester.runAsync(pixels);
      expect(resized, hasLength(96 * 72 * 4));
      expect(
        resized!.last,
        255,
        reason: 'the resized background fills the viewport',
      );
      expect(tester.binding.hasScheduledFrame, isFalse);
      await show(animate: false, size: Size.zero);
      await tester.pumpAndSettle();
      await tester.pumpWidget(const SizedBox.shrink());
      expect(tester.takeException(), isNull);
    },
  );

  Uint8List cover(int Function(int x, int y) value) {
    final px = Uint8List(128 * 128 * 4);
    for (var y = 0; y < 128; y++) {
      for (var x = 0; x < 128; x++) {
        final i = (y * 128 + x) * 4;
        px[i] = px[i + 1] = px[i + 2] = value(x, y);
        px[i + 3] = 255;
      }
    }
    return px;
  }

  test('cover blur keeps a flat cover flat within dither', () {
    final out = blurCoverPixels(cover((_, _) => 100), 128, 128);
    expect(out.length, 256 * 256 * 4);
    for (var i = 0; i < out.length; i += 4) {
      expect(out[i], inInclusiveRange(99, 101));
      expect(out[i + 3], 255);
    }
  });

  test('cover blur does not round horizontal stripes into constant rows', () {
    // 每行颜色一样、行间相差 1：模糊后大多数行落在两个整数之间
    final out = blurCoverPixels(cover((_, y) => 80 + y % 2), 128, 128);
    var constantRows = 0;
    for (var y = 0; y < 256; y++) {
      final row = {for (var x = 0; x < 256; x++) out[(y * 256 + x) * 4]};
      if (row.length == 1) constantRows++;
    }
    expect(constantRows, 0);
  });
}
