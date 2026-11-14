import 'package:flutter_test/flutter_test.dart';
import 'package:grouply/core/project_lpj.dart';

void main() {
  test('LPJ includes recorded facts and leaves evaluation for the author', () {
    final draft = projectLpj(
      {'title': 'Seminar'},
      [
        {
          'title': 'Poster',
          'status': 'done',
          'submissions': [
            {
              'links': ['https://example.org/old'],
            },
            {
              'links': ['https://example.org/final'],
            },
          ],
        },
      ],
      [
        {'title': 'Rapat panitia', 'minutes': 'Poster disetujui.'},
      ],
      (_) => throw StateError('Deleted participant must not be looked up'),
      (_) => 'Selesai',
    );
    expect(draft, contains('1 dari 1 tugas selesai.'));
    expect(draft, contains('Pelaksana: Pengguna terhapus'));
    expect(draft, contains('https://example.org/final'));
    expect(draft, isNot(contains('https://example.org/old')));
    expect(draft, contains('Rapat panitia\nPoster disetujui.'));
    expect(draft, contains('[Isi evaluasi pelaksanaan proker.]'));
    expect(draft, contains('[Isi rekomendasi untuk proker berikutnya.]'));
  });
}
