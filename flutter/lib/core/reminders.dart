import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import 'store.dart';

/// Local H-1 deadline reminders for the signed-in user's own open tasks.
/// Mirrors `Grouply/Core/DeadlineReminders.swift`; device-only, no server push.
typedef Reminder = ({String taskID, String title, DateTime fireAt});

List<Reminder> reminderPlan(GrouplyStore store, DateTime now) {
  final plan = <Reminder>[];
  for (final t in store.tasks) {
    final project = store.project(t.text('projectID'));
    final group = store.group(project?.text('groupID') ?? '');
    final due = t.date('dueAt');
    if (due == null ||
        t.text('assigneeID') != store.currentUserID ||
        !['todo', 'in_progress', 'needs_revision'].contains(t.text('status')) ||
        project?.text('status') != 'active' ||
        group?.ids('memberIDs').contains(store.currentUserID) != true) {
      continue;
    }
    final fireAt = due.subtract(const Duration(days: 1));
    if (fireAt.isAfter(now)) {
      plan.add((taskID: t.text('id'), title: t.text('title'), fireAt: fireAt));
    }
  }
  plan.sort((a, b) => a.fireAt.compareTo(b.fireAt));
  return plan;
}

class DeadlineReminders {
  final _plugin = FlutterLocalNotificationsPlugin();
  Future<void> _work = Future.value();
  bool _ready = false;
  String _lastKey = '';

  /// Replaces every scheduled reminder with [plan]; an empty plan (logout) clears them.
  /// Calls run one after another so an older plan never lands after a newer one.
  void sync(List<Reminder> plan) {
    final key = plan.map((r) => '${r.taskID}|${r.title}|${r.fireAt}').join(',');
    if (key == _lastKey) return;
    _lastKey = key;
    _work = _work.then((_) => _apply(plan)).catchError((Object _) {});
  }

  Future<void> _apply(List<Reminder> plan) async {
    if (!_ready) {
      await _init();
      _ready = true;
    }
    await _plugin.cancelAll();
    if (plan.isEmpty) return;
    final granted =
        await _plugin
            .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin
            >()
            ?.requestNotificationsPermission() ??
        await _plugin
            .resolvePlatformSpecificImplementation<
              IOSFlutterLocalNotificationsPlugin
            >()
            ?.requestPermissions(alert: true, sound: true);
    if (granted != true) return;
    const details = NotificationDetails(
      android: AndroidNotificationDetails(
        'deadline',
        'Pengingat deadline',
        importance: Importance.high,
      ),
      iOS: DarwinNotificationDetails(),
    );
    // ponytail: iOS keeps max 64 pending requests; nearest 60 only.
    for (final r in plan.take(60)) {
      await _plugin.zonedSchedule(
        id: r.taskID.hashCode & 0x7fffffff,
        title: 'Deadline besok',
        body: r.title,
        // Absolute instant in UTC, so the device time zone does not matter.
        scheduledDate: tz.TZDateTime.from(r.fireAt.toUtc(), tz.UTC),
        notificationDetails: details,
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      );
    }
  }

  Future<void> _init() async {
    tzdata.initializeTimeZones();
    await _plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        iOS: DarwinInitializationSettings(
          requestAlertPermission: false,
          requestBadgePermission: false,
          requestSoundPermission: false,
        ),
      ),
    );
  }
}
