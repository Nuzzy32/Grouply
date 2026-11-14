import 'store.dart';

String projectLpj(
  JsonMap project,
  List<JsonMap> tasks,
  List<JsonMap> meetings,
  String Function(String) nameFor,
  String Function(String) statusLabel,
) {
  final done = tasks.where((task) => task.text('status') == 'done').length;
  final lines = [
    'DRAF LAPORAN PERTANGGUNGJAWABAN',
    project.text('title'),
    if (project.text('description').isNotEmpty) project.text('description'),
    '',
    'REKAP PEKERJAAN',
    '$done dari ${tasks.length} tugas selesai.',
    if (tasks.isEmpty) 'Belum ada tugas.',
    for (final task in tasks) ...[
      '- ${task.text('title')} — ${statusLabel(task.text('status'))}',
      '  Pelaksana: ${task.text('assigneeID').isEmpty ? 'Pengguna terhapus' : nameFor(task.text('assigneeID'))}',
      if (task.date('dueAt') case final due?)
        '  Tenggat (UTC): ${due.toUtc().toIso8601String()}',
      if ((task['submissions'] as List? ?? []).whereType<JsonMap>().lastOrNull
          case final submission?)
        for (final link in submission.ids('links')) '  Tautan hasil: $link',
    ],
    '',
    'NOTULEN RAPAT TERKAIT',
    if (meetings.isEmpty) 'Belum ada notulen rapat yang tertaut.',
    for (final meeting in meetings) ...[
      '- ${meeting.text('title')}',
      meeting.text('minutes'),
    ],
    '',
    'EVALUASI',
    '[Isi evaluasi pelaksanaan proker.]',
    '',
    'REKOMENDASI',
    '[Isi rekomendasi untuk proker berikutnya.]',
  ];
  return '${lines.join('\n')}\n';
}
