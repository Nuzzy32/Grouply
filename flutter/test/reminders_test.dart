import 'package:flutter_test/flutter_test.dart';
import 'package:grouply/core/reminders.dart';
import 'package:grouply/core/store.dart';

void main() {
  test('H-1 plan covers only my open tasks in active member projects', () {
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
      ];
    final plan = reminderPlan(store, now);
    expect(plan.map((r) => r.taskID), ['revise', 'open']);
    expect(plan.last.fireAt, now.add(const Duration(days: 2)));
  });
}
