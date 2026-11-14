// Who did what in one project: each member's share of the approved tasks.
// Only `done` tasks count, every task weighs the same; lateness and revisions
// are shown next to the share, never subtracted from it.

typedef Contribution = ({
  String id,
  int done,
  int review,
  int active,
  int late,
  int percent,
});

/// One row per member (plus former assignees who finished tasks), sorted by
/// share. Percentages use largest remainders so they add up to exactly 100.
List<Contribution> contributions(
  List<Map<String, dynamic>> tasks,
  List<String> memberIDs,
  DateTime now,
) {
  String id(Map<String, dynamic> t) => '${t['assigneeID'] ?? ''}';
  String status(Map<String, dynamic> t) => '${t['status'] ?? ''}';
  final done = <String, int>{};
  for (final t in tasks.where((t) => status(t) == 'done')) {
    done.update(id(t), (n) => n + 1, ifAbsent: () => 1);
  }
  final ids = [
    ...memberIDs,
    for (final key in done.keys)
      if (!memberIDs.contains(key)) key,
  ];
  final total = done.values.fold<int>(0, (a, b) => a + b);

  // Largest remainder: floor every share, hand the leftover points to the
  // biggest fractions (ties: list order).
  final exact = {
    for (final i in ids) i: total == 0 ? 0.0 : (done[i] ?? 0) * 100 / total,
  };
  final percent = {for (final i in ids) i: exact[i]!.floor()};
  final int left = total == 0
      ? 0
      : 100 - percent.values.fold<int>(0, (a, b) => a + b);
  final byFraction = [...ids]
    ..sort(
      (a, b) => (exact[b]! - percent[b]!).compareTo(exact[a]! - percent[a]!),
    );
  for (final i in byFraction.take(left)) {
    percent[i] = percent[i]! + 1;
  }

  int count(String member, bool Function(Map<String, dynamic>) test) =>
      tasks.where((t) => id(t) == member && test(t)).length;
  bool late(Map<String, dynamic> t) {
    final due = DateTime.tryParse('${t['dueAt'] ?? ''}');
    return status(t) != 'done' && due != null && due.isBefore(now);
  }

  final rows = [
    for (final i in ids)
      (
        id: i,
        done: done[i] ?? 0,
        review: count(i, (t) => status(t) == 'in_review'),
        active: count(
          i,
          (t) => ['todo', 'in_progress', 'needs_revision'].contains(status(t)),
        ),
        late: count(i, late),
        percent: percent[i]!,
      ),
  ];
  rows.sort((a, b) => b.percent.compareTo(a.percent));
  return rows;
}
