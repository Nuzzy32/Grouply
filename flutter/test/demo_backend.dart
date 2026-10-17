import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:grouply/core/backend.dart';
import 'package:grouply/core/store.dart';

/// Swift `profilePersonas` (prototype `PERSONAS`).
const demoPersonas = [
  (id: 'u1', role: 'Koordinator'),
  (id: 'u2', role: 'Pelaksana'),
  (id: 'u3', role: 'Reviewer'),
  (id: 'u4', role: 'Anggota'),
  (id: 'u5', role: 'Anggota'),
  (id: 'u6', role: 'Koordinator'),
  (id: 'u7', role: 'Anggota'),
];

/// Test-only backend holding the former in-app demo: the Swift seed (u1–u7)
/// and a local copy of the server workflow rules, so widget tests can drive
/// the real store through `snapshot`/`mutate` without a network.
class DemoBackend implements GrouplyBackend {
  DemoBackend({DateTime Function()? clock}) : _clock = clock ?? DateTime.now {
    _seed();
    _actor = '';
  }

  final DateTime Function() _clock;
  final _changes = StreamController<String?>.broadcast(sync: true);
  List<JsonMap> users = [],
      groups = [],
      projects = [],
      tasks = [],
      messages = [],
      invites = [],
      reports = [];
  String _actor = '';
  Map<String, List<String>> _blocks = {}, _reads = {};

  /// Sends from the current actor are stored as `failed`, like the old demo.
  bool simulateSendFailure = false;

  /// Next sendMessage throws, like a dropped connection in cloud mode.
  bool offline = false;
  int mutations = 0;

  JsonMap? _find(List<JsonMap> rows, String id) {
    for (final row in rows) {
      if (row.text('id') == id) return row;
    }
    return null;
  }

  JsonMap? user(String id) => _find(users, id);
  JsonMap? group(String id) => _find(groups, id);
  JsonMap? project(String id) => _find(projects, id);
  JsonMap? task(String id) => _find(tasks, id);

  static dynamic _copy(Object? value) => jsonDecode(jsonEncode(value));

  @override
  bool get configured => true;
  @override
  String? get currentUserID => _actor.isEmpty ? null : _actor;
  @override
  Stream<String?> get authChanges => _changes.stream;
  @override
  Future<void> initialize() async {}

  /// Signs in as a seed persona; the email field is the user ID (e.g. `u1`).
  @override
  Future<void> signIn(String email, String password) async {
    final row = user(email);
    if (row == null || row.text('email').isEmpty) {
      throw const GrouplyException('Pengguna demo tidak valid.');
    }
    _actor = email;
    _changes.add(_actor);
  }

  @override
  Future<bool> signUp(String name, String email, String password) =>
      throw UnimplementedError();
  @override
  Future<void> sendPasswordReset(String email) => throw UnimplementedError();
  @override
  Future<void> resetPassword(String email, String code, String password) =>
      throw UnimplementedError();

  @override
  Future<void> signOut() async {
    _actor = '';
    _changes.add(null);
  }

  @override
  Future<JsonMap> snapshot() async => {
    'currentUserID': _actor,
    'users': _copy(users),
    'groups': _copy(groups),
    'projects': _copy(projects),
    'tasks': _copy(tasks),
    'messages': _copy(messages),
    'invites': _copy(invites),
    'reports': _copy(reports),
    'blockedUserIDs': [...?_blocks[_actor]],
    'readMessageIDs': [...?_reads[_actor]],
  };

  @override
  Future<JsonMap> mutate(String action, JsonMap payload) async {
    mutations++;
    if (offline && action == 'sendMessage') {
      throw StateError('offline');
    }
    final actor = _actor;
    final backup = jsonEncode({
      'users': users,
      'groups': groups,
      'projects': projects,
      'tasks': tasks,
      'messages': messages,
      'invites': invites,
      'reports': reports,
      'blocks': _blocks,
      'reads': _reads,
    });
    try {
      final result =
          _copy(_demoMutate(action, _copy(payload) as JsonMap)) as JsonMap;
      // Like the server, a deleted account keeps its session until sign-out.
      if (action == 'deleteAccount') _actor = actor;
      return result;
    } catch (_) {
      final saved = jsonDecode(backup) as JsonMap;
      List<JsonMap> rows(String key) =>
          (saved[key] as List).map((row) => row as JsonMap).toList();
      users = rows('users');
      groups = rows('groups');
      projects = rows('projects');
      tasks = rows('tasks');
      messages = rows('messages');
      invites = rows('invites');
      reports = rows('reports');
      Map<String, List<String>> lists(String key) => (saved[key] as Map).map(
        (id, value) => MapEntry(id as String, (value as List).cast<String>()),
      );
      _blocks = lists('blocks');
      _reads = lists('reads');
      rethrow;
    }
  }

  @override
  Future<void> connect(void Function() onChange) async {}
  @override
  Future<void> disconnect() async {}
  @override
  Future<void> foreground() async {}
  @override
  void dispose() {
    unawaited(_changes.close());
  }

  String _demoID() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    bytes[6] = (bytes[6] & 15) | 64;
    bytes[8] = (bytes[8] & 63) | 128;
    final hex = bytes
        .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
        .join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
  }

  Never _demoFail(String message) => throw GrouplyException(message);

  String _demoText(
    JsonMap payload,
    String key,
    int max, {
    bool required = true,
  }) {
    final raw = payload[key];
    if (raw != null && raw is! String) _demoFail('Isian $key tidak valid.');
    final value = (raw as String? ?? '').trim();
    if ((required && value.isEmpty) || value.runes.length > max) {
      _demoFail('Isi $key wajib diisi dan maksimal $max karakter.');
    }
    return value;
  }

  String _demoDue(JsonMap payload) {
    final due = payload.date('dueAt');
    if (due == null || !due.isAfter(_clock())) {
      _demoFail('Tenggat harus berupa tanggal di masa depan.');
    }
    return due.toUtc().toIso8601String();
  }

  JsonMap _demoMember(String id, {bool coordinator = false}) {
    final row = group(id);
    if (row == null || !row.ids('memberIDs').contains(_actor)) {
      _demoFail('Kamu bukan anggota grup ini.');
    }
    if (coordinator && row.text('coordinatorID') != _actor) {
      _demoFail('Hanya koordinator yang dapat melakukan tindakan ini.');
    }
    return row;
  }

  JsonMap _demoProject(
    String id, {
    bool writable = true,
    bool coordinator = false,
  }) {
    final row = project(id);
    if (row == null) _demoFail('Proyek tidak ditemukan.');
    _demoMember(row.text('groupID'), coordinator: coordinator);
    if (writable && row.text('status') != 'active') {
      _demoFail('Proyek selesai atau diarsipkan hanya dapat dibaca.');
    }
    return row;
  }

  void _demoAssignment(JsonMap group, String assignee, String reviewer) {
    final members = group.ids('memberIDs');
    if (assignee.isEmpty ||
        reviewer.isEmpty ||
        assignee == reviewer ||
        !members.contains(assignee) ||
        !members.contains(reviewer) ||
        user(assignee) == null ||
        user(reviewer) == null) {
      _demoFail('Pelaksana dan reviewer harus anggota grup yang berbeda.');
    }
  }

  void _demoNoAssignments(String userID, {String? groupID}) {
    if (tasks.any(
      (row) =>
          row.text('status') != 'done' &&
          (row.text('assigneeID') == userID ||
              row.text('reviewerID') == userID) &&
          (groupID == null ||
              project(row.text('projectID'))?.text('groupID') == groupID),
    )) {
      _demoFail(
        'Alihkan seluruh tugas aktif pelaksana dan reviewer terlebih dahulu.',
      );
    }
  }

  void _demoActivity(JsonMap task, String system, {String? groupText}) {
    final groupID = project(task.text('projectID'))!.text('groupID');
    for (final thread in [if (groupText != null) null, task.text('id')]) {
      messages.add({
        'id': _demoID(),
        'groupID': groupID,
        'taskID': thread,
        'senderID': _actor,
        'text': thread == null ? groupText : system,
        'createdAt': _clock().toUtc().toIso8601String(),
        'kind': thread == null ? 'activity' : 'system',
        'delivery': 'sent',
        'targetTaskID': task.text('id'),
      });
    }
  }

  /// Port of `DemoStore.loadSeed()` (Grouply/Core/DemoSeed.swift).
  void _seed() {
    // Demo clock: the prototype's "Jum, 16 Okt 19:30" mapped onto today.
    final today = _clock().toLocal();
    DateTime at(int offset, int h, int m) => DateTime(
      today.year,
      today.month,
      today.day + offset,
    ).add(Duration(hours: h, minutes: m));
    DateTime day(int offset) => at(offset, 23, 59);
    String iso(DateTime value) => value.toUtc().toIso8601String();
    JsonMap person(String id, String name, String email, String tint) => {
      'id': id,
      'name': name,
      'email': email,
      'tint': tint,
    };
    users = [
      person('u1', 'Alex', 'alex.pratama@student.ac.id', '#DED2FF'),
      person('u2', 'Raka', 'raka.aditya@student.ac.id', '#C9F2D6'),
      person('u3', 'Nadia', 'nadia.putri@student.ac.id', '#F9E9BE'),
      person('u4', 'Dimas', 'dimas.s@student.ac.id', '#D8EAF4'),
      person('u5', 'Sinta', 'sinta@student.ac.id', '#F6CED1'),
      person('u6', 'Bima', 'bima@student.ac.id', '#C9F2D6'),
      person('u7', 'Laras', 'laras@student.ac.id', '#D8EAF4'),
    ];
    groups = [
      {
        'id': 'g3',
        'name': 'Statistika · Kelompok 1',
        'description': 'Analisis data survei kebiasaan belajar.',
        'course': 'Statistika Dasar',
        'memberIDs': ['u6', 'u7'],
        'coordinatorID': 'u6',
        'tint': '#D8EAF4',
        'icon': 'chart.xyaxis.line',
      },
      {
        'id': 'g1',
        'name': 'Basis Data · Kelompok 3',
        'description': 'Tugas besar Basis Data semester 3.',
        'course': 'Basis Data · IF-B',
        'memberIDs': ['u1', 'u2', 'u3', 'u4', 'u5'],
        'coordinatorID': 'u1',
        'tint': '#C9F2D6',
        'icon': 'cylinder.split.1x2',
      },
      {
        'id': 'g2',
        'name': 'UI/UX Research',
        'description': 'Riset usability aplikasi kampus.',
        'course': 'Interaksi Manusia & Komputer',
        'memberIDs': ['u1', 'u3', 'u5'],
        'coordinatorID': 'u3',
        'tint': '#DED2FF',
        'icon': 'circle.grid.2x2',
      },
    ];
    projects = [
      {
        'id': 'p1',
        'groupID': 'g1',
        'title': 'Sistem Informasi Perpustakaan',
        'description':
            'Rancang basis data perpustakaan kampus: ERD, normalisasi sampai 3NF, DDL, dan presentasi akhir.',
        'dueAt': iso(day(8)),
        'status': 'active',
      },
      {
        'id': 'p3',
        'groupID': 'g1',
        'title': 'Proposal Topik',
        'description': 'Proposal topik tugas besar untuk disetujui dosen.',
        'dueAt': iso(day(-7)),
        'status': 'completed',
      },
      {
        'id': 'p2',
        'groupID': 'g2',
        'title': 'Laporan Usability Test',
        'description':
            'Uji 5 partisipan pada aplikasi KRS online dan susun laporan temuan.',
        'dueAt': iso(day(14)),
        'status': 'active',
      },
    ];
    JsonMap task(
      String id,
      String projectID,
      String title,
      String description,
      String assigneeID,
      String reviewerID,
      DateTime dueAt,
      String status,
    ) => {
      'id': id,
      'projectID': projectID,
      'title': title,
      'description': description,
      'assigneeID': assigneeID,
      'reviewerID': reviewerID,
      'dueAt': iso(dueAt),
      'status': status,
      'version': 1,
      'submissions': <JsonMap>[],
    };
    tasks = [
      task(
        't1',
        'p1',
        'Draft diagram ERD',
        'ERD lengkap dengan entity Member, Book, Loan, Fine beserta kardinalitasnya.',
        'u2',
        'u1',
        day(2),
        'in_review',
      ),
      task(
        't2',
        'p1',
        'Normalisasi tabel ke 3NF',
        'Turunkan ERD ke tabel relasional dan normalisasi sampai 3NF. Tulis alasan setiap dekomposisi.',
        'u1',
        'u3',
        day(1),
        'in_progress',
      ),
      task(
        't3',
        'p1',
        'Tulis script DDL SQL',
        'Script CREATE TABLE untuk PostgreSQL, lengkap dengan constraint dan index.',
        'u1',
        'u4',
        at(3, 12, 0),
        'needs_revision',
      ),
      task(
        't11',
        'p1',
        'Kamus data',
        'Dokumentasikan setiap atribut: tipe data, panjang, dan contoh nilai.',
        'u2',
        'u3',
        day(4),
        'todo',
      ),
      task(
        't4',
        'p1',
        'Studi literatur',
        'Rangkum 5 referensi sistem perpustakaan.',
        'u3',
        'u2',
        day(-4),
        'done',
      ),
      task(
        't5',
        'p1',
        'Slide presentasi',
        '10 slide untuk presentasi 15 menit di kelas.',
        'u4',
        'u1',
        day(6),
        'todo',
      ),
      task(
        't6',
        'p1',
        'Narasi use case',
        'Narasi use case peminjaman dan pengembalian buku.',
        'u5',
        'u3',
        day(-3),
        'done',
      ),
      task(
        't12',
        'p3',
        'Draft proposal',
        'Latar belakang, rumusan masalah, dan ruang lingkup.',
        'u5',
        'u1',
        day(-10),
        'done',
      ),
      task(
        't13',
        'p3',
        'Revisi proposal',
        'Perbaiki sesuai masukan dosen.',
        'u2',
        'u3',
        day(-7),
        'done',
      ),
      task(
        't7',
        'p2',
        'Rekrut 5 partisipan',
        'Rekrut mahasiswa angkatan 2024–2025.',
        'u5',
        'u1',
        day(-2),
        'done',
      ),
      task(
        't8',
        'p2',
        'Script wawancara',
        'Script wawancara 20 menit dan 6 skenario tugas.',
        'u1',
        'u5',
        day(-1),
        'todo',
      ),
      task(
        't9',
        'p2',
        'Affinity mapping',
        'Kelompokkan temuan dari 5 sesi wawancara.',
        'u3',
        'u5',
        day(9),
        'in_progress',
      ),
      task(
        't10',
        'p2',
        'Ringkasan temuan sesi 1',
        'Rangkum 5 temuan utama dari sesi 1, lengkap dengan kutipan partisipan.',
        'u1',
        'u3',
        day(5),
        'todo',
      ),
    ];
    JsonMap submission(
      String taskID,
      String authorID,
      String note,
      List<String> links,
      DateTime createdAt, {
      String? decision,
      String? feedback,
      String? reviewerID,
    }) => {
      'id': 's-$taskID-1',
      'revision': 1,
      'authorID': authorID,
      'note': note,
      'links': links,
      'createdAt': iso(createdAt),
      'decision': decision,
      'feedback': feedback,
      'reviewerID': reviewerID,
    };
    task_(String id) => tasks.firstWhere((row) => row['id'] == id);
    task_('t1')['submissions'] = [
      submission(
        't1',
        'u2',
        'ERD v1 dengan 9 entity. Relasi Member–Loan 1:N. Tolong cek apakah Fine perlu jadi entity sendiri.',
        ['https://drive.google.com/file/d/erd-v1'],
        at(-2, 15, 20),
      ),
    ];
    task_('t3')['submissions'] = [
      submission(
        't3',
        'u1',
        'DDL v1, 9 tabel dengan primary key.',
        ['https://github.com/kelompok3/perpus-ddl'],
        at(-1, 21, 5),
        decision: 'changes_requested',
        feedback:
            'Tambahkan ON DELETE untuk FK di tabel Loan, dan CHECK tanggal kembali ≥ tanggal pinjam.',
        reviewerID: 'u4',
      ),
    ];
    final approved = <String, (String, DateTime)>{
      't4': ('Rangkuman 5 jurnal.', at(-5, 12, 0)),
      't6': ('Narasi 4 use case.', at(-3, 12, 0)),
      't12': ('Draft 4 halaman.', at(-11, 12, 0)),
      't13': ('Sudah sesuai masukan.', at(-7, 12, 0)),
      't7': ('5 partisipan sudah terjadwal.', at(-3, 12, 0)),
    };
    for (final row in tasks.where((row) => row['status'] == 'done')) {
      final (note, date) =
          approved[row['id']] ??
          ('Hasil pekerjaan selesai.', row.date('dueAt')!);
      row['submissions'] = [
        submission(
          row.text('id'),
          row.text('assigneeID'),
          note,
          [],
          date,
          decision: 'approved',
          reviewerID: row.text('reviewerID'),
        ),
      ];
    }
    var nextMessage = 0;
    JsonMap msg(
      String groupID,
      String? taskID,
      String from,
      String text,
      DateTime date, [
      String kind = 'text',
      String? target,
    ]) => {
      'id': 'm${++nextMessage}',
      'groupID': groupID,
      'taskID': taskID,
      'senderID': from,
      'text': text,
      'createdAt': date,
      'kind': kind,
      'delivery': 'sent',
      'targetTaskID': target,
    };
    final seeded = [
      msg('g1', null, 'u2', 'mengirim hasil', at(-2, 15, 20), 'activity', 't1'),
      msg(
        'g1',
        null,
        'u3',
        'Guys, deadline ERD hari Minggu ya. Jangan mepet.',
        at(-1, 19, 40),
      ),
      msg('g1', null, 'u2', 'Siap, aku lanjut ERD malam ini.', at(-1, 20, 14)),
      msg('g1', null, 'u1', 'mengirim hasil', at(-1, 21, 5), 'activity', 't3'),
      msg('g1', null, 'u4', 'meminta revisi', at(0, 8, 40), 'activity', 't3'),
      msg(
        'g1',
        null,
        'u4',
        'Lex, cek feedback-ku di tugas DDL ya. Minor kok.',
        at(0, 8, 42),
      ),
      msg('g1', null, 'u1', 'Oke, nanti malam aku benerin.', at(0, 9, 15)),
      msg(
        'g1',
        null,
        'u5',
        'Template slide aku taruh sini: https://canva.com/design/perpus-k3',
        at(0, 12, 10),
      ),
      msg(
        'g1',
        null,
        'u2',
        'ERD-ku udah 2 hari nunggu review nih',
        at(0, 18, 55),
      ),
      msg(
        'g1',
        null,
        'u3',
        'Nanti malam call bentar bisa? 15 menit aja.',
        at(0, 19, 2),
      ),
      msg('g2', null, 'u1', 'menyetujui', at(-3, 16, 0), 'activity', 't7'),
      msg(
        'g2',
        null,
        'u5',
        'Makasih Alex! Jadwal sesi aku share besok.',
        at(-3, 16, 4),
      ),
      msg(
        'g2',
        null,
        'u3',
        'Sesi 1 lancar. Catatan lengkap: https://notion.so/sesi-1-krs',
        at(0, 10, 20),
      ),
      msg(
        'g2',
        null,
        'u3',
        'Alex, script wawancara jangan lupa ya, sesi 2 hari Senin.',
        at(0, 10, 21),
      ),
      msg('g3', null, 'u6', 'membuat grup', at(-1, 9, 0), 'system'),
      msg(
        'g3',
        null,
        'u7',
        'Halo! Nanti kita bagi tugas analisis ya.',
        at(-1, 9, 12),
      ),
      msg(
        'g1',
        't1',
        'u3',
        'Fine mending jadi entity sendiri, biar denda per hari gampang dihitung.',
        at(-2, 13, 2),
      ),
      msg(
        'g1',
        't1',
        'u2',
        'mengirim revisi 1',
        at(-2, 15, 20),
        'system',
        't1',
      ),
      msg(
        'g1',
        't1',
        'u2',
        'Udah aku kirim ya, tinggal nunggu review.',
        at(-2, 15, 21),
      ),
      msg(
        'g1',
        't2',
        'u3',
        'Sertakan tabel sebelum dan sesudah normalisasi ya.',
        at(-1, 10, 14),
      ),
      msg('g1', 't3', 'u1', 'mengirim revisi 1', at(-1, 21, 5), 'system', 't3'),
      msg('g1', 't3', 'u4', 'meminta revisi', at(0, 8, 40), 'system', 't3'),
      msg(
        'g1',
        't3',
        'u4',
        'Sisanya udah oke, tinggal constraint aja.',
        at(0, 8, 41),
      ),
    ];
    // Seed history must precede the wall clock so new local messages sort after it.
    final latest = seeded
        .map((row) => row['createdAt'] as DateTime)
        .reduce((a, b) => a.isAfter(b) ? a : b);
    final shift = latest.isAfter(_clock())
        ? _clock().subtract(const Duration(seconds: 60)).difference(latest)
        : Duration.zero;
    messages = [
      for (final row in seeded)
        {...row, 'createdAt': iso((row['createdAt'] as DateTime).add(shift))},
    ];
    invites = [
      for (final (id, groupID, code, created, expires, useCount, revoked) in [
        ('i1', 'g3', 'STAT-K1Q', -1, 6, 0, false),
        ('i2', 'g1', 'BD3-7KQ2', -2, 5, 0, false),
        ('i3', 'g1', 'BD3-USED', -6, 1, 1, false),
        ('i4', 'g2', 'UIX-OLD1', -15, -8, 0, false),
        ('i5', 'g1', 'BD3-OFF9', -3, 4, 0, true),
      ])
        {
          'id': id,
          'groupID': groupID,
          'code': code,
          'createdAt': iso(day(created)),
          'expiresAt': iso(day(expires)),
          'maxUses': 1,
          'useCount': useCount,
          'revoked': revoked,
        },
    ];
    reports = [];
    _blocks = {};
    // Unread counts from the prototype: everything else in the group chat is
    // already read. Flutter keeps one read set per user across groups.
    _reads = {};
    for (final (userID, groupID, unread) in [
      ('u1', 'g1', 2),
      ('u2', 'g1', 1),
      ('u3', 'g1', 0),
      ('u4', 'g1', 3),
      ('u5', 'g1', 0),
      ('u1', 'g2', 0),
      ('u3', 'g2', 1),
      ('u5', 'g2', 0),
      ('u6', 'g3', 0),
      ('u7', 'g3', 0),
    ]) {
      final thread = messages
          .where((row) => row['groupID'] == groupID && row['taskID'] == null)
          .toList();
      final fromOthers = [
        for (final row in thread)
          if (row['senderID'] != userID) row.text('id'),
      ];
      final unreadIDs = fromOthers.skip(fromOthers.length - unread).toSet();
      _reads[userID] = [
        ...?_reads[userID],
        for (final row in thread)
          if (!unreadIDs.contains(row['id'])) row.text('id'),
      ];
    }
    _actor = 'u1';
    assert(
      tasks.every(
        (row) =>
            row.text('assigneeID') != row.text('reviewerID') &&
            project(row.text('projectID')) != null &&
            row.number('version') > 0,
      ),
    );
  }

  JsonMap _demoMutate(String action, JsonMap payload) {
    final actor = _actor;
    if (actor.isEmpty ||
        user(actor) == null ||
        user(actor)!.text('name') == 'Pengguna dihapus') {
      _demoFail('Masuk terlebih dahulu.');
    }
    final now = _clock().toUtc();
    final stamp = now.toIso8601String();
    switch (action) {
      case 'createGroup':
        final id = _demoID();
        groups.add({
          'id': id,
          'name': _demoText(payload, 'name', 80),
          'description': _demoText(
            payload,
            'description',
            1000,
            required: false,
          ),
          'course': _demoText(payload, 'course', 120, required: false),
          'memberIDs': [actor],
          'coordinatorID': actor,
          'tint': '#DED2FF',
          'icon': 'person.3',
        });
        return {'id': id};
      case 'updateGroup':
        final row = _demoMember(payload.text('id'), coordinator: true);
        row.addAll({
          'name': _demoText(payload, 'name', 80),
          'description': _demoText(
            payload,
            'description',
            1000,
            required: false,
          ),
          'course': _demoText(payload, 'course', 120, required: false),
        });
        return {};
      case 'createProject':
        _demoMember(payload.text('groupID'), coordinator: true);
        final id = _demoID();
        projects.add({
          'id': id,
          'groupID': payload.text('groupID'),
          'title': _demoText(payload, 'title', 120),
          'description': _demoText(
            payload,
            'description',
            2000,
            required: false,
          ),
          'dueAt': _demoDue(payload),
          'status': 'active',
        });
        return {'id': id};
      case 'updateProject':
        final row = _demoProject(payload.text('id'), coordinator: true);
        row.addAll({
          'title': _demoText(payload, 'title', 120),
          'description': _demoText(
            payload,
            'description',
            2000,
            required: false,
          ),
          'dueAt': _demoDue(payload),
        });
        return {};
      case 'completeProject':
      case 'reopenProject':
      case 'archiveProject':
      case 'restoreProject':
        final row = _demoProject(
          payload.text('id'),
          writable: false,
          coordinator: true,
        );
        final status = row.text('status');
        if (action == 'completeProject') {
          final children = tasks.where(
            (task) => task.text('projectID') == row.text('id'),
          );
          if (status != 'active' ||
              children.isEmpty ||
              children.any((task) => task.text('status') != 'done')) {
            _demoFail('Semua tugas harus selesai sebelum proyek diselesaikan.');
          }
          row['status'] = 'completed';
        } else if (action == 'reopenProject') {
          if (status != 'completed') {
            _demoFail('Hanya proyek selesai dapat dibuka kembali.');
          }
          row['status'] = 'active';
        } else if (action == 'archiveProject') {
          if (status == 'archived') _demoFail('Proyek sudah diarsipkan.');
          row['previousStatus'] = status;
          row['status'] = 'archived';
        } else {
          if (status != 'archived') _demoFail('Proyek belum diarsipkan.');
          row['status'] = row['previousStatus'] ?? 'active';
          row['previousStatus'] = null;
        }
        return {};
      case 'createTask':
        final parent = _demoProject(
          payload.text('projectID'),
          coordinator: true,
        );
        _demoAssignment(
          group(parent.text('groupID'))!,
          payload.text('assigneeID'),
          payload.text('reviewerID'),
        );
        final id = _demoID();
        final row = <String, dynamic>{
          'id': id,
          'projectID': parent.text('id'),
          'title': _demoText(payload, 'title', 120),
          'description': _demoText(
            payload,
            'description',
            2000,
            required: false,
          ),
          'assigneeID': payload.text('assigneeID'),
          'reviewerID': payload.text('reviewerID'),
          'dueAt': _demoDue(payload),
          'status': 'todo',
          'version': 1,
          'submissions': <JsonMap>[],
        };
        tasks.add(row);
        _demoActivity(
          row,
          'membuat tugas ini',
          groupText: 'membuat tugas · ${row.text('title')}',
        );
        return {'id': id};
      case 'updateTask':
      case 'reassignTask':
      case 'startTask':
      case 'reopenTask':
      case 'submitWork':
      case 'review':
        final row = task(
          payload.text(
            action == 'submitWork' || action == 'review' ? 'taskID' : 'id',
          ),
        );
        if (row == null) _demoFail('Tugas tidak ditemukan.');
        final parent = _demoProject(row.text('projectID'));
        if (payload['expectedVersion'] is! int ||
            payload['expectedVersion'] != row['version']) {
          _demoFail('Tugas telah berubah. Tutup editor dan coba lagi.');
        }
        final status = row.text('status');
        String system;
        String? activity;
        if (action == 'updateTask' || action == 'reassignTask') {
          final team = _demoMember(parent.text('groupID'), coordinator: true);
          if (!['todo', 'in_progress', 'needs_revision'].contains(status)) {
            _demoFail('Tugas terkunci selama review atau setelah selesai.');
          }
          final assignee = action == 'updateTask'
              ? row.text('assigneeID')
              : payload.text('assigneeID');
          final reviewer = payload.text('reviewerID');
          _demoAssignment(team, assignee, reviewer);
          if (action == 'updateTask') {
            row.addAll({
              'title': _demoText(payload, 'title', 120),
              'description': _demoText(
                payload,
                'description',
                2000,
                required: false,
              ),
              'dueAt': _demoDue(payload),
            });
          } else if (status != 'needs_revision') {
            row['status'] = 'todo';
          }
          row['assigneeID'] = assignee;
          row['reviewerID'] = reviewer;
          system = action == 'updateTask'
              ? 'mengubah detail tugas'
              : 'mengalihkan tugas';
          activity = system;
        } else if (action == 'startTask') {
          if (row.text('assigneeID') != actor ||
              !['todo', 'needs_revision'].contains(status)) {
            _demoFail('Hanya pelaksana yang dapat memulai tugas baru.');
          }
          row['status'] = 'in_progress';
          system = 'mulai mengerjakan';
        } else if (action == 'reopenTask') {
          _demoMember(parent.text('groupID'), coordinator: true);
          if (status != 'done') {
            _demoFail('Hanya tugas selesai yang dapat dibuka kembali.');
          }
          if (row.text('assigneeID').isEmpty ||
              row.text('reviewerID').isEmpty ||
              user(row.text('assigneeID')) == null ||
              user(row.text('reviewerID')) == null) {
            _demoFail(
              'Pelaksana atau reviewer telah menghapus akun. Buat tugas pengganti; riwayat ini tetap disimpan.',
            );
          }
          row['status'] = 'in_progress';
          system = 'membuka kembali tugas';
        } else if (action == 'submitWork') {
          if (row.text('assigneeID') != actor ||
              !['in_progress', 'needs_revision'].contains(status)) {
            _demoFail(
              'Hanya pelaksana dapat mengirim hasil tugas yang sedang dikerjakan.',
            );
          }
          final note = _demoText(payload, 'note', 5000);
          final raw = payload['links'] ?? <String>[];
          if (raw is! List ||
              raw.length > 5 ||
              raw.any((link) => link is! String)) {
            _demoFail('Tautan tidak valid.');
          }
          final links = raw.cast<String>().map((link) => link.trim()).toList();
          if (links.length > 5 ||
              links.any((link) {
                final uri = Uri.tryParse(link);
                final authority = RegExp(
                  r'^https://([^/?#]*)',
                  caseSensitive: false,
                ).firstMatch(link)?.group(1);
                return link.length > 2048 ||
                    authority == null ||
                    authority.contains('@') ||
                    authority.contains('%') ||
                    RegExp(r'\s').hasMatch(link) ||
                    uri == null ||
                    uri.scheme.toLowerCase() != 'https' ||
                    uri.host.isEmpty ||
                    uri.userInfo.isNotEmpty;
              })) {
            _demoFail('Gunakan maksimal 5 tautan HTTPS yang valid.');
          }
          final submissions = List<JsonMap>.from(row['submissions'] as List);
          submissions.add({
            'id': _demoID(),
            'revision': submissions.length + 1,
            'authorID': actor,
            'note': note,
            'links': links,
            'createdAt': stamp,
          });
          row['submissions'] = submissions;
          row['status'] = 'in_review';
          system = 'mengirim revisi ${submissions.length}';
          activity = 'mengirim hasil';
        } else {
          final submissions = List<JsonMap>.from(row['submissions'] as List);
          if (status != 'in_review' ||
              row.text('reviewerID') != actor ||
              row.text('assigneeID') == actor ||
              submissions.isEmpty ||
              submissions.last.text('authorID') == actor ||
              submissions.last['decision'] != null) {
            _demoFail(
              'Review hanya dapat dilakukan reviewer yang bukan pelaksana atau penulis hasil terakhir.',
            );
          }
          if (payload['approve'] is! bool) {
            _demoFail('Keputusan review tidak valid.');
          }
          final approve = payload['approve'] as bool;
          final feedback = _demoText(
            payload,
            'feedback',
            3000,
            required: !approve,
          );
          submissions.last.addAll({
            'decision': approve ? 'approved' : 'changes_requested',
            'feedback': feedback,
            'reviewerID': actor,
          });
          row['submissions'] = submissions;
          row['status'] = approve ? 'done' : 'needs_revision';
          system = approve
              ? 'menyetujui revisi ${submissions.length}'
              : 'meminta revisi';
          activity = approve ? 'menyetujui' : 'meminta revisi';
        }
        row['version'] = row.number('version').toInt() + 1;
        _demoActivity(row, system, groupText: activity);
        return {};
      case 'sendMessage':
      case 'retryMessage':
        final retry =
            action == 'retryMessage' && payload.text('clientID').isEmpty
            ? _find(messages, payload.text('id'))
            : null;
        final groupID = retry?.text('groupID') ?? payload.text('groupID');
        final taskID = retry?['taskID'] ?? payload['taskID'];
        final clientID =
            retry?.text('id') ?? _demoText(payload, 'clientID', 128);
        _demoMember(groupID);
        if (taskID != null && taskID is! String) {
          _demoFail('Diskusi tugas tidak valid.');
        }
        final threadID = taskID == '' ? null : taskID;
        if (threadID != null) {
          final child = task(threadID as String);
          if (child == null ||
              _demoProject(child.text('projectID')).text('groupID') !=
                  groupID) {
            _demoFail('Diskusi tugas tidak ditemukan.');
          }
        }
        final existing = _find(messages, clientID);
        if (existing != null) {
          if (existing.text('senderID') != actor ||
              existing.text('groupID') != groupID ||
              existing['taskID'] != threadID ||
              existing.text('kind') != 'text') {
            _demoFail('Identitas pesan tidak valid.');
          }
          if (existing.text('delivery') == 'failed') {
            existing['delivery'] = simulateSendFailure ? 'failed' : 'sent';
          }
          return {'id': clientID};
        }
        if (messages
                .where(
                  (row) =>
                      row.text('senderID') == actor &&
                      row.text('groupID') == groupID &&
                      row.text('kind') == 'text' &&
                      (row
                              .date('createdAt')
                              ?.isAfter(
                                now.subtract(const Duration(minutes: 1)),
                              ) ??
                          false),
                )
                .length >=
            30) {
          _demoFail('Terlalu banyak pesan. Coba lagi sebentar.');
        }
        messages.add({
          'id': clientID,
          'clientID': clientID,
          'groupID': groupID,
          'taskID': threadID,
          'senderID': actor,
          'text': _demoText(payload, 'text', 2000),
          'createdAt': stamp,
          'kind': 'text',
          'delivery': simulateSendFailure ? 'failed' : 'sent',
          'targetTaskID': null,
        });
        return {'id': clientID};
      case 'markChatRead':
        final groupID = payload.text('groupID');
        _demoMember(groupID);
        final requested = payload['messageIDs'] ?? [];
        if (requested is! List || requested.any((id) => id is! String)) {
          _demoFail('Identitas pesan tidak valid.');
        }
        final read = {...?_reads[actor]};
        for (final row in messages.where(
          (row) => row.text('groupID') == groupID,
        )) {
          if (row['taskID'] == null && requested.contains(row.text('id'))) {
            read.add(row.text('id'));
          }
        }
        _reads[actor] = read.toList();
        return {};
      case 'generateInvite':
        final groupID = payload.text('groupID');
        _demoMember(groupID, coordinator: true);
        if (invites
                .where(
                  (row) =>
                      row.text('groupID') == groupID &&
                      (row
                              .date('createdAt')
                              ?.isAfter(
                                now.subtract(const Duration(minutes: 1)),
                              ) ??
                          false),
                )
                .length >=
            10) {
          _demoFail('Terlalu banyak undangan. Coba lagi sebentar.');
        }
        final id = _demoID();
        final invite = <String, dynamic>{
          'id': id,
          'groupID': groupID,
          'code': '${_demoID()}${_demoID()}'.replaceAll('-', '').toUpperCase(),
          'createdAt': stamp,
          'expiresAt': now.add(const Duration(days: 7)).toIso8601String(),
          'maxUses': 1,
          'useCount': 0,
          'revoked': false,
        };
        invites.add(invite);
        return {'id': id, 'invite': Map<String, dynamic>.from(invite)};
      case 'revokeInvite':
        final invite = _find(invites, payload.text('id'));
        if (invite == null) _demoFail('Undangan tidak ditemukan.');
        _demoMember(invite.text('groupID'), coordinator: true);
        invite['revoked'] = true;
        return {};
      case 'joinGroup':
        final code = _demoText(payload, 'code', 128).toUpperCase();
        final invite = invites
            .where((row) => row.text('code').toUpperCase() == code)
            .firstOrNull;
        if (invite == null ||
            invite['revoked'] == true ||
            !(invite.date('expiresAt')?.isAfter(now) ?? false)) {
          _demoFail('Undangan tidak valid, kedaluwarsa, atau dicabut.');
        }
        final team = group(invite.text('groupID'));
        if (team == null) _demoFail('Grup tidak ditemukan.');
        final members = team.ids('memberIDs');
        if (members.contains(actor)) return {'id': team.text('id')};
        if (invite.number('useCount') >= invite.number('maxUses')) {
          _demoFail('Undangan sudah digunakan.');
        }
        if (members.length >= 8) {
          _demoFail('Grup sudah mencapai batas 8 anggota.');
        }
        team['memberIDs'] = [...members, actor];
        invite['useCount'] = invite.number('useCount').toInt() + 1;
        return {'id': team.text('id')};
      case 'transferCoordinator':
        final team = _demoMember(payload.text('groupID'), coordinator: true);
        final target = payload.text('to');
        if (target == actor ||
            !team.ids('memberIDs').contains(target) ||
            user(target) == null) {
          _demoFail('Pilih anggota lain sebagai koordinator.');
        }
        team['coordinatorID'] = target;
        return {};
      case 'removeMember':
      case 'leaveGroup':
        final groupID = payload.text(action == 'leaveGroup' ? 'id' : 'groupID');
        final team = _demoMember(
          groupID,
          coordinator: action == 'removeMember',
        );
        final target = action == 'leaveGroup' ? actor : payload.text('userID');
        if (!team.ids('memberIDs').contains(target)) {
          _demoFail('Anggota tidak ditemukan.');
        }
        if (team.text('coordinatorID') == target) {
          _demoFail('Serahkan peran koordinator sebelum keluar.');
        }
        _demoNoAssignments(target, groupID: groupID);
        team['memberIDs'] = team
            .ids('memberIDs')
            .where((id) => id != target)
            .toList();
        return {};
      case 'updateProfile':
        user(actor)!['name'] = _demoText(payload, 'name', 80);
        return {};
      case 'blockUser':
      case 'unblockUser':
        final target = _demoText(payload, 'id', 128);
        if (target == actor) _demoFail('Pengguna tidak valid.');
        if (action == 'blockUser') {
          if (user(target) == null ||
              !groups.any(
                (row) =>
                    row.ids('memberIDs').contains(actor) &&
                    row.ids('memberIDs').contains(target),
              )) {
            _demoFail('Pengguna tidak valid.');
          }
          _blocks[actor] = {...?_blocks[actor], target}.toList();
        } else {
          _blocks[actor] = (_blocks[actor] ?? [])
              .where((id) => id != target)
              .toList();
        }
        return {};
      case 'reportMessage':
        final reason = _demoText(payload, 'reason', 1000);
        final message = _find(messages, payload.text('id'));
        if (message == null || message.text('senderID') == actor) {
          _demoFail('Pesan tidak dapat dilaporkan.');
        }
        _demoMember(message.text('groupID'));
        final existing = reports
            .where(
              (row) =>
                  row.text('reporterID') == actor &&
                  row.text('messageID') == message.text('id'),
            )
            .firstOrNull;
        if (existing != null) return {'id': existing.text('id')};
        if (reports
                .where(
                  (row) =>
                      row.text('reporterID') == actor &&
                      (row
                              .date('createdAt')
                              ?.isAfter(
                                now.subtract(const Duration(minutes: 1)),
                              ) ??
                          false),
                )
                .length >=
            5) {
          _demoFail('Terlalu banyak laporan. Coba lagi sebentar.');
        }
        final id = _demoID();
        reports.add({
          'id': id,
          'messageID': message.text('id'),
          'reporterID': actor,
          'reason': reason,
          'createdAt': stamp,
          'status': 'pending',
          'reviewedAt': null,
        });
        return {'id': id};
      case 'deleteAccount':
        if (payload.isNotEmpty) _demoFail('Permintaan hapus akun tidak valid.');
        if (groups.any(
          (row) =>
              row.text('coordinatorID') == actor &&
              row.ids('memberIDs').any((id) => id != actor),
        )) {
          _demoFail('Serahkan semua peran koordinator sebelum menghapus akun.');
        }
        _demoNoAssignments(actor);
        for (final team in groups) {
          if (team.text('coordinatorID') == actor) {
            for (final invite in invites.where(
              (row) => row.text('groupID') == team.text('id'),
            )) {
              invite['revoked'] = true;
            }
            team['coordinatorID'] = '';
          }
          team['memberIDs'] = team
              .ids('memberIDs')
              .where((id) => id != actor)
              .toList();
        }
        for (final row in tasks) {
          for (final field in ['assigneeID', 'reviewerID']) {
            if (row[field] == actor) row[field] = '';
          }
          for (final submission in row['submissions'] as List) {
            if (submission['authorID'] == actor) submission['authorID'] = '';
            if (submission['reviewerID'] == actor) {
              submission['reviewerID'] = null;
            }
          }
        }
        for (final message in messages.where(
          (row) => row.text('senderID') == actor,
        )) {
          message['senderID'] = '';
          message['clientID'] = null;
        }
        for (final report in reports.where(
          (row) => row.text('reporterID') == actor,
        )) {
          report['reporterID'] = '';
          report['reason'] = '[Pelapor terhapus]';
        }
        users.removeWhere((row) => row.text('id') == actor);
        _reads.remove(actor);
        _blocks.remove(actor);
        for (final blocked in _blocks.values) {
          blocked.removeWhere((id) => id == actor);
        }
        _actor = '';
        return {'deleted': true};
      default:
        _demoFail('Tindakan tidak dikenal: $action.');
    }
  }
}
