import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanade/ui/player_background.dart';

void main() {
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
      await tester.pumpWidget(const SizedBox.shrink());
      expect(tester.takeException(), isNull);
    },
  );
}
