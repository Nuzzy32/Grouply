import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:supabase_flutter/supabase_flutter.dart'
    show AuthException, PostgrestException;

import 'backend.dart';

typedef JsonMap = Map<String, dynamic>;

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
    try {
      final snapshot = await _backend.snapshot();
      if (_disposed ||
          generation != _generation ||
          order != _snapshotOrder ||
          actor != _backend.currentUserID) {
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
      'rate_limited'
          when action == 'createOrganization' || action == 'transferKetua' =>
        'Satu orang maksimal menjadi ketua di 3 organisasi.',
      'rate_limited' => 'Terlalu banyak permintaan. Coba lagi sebentar.',
      'forbidden' => 'Kamu tidak punya izin untuk tindakan ini.',
      'invalid_input' => 'Data tidak valid. Periksa isian lalu coba lagi.',
      'unauthorized' => 'Sesi berakhir. Masuk kembali untuk melanjutkan.',
      _ => null,
    };
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
                row['isMember'] is! bool,
          )) {
        throw const FormatException('Invalid organization');
      }
      result.add({
        ...org,
        'myRole': myRole,
        'roles': officers,
        'divisions': divisions,
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
                (row['memberIDs'] as List).any((id) => id is! String))) {
          throw const FormatException('Invalid membership');
        }
        if (key == 'projects' &&
            (!['active', 'completed', 'archived'].contains(row['status']) ||
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
