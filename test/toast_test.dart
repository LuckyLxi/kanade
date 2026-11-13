import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanade/ui/overlay_layout_state.dart';
import 'package:kanade/ui/toast.dart';

void main() {
  testWidgets('toast follows layout changes and replaces the old message', (
    tester,
  ) async {
    final layout = OverlayLayoutState.instance;
    layout.chrome.value = EdgeInsets.zero;
    layout.playerVisible.value = false;
    late BuildContext context;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (value) {
            context = value;
            return const Scaffold();
          },
        ),
      ),
    );
    showToast(context, 'first');
    await tester.pumpAndSettle();
    final initial = tester.getCenter(find.text('first'));
    layout.chrome.value = const EdgeInsets.only(bottom: 100);
    await tester.pumpAndSettle();
    expect(tester.getCenter(find.text('first')).dy, initial.dy - 100);
    layout.playerVisible.value = true;
    await tester.pumpAndSettle();
    expect(tester.getCenter(find.text('first')).dy, lessThan(100));
    layout.playerVisible.value = false;
    await tester.pumpAndSettle();
    expect(tester.getCenter(find.text('first')).dy, initial.dy - 100);
    showToast(context, 'second');
    await tester.pumpAndSettle();
    expect(find.text('first'), findsNothing);
    expect(find.text('second'), findsOneWidget);
    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();
    expect(find.text('second'), findsNothing);
    layout.chrome.value = EdgeInsets.zero;
    layout.playerVisible.value = false;
  });
}
