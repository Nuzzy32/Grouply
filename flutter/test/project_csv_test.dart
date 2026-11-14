import 'package:flutter_test/flutter_test.dart';
import 'package:grouply/core/project_csv.dart';

void main() {
  test(
    'CSV quotes text, neutralizes formulas, and exports the latest result',
    () {
      final csv = projectCsv(
        ' =1+2',
        [
          {
            'title': 'Poster "Seminar", café',
            'status': 'done',
            'dueAt': '2026-11-14T08:00:00+07:00',
            'submissions': [
              {
                'links': ['https://example.org/old'],
              },
              {
                'createdAt': '2026-11-13T10:00:00Z',
                'links': ['https://example.org/a', 'https://example.org/b'],
              },
            ],
          },
        ],
        (_) => throw StateError('Deleted participant must not be looked up'),
        (_) => 'Selesai',
      );
      expect(csv, startsWith('\uFEFF"Proker"'));
      expect(
        csv,
        contains(
          '"\' =1+2","Poster ""Seminar"", café","Pengguna terhapus","Selesai"',
        ),
      );
      expect(
        csv,
        contains('"2026-11-14T01:00:00.000Z","2026-11-13T10:00:00.000Z"'),
      );
      expect(
        csv,
        contains('"https://example.org/a\nhttps://example.org/b"\r\n'),
      );
      expect(csv, isNot(contains('https://example.org/old')));
    },
  );
}
