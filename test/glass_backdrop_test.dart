import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';

void main() {
  testWidgets('capture only the sampling region at the device pixel ratio', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.resetDevicePixelRatio);
    late BuildContext scopeContext;
    void onCapture() {}
    const bounds = Rect.fromLTWH(8, 12, 16, 20);
    await tester.pumpWidget(
      GlassBackdropScope(
        child: Builder(
          builder: (context) {
            scopeContext = context;
            GlassBackdropScope.maybeOf(context)!.addListener(onCapture);
            return Center(
              child: SizedBox.square(
                dimension: 64,
                child: GlassBackdropSource(
                  captureBounds: (_) => bounds,
                  child: ColoredBox(
                    color: const Color(0xFFFF0000),
                    child: Stack(
                      alignment: Alignment.topLeft,
                      children: [
                        Positioned.fromRect(
                          rect: bounds,
                          child: const ColoredBox(color: Color(0xFF00FF00)),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
    final backdrop = GlassBackdropScope.maybeOf(scopeContext)!;
    expect(backdrop.imageBounds, bounds);
    expect(backdrop.image!.width, 32);
    expect(backdrop.image!.height, 40);
    final pixels = await tester.runAsync(
      () => backdrop.image!.toByteData(format: ui.ImageByteFormat.rawRgba),
    );
    expect(pixels!.getUint8(0), 0);
    expect(pixels.getUint8(1), 255);
    expect(pixels.getUint8(2), 0);
    backdrop.removeListener(onCapture);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  for (final blur in [0.0, 2.0]) {
    testWidgets(
      'backdrop updates nested content without idle captures (blur $blur)',
      (tester) async {
        final color = ValueNotifier(const Color(0xFFFF0000));
        addTearDown(color.dispose);
        late BuildContext scopeContext;
        var captures = 0;
        void onCapture() => captures++;

        await tester.pumpWidget(
          GlassBackdropScope(
            blurSigma: blur,
            child: Builder(
              builder: (context) {
                scopeContext = context;
                GlassBackdropScope.maybeOf(context)!.addListener(onCapture);
                return Center(
                  child: SizedBox.square(
                    dimension: 32,
                    child: GlassBackdropSource(
                      child: RepaintBoundary(
                        child: ValueListenableBuilder(
                          valueListenable: color,
                          builder: (_, value, _) => ColoredBox(color: value),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        );
        final backdrop = GlassBackdropScope.maybeOf(scopeContext)!;

        for (var i = 0; i < 8; i++) {
          color.value = i.isEven
              ? const Color(0xFF00FF00)
              : const Color(0xFF0000FF);
          await tester.pump();
        }
        expect(captures, 9);

        final pixels = await tester.runAsync(
          () => backdrop.image!.toByteData(format: ui.ImageByteFormat.rawRgba),
        );
        final center = (16 * backdrop.image!.width + 16) * 4;
        expect(pixels!.getUint8(center), 0);
        expect(pixels.getUint8(center + 1), 0);
        expect(pixels.getUint8(center + 2), 255);

        await tester.pump();
        await tester.pump();
        expect(
          captures,
          9,
          reason: 'unchanged content must not capture continuously',
        );
        backdrop.removeListener(onCapture);
        expect(backdrop.image, isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }

  testWidgets('release the capture when the scope is disposed', (tester) async {
    late BuildContext scopeContext;
    var captures = 0;
    await tester.pumpWidget(
      GlassBackdropScope(
        blurSigma: 2,
        child: Builder(
          builder: (context) {
            scopeContext = context;
            GlassBackdropScope.maybeOf(context)!.addListener(() => captures++);
            return const SizedBox.square(
              dimension: 32,
              child: GlassBackdropSource(
                child: ColoredBox(color: Color(0xFFFF0000)),
              ),
            );
          },
        ),
      ),
    );
    final backdrop = GlassBackdropScope.maybeOf(scopeContext)!;
    await tester.pumpWidget(const SizedBox.shrink());
    expect(backdrop.image, isNull);
    expect(captures, 1);
    expect(tester.takeException(), isNull);
  });
}
