import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:grouply/core/lpj_export.dart';

/// Fake `grouply_report` data (§4.2) with non-Latin names and a formula.
Map<String, dynamic> _report() => {
  'generatedAt': '2026-11-13T08:00:00Z',
  'organization': 'BEM FST',
  'period': '2026/2027',
  'group': {
    'name': 'Panitia Seminar',
    'isCommittee': true,
    'coordinator': 'Ayu Ñúñez',
  },
  'projects': [
    {
      'title': 'Sie Publikasi',
      'dueAt': '2026-11-20T16:59:00Z',
      'status': 'completed',
      'lead': 'Дмитрий',
      'tasks': [
        {
          'title': '=HYPERLINK("http://evil")',
          'assignee': 'Γιώργος',
          'reviewer': 'Şükrü',
          'status': 'done',
          'dueAt': '2026-11-10T16:59:00Z',
          'doneAt': '2026-11-09T10:00:00Z',
          'revisions': 2,
          'links': [
            'https://drive.google.com/poster-final-dengan-nama-yang-sangat-panjang-sekali',
          ],
        },
        {
          'title': 'Caption "promo", minggu 1 🎉 漢字',
          'assignee': '@raka',
          'reviewer': '-Nadia',
          'status': 'in_review',
          'dueAt': '2026-11-12T16:59:00Z',
          'doneAt': null,
          'revisions': 0,
          'links': <String>[],
        },
      ],
    },
  ],
  'meetings': [
    {
      'title': 'Rapat perdana',
      'startsAt': '2026-11-01T07:00:00Z',
      'present': 12,
      'excused': 2,
      'minutes': 'Pembagian sie.\nPoster oleh Γιώργος.',
      'minutesTruncated': true,
    },
  ],
  'approvals': [
    {
      'title': '+Dana publikasi',
      'amount': 500000,
      'status': 'approved',
      'closedAt': '2026-11-05T07:00:00Z',
      'chain': ['Raka (disetujui)', 'Ayu (disetujui)'],
    },
  ],
  'totals': {'tasks': 2, 'done': 1, 'approvedAmount': 500000},
};

void main() {
  test('csv cells neutralise formulas and quote separators', () {
    expect(csvCell('=SUM(A1)'), "'=SUM(A1)");
    expect(csvCell('+62 812'), "'+62 812");
    expect(csvCell('-5'), "'-5");
    expect(csvCell('@user'), "'@user");
    expect(csvCell('\t=1+1'), "'\t=1+1");
    expect(csvCell('\r=1+1'), "\"'\r=1+1\"");
    expect(csvCell('a,b'), '"a,b"');
    expect(csvCell('say "hi"'), '"say ""hi"""');
    expect(csvCell('two\nlines'), '"two\nlines"');
    expect(csvCell(null), '');
    expect(csvCell(12), '12');
    expect(csvCell('Biasa'), 'Biasa');
  });

  test('csv is UTF-8 with BOM and keeps every row', () {
    final bytes = lpjCsv(_report());
    expect(bytes.sublist(0, 3), [0xEF, 0xBB, 0xBF]);
    final text = utf8.decode(bytes.sublist(3));
    expect(text, contains('Ayu Ñúñez'));
    expect(text, contains("'=HYPERLINK(\"\"http://evil\"\")"));
    expect(text, contains('"Caption ""promo"", minggu 1 🎉 漢字"'));
    expect(text, contains("'@raka,'-Nadia,Review"));
    expect(text, contains("'+Dana publikasi,500000,Disetujui"));
    expect(text, contains('[dipotong]'));
    expect(text, contains('\r\n'));
    expect(
      text.split('\r\n').where((line) => line.startsWith('Sie Publikasi')),
      hasLength(2),
    );
  });

  test('approvals block is left out when the report has none', () {
    final report = _report()..remove('approvals');
    final text = utf8.decode(lpjCsv(report).sublist(3));
    expect(text, isNot(contains('Pengajuan,Nominal')));
  });

  test('file name drops path separators', () {
    final report = _report()
      ..['group'] = {
        'name': 'Sie A/B',
        'isCommittee': false,
        'coordinator': '',
      };
    expect(lpjFileName(report, 'csv'), 'Rekap LPJ - Sie A-B - 2026-2027.csv');
  });

  Uint8List font(String name) => File('assets/fonts/$name').readAsBytesSync();

  test('pdf builds with the bundled Noto Sans and non-Latin text', () async {
    final bytes = await buildLpjPdf((
      report: _report(),
      regular: font('NotoSans-Regular.ttf'),
      bold: font('NotoSans-Bold.ttf'),
    ));
    expect(ascii.decode(bytes.sublist(0, 5)), '%PDF-');
    expect(bytes.length, greaterThan(5000));
  });

  test('pdf spans minutes of 4,000 characters over many lines', () async {
    final minutes = [
      for (var i = 1; i <= 120; i++) 'Baris $i: keputusan rapat Γιώργος.',
    ].join('\n');
    expect(minutes.length, greaterThan(4000));
    final report = _report()
      ..['meetings'] = [
        for (var m = 0; m < 3; m++)
          {
            'title': 'Rapat $m',
            'startsAt': '2026-11-01T07:00:00Z',
            'present': 10,
            'excused': 0,
            'minutes': minutes.substring(0, 4000),
            'minutesTruncated': true,
          },
      ]
      ..['period'] = '';
    final bytes = await buildLpjPdf((
      report: report,
      regular: font('NotoSans-Regular.ttf'),
      bold: font('NotoSans-Bold.ttf'),
    ));
    expect(ascii.decode(bytes.sublist(0, 5)), '%PDF-');
  });
}
