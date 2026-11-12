import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import 'store.dart';

/// Local reminders for the signed-in user's own open tasks: H-3 and H-1 before the deadline,
/// plus one nudge after 48 hours without recorded activity; and for scheduled
/// meetings of the user's groups: H-1 and one hour before (Tahap 2 §5.1).
/// Device-only, no server push. (The SwiftUI client still does H-1 only.)
/// [id] is the task or meeting ID.
typedef Reminder = ({String id, String heading, String title, DateTime fireAt});

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
    final idleSince = store.lastActivity(t);
    for (final (heading, fireAt) in [
      ('Deadline 3 hari lagi', due.subtract(const Duration(days: 3))),
      ('Deadline besok', due.subtract(const Duration(days: 1))),
      if (idleSince != null)
        (
          'Belum ada kabar 2 hari',
          idleSince.add(const Duration(hours: idleNudgeHours)),
        ),
    ]) {
      if (fireAt.isAfter(now)) {
        plan.add((
          id: t.text('id'),
          heading: heading,
          title: t.text('title'),
          fireAt: fireAt,
        ));
      }
    }
  }
  for (final m in store.meetings) {
    final start = m.date('startsAt');
    if (start == null ||
        m.text('status') != 'scheduled' ||
        store
                .group(m.text('groupID'))
                ?.ids('memberIDs')
                .contains(store.currentUserID) !=
            true) {
      continue;
    }
    for (final (heading, fireAt) in [
      ('Rapat besok', start.subtract(const Duration(days: 1))),
      ('Rapat 1 jam lagi', start.subtract(const Duration(hours: 1))),
    ]) {
      if (fireAt.isAfter(now)) {
        plan.add((
          id: m.text('id'),
          heading: heading,
          title: m.text('title'),
          fireAt: fireAt,
        ));
      }
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
    final key = plan
        .map((r) => '${r.id}|${r.heading}|${r.title}|${r.fireAt}')
        .join(',');
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
        id: '${r.heading}|${r.id}'.hashCode & 0x7fffffff,
        title: r.heading,
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
