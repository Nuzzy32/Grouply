import 'package:flutter_test/flutter_test.dart';
import 'package:grouply/core/reminders.dart';
import 'package:grouply/core/store.dart';

void main() {
  test('plan covers only my open tasks in active member projects', () {
    final now = DateTime.utc(2026, 10, 17);
    String due(double days) =>
        now.add(Duration(minutes: (days * 1440).round())).toIso8601String();
    JsonMap task(
      String id,
      String status, {
      String project = 'p1',
      String assignee = 'u1',
      double days = 3,
    }) => {
      'id': id,
      'projectID': project,
      'title': id,
      'assigneeID': assignee,
      'status': status,
      'dueAt': due(days),
    };
    final store = GrouplyStore()
      ..currentUserID = 'u1'
      ..groups = [
        {
          'id': 'g1',
          'memberIDs': ['u1'],
        },
        {
          'id': 'g2',
          'memberIDs': ['u2'],
        },
      ]
      ..projects = [
        {'id': 'p1', 'groupID': 'g1', 'status': 'active'},
        {'id': 'p2', 'groupID': 'g1', 'status': 'archived'},
        {'id': 'p3', 'groupID': 'g2', 'status': 'active'},
      ]
      ..tasks = [
        task('open', 'todo'),
        task('revise', 'needs_revision', days: 2),
        task('review', 'in_review'),
        task('done', 'done'),
        task('other', 'todo', assignee: 'u2'),
        task('archived', 'todo', project: 'p2'),
        task('left', 'todo', project: 'p3'),
        task('soon', 'in_progress', days: 0.5),
        task('later', 'todo', days: 4.5),
      ]
      ..messages = [
        // 47 hours idle: the nudge fires an hour from now.
        {
          'id': 'm1',
          'taskID': 'open',
          'createdAt': now
              .subtract(const Duration(hours: 47))
              .toIso8601String(),
        },
      ];
    final plan = reminderPlan(store, now);
    expect(plan.map((r) => '${r.heading}:${r.id}'), [
      'Belum ada kabar 2 hari:open',
      'Deadline besok:revise',
      'Deadline 3 hari lagi:later',
      'Deadline besok:open',
      'Deadline besok:later',
    ]);
    expect(plan[3].fireAt, now.add(const Duration(days: 2)));
  });

  test('scheduled meetings of my groups remind H-1 and one hour before', () {
    final now = DateTime.utc(2026, 11, 12, 8);
    JsonMap meeting(
      String id,
      Duration from, {
      String group = 'g1',
      String status = 'scheduled',
    }) => {
      'id': id,
      'groupID': group,
      'title': 'Rapat $id',
      'status': status,
      'startsAt': now.add(from).toIso8601String(),
    };
    final store = GrouplyStore()
      ..currentUserID = 'u1'
      ..groups = [
        {
          'id': 'g1',
          'memberIDs': ['u1'],
        },
        {
          'id': 'g2',
          'memberIDs': ['u2'],
        },
      ]
      ..meetings = [
        meeting('soon', const Duration(minutes: 90)),
        meeting('week', const Duration(days: 7)),
        meeting('past', const Duration(hours: -2)),
        meeting('off', const Duration(days: 2), status: 'cancelled'),
        meeting('done', const Duration(days: 2), status: 'done'),
        meeting('other', const Duration(days: 2), group: 'g2'),
      ];
    final plan = reminderPlan(store, now);
    expect(plan.map((r) => '${r.heading}:${r.id}'), [
      'Rapat 1 jam lagi:soon',
      'Rapat besok:week',
      'Rapat 1 jam lagi:week',
    ]);
    expect(plan.first.title, 'Rapat soon');
    expect(plan.first.fireAt, now.add(const Duration(minutes: 30)));
  });

  test(
    'idleHours uses the latest submission or thread message on open tasks',
    () {
      final now = DateTime.utc(2026, 10, 17);
      String ago(int h) => now.subtract(Duration(hours: h)).toIso8601String();
      final task = <String, dynamic>{
        'id': 't1',
        'status': 'in_progress',
        'submissions': [
          {'createdAt': ago(72)},
        ],
      };
      final store = GrouplyStore()
        ..messages = [
          {'id': 'm1', 'taskID': 't1', 'createdAt': ago(60)},
          {'id': 'm2', 'taskID': '', 'createdAt': ago(1)},
        ];
      expect(store.idleHours(task, now), 60);
      expect(store.idleHours({...task, 'status': 'in_review'}, now), isNull);
      expect(store.idleHours({'id': 't2', 'status': 'todo'}, now), isNull);
    },
  );
}
