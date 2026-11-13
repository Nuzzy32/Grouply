import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:supabase_flutter/supabase_flutter.dart'
    show AuthException, PostgrestException;

import 'backend.dart';

typedef JsonMap = Map<String, dynamic>;

/// Hours without recorded activity before an open task counts as stalled ("tanpa kabar").
const idleNudgeHours = 48;

extension Fields on JsonMap {
  String text(String key) => this[key] is String ? this[key] as String : '';
  num number(String key) => this[key] is num ? this[key] as num : 0;
  List<String> ids(String key) =>
      this[key] is List ? (this[key] as List).whereType<String>().toList() : [];
  DateTime? date(String key) => DateTime.tryParse(text(key));
}

class GrouplyException implements Exception {
  const GrouplyException(this.message);
  final String message;
  @override
  String toString() => message;
}

class GrouplyStore extends ChangeNotifier with WidgetsBindingObserver {
  GrouplyStore({GrouplyBackend? backend, DateTime Function()? clock})
    : _backend = backend ?? SupabaseGrouplyBackend(),
      _clock = clock ?? DateTime.now;

  final GrouplyBackend _backend;
  final DateTime Function() _clock;
  List<JsonMap> users = [],
      groups = [],
      projects = [],
      tasks = [],
      messages = [],
      invites = [],
      reports = [];
  String currentUserID = '';
  bool loading = false;
  bool get authenticated => currentUserID.isNotEmpty;
  DateTime get now => _clock();
  bool get configured => _backend.configured;
  String? error;
  Map<String, List<String>> _blocks = {}, _reads = {};
  List<String> get blockedUserIDs =>
      List.unmodifiable(_blocks[currentUserID] ?? []);
  List<String> get readMessageIDs =>
      List.unmodifiable(_reads[currentUserID] ?? []);
  StreamSubscription<String?>? _auth;
  Timer? _refreshTimer;
  int _generation = 0;
  int _snapshotOrder = 0;
  // Completes when the newest explicit or realtime refresh has finished.
  Future<void>? _newestRefresh;
  bool _disposed = false,
      _initialized = false,
      _active = true,
      _mutating = false;
  Future<void> _sessionWork = Future.value();

  Future<void> _session(Future<void> Function() operation) {
    final result = _sessionWork.then((_) => operation());
    _sessionWork = result.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    return result;
  }

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

  /// Latest recorded activity on an open task: a submission or any message in its thread
  /// (the server logs create/edit/reassign/submit/review there). Null when done/in review.
  DateTime? lastActivity(JsonMap task) {
    if (![
      'todo',
      'in_progress',
      'needs_revision',
    ].contains(task.text('status'))) {
      return null;
    }
    final id = task.text('id');
    DateTime? last;
    for (final d in [
      for (final s in (task['submissions'] as List? ?? []).whereType<JsonMap>())
        s.date('createdAt'),
      for (final m in messages)
        if (m.text('taskID') == id) m.date('createdAt'),
    ]) {
      if (d != null && (last == null || d.isAfter(last))) last = d;
    }
    return last;
  }

  /// Whole hours an open task has gone without recorded activity.
  /// See [idleNudgeHours] for the "mandek" threshold.
  int? idleHours(JsonMap task, DateTime now) {
    final last = lastActivity(task);
    return last == null ? null : now.difference(last).inHours;
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  void _clear() {
    users = [];
    groups = [];
    projects = [];
    tasks = [];
    messages = [];
    invites = [];
    reports = [];
    organizations = [];
    meetings = [];
    currentUserID = '';
    _blocks = {};
    _reads = {};
    _snapshotOrder++;
  }

  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;
    final generation = _generation;
    WidgetsBinding.instance.addObserver(this);
    loading = true;
    _notify();
    _auth = _backend.authChanges.listen(
      (actor) {
        if (_disposed) return;
        if (currentUserID.isNotEmpty && actor != currentUserID) {
          _generation++;
          _clear();
          loading = false;
          _notify();
          unawaited(_backend.disconnect());
        }
        if (actor != null && _active && !loading) _scheduleRefresh();
      },
      onError: (Object _, StackTrace _) {
        error = 'Sesi belum dapat diperbarui. Coba masuk kembali.';
        _notify();
      },
    );
    try {
      await _session(() async {
        await _backend.initialize();
      });
      if (_disposed || generation != _generation) return;
      if (_backend.currentUserID != null) {
        await refresh();
        await _connect();
      }
    } catch (_) {
      if (generation == _generation) {
        error = 'Sesi belum dapat dipulihkan. Coba masuk kembali.';
      }
    } finally {
      if (generation == _generation) {
        loading = false;
        _notify();
      }
    }
  }

  Future<void> signIn(String email, String password) => _authenticate(() async {
    await _backend.signIn(email.trim(), password);
    return true;
  }, 'Tidak dapat masuk. Periksa akun dan koneksi.');

  /// Returns false when the account exists but its email must be confirmed
  /// before signing in.
  Future<bool> signUp(String name, String email, String password) =>
      _authenticate(
        () => _backend.signUp(name.trim(), email.trim(), password),
        'Akun belum dapat dibuat. Periksa data dan koneksi.',
      );

  Future<void> sendPasswordReset(String email) async {
    try {
      await _backend.sendPasswordReset(email.trim());
    } catch (failure) {
      throw GrouplyException(
        _authMessage(failure) ??
            'Kode belum dapat dikirim. Periksa email dan koneksi.',
      );
    }
  }

  Future<void> resetPassword(String email, String code, String password) =>
      _authenticate(() async {
        await _backend.resetPassword(email.trim(), code.trim(), password);
        return true;
      }, 'Kata sandi belum dapat diubah. Periksa kode dan koneksi.');

  static String? _authMessage(Object failure) {
    if (failure is! AuthException) return null;
    return switch (failure.code) {
      'user_already_exists' ||
      'email_exists' => 'Email sudah terdaftar. Silakan masuk.',
      'weak_password' =>
        'Kata sandi terlalu lemah. Gunakan yang lebih panjang.',
      'same_password' => 'Gunakan kata sandi yang berbeda dari sebelumnya.',
      'otp_expired' => 'Kode salah atau kedaluwarsa. Minta kode baru.',
      'email_address_invalid' => 'Format email tidak valid.',
      'signup_disabled' => 'Pendaftaran sedang ditutup.',
      'over_email_send_rate_limit' ||
      'over_request_rate_limit' => 'Terlalu banyak percobaan. Coba lagi nanti.',
      _ => null,
    };
  }

  Future<bool> _authenticate(
    Future<bool> Function() operation,
    String failureMessage,
  ) async {
    if (loading || _mutating) {
      throw const GrouplyException('Tunggu proses sebelumnya selesai.');
    }
    final generation = ++_generation;
    _clear();
    error = null;
    loading = true;
    _notify();
    try {
      var signedIn = false;
      await _session(() async {
        await _backend.disconnect();
        signedIn = await operation();
      });
      if (!signedIn || generation != _generation || _disposed) return signedIn;
      await refresh();
      await _connect();
      return true;
    } catch (failure) {
      final message = _authMessage(failure) ?? failureMessage;
      if (generation == _generation) {
        _clear();
        error = message;
      }
      throw GrouplyException(message);
    } finally {
      if (generation == _generation) {
        loading = false;
        _notify();
      }
    }
  }

  Future<void> signOut() async {
    final generation = ++_generation;
    _refreshTimer?.cancel();
    _clear();
    loading = true;
    error = null;
    _notify();
    try {
      await _session(() async {
        await _backend.disconnect();
        await _backend.signOut();
      });
    } catch (_) {
      if (generation == _generation) {
        error =
            'Sesi lokal ditutup; pencabutan sesi server belum terkonfirmasi.';
      }
    } finally {
      if (generation == _generation) {
        loading = false;
        _notify();
      }
    }
  }

  Future<void> refresh() async {
    if (_disposed || _mutating || _backend.currentUserID == null) {
      return;
    }
    final generation = _generation, order = ++_snapshotOrder;
    final actor = _backend.currentUserID;
    final done = Completer<void>();
    _newestRefresh = done.future;
    try {
      final snapshot = await _backend.snapshot();
      if (_disposed ||
          generation != _generation ||
          order != _snapshotOrder ||
          actor != _backend.currentUserID) {
        // Overtaken by a newer refresh: resolve only once its state is applied,
        // so callers never read data older than when they asked.
        final newer = _newestRefresh;
        if (order != _snapshotOrder &&
            newer != null &&
            !identical(newer, done.future)) {
          await newer;
        }
        return;
      }
      if (snapshot['currentUserID'] != actor) {
        throw const FormatException('Snapshot identity mismatch');
      }
      _apply(snapshot);
      error = null;
      _notify();
    } catch (_) {
      if (generation == _generation && order == _snapshotOrder && !_disposed) {
        if (_backend.currentUserID == null) {
          ++_generation;
          _clear();
        }
        error = 'Data server belum dapat dimuat. Coba lagi.';
        _notify();
      }
      rethrow;
    } finally {
      done.complete();
    }
  }

  Future<JsonMap> mutate(String action, [JsonMap payload = const {}]) async {
    if (!authenticated || _mutating || loading) {
      throw const GrouplyException(
        'Masuk atau tunggu proses sebelumnya selesai.',
      );
    }
    _mutating = true;
    error = null;
    final generation = _generation;
    try {
      final actor = currentUserID;
      ++_snapshotOrder;
      final result = await _backend.mutate(action, Map.of(payload));
      if (_disposed ||
          generation != _generation ||
          actor != _backend.currentUserID) {
        throw const GrouplyException('Sesi telah berubah.');
      }
      if (action == 'deleteAccount') {
        if (result['deleted'] != true) {
          throw const FormatException('Deletion not confirmed');
        }
        await signOut();
        return {'deleted': true};
      }
      try {
        final snapshot = await _backend.snapshot();
        if (_disposed ||
            generation != _generation ||
            actor != _backend.currentUserID) {
          throw const GrouplyException('Sesi telah berubah.');
        }
        if (snapshot['currentUserID'] != actor) {
          throw const FormatException('Snapshot identity mismatch');
        }
        ++_snapshotOrder;
        _apply(snapshot);
      } catch (_) {
        if (generation != _generation ||
            _disposed ||
            actor != _backend.currentUserID) {
          throw const GrouplyException('Sesi telah berubah.');
        }
        error =
            'Perubahan tersimpan di server. Tampilan belum diperbarui; muat ulang, jangan kirim ulang.';
        _scheduleRefresh();
      }
      if (result['invite'] is Map) {
        final invite = Map<String, dynamic>.from(result['invite'] as Map);
        final index = invites.indexWhere((row) => row['id'] == invite['id']);
        if (index >= 0) {
          invites[index] = invite;
        } else {
          invites.add(invite);
        }
      }
      _notify();
      return result;
    } catch (failure) {
      final message = failure is GrouplyException
          ? failure.message
          : serverMessage(failure, action) ??
                'Perubahan belum terkonfirmasi. Muat ulang sebelum mencoba lagi.';
      if (generation == _generation) {
        // A closed approval/meeting or a stale version means the card on
        // screen is out of date: reload so it disappears (Tahap 2 §5.1).
        // A koordinator sie who was just revoked gets `forbidden` on task
        // actions; reloading hides the task buttons they no longer have.
        if (failure is PostgrestException &&
            failure.code == 'P0001' &&
            (const [
                  'approval_closed',
                  'meeting_closed',
                  'stale_version',
                  'group_closed',
                  'plan_item_used',
                  'committee_busy',
                ].contains(failure.message) ||
                (failure.message == 'invalid_input' &&
                    _handoverActions.contains(action)) ||
                (failure.message == 'forbidden' &&
                    const [
                      'createTask',
                      'updateTask',
                      'reassignTask',
                      'reopenTask',
                    ].contains(action)))) {
          _scheduleRefresh();
        }
        if (_backend.currentUserID == null) {
          ++_generation;
          _clear();
        }
        error = message;
        _notify();
      }
      throw GrouplyException(message);
    } finally {
      _mutating = false;
    }
  }

  Future<void> markChatRead(String groupID, List<String> messageIDs) async {
    await mutate('markChatRead', {
      'groupID': groupID,
      'messageIDs': messageIDs,
    });
  }

  // MARK: - Organization Plan (ORG-01..06, docs/DESIGN-org-tahap1.md §4–5)

  /// Organizations the user belongs to; `[]` on a server without the plan.
  List<JsonMap> organizations = [];
  JsonMap? organization(String id) => _find(organizations, id);

  /// `ketua`, `bph` or `pembina`; '' for a Kadiv, staff or non-member.
  String orgRole(String orgID) => organization(orgID)?.text('myRole') ?? '';

  /// A division is an ordinary group linked to an organization.
  bool isDivision(JsonMap? group) =>
      (group?.text('organizationID') ?? '').isNotEmpty;

  // MARK: - Organization Plan Tahap 2 (ORG-07..10, docs/DESIGN-org-tahap2.md §4–5)

  /// Meetings of the user's groups (§4.5); `[]` on a server without Tahap 2.
  List<JsonMap> meetings = [];
  JsonMap? meeting(String id) => _find(meetings, id);

  /// A committee (kepanitiaan) is an organization group flagged by the server.
  bool isCommittee(JsonMap? group) => group?['isCommittee'] == true;

  /// Own report on organization content (`kind` is announcement/meeting/approval).
  bool hasReported(String kind, String id) =>
      reports.any((row) => row['kind'] == kind && row['targetID'] == id);

  /// Coordinator of the project's group, or its koordinator sie (`leadID`).
  bool canManageTasks(JsonMap? project) {
    final group = this.group(project?.text('groupID') ?? '');
    if (group == null || !group.ids('memberIDs').contains(currentUserID)) {
      return false;
    }
    return currentUserID.isNotEmpty &&
        (group.text('coordinatorID') == currentUserID ||
            project!.text('leadID') == currentUserID);
  }

  List<JsonMap> approvals(String orgID) =>
      (organization(orgID)?['approvals'] as List? ?? []).cast<JsonMap>();

  List<JsonMap> announcements(String orgID) =>
      (organization(orgID)?['announcements'] as List? ?? []).cast<JsonMap>();

  /// First step nobody has decided yet; null once the chain is complete.
  static JsonMap? currentStep(JsonMap approval) {
    for (final step in (approval['steps'] as List? ?? []).cast<JsonMap>()) {
      if (step['decision'] == null) return step;
    }
    return null;
  }

  /// Pending approvals whose running step is the user's and still valid.
  List<JsonMap> pendingForMe(String orgID) => [
    for (final approval in approvals(orgID))
      if (approval.text('status') == 'pending')
        if (currentStep(approval) case final step?)
          if (step.text('approverID') == currentUserID &&
              step['eligible'] == true)
            approval,
  ];

  List<JsonMap> unreadAnnouncements(String orgID) => [
    for (final row in announcements(orgID))
      if (row['read'] != true) row,
  ];

  /// Agenda, minutes and attendance (`grouply_meeting`). Not cached:
  /// the meeting screen reloads it when the snapshot `version` changes.
  Future<JsonMap> meetingDetail(String id) async {
    if (!authenticated) throw const GrouplyException('Masuk terlebih dahulu.');
    try {
      final value = await _backend.meetingDetail(id);
      final attendance = [
        for (final item in value['attendance'] as List)
          Map<String, dynamic>.from(item as Map),
      ];
      if (value['version'] is! int ||
          value['agenda'] is! String ||
          value['minutes'] is! String ||
          attendance.any(
            (row) =>
                row.text('userID').isEmpty ||
                !['hadir', 'izin'].contains(row['status']),
          )) {
        throw const FormatException('Invalid meeting');
      }
      return {...value, 'attendance': attendance};
    } catch (failure) {
      throw GrouplyException(
        serverMessage(failure) ??
            'Detail rapat belum dapat dimuat. Periksa koneksi lalu coba lagi.',
      );
    }
  }

  /// Dashboard summary (`grouply_org_overview`). Not cached: callers reload
  /// it on open, pull to refresh and resume.
  Future<JsonMap> orgOverview(String id) async {
    if (!authenticated) throw const GrouplyException('Masuk terlebih dahulu.');
    try {
      final value = await _backend.orgOverview(id);
      List<JsonMap> rows(Object? list) => [
        for (final item in list as List) Map<String, dynamic>.from(item as Map),
      ];
      final divisions = rows(value['divisions']);
      for (final division in divisions) {
        division['projects'] = rows(division['projects']);
      }
      return {
        ...value,
        'divisions': divisions,
        'attention': rows(value['attention']),
        'users': rows(value['users']),
      };
    } catch (failure) {
      throw GrouplyException(
        serverMessage(failure) ??
            'Dashboard belum dapat dimuat. Periksa koneksi lalu coba lagi.',
      );
    }
  }

  // MARK: - Organization Plan Tahap 3a (ORG-12..14, docs/DESIGN-org-tahap3.md §4–5)

  /// A committee closed by its coordinator or the Ketua (§1.5): read-only
  /// apart from chat, leaving, removing, handing over and reporting.
  bool isClosed(JsonMap? group) => group?['closed'] == true;

  /// Plan items of an active project not yet turned into tasks (§4.3).
  List<JsonMap> planItems(JsonMap? project) =>
      (project?['planItems'] as List? ?? []).cast<JsonMap>();

  /// Closed periods of an organization, newest first.
  List<JsonMap> periods(String orgID) =>
      (organization(orgID)?['periods'] as List? ?? []).cast<JsonMap>();

  /// Wraps a read-only RPC: server codes keep their text, anything else
  /// (network, malformed reply) becomes [fallback].
  Future<T> _read<T>(Future<T> Function() load, String fallback) async {
    if (!authenticated) throw const GrouplyException('Masuk terlebih dahulu.');
    try {
      return await load();
    } catch (failure) {
      throw GrouplyException(serverMessage(failure) ?? fallback);
    }
  }

  static List<JsonMap> _rows(Object? list) => [
    for (final item in list as List) Map<String, dynamic>.from(item as Map),
  ];

  static JsonMap _checked(JsonMap row, bool valid) =>
      valid ? row : throw const FormatException('Invalid row');

  /// Template list (`grouply_templates`). Not cached.
  Future<List<JsonMap>> templates(String orgID) => _read(() async {
    return [
      for (final row in await _backend.templates(orgID))
        _checked(
          Map<String, dynamic>.from(row),
          row['id'] is String &&
              row['name'] is String &&
              row['builtIn'] is bool &&
              row['sectionCount'] is int &&
              row['itemCount'] is int,
        ),
    ];
  }, 'Template belum dapat dimuat. Periksa koneksi lalu coba lagi.');

  /// One template with sections and items (`grouply_template`). Not cached.
  Future<JsonMap> template(String id) => _read(() async {
    final value = await _backend.template(id);
    final sections = _rows(value['sections']);
    for (final section in sections) {
      section['items'] = _rows(section['items']);
      if (section['title'] is! String ||
          section['offsetDays'] is! int ||
          (section['items'] as List<JsonMap>).any(
            (item) => item['title'] is! String || item['offsetDays'] is! int,
          )) {
        throw const FormatException('Invalid template');
      }
    }
    if (value['name'] is! String || value['builtIn'] is! bool) {
      throw const FormatException('Invalid template');
    }
    return {...value, 'sections': sections};
  }, 'Template belum dapat dimuat. Periksa koneksi lalu coba lagi.');

  /// Ketua-only list of every org group and its members
  /// (`grouply_org_members`). Not cached.
  Future<List<JsonMap>> orgMembers(String orgID) => _read(
    () async {
      return [
        for (final raw in await _backend.orgMembers(orgID))
          () {
            final row = Map<String, dynamic>.from(raw);
            final members = _rows(row['members']);
            return _checked(
              {...row, 'members': members},
              row.text('groupID').isNotEmpty &&
                  row['name'] is String &&
                  row['isCommittee'] is bool &&
                  row['closed'] is bool &&
                  row['coordinatorID'] is String &&
                  members.every(
                    (m) => m.text('id').isNotEmpty && m['name'] is String,
                  ),
            );
          }(),
      ];
    },
    'Daftar anggota organisasi belum dapat dimuat. Periksa koneksi lalu coba lagi.',
  );

  /// Closed periods for officers (`grouply_org_archive`). Not cached.
  Future<JsonMap> orgArchive(String orgID) => _read(() async {
    final value = await _backend.orgArchive(orgID);
    final periods = _rows(value['periods']);
    for (final period in periods) {
      period['projects'] = _rows(period['projects']);
      period['committees'] = _rows(period['committees']);
      if (period['label'] is! String || period.date('closedAt') == null) {
        throw const FormatException('Invalid period');
      }
    }
    return {...value, 'periods': periods};
  }, 'Arsip belum dapat dimuat. Periksa koneksi lalu coba lagi.');

  /// LPJ data (`grouply_report`); null [periodID] = current period, null
  /// [projectIDs] = every project of it. Not cached.
  Future<JsonMap> report(
    String groupID, {
    String? periodID,
    List<String>? projectIDs,
  }) => _read(() async {
    final value = await _backend.report(
      groupID,
      periodID: periodID,
      projectIDs: projectIDs,
    );
    final projects = _rows(value['projects']);
    for (final project in projects) {
      project['tasks'] = _rows(project['tasks']);
    }
    final approvals = value['approvals'] == null
        ? <JsonMap>[]
        : _rows(value['approvals']);
    if (value['group'] is! Map || value['totals'] is! Map) {
      throw const FormatException('Invalid report');
    }
    return {
      ...value,
      'group': Map<String, dynamic>.from(value['group'] as Map),
      'totals': Map<String, dynamic>.from(value['totals'] as Map),
      'projects': projects,
      'meetings': _rows(value['meetings'] ?? []),
      'approvals': approvals,
    };
  }, 'Rekap belum dapat dimuat. Periksa koneksi lalu coba lagi.');

  /// [serverMessage] for a bare server code, so screens can recognise it.
  static String codeText(String code, [String action = '']) =>
      serverMessage(PostgrestException(message: code, code: 'P0001'), action)!;

  /// Indonesian text for an error the server raised on purpose
  /// (`raise exception '<code>'`, SQLSTATE P0001). Null for anything else,
  /// such as a network failure where the change may already be saved.
  static String? serverMessage(Object failure, [String action = '']) {
    if (failure is! PostgrestException || failure.code != 'P0001') return null;
    return switch (failure.message) {
      'org_full' =>
        'Kursi organisasi sudah penuh. Minta ketua menambah kursi paket.',
      'plan_inactive' =>
        'Paket organisasi belum aktif. Hubungi tim Grouply dengan kode organisasi.',
      'ketua_transfer_required' =>
        'Ketua harus menyerahkan jabatannya dulu sebelum meninggalkan divisi terakhirnya.',
      'org_role_holder' =>
        'Anggota ini memegang jabatan organisasi. Ketua harus mencabut jabatannya dulu.',
      'group_full' => 'Grup sudah mencapai batas anggota.',
      'invite_full' =>
        'Kode undangan sudah mencapai batas pemakaian. Minta kode baru.',
      'invite_expired' => 'Kode undangan sudah kedaluwarsa. Minta kode baru.',
      'active_assignment' =>
        'Alihkan tugas aktif dan selesaikan review yang tertunda terlebih dahulu.',
      'coordinator_transfer_required' =>
        'Serahkan peran koordinator ke anggota lain terlebih dahulu.',
      'stale_version' =>
        'Data sudah diubah orang lain. Muat ulang lalu coba lagi.',
      'project_read_only' =>
        'Proyek selesai atau diarsipkan hanya dapat dibaca.',
      'already_reviewed' => 'Hasil kerja ini sudah direview.',
      'approval_closed' =>
        'Pengajuan ini sudah diputuskan, dibatalkan, atau gugur. Daftar dimuat ulang.',
      'meeting_closed' =>
        'Rapat ini sudah selesai atau dibatalkan. Data dimuat ulang.',
      'rate_limited'
          when action == 'createOrganization' || action == 'transferKetua' =>
        'Satu orang maksimal menjadi ketua di 3 organisasi.',
      'rate_limited' when action == 'requestApproval' =>
        'Maksimal 5 pengajuan terbuka. Batalkan atau tunggu keputusan pengajuan sebelumnya.',
      'rate_limited' when action == 'postAnnouncement' =>
        'Batas pengumuman tercapai: 5 per jam untuk seluruh organisasi, 10 per jam per grup. Coba lagi nanti.',
      'group_closed' =>
        'Kepanitiaan ini sudah ditutup. Hanya chat, keluar, dan serah koordinator yang masih bisa.',
      'committee_busy' =>
        'Kepanitiaan belum bisa ditutup: masih ada tugas yang belum selesai (termasuk di sie arsip), sie aktif, atau pengajuan yang menunggu. Sie yang sudah selesai tidak perlu diarsipkan.',
      'invalid_input' when action == 'reopenCommittee' =>
        'Kepanitiaan belum bisa dibuka kembali: organisasi sudah punya 30 kepanitiaan aktif.',
      'invalid_input' when action == 'setCoordinator' =>
        'Orang itu sudah tidak menjadi anggota grup ini atau sudah menjadi koordinatornya. Daftar dimuat ulang.',
      'invalid_input' when action == 'closePeriod' =>
        'Label periode sekarang belum diisi, atau label periode baru kosong atau sama dengan yang sekarang.',
      'invalid_input' when action == 'removeClosedMember' =>
        'Orang itu sudah keluar, atau kepanitiaannya sudah dibuka kembali. Daftar dimuat ulang.',
      'plan_item_used' =>
        'Butir rencana ini sudah dijadikan tugas. Data dimuat ulang.',
      'period_exists' =>
        'Label periode itu sudah pernah ditutup. Pakai label lain.',
      'rate_limited' when action == 'applyTemplate' =>
        'Template paling banyak dipakai 5 kali per jam untuk satu grup. Coba lagi nanti.',
      'rate_limited' when action == 'createTemplate' =>
        'Organisasi ini sudah punya 50 template. Hapus template lama dulu.',
      'rate_limited'
          when const [
            'createMeeting',
            'updateMeeting',
            'cancelMeeting',
            'recordMeeting',
          ].contains(action) =>
        'Batas 30 perubahan rapat per jam untuk grup ini tercapai. Coba lagi nanti.',
      'rate_limited' => 'Terlalu banyak permintaan. Coba lagi sebentar.',
      'forbidden' => 'Kamu tidak punya izin untuk tindakan ini.',
      'invalid_input' => 'Data tidak valid. Periksa isian lalu coba lagi.',
      'unauthorized' => 'Sesi berakhir. Masuk kembali untuk melanjutkan.',
      _ => null,
    };
  }

  /// Handover actions whose `invalid_input` means the screen is stale.
  static const _handoverActions = [
    'reopenCommittee',
    'setCoordinator',
    'closePeriod',
    'removeClosedMember',
  ];

  static const _approvalStatuses = [
    'pending',
    'approved',
    'rejected',
    'cancelled',
    'lapsed',
  ];

  /// Missing key = `[]` (database without Tahap 2); otherwise strict.
  static List<JsonMap> _decodeMeetings(Object? raw) {
    if (raw == null) return [];
    if (raw is! List) throw const FormatException('Invalid meetings');
    return [
      for (final item in raw)
        () {
          final row = Map<String, dynamic>.from(item as Map);
          if (row.text('id').isEmpty ||
              row.text('groupID').isEmpty ||
              row['title'] is! String ||
              row.date('startsAt') == null ||
              row['version'] is! int ||
              !['scheduled', 'done', 'cancelled'].contains(row['status']) ||
              (row['taskIDs'] != null && row['taskIDs'] is! List)) {
            throw const FormatException('Invalid meeting');
          }
          return row;
        }(),
    ];
  }

  /// Validates `organizations` like the other snapshot keys, but a missing
  /// key is `[]` so this build still runs against an unmigrated database.
  static List<JsonMap> _decodeOrganizations(Object? raw, List<JsonMap> groups) {
    if (groups.any(
      (row) =>
          row['organizationID'] != null && row['organizationID'] is! String,
    )) {
      throw const FormatException('Invalid division');
    }
    if (raw == null) return [];
    if (raw is! List) throw const FormatException('Invalid organizations');
    const roles = ['ketua', 'bph', 'pembina'];
    List<JsonMap> rows(Object? value) => value is List
        ? [for (final item in value) Map<String, dynamic>.from(item as Map)]
        : throw const FormatException('Invalid organization');
    final result = <JsonMap>[];
    for (final item in raw) {
      final org = Map<String, dynamic>.from(item as Map);
      final myRole = org['myRole'] ?? '';
      final officers = rows(org['roles']);
      final divisions = rows(org['divisions']);
      final approvals = org['approvals'] == null
          ? <JsonMap>[]
          : rows(org['approvals']);
      final announcements = org['announcements'] == null
          ? <JsonMap>[]
          : rows(org['announcements']);
      for (final approval in approvals) {
        approval['steps'] = rows(approval['steps']);
      }
      final periods = org['periods'] == null
          ? <JsonMap>[]
          : rows(org['periods']);
      if (org.text('id').isEmpty ||
          [
            'name',
            'description',
            'periodLabel',
          ].any((field) => org[field] is! String) ||
          org['planActive'] is! bool ||
          (org['planExpiresAt'] != null && org.date('planExpiresAt') == null) ||
          org['seatLimit'] is! int ||
          org['seatsUsed'] is! int ||
          !['', ...roles].contains(myRole) ||
          officers.any(
            (row) =>
                row.text('userID').isEmpty ||
                row['name'] is! String ||
                !roles.contains(row['role']),
          ) ||
          divisions.any(
            (row) =>
                row.text('id').isEmpty ||
                row['name'] is! String ||
                row['memberCount'] is! int ||
                row['isMember'] is! bool ||
                (row['isCommittee'] != null && row['isCommittee'] is! bool) ||
                (row['closed'] != null && row['closed'] is! bool),
          ) ||
          periods.any(
            (row) =>
                row.text('id').isEmpty ||
                row['label'] is! String ||
                (row['startedAt'] != null && row.date('startedAt') == null) ||
                row.date('closedAt') == null,
          ) ||
          approvals.any(
            (row) =>
                row.text('id').isEmpty ||
                row.text('groupID').isEmpty ||
                row['title'] is! String ||
                row['note'] is! String ||
                (row['amount'] != null && row['amount'] is! int) ||
                row['links'] is! List ||
                !_approvalStatuses.contains(row['status']) ||
                row.date('createdAt') == null ||
                (row['steps'] as List<JsonMap>).any(
                  (step) =>
                      step['position'] is! int ||
                      step['approverID'] is! String ||
                      step['eligible'] is! bool ||
                      (step['decision'] != null &&
                          !['approved', 'rejected'].contains(step['decision'])),
                ),
          ) ||
          announcements.any(
            (row) =>
                row.text('id').isEmpty ||
                row['title'] is! String ||
                row['body'] is! String ||
                row['read'] is! bool ||
                row.date('createdAt') == null ||
                (row['groupID'] != null && row['groupID'] is! String),
          )) {
        throw const FormatException('Invalid organization');
      }
      result.add({
        ...org,
        'myRole': myRole,
        'roles': officers,
        'divisions': divisions,
        'approvals': approvals,
        'announcements': announcements,
        'periods': periods,
      });
    }
    return result;
  }

  Future<void> _connect() async {
    if (authenticated && _active && !_disposed) {
      await _backend.connect(_scheduleRefresh);
    }
  }

  void _scheduleRefresh() {
    _refreshTimer?.cancel();
    _refreshTimer = Timer(const Duration(milliseconds: 120), () async {
      if (!_active || _disposed) return;
      if (_mutating) {
        _scheduleRefresh();
        return;
      }
      try {
        await refresh();
        await _connect();
      } catch (_) {
        /* errors are surfaced by refresh */
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _active = state == AppLifecycleState.resumed;
    if (!_active) {
      _refreshTimer?.cancel();
      unawaited(_backend.disconnect());
    } else {
      unawaited(_resume());
    }
  }

  Future<void> _resume() async {
    if (_disposed) return;
    try {
      await _backend.foreground();
      await refresh();
      await _connect();
    } catch (_) {
      error = 'Sambungan belum pulih. Coba muat ulang.';
      _notify();
    }
  }

  void _apply(JsonMap value) {
    const strings = {
      'users': ['name', 'email', 'tint'],
      'groups': [
        'name',
        'description',
        'course',
        'coordinatorID',
        'tint',
        'icon',
      ],
      'projects': ['groupID', 'title', 'description', 'dueAt', 'status'],
      'tasks': [
        'projectID',
        'title',
        'description',
        'assigneeID',
        'reviewerID',
        'dueAt',
        'status',
      ],
      'messages': [
        'groupID',
        'senderID',
        'text',
        'createdAt',
        'kind',
        'delivery',
      ],
      'invites': ['groupID', 'code', 'createdAt', 'expiresAt'],
      'reports': ['messageID', 'reporterID', 'reason', 'createdAt'],
    };
    final decoded = <String, List<JsonMap>>{};
    for (final key in [
      'users',
      'groups',
      'projects',
      'tasks',
      'messages',
      'invites',
      'reports',
    ]) {
      if (value[key] is! List) throw const FormatException('Invalid snapshot');
      decoded[key] = (value[key] as List).map((item) {
        final row = Map<String, dynamic>.from(item as Map);
        if (row['id'] is! String || row.text('id').isEmpty) {
          throw const FormatException('Invalid row');
        }
        if (strings[key]!.any((field) => row[field] is! String)) {
          throw const FormatException('Invalid fields');
        }
        for (final field in ['dueAt', 'createdAt', 'expiresAt', 'reviewedAt']) {
          if (row[field] != null && row.date(field) == null) {
            throw const FormatException('Invalid date');
          }
        }
        if (key == 'tasks') {
          if (row['submissions'] is! List ||
              row['version'] is! int ||
              row.number('version') < 1 ||
              ![
                'todo',
                'in_progress',
                'in_review',
                'needs_revision',
                'done',
              ].contains(row['status'])) {
            throw const FormatException('Invalid task');
          }
          for (final item in row['submissions'] as List) {
            final submission = Map<String, dynamic>.from(item as Map);
            if ([
                  'id',
                  'authorID',
                  'note',
                  'createdAt',
                ].any((field) => submission[field] is! String) ||
                submission['revision'] is! int ||
                submission.date('createdAt') == null ||
                submission['links'] is! List ||
                (submission['links'] as List).any((link) => link is! String) ||
                ['decision', 'feedback', 'reviewerID'].any(
                  (field) =>
                      submission[field] != null && submission[field] is! String,
                )) {
              throw const FormatException('Invalid submission');
            }
          }
        }
        if (key == 'groups' &&
            (row['memberIDs'] is! List ||
                (row['isCommittee'] != null && row['isCommittee'] is! bool) ||
                (row['closed'] != null && row['closed'] is! bool) ||
                (row['memberIDs'] as List).any((id) => id is! String))) {
          throw const FormatException('Invalid membership');
        }
        if (key == 'projects') {
          // Tahap 3a keys: missing = current period, no plan items.
          if (row['periodLabel'] != null && row['periodLabel'] is! String) {
            throw const FormatException('Invalid project');
          }
          final raw = row['planItems'] ?? [];
          if (raw is! List) throw const FormatException('Invalid plan items');
          final items = [
            for (final item in raw) Map<String, dynamic>.from(item as Map),
          ];
          if (items.any(
            (item) =>
                item.text('id').isEmpty ||
                item['position'] is! int ||
                item['title'] is! String ||
                (item['description'] != null &&
                    item['description'] is! String) ||
                item.date('dueAt') == null,
          )) {
            throw const FormatException('Invalid plan item');
          }
          row['planItems'] = items
            ..sort(
              (a, b) => a.number('position').compareTo(b.number('position')),
            );
          row['periodLabel'] ??= '';
        }
        if (key == 'projects' &&
            (!['active', 'completed', 'archived'].contains(row['status']) ||
                (row['leadID'] != null && row['leadID'] is! String) ||
                (row['previousStatus'] != null &&
                    ![
                      'active',
                      'completed',
                    ].contains(row['previousStatus'])))) {
          throw const FormatException('Invalid project');
        }
        if (key == 'messages' &&
            ([
                  'taskID',
                  'targetTaskID',
                ].any((field) => row[field] != null && row[field] is! String) ||
                !['sending', 'sent', 'failed'].contains(row['delivery']))) {
          throw const FormatException('Invalid message');
        }
        if (key == 'invites' &&
            (row['revoked'] is! bool ||
                row['maxUses'] is! int ||
                row['useCount'] is! int)) {
          throw const FormatException('Invalid invite');
        }
        return row;
      }).toList();
    }
    final actor = value['currentUserID'];
    if (actor is! String) throw const FormatException('Invalid identity');
    if (actor.isNotEmpty &&
        !decoded['users']!.any((row) => row['id'] == actor)) {
      throw const FormatException('Missing identity');
    }
    final blocks = (value['blockedUserIDs'] as List).cast<String>().toList();
    final reads = (value['readMessageIDs'] as List).cast<String>().toList();
    final orgs = _decodeOrganizations(
      value['organizations'],
      decoded['groups']!,
    );
    final meetings = _decodeMeetings(value['meetings']);
    final codes = {
      for (final invite in invites)
        if (invite.text('code').isNotEmpty)
          invite.text('id'): invite.text('code'),
    };
    if (actor == currentUserID) {
      for (final invite in decoded['invites']!) {
        if (decoded['groups']!.any(
          (row) =>
              row['id'] == invite['groupID'] && row['coordinatorID'] == actor,
        )) {
          invite['code'] = codes[invite['id']] ?? invite['code'];
        }
      }
    }
    users = decoded['users']!;
    groups = decoded['groups']!;
    projects = decoded['projects']!;
    tasks = decoded['tasks']!;
    messages = decoded['messages']!;
    invites = decoded['invites']!;
    reports = decoded['reports']!;
    organizations = orgs;
    this.meetings = meetings;
    currentUserID = actor;
    _blocks = {actor: blocks};
    _reads = {actor: reads};
  }

  @override
  void dispose() {
    _disposed = true;
    ++_generation;
    _refreshTimer?.cancel();
    _auth?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _backend.dispose();
    super.dispose();
  }
}
