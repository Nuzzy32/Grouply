import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:grouply/core/backend.dart';
import 'package:grouply/core/store.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;

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
    _seedTemplates();
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
      reports = [],
      organizations = [],
      meetings = [],
      approvals = [],
      announcements = [],
      templateRows = [],
      planItems = [],
      periods = [],
      templateUses = [];
  String _actor = '';
  Map<String, List<String>> _blocks = {}, _reads = {};
  final _taskBatchReceipts = <(String, String, String), (String, JsonMap)>{};
  bool taskBatchAvailable = true;

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
    'taskBatchAvailable': taskBatchAvailable,
    'meetingFollowUpsAvailable': true,
    'users': _copy(users),
    'groups': [
      for (final row in _copy(groups) as List)
        {...row as JsonMap, 'closed': row['closedAt'] != null}
          ..remove('closedAt'),
    ],
    'projects': _snapshotProjects(),
    'tasks': _copy(tasks),
    'messages': _copy(messages),
    'invites': _copy(invites),
    'reports': _copy(reports),
    'organizations': _snapshotOrganizations(),
    'meetings': _snapshotMeetings(),
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
      'organizations': organizations,
      'meetings': meetings,
      'approvals': approvals,
      'announcements': announcements,
      'templates': templateRows,
      'planItems': planItems,
      'periods': periods,
      'templateUses': templateUses,
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
      organizations = rows('organizations');
      meetings = rows('meetings');
      approvals = rows('approvals');
      announcements = rows('announcements');
      templateRows = rows('templates');
      planItems = rows('planItems');
      periods = rows('periods');
      templateUses = rows('templateUses');
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
    if (!_closedAllowed.contains(action) &&
        group(_targetGroup(action, payload))?['closedAt'] != null) {
      throw _code('group_closed');
    }
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
          // A project labelled by a closed period stays in that archive.
          if (row['periodID'] != null) throw _code('project_read_only');
          row['status'] = row['previousStatus'] ?? 'active';
          row['previousStatus'] = null;
        }
        return {};
      case 'publishTaskBatch':
        final parent = _demoProject(payload.text('projectID'));
        final team = group(parent.text('groupID'))!;
        final batch = payload['tasks'];
        if (batch is! List ||
            batch.isEmpty ||
            batch.length > 20 ||
            payload.text('requestID').isEmpty) {
          throw _code('invalid_input');
        }
        final key = (actor, parent.text('id'), payload.text('requestID'));
        final encoded = jsonEncode(batch);
        final receipt = _taskBatchReceipts[key];
        if (receipt != null) {
          if (receipt.$1 != encoded) throw _code('invalid_input');
          return receipt.$2;
        }
        _demoTaskManager(parent);
        if (!_planActive(_orgOf(team))) throw _code('plan_inactive');
        final result = {
          'ids': [
            for (final item in batch)
              _demoMutate('createTask', {
                ...item as JsonMap,
                'projectID': parent.text('id'),
              }).text('id'),
          ],
        };
        _taskBatchReceipts[key] = (encoded, result);
        return result;
      case 'addMeetingFollowUp':
      case 'publishMeetingFollowUp':
        final mid = payload.text('meetingID');
        final meeting = _find(meetings, mid);
        if (meeting == null) throw _code('forbidden');
        final groupID = meeting.text('groupID');
        final team = _demoMember(groupID);
        final rows = (meeting['followUps'] as List? ?? []).cast<JsonMap>();
        final adding = action == 'addMeetingFollowUp';
        final id = payload.text(adding ? 'requestID' : 'followUpID');
        final row = _find(rows, id);
        if (!adding && row == null) throw _code('invalid_input');
        if (!adding && row!.text('taskID').isNotEmpty) {
          return {'id': row.text('taskID')};
        }
        if (meeting.text('status') != 'done') throw _code('meeting_closed');
        if (!_planActive(_orgOf(team))) throw _code('plan_inactive');
        if (adding) {
          if (id.isEmpty ||
              !team.ids('memberIDs').contains(payload.text('assigneeID'))) {
            throw _code('invalid_input');
          }
          if (team.text('coordinatorID') != actor &&
              meeting.text('noteTakerID') != actor) {
            throw _code('forbidden');
          }
          if (row != null) return {'id': id};
          rows.add({
            'id': id,
            'title': _input(payload, 'title', 120),
            'assigneeID': payload.text('assigneeID'),
            'dueAt': _demoDue(payload),
            'taskID': null,
          });
          meeting['followUps'] = rows;
        } else {
          final target = _demoProject(payload.text('projectID'));
          if (target.text('groupID') != groupID) throw _code('forbidden');
          row!['taskID'] = _demoMutate('createTask', {
            ...row,
            'projectID': payload.text('projectID'),
            'reviewerID': payload.text('reviewerID'),
            'meetingID': mid,
          }).text('id');
        }
        meeting['version'] = meeting.number('version').toInt() + 1;
        return {'id': adding ? id : row!.text('taskID')};
      case 'createTask':
        final parent = _demoProject(payload.text('projectID'));
        _demoTaskManager(parent);
        final meetingID = payload['meetingID'];
        if (meetingID != null) {
          final source = meetingID is String
              ? _find(meetings, meetingID)
              : null;
          if (source == null ||
              source.text('groupID') != parent.text('groupID') ||
              source.text('status') == 'cancelled') {
            throw _code('invalid_input');
          }
        }
        _demoAssignment(
          group(parent.text('groupID'))!,
          payload.text('assigneeID'),
          payload.text('reviewerID'),
        );
        final itemID = payload['planItemID'];
        JsonMap? item;
        if (itemID != null) {
          item = itemID is String ? _find(planItems, itemID) : null;
          if (item == null || item['projectID'] != parent['id']) {
            throw _code('invalid_input');
          }
          if (item['taskID'] != null) throw _code('plan_item_used');
        }
        final id = _demoID();
        item?['taskID'] = id;
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
          'meetingID': ?meetingID,
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
          final team = _demoTaskManager(parent);
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
          _demoTaskManager(parent);
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
          final links = _httpsLinks(raw);
          if (links == null) {
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
        final active = _activeOrg(_demoMember(groupID, coordinator: true));
        final uses = payload['maxUses'];
        if (uses != null &&
            (uses is! int || uses < 1 || uses > (active ? 200 : 1))) {
          throw _code('invalid_input');
        }
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
          'maxUses': uses ?? 1,
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
        final active = _activeOrg(team);
        // Multi-use codes count as single-use once the plan has lapsed.
        if (invite.number('useCount') >=
            (active ? invite.number('maxUses') : 1)) {
          _demoFail('Undangan sudah digunakan.');
        }
        if (active) {
          final org = _find(organizations, team.text('organizationID'))!;
          final seats = _orgMembers(org.text('id'));
          if (!seats.contains(actor) &&
              seats.length >= org.number('seatLimit')) {
            throw _code('org_full');
          }
          if (members.length >= 200) throw _code('group_full');
        } else if (members.length >= 8) {
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
        _afterLeave(target, team);
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
          'kind': 'message',
          'targetID': message.text('id'),
          'reporterID': actor,
          'reason': reason,
          'createdAt': stamp,
          'status': 'pending',
          'reviewedAt': null,
        });
        return {'id': id};
      case 'reportContent':
        final reason = _demoText(payload, 'reason', 1000);
        final kind = payload.text('kind'), target = payload.text('id');
        final allowed = switch (kind) {
          'announcement' => switch (_find(announcements, target)) {
            final row? =>
              row['authorID'] != actor && _audience(row).contains(actor),
            null => false,
          },
          'meeting' => switch (_find(meetings, target)) {
            final row? =>
              group(row.text('groupID'))?.ids('memberIDs').contains(actor) ??
                  false,
            null => false,
          },
          'approval' => switch (_find(approvals, target)) {
            final row? => row['requesterID'] != actor && _seesApproval(row),
            null => false,
          },
          'template' => switch (_find(templateRows, target)) {
            final row? =>
              row['organizationID'] != null &&
                  row['createdBy'] != actor &&
                  _orgMembers(row.text('organizationID')).contains(actor),
            null => false,
          },
          _ => throw _code('invalid_input'),
        };
        if (!allowed) throw _code('forbidden');
        final existing = reports
            .where(
              (row) =>
                  row.text('reporterID') == actor &&
                  row['kind'] == kind &&
                  row['targetID'] == target,
            )
            .firstOrNull;
        if (existing != null) return {'id': existing.text('id')};
        final id = _demoID();
        reports.add({
          'id': id,
          'messageID': '',
          'kind': kind,
          'targetID': target,
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
          final member = team.ids('memberIDs').contains(actor);
          team['memberIDs'] = team
              .ids('memberIDs')
              .where((id) => id != actor)
              .toList();
          if (member) _afterLeave(actor, team);
        }
        // Tahap 2 actor columns are SET NULL; attendance and reads cascade.
        for (final row in approvals) {
          if (row['requesterID'] == actor) row['requesterID'] = '';
          for (final step in (row['steps'] as List).cast<JsonMap>()) {
            if (step['approverID'] == actor) step['approverID'] = '';
          }
        }
        for (final row in announcements) {
          if (row['authorID'] == actor) row['authorID'] = '';
          (row['reads'] as List).remove(actor);
        }
        for (final row in meetings) {
          if (row['createdBy'] == actor) row['createdBy'] = '';
          (row['attendance'] as Map).remove(actor);
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
      case 'createOrganization':
      case 'updateOrganization':
      case 'createDivision':
      case 'setOrgRole':
      case 'transferKetua':
        return _orgMutate(action, payload);
      case 'setProjectLead':
      case 'createMeeting':
      case 'updateMeeting':
      case 'cancelMeeting':
      case 'recordMeeting':
      case 'requestApproval':
      case 'decideApproval':
      case 'cancelApproval':
      case 'postAnnouncement':
      case 'deleteAnnouncement':
      case 'markAnnouncementRead':
        return _workMutate(action, payload);
      case 'applyTemplate':
      case 'createTemplate':
      case 'deleteTemplate':
      case 'deletePlanItem':
      case 'closeCommittee':
      case 'reopenCommittee':
      case 'setCoordinator':
      case 'removeClosedMember':
      case 'closePeriod':
        return _planMutate(action, payload);
      default:
        _demoFail('Tindakan tidak dikenal: $action.');
    }
  }

  // MARK: - Organization Plan (docs/DESIGN-org-tahap1.md §4)
  // Rows: {id, name, description, periodLabel, seatLimit, planExpiresAt,
  // roles: {userID: ketua|bph|pembina}}. Server codes surface as P0001.

  static PostgrestException _code(String code) =>
      PostgrestException(message: code, code: 'P0001');

  List<JsonMap> _divisions(String orgID) => groups
      .where(
        (row) =>
            row.text('organizationID') == orgID &&
            row.ids('memberIDs').isNotEmpty,
      )
      .toList();

  Set<String> _orgMembers(String orgID) => {
    for (final row in _divisions(orgID)) ...row.ids('memberIDs'),
  };

  Map<String, String> _roles(JsonMap org) =>
      (org['roles'] as Map).cast<String, String>();

  bool _planActive(JsonMap org) =>
      org.date('planExpiresAt')?.isAfter(_clock()) ?? false;

  bool _activeOrg(JsonMap group) {
    final org = _find(organizations, group.text('organizationID'));
    return org != null && _planActive(org);
  }

  /// Operator activation (`grouply_billing activatePlan`).
  void activatePlan(String orgID, {int seats = 150, DateTime? until}) {
    _find(organizations, orgID)!
      ..['seatLimit'] = seats
      ..['planExpiresAt'] = (until ?? _clock().add(const Duration(days: 300)))
          .toUtc()
          .toIso8601String();
  }

  /// Test fixture: the seed groups become divisions of "BEM FST" (u1 ketua,
  /// u3 BPH, u7 pembina). g3, which u1 is not in, gets an overdue task.
  void seedOrganization({bool active = true}) {
    organizations.add({
      'id': 'o1',
      'name': 'BEM FST',
      'description': 'Badan Eksekutif Mahasiswa Fakultas Sains dan Teknologi.',
      'periodLabel': '2026/2027',
      'seatLimit': 0,
      'planExpiresAt': null,
      'roles': {'u1': 'ketua', 'u3': 'bph', 'u7': 'pembina'},
    });
    if (active) activatePlan('o1', seats: 120);
    for (final row in groups) {
      row['organizationID'] = 'o1';
    }
    final due = _clock().subtract(const Duration(days: 2)).toUtc();
    projects.add({
      'id': 'p9',
      'groupID': 'g3',
      'title': 'Survei Kebiasaan Belajar',
      'description': 'Survei 100 responden.',
      'dueAt': due.add(const Duration(days: 30)).toIso8601String(),
      'status': 'active',
    });
    tasks.add({
      'id': 't90',
      'projectID': 'p9',
      'title': 'Sebar kuesioner',
      'description': 'Sebar ke 100 responden.',
      'assigneeID': 'u7',
      'reviewerID': 'u6',
      'dueAt': due.toIso8601String(),
      'status': 'in_progress',
      'version': 1,
      'submissions': <JsonMap>[],
    });
  }

  List<JsonMap> _snapshotOrganizations() => [
    for (final org in organizations)
      if (_orgMembers(org.text('id')).contains(_actor))
        {
          'id': org['id'],
          'name': org['name'],
          'description': org['description'],
          'periodLabel': org['periodLabel'],
          'planActive': _planActive(org),
          'planExpiresAt': org['planExpiresAt'],
          'seatLimit': org['seatLimit'],
          'seatsUsed': _orgMembers(org.text('id')).length,
          'myRole': _roles(org)[_actor],
          'roles': [
            for (final MapEntry(key: id, value: role) in _roles(org).entries)
              {
                'userID': id,
                'name': user(id)?.text('name') ?? 'Anggota',
                'role': role,
              },
          ],
          'divisions': [
            for (final row in _divisions(org.text('id')))
              {
                'id': row['id'],
                'name': row['name'],
                'memberCount': row.ids('memberIDs').length,
                'isMember': row.ids('memberIDs').contains(_actor),
                'isCommittee': row['isCommittee'] == true,
                'closed': row['closedAt'] != null,
              },
          ],
          'periods': [
            for (final row in _orgPeriods(org.text('id')))
              {
                'id': row['id'],
                'label': row['label'],
                'startedAt': row['startedAt'],
                'closedAt': row['closedAt'],
              },
          ],
          'approvals': _snapshotApprovals(org),
          'announcements': _snapshotAnnouncements(org),
        },
  ];

  JsonMap _division(String orgID, String name) {
    final id = _demoID();
    groups.add({
      'id': id,
      'name': name,
      'description': '',
      'course': '',
      'memberIDs': [_actor],
      'coordinatorID': _actor,
      'tint': '#DED2FF',
      'icon': 'person.3',
      'organizationID': orgID,
    });
    return {'id': id};
  }

  JsonMap _orgMutate(String action, JsonMap payload) {
    final actor = _actor;
    int ketuaCount(String id) =>
        organizations.where((org) => _roles(org)[id] == 'ketua').length;
    if (action == 'createOrganization') {
      if (ketuaCount(actor) >= 3) throw _code('rate_limited');
      final id = _demoID();
      organizations.add({
        'id': id,
        'name': _demoText(payload, 'name', 80),
        'description': _demoText(payload, 'description', 1000, required: false),
        'periodLabel': _demoText(payload, 'periodLabel', 40, required: false),
        'seatLimit': 0,
        'planExpiresAt': null,
        'roles': {actor: 'ketua'},
      });
      final division = payload.text('divisionName').trim();
      return {
        'id': id,
        'groupID': _division(
          id,
          division.isEmpty ? 'BPH Inti' : division,
        )['id'],
      };
    }
    final orgID = payload.text(
      action == 'updateOrganization' ? 'id' : 'organizationID',
    );
    final org = _find(organizations, orgID);
    if (org == null || !_orgMembers(orgID).contains(actor)) {
      throw _code('forbidden');
    }
    final roles = _roles(org);
    final allowed = action == 'createDivision'
        ? ['ketua', 'bph'].contains(roles[actor])
        : roles[actor] == 'ketua';
    if (!allowed) throw _code('forbidden');
    switch (action) {
      case 'updateOrganization':
        if (periods.any(
          (row) =>
              row['organizationID'] == orgID &&
              row['label'] == payload.text('periodLabel').trim(),
        )) {
          throw _code('period_exists');
        }
        org.addAll({
          'name': _demoText(payload, 'name', 80),
          'description': _demoText(
            payload,
            'description',
            1000,
            required: false,
          ),
          'periodLabel': _demoText(payload, 'periodLabel', 40, required: false),
        });
        return {};
      case 'createDivision':
        final committee = payload['committee'] ?? false;
        if (committee is! bool) throw _code('invalid_input');
        if (!_planActive(org)) throw _code('plan_inactive');
        // Divisions and committees each have their own cap of 30; closed
        // committees do not count (Tahap 3 §4.1).
        if (_divisions(orgID)
                .where(
                  (row) =>
                      (row['isCommittee'] == true) == committee &&
                      row['closedAt'] == null,
                )
                .length >=
            30) {
          throw _code('invalid_input');
        }
        final created = _division(orgID, _demoText(payload, 'name', 80));
        group(created.text('id'))!['isCommittee'] = committee;
        return created;
      default: // setOrgRole, transferKetua
        final target = payload.text('userID');
        final role = payload['role'];
        if (target == actor ||
            !_orgMembers(orgID).contains(target) ||
            (action == 'setOrgRole' &&
                role != null &&
                role != 'bph' &&
                role != 'pembina')) {
          throw _code('invalid_input');
        }
        if (action == 'transferKetua') {
          if (ketuaCount(target) >= 3) throw _code('rate_limited');
          roles[actor] = 'bph';
          roles[target] = 'ketua';
        } else if (role == null) {
          roles.remove(target);
        } else {
          roles[target] = role as String;
        }
        return {};
    }
  }

  /// Port of `grouply_org_overview` (design §4.5) over the local rows.
  @override
  Future<JsonMap> orgOverview(String id) async {
    final org = _find(organizations, id);
    if (org == null ||
        !_orgMembers(id).contains(_actor) ||
        _roles(org)[_actor] == null) {
      throw _code('forbidden');
    }
    if (!_planActive(org)) throw _code('plan_inactive');
    final now = _clock();
    const stale = Duration(hours: 48);
    final attention = <(int, DateTime, JsonMap)>[];
    final people = <String>{};
    JsonMap row(JsonMap task, JsonMap division, String reason, Duration age) {
      people.add(task.text('assigneeID'));
      return {
        'taskID': task['id'],
        'title': task['title'],
        'divisionID': division['id'],
        'projectID': task['projectID'],
        'assigneeID': task['assigneeID'],
        'status': task['status'],
        'dueAt': task['dueAt'],
        'reason': reason,
        'hours': age.inHours,
      };
    }

    final divisions = [
      for (final division in _divisions(id))
        if (division['closedAt'] == null)
          {
            'id': division['id'],
            'name': division['name'],
            'isCommittee': division['isCommittee'] == true,
            'coordinatorID': division.text('coordinatorID'),
            'memberCount': division.ids('memberIDs').length,
            'projects': [
              for (final project in projects.where(
                (p) =>
                    p['groupID'] == division['id'] && p['status'] == 'active',
              ))
                () {
                  final list = tasks
                      .where((t) => t['projectID'] == project['id'])
                      .toList();
                  var overdue = 0, idle = 0, pending = 0;
                  for (final task in list) {
                    final status = task.text('status');
                    final due = task.date('dueAt');
                    final submitted = _submissions(task).lastOrNull;
                    final last =
                        [
                          for (final s in _submissions(task))
                            s.date('createdAt'),
                          for (final m in messages)
                            if (m['taskID'] == task['id']) m.date('createdAt'),
                        ].nonNulls.fold<DateTime?>(
                          null,
                          (a, b) => a == null || b.isAfter(a) ? b : a,
                        );
                    final late = status != 'done' && due!.isBefore(now);
                    final review =
                        status == 'in_review' &&
                        submitted != null &&
                        now.difference(submitted.date('createdAt')!) > stale;
                    final quiet =
                        [
                          'todo',
                          'in_progress',
                          'needs_revision',
                        ].contains(status) &&
                        last != null &&
                        now.difference(last) > stale;
                    if (late) overdue++;
                    if (review) pending++;
                    if (quiet) idle++;
                    // One row per task, by priority: overdue, review, idle.
                    if (late) {
                      attention.add((
                        0,
                        due,
                        row(task, division, 'overdue', now.difference(due)),
                      ));
                    } else if (review) {
                      final at = submitted.date('createdAt')!;
                      attention.add((
                        1,
                        at,
                        row(
                          task,
                          division,
                          'review_pending',
                          now.difference(at),
                        ),
                      ));
                    } else if (quiet) {
                      attention.add((
                        2,
                        last,
                        row(task, division, 'idle', now.difference(last)),
                      ));
                    }
                  }
                  return {
                    'id': project['id'],
                    'title': project['title'],
                    'dueAt': project['dueAt'],
                    'total': list.length,
                    'done': list.where((t) => t['status'] == 'done').length,
                    'inReview': list
                        .where((t) => t['status'] == 'in_review')
                        .length,
                    'overdue': overdue,
                    'idle': idle,
                    'reviewPending': pending,
                  };
                }(),
            ],
          },
    ];
    attention.sort((a, b) => a.$1 != b.$1 ? a.$1 - b.$1 : a.$2.compareTo(b.$2));
    people.addAll(divisions.map((d) => d['coordinatorID'] as String));
    return _copy({
          'generatedAt': now.toUtc().toIso8601String(),
          'divisions': divisions,
          'attention': [for (final item in attention.take(50)) item.$3],
          'users': [
            for (final id in people)
              if (user(id) case final person?)
                {'id': id, 'name': person['name'], 'tint': person['tint']},
          ],
        })
        as JsonMap;
  }

  /// `private.valid_links`: at most 5 trimmed HTTPS links; null if invalid.
  static List<String>? _httpsLinks(Object? raw) {
    if (raw is! List || raw.length > 5 || raw.any((link) => link is! String)) {
      return null;
    }
    final links = raw.cast<String>().map((link) => link.trim()).toList();
    final valid = links.every((link) {
      final uri = Uri.tryParse(link);
      final authority = RegExp(
        r'^https://([^/?#]*)',
        caseSensitive: false,
      ).firstMatch(link)?.group(1);
      return link.length <= 2048 &&
          authority != null &&
          !authority.contains('@') &&
          !authority.contains('%') &&
          !RegExp(r'\s').hasMatch(link) &&
          uri != null &&
          uri.scheme.toLowerCase() == 'https' &&
          uri.host.isNotEmpty &&
          uri.userInfo.isEmpty;
    });
    return valid ? links : null;
  }

  // MARK: - Organization Plan Tahap 2 (docs/DESIGN-org-tahap2.md §3–4)
  // meetings: {id, groupID, createdBy, noteTakerID, title, startsAt, place,
  //   agenda, minutes, status, version, attendance: {userID: hadir|izin}}
  // approvals: {id, organizationID, groupID, requesterID, title, note, amount,
  //   links, status, createdAt, closedAt, steps: [{position, approverID,
  //   decision, note, decidedAt}]}
  // announcements: {id, organizationID, groupID ('' = whole org), authorID,
  //   title, body, createdAt, reads: [userID]}

  /// Coordinator of the project's group or its koordinator sie (§4.2).
  JsonMap _demoTaskManager(JsonMap project) {
    final team = _demoMember(project.text('groupID'));
    if (team.text('coordinatorID') != _actor &&
        project.text('leadID') != _actor) {
      throw _code('forbidden');
    }
    return team;
  }

  /// `group_members_org_guard` (§4.4) after [userID] left [team].
  void _afterLeave(String userID, JsonMap team) {
    for (final row in projects) {
      if (row['groupID'] == team['id'] && row['leadID'] == userID) {
        row['leadID'] = '';
      }
    }
    for (final row in meetings) {
      if (row['groupID'] == team['id'] && row['noteTakerID'] == userID) {
        row['noteTakerID'] = '';
      }
    }
    final orgID = team.text('organizationID');
    if (orgID.isEmpty || _orgMembers(orgID).contains(userID)) return;
    for (final row in approvals) {
      if (row['organizationID'] == orgID &&
          row['status'] == 'pending' &&
          (row['requesterID'] == userID ||
              _steps(row).any(
                (step) =>
                    step['approverID'] == userID && step['decision'] == null,
              ))) {
        row['status'] = 'lapsed';
        row['closedAt'] = _clock().toUtc().toIso8601String();
      }
    }
  }

  static List<JsonMap> _steps(JsonMap approval) =>
      (approval['steps'] as List).cast<JsonMap>();

  String _name(String id) => id.isEmpty || (_blocks[_actor] ?? []).contains(id)
      ? 'Anggota'
      : user(id)?.text('name') ?? 'Anggota';

  bool _officer(JsonMap org, String id) => _roles(org)[id] != null;

  /// Approver still entitled to decide: org officer or origin coordinator.
  bool _eligible(JsonMap approval, String id) {
    final org = _find(organizations, approval.text('organizationID'))!;
    return id.isNotEmpty &&
        (_officer(org, id) ||
            group(approval.text('groupID'))?.text('coordinatorID') == id);
  }

  bool _seesApproval(JsonMap approval) {
    final org = _find(organizations, approval.text('organizationID'))!;
    return approval['requesterID'] == _actor ||
        (_officer(org, _actor) &&
            _orgMembers(org.text('id')).contains(_actor)) ||
        group(approval.text('groupID'))?.text('coordinatorID') == _actor;
  }

  /// Current recipients of an announcement.
  Set<String> _audience(JsonMap row) {
    final groupID = row.text('groupID');
    return groupID.isEmpty
        ? _orgMembers(row.text('organizationID'))
        : {...?group(groupID)?.ids('memberIDs')};
  }

  List<JsonMap> _snapshotApprovals(JsonMap org) {
    final visible = approvals
        .where(
          (row) => row['organizationID'] == org['id'] && _seesApproval(row),
        )
        .toList();
    final pending = visible.where((row) => row['status'] == 'pending').toList()
      ..sort((a, b) => a.text('createdAt').compareTo(b.text('createdAt')));
    final closed = visible.where((row) => row['status'] != 'pending').toList()
      ..sort((a, b) => b.text('closedAt').compareTo(a.text('closedAt')));
    return [
      for (final row in [...pending.take(100), ...closed.take(30)])
        {
          'id': row['id'],
          'groupID': row['groupID'],
          'groupName': group(row.text('groupID'))?.text('name') ?? 'Grup',
          'title': row['title'],
          'note': row['note'],
          'amount': row['amount'],
          'links': row['links'],
          'status': row['status'],
          'createdAt': row['createdAt'],
          'closedAt': row['closedAt'],
          'requesterID': row['requesterID'],
          'requesterName': _name(row.text('requesterID')),
          'steps': [
            for (final step in _steps(row))
              {
                'position': step['position'],
                'approverID': step['approverID'],
                'name': _name(step.text('approverID')),
                'eligible': _eligible(row, step.text('approverID')),
                'decision': step['decision'],
                'note': step['note'],
                'decidedAt': step['decidedAt'],
              },
          ],
        },
    ];
  }

  List<JsonMap> _snapshotAnnouncements(JsonMap org) {
    final orgID = org.text('id');
    final mine =
        announcements
            .where(
              (row) =>
                  row['organizationID'] == orgID &&
                  _audience(row).contains(_actor),
            )
            .toList()
          ..sort((a, b) => b.text('createdAt').compareTo(a.text('createdAt')));
    final coordinator = _divisions(
      orgID,
    ).any((row) => row['coordinatorID'] == _actor);
    final peers = {
      for (final row in groups)
        if (row.ids('memberIDs').contains(_actor)) ...row.ids('memberIDs'),
    }..remove(_actor);
    return [
      for (final row in mine.take(30))
        () {
          final author = row.text('authorID');
          final reads = (row['reads'] as List).cast<String>();
          // Like the server, the author is a recipient (and has read it).
          final audience = _audience(row);
          final counts = author == _actor || _officer(org, _actor);
          return {
            'id': row['id'],
            'groupID': row['groupID'],
            'title': row['title'],
            'body': row['body'],
            'createdAt': row['createdAt'],
            'authorID': author,
            'authorName': _name(author),
            'read': reads.contains(_actor),
            'readCount': counts ? audience.where(reads.contains).length : 0,
            'audienceCount': counts ? audience.length : 0,
            'unreadIDs': counts || coordinator
                ? [
                    for (final id in audience)
                      if (!reads.contains(id) && peers.contains(id)) id,
                  ]
                : <String>[],
          };
        }(),
    ];
  }

  List<JsonMap> _snapshotMeetings() {
    final cutoff = _clock().subtract(const Duration(days: 30));
    final mine =
        meetings
            .where(
              (row) =>
                  group(
                    row.text('groupID'),
                  )?.ids('memberIDs').contains(_actor) ??
                  false,
            )
            .toList()
          ..sort((a, b) => b.text('startsAt').compareTo(a.text('startsAt')));
    final recent = mine.where((row) => row.date('startsAt')!.isAfter(cutoff));
    final older = mine.where((row) => !row.date('startsAt')!.isAfter(cutoff));
    return [
      for (final row in [...recent, ...older.take(100)])
        () {
          final attendance = (row['attendance'] as Map).cast<String, String>();
          return {
            'id': row['id'],
            'groupID': row['groupID'],
            'title': row['title'],
            'startsAt': row['startsAt'],
            'place': row['place'],
            'status': row['status'],
            'version': row['version'],
            'createdBy': row['createdBy'],
            'noteTakerID': row['noteTakerID'],
            'hasMinutes': row.text('minutes').isNotEmpty,
            'present': attendance.values.where((s) => s == 'hadir').length,
            'excused': attendance.values.where((s) => s == 'izin').length,
            'myStatus': attendance[_actor] ?? '',
            'taskIDs': [
              for (final task in tasks)
                if (task['meetingID'] == row['id']) task['id'],
            ],
          };
        }(),
    ];
  }

  /// When set, `meetingDetail` waits for it (slow network in widget tests).
  Completer<void>? meetingGate;

  @override
  Future<JsonMap> meetingDetail(String id) async {
    await meetingGate?.future;
    final row = _find(meetings, id);
    if (row == null ||
        !(group(row.text('groupID'))?.ids('memberIDs').contains(_actor) ??
            false)) {
      throw _code('forbidden');
    }
    return _copy({
          'id': row['id'],
          'version': row['version'],
          'agenda': row['agenda'],
          'minutes': row['minutes'],
          'followUps': row['followUps'] ?? [],
          'attendance': [
            for (final MapEntry(key: userID, value: status)
                in (row['attendance'] as Map).entries)
              {'userID': userID, 'status': status},
          ],
        })
        as JsonMap;
  }

  /// Text field checked like the server: wrong type or length → invalid_input.
  String _input(JsonMap payload, String key, int max, {int min = 1}) {
    final raw = payload[key] ?? '';
    if (raw is! String) throw _code('invalid_input');
    final value = raw.trim();
    if (value.runes.length < min || value.runes.length > max) {
      throw _code('invalid_input');
    }
    return value;
  }

  void _groupActivity(String groupID, String text) => messages.add({
    'id': _demoID(),
    'groupID': groupID,
    'taskID': null,
    'senderID': _actor,
    'text': text,
    'createdAt': _clock().toUtc().toIso8601String(),
    'kind': 'activity',
    'delivery': 'sent',
    'targetTaskID': null,
  });

  /// Member of [groupID] (and its coordinator when [coordinator]); else forbidden.
  JsonMap _orgWorkGroup(String groupID, {bool coordinator = false}) {
    final team = group(groupID);
    if (team == null ||
        !team.ids('memberIDs').contains(_actor) ||
        (coordinator && team.text('coordinatorID') != _actor)) {
      throw _code('forbidden');
    }
    return team;
  }

  /// Organization of [team]; a plain group → invalid_input.
  JsonMap _orgOf(JsonMap team) =>
      _find(organizations, team.text('organizationID')) ??
      (throw _code('invalid_input'));

  JsonMap _workMutate(String action, JsonMap payload) {
    final actor = _actor;
    final now = _clock().toUtc();
    final stamp = now.toIso8601String();
    int recent(Iterable<JsonMap> rows) => rows
        .where(
          (row) =>
              row
                  .date('createdAt')
                  ?.isAfter(now.subtract(const Duration(hours: 1))) ??
              false,
        )
        .length;
    switch (action) {
      case 'setProjectLead':
        final row = project(payload.text('projectID'));
        if (row == null) throw _code('forbidden');
        final team = _orgWorkGroup(row.text('groupID'), coordinator: true);
        final target = payload['userID'];
        if (target == null) {
          row['leadID'] = '';
          return {};
        }
        if (target is! String) throw _code('invalid_input');
        if (!_planActive(_orgOf(team))) throw _code('plan_inactive');
        if (row['status'] != 'active') throw _code('project_read_only');
        if (!team.ids('memberIDs').contains(target)) {
          throw _code('invalid_input');
        }
        row['leadID'] = target;
        _groupActivity(
          team.text('id'),
          'menunjuk koordinator sie · ${row.text('title')}',
        );
        return {};
      case 'createMeeting':
        final team = _orgWorkGroup(payload.text('groupID'), coordinator: true);
        if (!_planActive(_orgOf(team))) throw _code('plan_inactive');
        final startsAt = payload.date('startsAt');
        final noteTaker = payload['noteTakerID'] ?? '';
        if (startsAt == null ||
            noteTaker is! String ||
            (noteTaker.isNotEmpty &&
                !team.ids('memberIDs').contains(noteTaker))) {
          throw _code('invalid_input');
        }
        final id = _demoID();
        final title = _input(payload, 'title', 120);
        meetings.add({
          'id': id,
          'groupID': team['id'],
          'createdBy': actor,
          'noteTakerID': noteTaker,
          'title': title,
          'startsAt': startsAt.toUtc().toIso8601String(),
          'place': _input(payload, 'place', 200, min: 0),
          'agenda': _input(payload, 'agenda', 5000, min: 0),
          'minutes': '',
          'status': 'scheduled',
          'version': 1,
          'attendance': <String, String>{},
          'createdAt': stamp,
        });
        _groupActivity(team.text('id'), 'menjadwalkan rapat · $title');
        return {'id': id};
      case 'updateMeeting':
      case 'cancelMeeting':
      case 'recordMeeting':
        final row = _find(meetings, payload.text('id'));
        if (row == null) throw _code('forbidden');
        final team = _orgWorkGroup(row.text('groupID'));
        final coordinator = team['coordinatorID'] == actor;
        if (!coordinator &&
            !(action == 'recordMeeting' && row['noteTakerID'] == actor)) {
          throw _code('forbidden');
        }
        final status = row.text('status');
        if (action == 'recordMeeting'
            ? status == 'cancelled'
            : status != 'scheduled') {
          throw _code('meeting_closed');
        }
        if (action == 'recordMeeting' &&
            row.date('startsAt')!.isAfter(_clock())) {
          throw _code('invalid_input');
        }
        if (payload['expectedVersion'] != row['version']) {
          throw _code('stale_version');
        }
        final title = row.text('title');
        if (action == 'updateMeeting') {
          final startsAt = payload.date('startsAt');
          final noteTaker = payload['noteTakerID'] ?? '';
          if (startsAt == null ||
              noteTaker is! String ||
              (noteTaker.isNotEmpty &&
                  !team.ids('memberIDs').contains(noteTaker))) {
            throw _code('invalid_input');
          }
          final moved =
              !startsAt.isAtSameMomentAs(row.date('startsAt')!) ||
              payload['place'] != row['place'];
          row.addAll({
            'title': _input(payload, 'title', 120),
            'startsAt': startsAt.toUtc().toIso8601String(),
            'place': _input(payload, 'place', 200, min: 0),
            'agenda': _input(payload, 'agenda', 5000, min: 0),
            'noteTakerID': noteTaker,
          });
          if (moved) {
            _groupActivity(team.text('id'), 'mengubah rapat · ${row['title']}');
          }
        } else if (action == 'cancelMeeting') {
          row['status'] = 'cancelled';
          _groupActivity(team.text('id'), 'membatalkan rapat · $title');
        } else {
          final raw = payload['attendance'] ?? [];
          final members = team.ids('memberIDs');
          if (raw is! List) throw _code('invalid_input');
          final next = <String, String>{};
          for (final item in raw) {
            if (item is! Map ||
                item['userID'] is! String ||
                !members.contains(item['userID']) ||
                !['hadir', 'izin'].contains(item['status']) ||
                next.containsKey(item['userID'])) {
              throw _code('invalid_input');
            }
            next[item['userID'] as String] = item['status'] as String;
          }
          final attendance = (row['attendance'] as Map).cast<String, String>()
            ..removeWhere((id, _) => members.contains(id))
            ..addAll(next);
          row['attendance'] = attendance;
          final first = row.text('minutes').isEmpty;
          row['minutes'] = _input(payload, 'minutes', 20000, min: 0);
          row['status'] = 'done';
          if (first && row.text('minutes').isNotEmpty) {
            _groupActivity(team.text('id'), 'mengisi notulen · $title');
          }
        }
        row['version'] = row.number('version').toInt() + 1;
        return {};
      case 'requestApproval':
        final team = _orgWorkGroup(payload.text('groupID'));
        final org = _orgOf(team);
        if (!_planActive(org)) throw _code('plan_inactive');
        final amount = payload['amount'];
        final links = _httpsLinks(payload['links'] ?? []);
        final raw = payload['approverIDs'];
        if ((amount != null &&
                (amount is! int || amount < 0 || amount > 999999999999)) ||
            links == null ||
            raw is! List ||
            raw.isEmpty ||
            raw.length > 5 ||
            raw.toSet().length != raw.length ||
            raw.any(
              (id) =>
                  id is! String ||
                  id == actor ||
                  !(team['coordinatorID'] == id || _officer(org, id)),
            )) {
          throw _code('invalid_input');
        }
        final title = _input(payload, 'title', 120);
        final note = _input(payload, 'note', 2000);
        if (approvals
                .where(
                  (row) =>
                      row['requesterID'] == actor && row['status'] == 'pending',
                )
                .length >=
            5) {
          throw _code('rate_limited');
        }
        final id = _demoID();
        approvals.add({
          'id': id,
          'organizationID': org['id'],
          'groupID': team['id'],
          'requesterID': actor,
          'title': title,
          'note': note,
          'amount': amount,
          'links': links,
          'status': 'pending',
          'createdAt': stamp,
          'closedAt': null,
          'steps': [
            for (final (i, approver) in raw.cast<String>().indexed)
              {
                'position': i + 1,
                'approverID': approver,
                'decision': null,
                'note': '',
                'decidedAt': null,
              },
          ],
        });
        return {'id': id};
      case 'decideApproval':
      case 'cancelApproval':
        final row = _find(approvals, payload.text('id'));
        if (row == null || !_seesApproval(row)) throw _code('forbidden');
        if (action == 'cancelApproval' && row['requesterID'] != actor) {
          throw _code('forbidden');
        }
        if (row['status'] != 'pending') throw _code('approval_closed');
        if (action == 'cancelApproval') {
          row['status'] = 'cancelled';
          row['closedAt'] = stamp;
          return {};
        }
        final approve = payload['approve'];
        if (approve is! bool) throw _code('invalid_input');
        final step = _steps(row).firstWhere((step) => step['decision'] == null);
        if (step['approverID'] != actor || !_eligible(row, actor)) {
          throw _code('forbidden');
        }
        step.addAll({
          'decision': approve ? 'approved' : 'rejected',
          'note': _input(payload, 'note', 1000, min: approve ? 0 : 1),
          'decidedAt': stamp,
        });
        if (!approve || _steps(row).every((s) => s['decision'] != null)) {
          row['status'] = approve ? 'approved' : 'rejected';
          row['closedAt'] = stamp;
        }
        return {};
      case 'postAnnouncement':
        final org = _find(organizations, payload.text('organizationID'));
        if (org == null || !_orgMembers(org.text('id')).contains(actor)) {
          throw _code('forbidden');
        }
        final groupID = payload['groupID'] ?? '';
        if (groupID is! String) throw _code('invalid_input');
        if (groupID.isEmpty) {
          if (!['ketua', 'bph'].contains(_roles(org)[actor])) {
            throw _code('forbidden');
          }
        } else {
          final team = _orgWorkGroup(groupID, coordinator: true);
          if (team['organizationID'] != org['id']) throw _code('forbidden');
        }
        if (!_planActive(org)) throw _code('plan_inactive');
        if (recent(
              announcements.where(
                (row) =>
                    row['organizationID'] == org['id'] &&
                    row['groupID'] == groupID,
              ),
            ) >=
            (groupID.isEmpty ? 5 : 10)) {
          throw _code('rate_limited');
        }
        final id = _demoID();
        announcements.add({
          'id': id,
          'organizationID': org['id'],
          'groupID': groupID,
          'authorID': actor,
          'title': _input(payload, 'title', 120),
          'body': _input(payload, 'body', 2000),
          'createdAt': stamp,
          'reads': <String>[actor],
        });
        return {'id': id};
      case 'deleteAnnouncement':
      case 'markAnnouncementRead':
        final row = _find(announcements, payload.text('id'));
        if (row == null) throw _code('forbidden');
        if (action == 'markAnnouncementRead') {
          if (!_audience(row).contains(actor)) throw _code('forbidden');
          final reads = (row['reads'] as List).cast<String>();
          if (!reads.contains(actor)) reads.add(actor);
          return {};
        }
        final org = _find(organizations, row.text('organizationID'))!;
        if (row['authorID'] != actor &&
            !(row.text('groupID').isEmpty && _roles(org)[actor] == 'ketua')) {
          throw _code('forbidden');
        }
        announcements.remove(row);
        return {};
      default:
        _demoFail('Tindakan tidak dikenal: $action.');
    }
  }

  /// Test fixture on top of [seedOrganization]: g1 (u1 coordinator) has a
  /// scheduled meeting tomorrow (m1, notulis u2) and a finished one (m2);
  /// u2 asked for approval a1 (u1 → u3); u3 (BPH) posted org-wide n1.
  void seedOrgWork() {
    String at(Duration offset) =>
        _clock().add(offset).toUtc().toIso8601String();
    meetings.addAll([
      {
        'id': 'm1',
        'groupID': 'g1',
        'createdBy': 'u1',
        'noteTakerID': 'u2',
        'title': 'Rapat mingguan',
        'startsAt': at(const Duration(days: 1)),
        'place': 'Sekre BEM',
        'agenda': 'Evaluasi ERD',
        'minutes': '',
        'status': 'scheduled',
        'version': 1,
        'attendance': <String, String>{},
        'createdAt': at(const Duration(days: -1)),
      },
      {
        'id': 'm2',
        'groupID': 'g1',
        'createdBy': 'u1',
        'noteTakerID': 'u2',
        'title': 'Rapat perdana',
        'startsAt': at(const Duration(days: -2)),
        'place': 'Ruang 301',
        'agenda': 'Pembagian tugas',
        'minutes': 'Raka menyusun ERD.',
        'status': 'done',
        'version': 2,
        'attendance': {'u1': 'hadir', 'u2': 'hadir', 'u4': 'izin'},
        'createdAt': at(const Duration(days: -3)),
      },
    ]);
    approvals.add({
      'id': 'a1',
      'organizationID': 'o1',
      'groupID': 'g1',
      'requesterID': 'u2',
      'title': 'Dana cetak poster',
      'note': 'Cetak 20 poster A3 untuk publikasi.',
      'amount': 750000,
      'links': ['https://drive.google.com/rab'],
      'status': 'pending',
      'createdAt': at(const Duration(days: -3)),
      'closedAt': null,
      'steps': [
        for (final (i, id) in ['u1', 'u3'].indexed)
          {
            'position': i + 1,
            'approverID': id,
            'decision': null,
            'note': '',
            'decidedAt': null,
          },
      ],
    });
    announcements.add({
      'id': 'n1',
      'organizationID': 'o1',
      'groupID': '',
      'authorID': 'u3',
      'title': 'Rapat pleno ditiadakan',
      'body': 'Silakan rapat per divisi minggu ini.',
      'createdAt': at(const Duration(hours: -5)),
      'reads': ['u3', 'u2'],
    });
  }

  // MARK: - Organization Plan Tahap 3a (docs/DESIGN-org-tahap3.md §3–4)
  // templates: {id, organizationID (null = built-in), createdBy, name,
  //   description, sections, createdAt}
  // planItems: {id, projectID, position, title, description, dueAt, taskID}
  // periods: {id, organizationID, label, startedAt, closedAt, closedBy}
  // projects.periodID, groups.closedAt; templateUses: {groupID, createdAt}

  /// Actions a closed committee still accepts (§4.1 daftar izin).
  static const _closedAllowed = {
    'sendMessage',
    'retryMessage',
    'markChatRead',
    'reportMessage',
    'reportContent',
    'leaveGroup',
    'removeMember',
    'transferCoordinator',
    'setCoordinator',
    'removeClosedMember',
    'markAnnouncementRead',
    'deleteAnnouncement',
    'reopenCommittee',
  };

  /// Group an action writes to, for the closed-group check; '' if none.
  String _targetGroup(String action, JsonMap payload) {
    String ofProject(String? id) => project(id ?? '')?.text('groupID') ?? '';
    String ofTask(String id) => ofProject(task(id)?.text('projectID'));
    return switch (action) {
      'updateGroup' => payload.text('id'),
      'createProject' ||
      'generateInvite' ||
      'createMeeting' ||
      'requestApproval' ||
      'postAnnouncement' ||
      'applyTemplate' => payload.text('groupID'),
      'updateProject' ||
      'completeProject' ||
      'reopenProject' ||
      'archiveProject' ||
      'restoreProject' => ofProject(payload.text('id')),
      'createTask' || 'setProjectLead' => ofProject(payload.text('projectID')),
      'updateTask' ||
      'reassignTask' ||
      'startTask' ||
      'reopenTask' => ofTask(payload.text('id')),
      'submitWork' || 'review' => ofTask(payload.text('taskID')),
      'revokeInvite' =>
        _find(invites, payload.text('id'))?.text('groupID') ?? '',
      'joinGroup' =>
        invites
                .where(
                  (row) =>
                      row.text('code').toUpperCase() ==
                      payload.text('code').trim().toUpperCase(),
                )
                .firstOrNull
                ?.text('groupID') ??
            '',
      'updateMeeting' || 'cancelMeeting' || 'recordMeeting' =>
        _find(meetings, payload.text('id'))?.text('groupID') ?? '',
      'decideApproval' || 'cancelApproval' =>
        _find(approvals, payload.text('id'))?.text('groupID') ?? '',
      'deletePlanItem' => ofProject(
        _find(planItems, payload.text('id'))?.text('projectID'),
      ),
      _ => '',
    };
  }

  /// Two generic built-ins standing in for the migration's four (§1.4).
  void _seedTemplates() {
    JsonMap item(String title, int offset) => {
      'title': title,
      'description': '',
      'offsetDays': offset,
    };
    templateRows = [
      {
        'id': 'tpl-seminar',
        'organizationID': null,
        'createdBy': null,
        'name': 'Seminar',
        'description': 'Kerangka panitia seminar satu hari.',
        'createdAt': '2026-01-01T00:00:00.000Z',
        'sections': [
          {
            'title': 'Sie Acara',
            'description': 'Rundown dan pembicara.',
            'offsetDays': -1,
            'items': [
              item('Hubungi pembicara', -21),
              item('Susun rundown', -7),
            ],
          },
          {
            'title': 'Sie Publikasi',
            'description': '',
            'offsetDays': -3,
            'items': [item('Desain poster', -14)],
          },
        ],
      },
      {
        'id': 'tpl-oprec',
        'organizationID': null,
        'createdBy': null,
        'name': 'Open recruitment',
        'description': 'Pendaftaran dan seleksi anggota baru.',
        'createdAt': '2026-01-01T00:00:00.000Z',
        'sections': [
          {
            'title': 'Sie Seleksi',
            'description': '',
            'offsetDays': 0,
            'items': [item('Buka formulir', -14), item('Wawancara', -2)],
          },
        ],
      },
    ];
  }

  List<JsonMap> _orgPeriods(String orgID) =>
      periods.where((row) => row['organizationID'] == orgID).toList()
        ..sort((a, b) => b.text('closedAt').compareTo(a.text('closedAt')));

  List<JsonMap> _snapshotProjects() => [
    for (final row in projects)
      {
        ...(_copy(row) as JsonMap)..remove('periodID'),
        'periodLabel':
            _find(periods, row['periodID'] as String? ?? '')?.text('label') ??
            '',
        'planItems': row['status'] == 'active'
            ? [
                for (final item in planItems)
                  if (item['projectID'] == row['id'] && item['taskID'] == null)
                    {
                      'id': item['id'],
                      'position': item['position'],
                      'title': item['title'],
                      'description': item['description'],
                      'dueAt': item['dueAt'],
                    },
              ]
            : <JsonMap>[],
      },
  ];

  bool _orgCoordinator(String orgID, String id) =>
      _divisions(orgID).any((row) => row['coordinatorID'] == id);

  /// Template visible to the actor: built-in, or of an org they belong to.
  JsonMap _visibleTemplate(String id) {
    final row = _find(templateRows, id);
    final orgID = row?['organizationID'] as String?;
    if (row == null ||
        (orgID != null && !_orgMembers(orgID).contains(_actor))) {
      throw _code('forbidden');
    }
    return row;
  }

  /// `createTemplate` shape check (§4.5); anything off → invalid_input.
  List<JsonMap> _templateSections(Object? raw) {
    Never bad() => throw _code('invalid_input');
    int offset(Object? value) =>
        value is int && value >= -365 && value <= 365 ? value : bad();
    String text(Object? value, int min, int max) {
      if (value is! String) bad();
      final trimmed = value.trim();
      return trimmed.runes.length >= min && trimmed.runes.length <= max
          ? trimmed
          : bad();
    }

    if (raw is! List || raw.isEmpty || raw.length > 20) bad();
    var total = 0;
    return [
      for (final section in raw)
        () {
          if (section is! Map ||
              section.keys.any(
                (key) => ![
                  'title',
                  'description',
                  'offsetDays',
                  'items',
                ].contains(key),
              )) {
            bad();
          }
          final items = section['items'];
          if (items is! List || items.length > 40) bad();
          total += items.length;
          if (total > 200) bad();
          return <String, dynamic>{
            'title': text(section['title'], 3, 120),
            'description': text(section['description'] ?? '', 0, 2000),
            'offsetDays': offset(section['offsetDays']),
            'items': [
              for (final item in items)
                if (item is! Map ||
                    item.keys.any(
                      (key) =>
                          !['title', 'description', 'offsetDays'].contains(key),
                    ))
                  bad()
                else
                  {
                    'title': text(item['title'], 3, 120),
                    'description': text(item['description'] ?? '', 0, 2000),
                    'offsetDays': offset(item['offsetDays']),
                  },
            ],
          };
        }(),
    ];
  }

  JsonMap _planMutate(String action, JsonMap payload) {
    final actor = _actor;
    final now = _clock().toUtc();
    final stamp = now.toIso8601String();
    switch (action) {
      case 'applyTemplate':
        final team = _orgWorkGroup(payload.text('groupID'), coordinator: true);
        final org = _orgOf(team);
        if (!_planActive(org)) throw _code('plan_inactive');
        final template = _visibleTemplate(payload.text('templateID'));
        final orgID = template['organizationID'];
        if (orgID != null && orgID != org['id']) throw _code('forbidden');
        final eventAt = payload.date('eventAt');
        if (eventAt == null) throw _code('invalid_input');
        if (templateUses
                .where(
                  (row) =>
                      row['groupID'] == team['id'] &&
                      row
                          .date('createdAt')!
                          .isAfter(now.subtract(const Duration(hours: 1))),
                )
                .length >=
            5) {
          throw _code('rate_limited');
        }
        String due(Object? offset) => eventAt
            .add(Duration(days: offset as int))
            .toUtc()
            .toIso8601String();
        final ids = <String>[];
        for (final section in (template['sections'] as List).cast<JsonMap>()) {
          if (!DateTime.parse(due(section['offsetDays'])).isAfter(now)) {
            throw _code('invalid_input');
          }
          final id = _demoID();
          ids.add(id);
          projects.add({
            'id': id,
            'groupID': team['id'],
            'title': section['title'],
            'description': section['description'] ?? '',
            'dueAt': due(section['offsetDays']),
            'status': 'active',
          });
          for (final (i, item)
              in (section['items'] as List).cast<JsonMap>().indexed) {
            planItems.add({
              'id': _demoID(),
              'projectID': id,
              'position': i + 1,
              'title': item['title'],
              'description': item['description'] ?? '',
              'dueAt': due(item['offsetDays']),
              'taskID': null,
            });
          }
        }
        templateUses.add({'groupID': team['id'], 'createdAt': stamp});
        return {'projectIDs': ids};
      case 'createTemplate':
        final org = _find(organizations, payload.text('organizationID'));
        if (org == null || !_orgMembers(org.text('id')).contains(actor)) {
          throw _code('forbidden');
        }
        if (!['ketua', 'bph'].contains(_roles(org)[actor]) &&
            !_orgCoordinator(org.text('id'), actor)) {
          throw _code('forbidden');
        }
        if (!_planActive(org)) throw _code('plan_inactive');
        final sections = _templateSections(payload['sections']);
        final name = _input(payload, 'name', 80);
        final description = _input(payload, 'description', 1000, min: 0);
        if (templateRows
                .where((row) => row['organizationID'] == org['id'])
                .length >=
            50) {
          throw _code('rate_limited');
        }
        final id = _demoID();
        templateRows.add({
          'id': id,
          'organizationID': org['id'],
          'createdBy': actor,
          'name': name,
          'description': description,
          'sections': sections,
          'createdAt': stamp,
        });
        return {'id': id};
      case 'deleteTemplate':
        final row = _visibleTemplate(payload.text('id'));
        final orgID = row['organizationID'] as String?;
        if (orgID == null ||
            (row['createdBy'] != actor &&
                _roles(_find(organizations, orgID)!)[actor] != 'ketua')) {
          throw _code('forbidden');
        }
        templateRows.remove(row);
        return {};
      case 'deletePlanItem':
        final item = _find(planItems, payload.text('id'));
        final parent = project(item?.text('projectID') ?? '');
        if (item == null || parent == null) throw _code('forbidden');
        _demoTaskManager(parent);
        if (item['taskID'] != null) throw _code('plan_item_used');
        if (parent['status'] != 'active') throw _code('project_read_only');
        planItems.remove(item);
        return {};
      case 'closeCommittee':
      case 'reopenCommittee':
      case 'setCoordinator':
      case 'removeClosedMember':
        final team = group(payload.text('groupID'));
        if (team == null) throw _code('forbidden');
        final org = _orgOf(team);
        final ketua =
            _roles(org)[actor] == 'ketua' &&
            _orgMembers(org.text('id')).contains(actor);
        if (action == 'setCoordinator') {
          if (!ketua) throw _code('forbidden');
          final target = payload.text('userID');
          if (!team.ids('memberIDs').contains(target) ||
              team['coordinatorID'] == target) {
            throw _code('invalid_input');
          }
          team['coordinatorID'] = target;
          return {};
        }
        if (action == 'removeClosedMember') {
          if (!ketua) throw _code('forbidden');
          final target = payload.text('userID');
          if (team['closedAt'] == null ||
              !team.ids('memberIDs').contains(target)) {
            throw _code('invalid_input');
          }
          if (team['coordinatorID'] == target) {
            throw _code('coordinator_transfer_required');
          }
          team['memberIDs'] = [
            for (final id in team.ids('memberIDs'))
              if (id != target) id,
          ];
          _afterLeave(target, team);
          return {};
        }
        if (team['isCommittee'] != true) throw _code('invalid_input');
        if (action == 'reopenCommittee') {
          if (!ketua) throw _code('forbidden');
          if (team['closedAt'] == null) throw _code('invalid_input');
          if (!_planActive(org)) throw _code('plan_inactive');
          if (_divisions(org.text('id'))
                  .where(
                    (row) =>
                        row['isCommittee'] == true && row['closedAt'] == null,
                  )
                  .length >=
              30) {
            throw _code('invalid_input');
          }
          team['closedAt'] = null;
          return {};
        }
        if (!ketua &&
            !(team.text('coordinatorID') == actor &&
                team.ids('memberIDs').contains(actor))) {
          throw _code('forbidden');
        }
        if (team['closedAt'] != null) throw _code('invalid_input');
        final own = projects.where((row) => row['groupID'] == team['id']);
        final ownIDs = own.map((row) => row['id']).toSet();
        if (own.any((row) => row['status'] == 'active') ||
            tasks.any(
              (row) =>
                  ownIDs.contains(row['projectID']) && row['status'] != 'done',
            ) ||
            approvals.any(
              (row) =>
                  row['groupID'] == team['id'] && row['status'] == 'pending',
            )) {
          throw _code('committee_busy');
        }
        team['closedAt'] = stamp;
        for (final invite in invites.where(
          (row) => row['groupID'] == team['id'],
        )) {
          invite['revoked'] = true;
        }
        for (final meeting in meetings.where(
          (row) =>
              row['groupID'] == team['id'] &&
              row['status'] == 'scheduled' &&
              row.date('startsAt')!.isAfter(now),
        )) {
          meeting['status'] = 'cancelled';
          meeting['version'] = meeting.number('version').toInt() + 1;
        }
        return {};
      case 'closePeriod':
        final org = _find(organizations, payload.text('organizationID'));
        if (org == null ||
            !_orgMembers(org.text('id')).contains(actor) ||
            _roles(org)[actor] != 'ketua') {
          throw _code('forbidden');
        }
        final current = org.text('periodLabel');
        final asked = payload['currentLabel'];
        if (asked is! String || asked.trim().isEmpty) {
          throw _code('invalid_input');
        }
        if (asked.trim() != current) throw _code('stale_version');
        final next = _input(payload, 'nextLabel', 40);
        if (next == current) throw _code('invalid_input');
        final orgID = org.text('id');
        if (_orgPeriods(orgID).any((row) => row['label'] == next)) {
          throw _code('period_exists');
        }
        final id = _demoID();
        final previous = _orgPeriods(orgID).firstOrNull;
        periods.add({
          'id': id,
          'organizationID': orgID,
          'label': current,
          'startedAt': previous?['closedAt'],
          'closedAt': stamp,
          'closedBy': actor,
        });
        final teams = groups
            .where((row) => row['organizationID'] == orgID)
            .map((row) => row['id'])
            .toSet();
        var archived = 0;
        for (final row in projects.where(
          (row) => teams.contains(row['groupID']),
        )) {
          if (row['status'] == 'completed') {
            row['previousStatus'] = 'completed';
            row['status'] = 'archived';
          }
          if (row['status'] == 'archived' && row['periodID'] == null) {
            row['periodID'] = id;
            archived++;
          }
        }
        org['periodLabel'] = next;
        return {'periodID': id, 'archived': archived};
      default:
        _demoFail('Tindakan tidak dikenal: $action.');
    }
  }

  @override
  Future<List<JsonMap>> templates(String orgID) async {
    if (!_orgMembers(orgID).contains(_actor)) throw _code('forbidden');
    return [
      for (final row in templateRows)
        if (row['organizationID'] == null || row['organizationID'] == orgID)
          {
            'id': row['id'],
            'name': row['name'],
            'description': row['description'],
            'builtIn': row['organizationID'] == null,
            'sectionCount': (row['sections'] as List).length,
            'itemCount': [
              for (final section in row['sections'] as List)
                (section['items'] as List).length,
            ].fold<int>(0, (a, b) => a + b),
            'createdAt': row['createdAt'],
            'mine': row['createdBy'] == _actor,
          },
    ];
  }

  @override
  Future<List<JsonMap>> orgMembers(String orgID) async {
    final org = _find(organizations, orgID);
    if (org == null || _roles(org)[_actor] != 'ketua') throw _code('forbidden');
    final rows = groups.where((row) => row['organizationID'] == orgID).toList()
      ..sort(
        (a, b) =>
            (a['isCommittee'] == true ? 1 : 0) !=
                (b['isCommittee'] == true ? 1 : 0)
            ? (a['isCommittee'] == true ? 1 : -1)
            : a.text('name').compareTo(b.text('name')),
      );
    return [
      for (final row in rows)
        {
          'groupID': row['id'],
          'name': row['name'],
          'isCommittee': row['isCommittee'] == true,
          'closed': row['closedAt'] != null,
          'coordinatorID': row.text('coordinatorID'),
          'members': [
            for (final id in row.ids('memberIDs'))
              {'id': id, 'name': _name(id)},
          ],
        },
    ];
  }

  @override
  Future<JsonMap> template(String id) async {
    final row = _visibleTemplate(id);
    return _copy({
          'id': row['id'],
          'name': row['name'],
          'description': row['description'],
          'builtIn': row['organizationID'] == null,
          'sections': row['sections'],
        })
        as JsonMap;
  }

  bool _orgOfficer(JsonMap org) =>
      _officer(org, _actor) && _orgMembers(org.text('id')).contains(_actor);

  @override
  Future<JsonMap> orgArchive(String orgID) async {
    final org = _find(organizations, orgID);
    if (org == null || !_orgOfficer(org)) throw _code('forbidden');
    return _copy({
          'periods': [
            for (final period in _orgPeriods(orgID))
              {
                'id': period['id'],
                'label': period['label'],
                'startedAt': period['startedAt'],
                'closedAt': period['closedAt'],
                'projects': [
                  for (final row in projects)
                    if (row['periodID'] == period['id'])
                      {
                        'id': row['id'],
                        'groupID': row['groupID'],
                        'groupName': group(row.text('groupID'))?['name'],
                        'title': row['title'],
                        'dueAt': row['dueAt'],
                        'total': tasks
                            .where((t) => t['projectID'] == row['id'])
                            .length,
                        'done': tasks
                            .where(
                              (t) =>
                                  t['projectID'] == row['id'] &&
                                  t['status'] == 'done',
                            )
                            .length,
                      },
                ],
                'committees': [
                  for (final row in groups)
                    if (row['organizationID'] == orgID &&
                        row['closedAt'] != null &&
                        row
                                .text('closedAt')
                                .compareTo(period.text('closedAt')) <=
                            0 &&
                        row
                                .text('closedAt')
                                .compareTo(period.text('startedAt')) >
                            0)
                      {
                        'id': row['id'],
                        'name': row['name'],
                        'closedAt': row['closedAt'],
                      },
                ],
              },
          ],
        })
        as JsonMap;
  }

  @override
  Future<JsonMap> report(
    String groupID, {
    String? periodID,
    List<String>? projectIDs,
  }) async {
    final team = group(groupID);
    if (team == null) throw _code('forbidden');
    final org = _orgOf(team);
    final member = team.ids('memberIDs').contains(_actor);
    // Any org role has full access (private.report), member or not.
    final officer = _roles(org)[_actor] != null;
    final coordinator = member && team['coordinatorID'] == _actor;
    final leadOnly = !officer && !coordinator;
    final period = periodID == null ? null : _find(periods, periodID);
    if (periodID != null &&
        (period == null || period['organizationID'] != org['id'])) {
      throw _code('invalid_input');
    }
    final now = _clock().toUtc();
    final start =
        (period?['startedAt'] ??
                _orgPeriods(org.text('id')).firstOrNull?['closedAt'])
            as String?;
    final end = period?.text('closedAt') ?? now.toIso8601String();
    bool inWindow(String at) =>
        (start == null || at.compareTo(start) > 0) && at.compareTo(end) <= 0;
    final candidates = projects
        .where(
          (row) =>
              row['groupID'] == groupID &&
              row['periodID'] == periodID &&
              (!leadOnly || (member && row['leadID'] == _actor)),
        )
        .toList();
    // A koordinator sie without a sie in this period has no access.
    if (leadOnly && candidates.isEmpty) throw _code('forbidden');
    final List<JsonMap> picked;
    if (projectIDs != null) {
      if (projectIDs.length > 20 ||
          projectIDs.any((id) => !candidates.any((row) => row['id'] == id))) {
        throw _code('forbidden');
      }
      picked = candidates
          .where((row) => projectIDs.contains(row['id']))
          .toList();
    } else {
      picked =
          (candidates
                ..sort((a, b) => b.text('dueAt').compareTo(a.text('dueAt'))))
              .take(20)
              .toList();
    }
    final taskRows = <JsonMap>[];
    final reportProjects = [
      for (final row in picked)
        {
          'id': row['id'],
          'title': row['title'],
          'dueAt': row['dueAt'],
          'status': row['status'],
          'lead': row.text('leadID').isEmpty ? '' : _name(row.text('leadID')),
          'tasks': [
            for (final t in tasks.where((t) => t['projectID'] == row['id']))
              () {
                taskRows.add(t);
                final submissions = _submissions(t);
                final approved = submissions
                    .where((s) => s['decision'] == 'approved')
                    .lastOrNull;
                return {
                  'title': t['title'],
                  'assignee': _name(t.text('assigneeID')),
                  'reviewer': _name(t.text('reviewerID')),
                  'status': t['status'],
                  'dueAt': t['dueAt'],
                  'doneAt': t['status'] == 'done'
                      ? (approved?['createdAt'])
                      : null,
                  // Sends after the first one (private.report).
                  'revisions': max(submissions.length - 1, 0),
                  'links': submissions.lastOrNull?['links'] ?? <String>[],
                };
              }(),
          ],
        },
    ];
    final groupApprovals = leadOnly
        ? <JsonMap>[]
        : approvals
              .where(
                (row) =>
                    row['groupID'] == groupID &&
                    ['approved', 'rejected'].contains(row['status']) &&
                    inWindow(row.text('closedAt')),
              )
              .toList();
    return _copy({
          'generatedAt': now.toIso8601String(),
          'organization': org['name'],
          'period': period?['label'] ?? org['periodLabel'],
          'group': {
            'name': team['name'],
            'isCommittee': team['isCommittee'] == true,
            'coordinator': _name(team.text('coordinatorID')),
          },
          'projects': reportProjects,
          'meetings': [
            for (final row in meetings)
              if (row['groupID'] == groupID &&
                  row['status'] != 'cancelled' &&
                  inWindow(row.text('startsAt')))
                () {
                  final minutes = row.text('minutes');
                  final attendance = (row['attendance'] as Map).values;
                  return {
                    'title': row['title'],
                    'startsAt': row['startsAt'],
                    'present': attendance.where((s) => s == 'hadir').length,
                    'excused': attendance.where((s) => s == 'izin').length,
                    'minutes': minutes.length > 4000
                        ? minutes.substring(0, 4000)
                        : minutes,
                    'minutesTruncated': minutes.length > 4000,
                  };
                }(),
          ].take(100).toList(),
          'approvals': [
            for (final row in groupApprovals)
              {
                'title': row['title'],
                'amount': row['amount'],
                'status': row['status'],
                'closedAt': row['closedAt'],
                'chain': [
                  for (final step in _steps(row))
                    '${_name(step.text('approverID'))} (${switch (step['decision']) {
                      'approved' => 'disetujui',
                      'rejected' => 'ditolak',
                      _ => 'menunggu',
                    }})',
                ],
              },
          ],
          'totals': {
            'tasks': taskRows.length,
            'done': taskRows.where((t) => t['status'] == 'done').length,
            'approvedAmount': groupApprovals
                .where((row) => row['status'] == 'approved')
                .fold<int>(0, (sum, row) => sum + (row['amount'] as int? ?? 0)),
          },
        })
        as JsonMap;
  }

  /// Test fixture on top of [seedOrganization]: committee g4 "Panitia
  /// Seminar" (u1 coordinator, u2, u5) with sie p40 holding two plan items
  /// (one already past), and an org template by u3 (BPH).
  void seedOrgPlan() {
    String at(Duration offset) =>
        _clock().add(offset).toUtc().toIso8601String();
    groups.add({
      'id': 'g4',
      'name': 'Panitia Seminar',
      'description': '',
      'course': '',
      'memberIDs': ['u1', 'u2', 'u5'],
      'coordinatorID': 'u1',
      'tint': '#F9E9BE',
      'icon': 'person.3',
      'organizationID': 'o1',
      'isCommittee': true,
    });
    projects.add({
      'id': 'p40',
      'groupID': 'g4',
      'title': 'Sie Publikasi',
      'description': 'Poster dan media sosial.',
      'dueAt': at(const Duration(days: 10)),
      'status': 'active',
    });
    planItems.addAll([
      {
        'id': 'pi1',
        'projectID': 'p40',
        'position': 1,
        'title': 'Desain poster',
        'description': 'Ukuran A3.',
        'dueAt': at(const Duration(days: 5)),
        'taskID': null,
      },
      {
        'id': 'pi2',
        'projectID': 'p40',
        'position': 2,
        'title': 'Hubungi media partner',
        'description': '',
        'dueAt': at(const Duration(days: -1)),
        'taskID': null,
      },
    ]);
    templateRows.add({
      'id': 'tpl-bem',
      'organizationID': 'o1',
      'createdBy': 'u3',
      'name': 'Makrab BEM',
      'description': 'Kerangka makrab tahun lalu.',
      'createdAt': at(const Duration(days: -30)),
      'sections': [
        {
          'title': 'Sie Konsumsi',
          'description': '',
          'offsetDays': -1,
          'items': [
            {'title': 'Pesan katering', 'description': '', 'offsetDays': -7},
          ],
        },
      ],
    });
  }

  static List<JsonMap> _submissions(JsonMap task) =>
      (task['submissions'] as List).cast<JsonMap>();
}
