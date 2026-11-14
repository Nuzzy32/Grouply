import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app.dart';
import 'core/reminders.dart';
import 'core/store.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // The bundled Noto Sans (LPJ PDF) is OFL: ship its license notice.
  LicenseRegistry.addLicense(() async* {
    yield LicenseEntryWithLineBreaks([
      'Noto Sans',
    ], await rootBundle.loadString('assets/fonts/OFL.txt'));
  });
  final store = GrouplyStore();
  final reminders = DeadlineReminders();
  store.addListener(() => reminders.sync(reminderPlan(store, DateTime.now())));
  runApp(GrouplyApp(store: store));
  await store.initialize();
}
