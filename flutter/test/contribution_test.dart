import 'package:flutter_test/flutter_test.dart';
import 'package:grouply/core/contribution.dart';

void main() {
  final now = DateTime.utc(2026, 11, 14, 12);
  Map<String, dynamic> task(String who, String status, {int dueInDays = 3}) => {
    'assigneeID': who,
    'status': status,
    'dueAt': now.add(Duration(days: dueInDays)).toIso8601String(),
  };

  test('shares come from approved tasks only and add up to 100', () {
    final rows = contributions(
      [
        task('a', 'done'),
        task('a', 'done'),
        task('b', 'done'),
        task('c', 'in_review'),
        task('c', 'in_progress', dueInDays: -1),
      ],
      ['a', 'b', 'c'],
      now,
    );
    expect(
      [for (final r in rows) (r.id, r.percent)],
      [('a', 67), ('b', 33), ('c', 0)],
    );
    final c = rows.last;
    expect((c.done, c.review, c.active, c.late), (0, 1, 1, 1));
  });

  test('thirds still sum to 100; nothing approved means 0 for everyone', () {
    final thirds = contributions(
      [task('a', 'done'), task('b', 'done'), task('c', 'done')],
      ['a', 'b', 'c'],
      now,
    );
    expect(thirds.fold(0, (sum, r) => sum + r.percent), 100);
    final none = contributions([task('a', 'todo')], ['a', 'b'], now);
    expect(none.every((r) => r.percent == 0), isTrue);
    expect(none.length, 2);
  });

  test('someone who left keeps the share of the work they finished', () {
    final rows = contributions(
      [task('gone', 'done'), task('a', 'done')],
      ['a'],
      now,
    );
    expect({for (final r in rows) r.id: r.percent}, {'a': 50, 'gone': 50});
  });
}
