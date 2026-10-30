import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanade/ui/smooth_scroll.dart';

void main() {
  late SmoothScrollController controller;

  Future<void> pump(WidgetTester tester) async {
    controller = SmoothScrollController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: ListView.builder(
          controller: controller,
          itemExtent: 50,
          itemCount: 100,
          itemBuilder: (_, i) => Text('$i'),
        ),
      ),
    );
  }

  Future<void> wheel(WidgetTester tester, double dy) async {
    final pointer = TestPointer(1, PointerDeviceKind.mouse);
    await tester.sendEventToBinding(pointer.hover(tester.getCenter(find.byType(ListView))));
    await tester.sendEventToBinding(pointer.scroll(Offset(0, dy)));
  }

  testWidgets('Windows 上滚轮是动画滑过去的，连滚会累加', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    await pump(tester);

    await wheel(tester, 100);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    final mid = controller.offset;
    expect(mid, greaterThan(0));
    expect(mid, lessThan(100));

    // 动画还没播完又滚一格，目标是 200 而不是 mid + 100
    await wheel(tester, 100);
    await tester.pumpAndSettle();
    expect(controller.offset, 200);

    // 往回滚到顶会停在 0
    await wheel(tester, -1000);
    await tester.pumpAndSettle();
    expect(controller.offset, 0);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('其他平台照旧直接跳', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    await pump(tester);
    await wheel(tester, 100);
    await tester.pump();
    expect(controller.offset, 100);
    debugDefaultTargetPlatformOverride = null;
  });
}
