import 'package:flutter/widgets.dart';

import 'app.dart';
import 'ui/glass.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initApp();
  runApp(KanadeGlass.wrap(child: const AppProviders(child: KanadeApp())));
}
