import 'store.dart';

String projectCsv(
  String title,
  Iterable<JsonMap> tasks,
  String Function(String id) nameFor,
  String Function(String status) statusLabel,
) {
  String cell(String value) {
    final safe = RegExp(r'^[\s\uFEFF]*[=+\-@]|^[\t\r\n]').hasMatch(value)
        ? "'$value"
        : value;
    return '"${safe.replaceAll('"', '""')}"';
  }

  String utc(JsonMap row, String key) =>
      row.date(key)?.toUtc().toIso8601String() ?? '';

  final rows = [
    [
      'Proker',
      'Tugas',
      'Pelaksana',
      'Status',
      'Tenggat (UTC)',
      'Hasil terakhir dikirim (UTC)',
      'Tautan hasil terakhir',
    ],
    for (final task in tasks)
      [
        title,
        task.text('title'),
        task.text('assigneeID').isEmpty
            ? 'Pengguna terhapus'
            : nameFor(task.text('assigneeID')),
        statusLabel(task.text('status')),
        utc(task, 'dueAt'),
        if ((task['submissions'] as List? ?? []).whereType<JsonMap>().lastOrNull
            case final submission?) ...[
          utc(submission, 'createdAt'),
          submission.ids('links').join('\n'),
        ] else ...[
          '',
          '',
        ],
      ],
  ];
  return '\uFEFF${rows.map((row) => row.map(cell).join(',')).join('\r\n')}\r\n';
}
