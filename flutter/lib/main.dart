import 'package:flutter/material.dart';

import 'app.dart';
import 'core/store.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final store = GrouplyStore();
  runApp(GrouplyApp(store: store));
  await store.initialize();
}
