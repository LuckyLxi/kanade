import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:kanade/src/rust/api/music.dart' as api;
import 'package:kanade/src/rust/frb_generated.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async => await RustLib.init());
  test('Rust 层能拿到榜单', () async {
    final groups = await api.getToplists();
    expect(groups, isNotEmpty);
  });
}
