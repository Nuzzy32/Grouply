// LPJ recap export (docs/DESIGN-org-tahap3.md §5): CSV and PDF built on the
// device from `grouply_report` data. Nothing is stored on the server.

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show compute;
import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'store.dart';

const _months = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'Mei',
  'Jun',
  'Jul',
  'Agu',
  'Sep',
  'Okt',
  'Nov',
  'Des',
];

String _date(Object? iso) {
  final value = iso is String ? DateTime.tryParse(iso)?.toLocal() : null;
  return value == null
      ? ''
      : '${value.day} ${_months[value.month - 1]} ${value.year}';
}

String lpjRupiah(num value) {
  final digits = value.toInt().toString();
  final out = StringBuffer('Rp ');
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) out.write('.');
    out.write(digits[i]);
  }
  return out.toString();
}

String lpjTaskStatus(String status) => switch (status) {
  'todo' => 'Belum dimulai',
  'in_progress' => 'Dikerjakan',
  'in_review' => 'Review',
  'needs_revision' => 'Revisi',
  'done' => 'Selesai',
  _ => status,
};

String lpjProjectStatus(String status) => switch (status) {
  'active' => 'Aktif',
  'completed' => 'Selesai',
  'archived' => 'Diarsipkan',
  _ => status,
};

String lpjApprovalStatus(String status) => switch (status) {
  'pending' => 'Menunggu',
  'approved' => 'Disetujui',
  'rejected' => 'Ditolak',
  'cancelled' => 'Dibatalkan',
  'lapsed' => 'Gugur',
  _ => status,
};

List<JsonMap> _list(JsonMap row, String key) =>
    (row[key] as List? ?? []).cast<JsonMap>();

/// `Rekap LPJ - <grup> - <periode>.<ext>`, without path separators.
String lpjFileName(JsonMap report, String ext) {
  final group = (report['group'] as Map?)?['name'] ?? 'Grup';
  final period = report['period'] is String && report['period'] != ''
      ? ' - ${report['period']}'
      : '';
  final name = 'Rekap LPJ - $group$period'.replaceAll(
    RegExp(r'[\\/:*?"<>|\n\r]'),
    '-',
  );
  return '$name.$ext';
}

// MARK: - CSV

/// One CSV cell. A leading `= + - @`, tab or carriage return gets a `'` so
/// spreadsheets do not run it as a formula; commas, quotes and newlines are
/// quoted.
String csvCell(Object? value) {
  var text = value?.toString() ?? '';
  if (text.isNotEmpty && '=+-@\t\r'.contains(text[0])) text = "'$text";
  if (RegExp(r'[",\r\n]').hasMatch(text)) {
    text = '"${text.replaceAll('"', '""')}"';
  }
  return text;
}

/// UTF-8 with BOM so Excel reads Indonesian names correctly; CRLF rows.
Uint8List lpjCsv(JsonMap report) {
  final group = Map<String, dynamic>.from(report['group'] as Map);
  final totals = Map<String, dynamic>.from(report['totals'] as Map);
  final rows = <List<Object?>>[
    ['Rekap LPJ'],
    ['Organisasi', report['organization']],
    ['Periode', report['period']],
    [group['isCommittee'] == true ? 'Kepanitiaan' : 'Divisi', group['name']],
    ['Koordinator', group['coordinator']],
    ['Dibuat', _date(report['generatedAt'])],
    [],
    [
      'Proker/Sie',
      'Status proker',
      'Penanggung jawab',
      'Tugas',
      'Pelaksana',
      'Reviewer',
      'Status',
      'Deadline',
      'Selesai',
      'Revisi',
      'Tautan',
    ],
    for (final project in _list(report, 'projects'))
      for (final task in _list(project, 'tasks'))
        [
          project['title'],
          lpjProjectStatus('${project['status']}'),
          project['lead'],
          task['title'],
          task['assignee'],
          task['reviewer'],
          lpjTaskStatus('${task['status']}'),
          _date(task['dueAt']),
          _date(task['doneAt']),
          task['revisions'],
          (task['links'] as List? ?? []).join(' '),
        ],
    [],
    ['Rapat', 'Waktu', 'Hadir', 'Izin', 'Notulen'],
    for (final meeting in _list(report, 'meetings'))
      [
        meeting['title'],
        _date(meeting['startsAt']),
        meeting['present'],
        meeting['excused'],
        '${meeting['minutes'] ?? ''}${meeting['minutesTruncated'] == true ? ' [dipotong]' : ''}',
      ],
    if (report['approvals'] case final List approvals
        when approvals.isNotEmpty) ...[
      [],
      ['Pengajuan', 'Nominal', 'Status', 'Ditutup', 'Jenjang'],
      for (final approval in approvals.cast<JsonMap>())
        [
          approval['title'],
          approval['amount'],
          lpjApprovalStatus('${approval['status']}'),
          _date(approval['closedAt']),
          (approval['chain'] as List? ?? []).join('; '),
        ],
    ],
    [],
    ['Total tugas', totals['tasks']],
    ['Tugas selesai', totals['done']],
    ['Dana disetujui', totals['approvedAmount']],
  ];
  final text = rows.map((row) => row.map(csvCell).join(',')).join('\r\n');
  return Uint8List.fromList([0xEF, 0xBB, 0xBF, ...utf8.encode('$text\r\n')]);
}

// MARK: - PDF

/// Loads the bundled Noto Sans and builds the PDF in a background isolate.
Future<Uint8List> lpjPdf(JsonMap report) async {
  final regular = await rootBundle.load('assets/fonts/NotoSans-Regular.ttf');
  final bold = await rootBundle.load('assets/fonts/NotoSans-Bold.ttf');
  return compute(buildLpjPdf, (
    report: report,
    regular: regular.buffer.asUint8List(),
    bold: bold.buffer.asUint8List(),
  ));
}

typedef LpjPdfInput = ({JsonMap report, Uint8List regular, Uint8List bold});

/// Pure builder (runs inside [compute]). Characters Noto Sans lacks, such
/// as emoji or CJK, become `?` instead of blank boxes.
Future<Uint8List> buildLpjPdf(LpjPdfInput input) {
  final regularData = ByteData.sublistView(input.regular);
  final supported = TtfParser(regularData).charToGlyphIndexMap.keys.toSet();
  String t(Object? value) => String.fromCharCodes(
    (value?.toString() ?? '').runes.map(
      (rune) => rune == 10 || supported.contains(rune) ? rune : 0x3F,
    ),
  );

  final report = input.report;
  final group = Map<String, dynamic>.from(report['group'] as Map);
  final totals = Map<String, dynamic>.from(report['totals'] as Map);
  final theme = pw.ThemeData.withFont(
    base: pw.Font.ttf(regularData),
    bold: pw.Font.ttf(ByteData.sublistView(input.bold)),
  );
  const small = pw.TextStyle(fontSize: 9);
  final head = pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold);
  pw.Widget heading(String text) => pw.Padding(
    padding: const pw.EdgeInsets.only(top: 14, bottom: 6),
    child: pw.Text(
      t(text),
      style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold),
    ),
  );
  pw.Widget table(List<String> headers, List<List<Object?>> rows) =>
      pw.TableHelper.fromTextArray(
        headers: [for (final h in headers) t(h)],
        data: [
          for (final row in rows) [for (final cell in row) t(cell)],
        ],
        headerStyle: head,
        cellStyle: small,
        headerAlignment: pw.Alignment.centerLeft,
        headerDecoration: const pw.BoxDecoration(color: PdfColors.grey200),
        cellPadding: const pw.EdgeInsets.all(4),
        border: pw.TableBorder.all(color: PdfColors.grey400, width: 0.5),
      );

  final doc = pw.Document(
    title: t(lpjFileName(report, 'pdf')),
    creator: 'Grouply',
  );
  final approvals = _list(report, 'approvals');
  doc.addPage(
    pw.MultiPage(
      theme: theme,
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(36),
      footer: (context) => pw.Align(
        alignment: pw.Alignment.centerRight,
        child: pw.Text(
          t('Halaman ${context.pageNumber} dari ${context.pagesCount}'),
          style: small,
        ),
      ),
      build: (context) => [
        pw.Text(
          t('Rekap LPJ'),
          style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold),
        ),
        pw.SizedBox(height: 4),
        pw.Text(
          t(
            '${report['organization']}${'${report['period'] ?? ''}'.isEmpty ? '' : ' · Periode ${report['period']}'}',
          ),
        ),
        pw.Text(
          t(
            '${group['isCommittee'] == true ? 'Kepanitiaan' : 'Divisi'} ${group['name']} · Koordinator ${group['coordinator']}',
          ),
        ),
        pw.Text(t('Dibuat ${_date(report['generatedAt'])}'), style: small),
        heading('Ringkasan'),
        pw.Text(
          t(
            '${totals['done']} dari ${totals['tasks']} tugas selesai'
            '${approvals.isEmpty ? '' : ' · Dana disetujui ${lpjRupiah(totals['approvedAmount'] as num? ?? 0)}'}',
          ),
        ),
        for (final project in _list(report, 'projects')) ...[
          heading('${project['title']}'),
          pw.Text(
            t(
              '${lpjProjectStatus('${project['status']}')} · Deadline ${_date(project['dueAt'])}'
              '${'${project['lead'] ?? ''}'.isEmpty ? '' : ' · Penanggung jawab ${project['lead']}'}',
            ),
            style: small,
          ),
          pw.SizedBox(height: 6),
          if (_list(project, 'tasks').isEmpty)
            pw.Text(t('Belum ada tugas.'), style: small)
          else
            table(
              [
                'Tugas',
                'Pelaksana',
                'Reviewer',
                'Status',
                'Deadline',
                'Selesai',
                'Revisi',
                'Tautan',
              ],
              [
                for (final task in _list(project, 'tasks'))
                  [
                    task['title'],
                    task['assignee'],
                    task['reviewer'],
                    lpjTaskStatus('${task['status']}'),
                    _date(task['dueAt']),
                    _date(task['doneAt']),
                    task['revisions'],
                    (task['links'] as List? ?? []).join('\n'),
                  ],
              ],
            ),
        ],
        heading('Rapat'),
        if (_list(report, 'meetings').isEmpty)
          pw.Text(t('Tidak ada rapat di periode ini.'), style: small)
        else
          for (final meeting in _list(report, 'meetings')) ...[
            pw.Text(
              t(
                '${meeting['title']} · ${_date(meeting['startsAt'])} · ${meeting['present']} hadir, ${meeting['excused']} izin',
              ),
              style: head,
            ),
            if ('${meeting['minutes'] ?? ''}'.isNotEmpty)
              pw.Padding(
                padding: const pw.EdgeInsets.only(top: 2, bottom: 6),
                child: pw.Text(
                  t(
                    '${meeting['minutes']}${meeting['minutesTruncated'] == true ? ' [notulen dipotong]' : ''}',
                  ),
                  style: small,
                  // Long minutes continue on the next page instead of
                  // failing the whole document.
                  overflow: pw.TextOverflow.span,
                ),
              ),
          ],
        if (approvals.isNotEmpty) ...[
          heading('Pengajuan'),
          table(
            ['Pengajuan', 'Nominal', 'Status', 'Ditutup', 'Jenjang'],
            [
              for (final approval in approvals)
                [
                  approval['title'],
                  approval['amount'] is num
                      ? lpjRupiah(approval['amount'] as num)
                      : '',
                  lpjApprovalStatus('${approval['status']}'),
                  _date(approval['closedAt']),
                  (approval['chain'] as List? ?? []).join('\n'),
                ],
            ],
          ),
        ],
      ],
    ),
  );
  return doc.save();
}
