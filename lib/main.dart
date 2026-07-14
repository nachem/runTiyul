import 'package:flutter/material.dart';

import 'app/app.dart';
import 'app/app_store.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final store = await AppStore.create();
  runApp(TrailRunnerApp(store: store));
}
