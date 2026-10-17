import 'package:flutter/material.dart';

import 'app.dart';
import 'core/reminders.dart';
import 'core/store.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final store = GrouplyStore();
  final reminders = DeadlineReminders();
  store.addListener(() => reminders.sync(reminderPlan(store, DateTime.now())));
  runApp(GrouplyApp(store: store));
  await store.initialize();
}
