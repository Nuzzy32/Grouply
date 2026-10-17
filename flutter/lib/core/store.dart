import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'backend.dart';

part 'demo.dart';

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
  GrouplyStore({
    GrouplyBackend? backend,
    SharedPreferences? preferences,
    DateTime Function()? clock,
  }) : _backend = backend ?? SupabaseGrouplyBackend(),
       _preferences = preferences,
       _clock = clock ?? DateTime.now;

  final GrouplyBackend _backend;
  SharedPreferences? _preferences;
  final DateTime Function() _clock;
  static const demoStorageKey = 'grouply.demo.v2';
  List<JsonMap> users = [],
      groups = [],
      projects = [],
      tasks = [],
      messages = [],
      invites = [],
      reports = [];
  String currentUserID = '';
  bool demoMode = false, loading = false;
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
  bool simulateSendFailure = false;
  bool _demoWritable = true;
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
        if (demoMode || _disposed) return;
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
        _preferences ??= await SharedPreferences.getInstance();
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

  Future<void> signIn(String email, String password) async {
    if (loading || _mutating) {
      throw const GrouplyException('Tunggu proses sebelumnya selesai.');
    }
    final generation = ++_generation;
    demoMode = false;
    _clear();
    error = null;
    loading = true;
    _notify();
    try {
      await _session(() async {
        await _backend.disconnect();
        await _backend.signIn(email.trim(), password);
      });
      if (generation != _generation || _disposed) return;
      await refresh();
      await _connect();
    } catch (_) {
      if (generation == _generation) {
        _clear();
        error = 'Tidak dapat masuk. Periksa akun dan koneksi.';
      }
      throw const GrouplyException(
        'Tidak dapat masuk. Periksa akun dan koneksi.',
      );
    } finally {
      if (generation == _generation) {
        loading = false;
        _notify();
      }
    }
  }

  Future<bool> signUp(String name, String email, String password) async {
    if (loading || _mutating) {
      throw const GrouplyException('Tunggu proses sebelumnya selesai.');
    }
    final generation = ++_generation;
    demoMode = false;
    _clear();
    error = null;
    loading = true;
    _notify();
    try {
      var signedIn = false;
      await _session(() async {
        await _backend.disconnect();
        signedIn = await _backend.signUp(name.trim(), email.trim(), password);
      });
      if (generation != _generation || _disposed) return false;
      if (!signedIn) {
        _clear();
        return false;
      }
      await refresh();
      await _connect();
      return true;
    } catch (_) {
      if (generation == _generation) {
        _clear();
        error = 'Tidak dapat mendaftar. Periksa data dan koneksi.';
      }
      throw const GrouplyException(
        'Tidak dapat mendaftar. Periksa data dan koneksi.',
      );
    } finally {
      if (generation == _generation) {
        loading = false;
        _notify();
      }
    }
  }

  Future<void> requestPasswordReset(String email) async {
    try {
      await _backend.requestPasswordReset(email.trim());
    } catch (_) {
      throw const GrouplyException(
        'Kode pemulihan belum dapat dikirim. Coba lagi nanti.',
      );
    }
  }

  Future<void> recoverPassword(
    String email,
    String token,
    String password,
  ) async {
    if (loading || _mutating) {
      throw const GrouplyException('Tunggu proses sebelumnya selesai.');
    }
    final generation = ++_generation;
    demoMode = false;
    _clear();
    error = null;
    loading = true;
    _notify();
    try {
      await _session(() async {
        await _backend.disconnect();
        await _backend.recoverPassword(email.trim(), token.trim(), password);
      });
      if (generation != _generation || _disposed) return;
      await refresh();
      await _connect();
    } catch (_) {
      if (generation == _generation) {
        _clear();
        error = 'Kode salah atau sudah kedaluwarsa. Minta kode baru.';
      }
      throw const GrouplyException(
        'Kode salah atau sudah kedaluwarsa. Minta kode baru.',
      );
    } finally {
      if (generation == _generation) {
        loading = false;
        _notify();
      }
    }
  }

  Future<void> signOut() async {
    final wasDemo = demoMode;
    final generation = ++_generation;
    _refreshTimer?.cancel();
    demoMode = false;
    _clear();
    loading = true;
    error = null;
    _notify();
    try {
      await _session(() async {
        await _backend.disconnect();
        if (!wasDemo) await _backend.signOut();
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

  Future<void> startDemo() async {
    if (loading || _mutating) {
      throw const GrouplyException('Tunggu proses sebelumnya selesai.');
    }
    final generation = ++_generation;
    _refreshTimer?.cancel();
    loading = true;
    _notify();
    try {
      await _session(() async {
        await _backend.disconnect();
        if (_backend.currentUserID != null) await _backend.signOut();
        _preferences ??= await SharedPreferences.getInstance();
      });
      if (generation != _generation || _disposed) return;
    } catch (_) {
      if (generation == _generation) {
        loading = false;
        error = 'Sesi server belum dapat ditutup.';
        _notify();
      }
      rethrow;
    }
    demoMode = true;
    _clear();
    error = null;
    _demoWritable = true;
    final saved = _preferences!.getString(demoStorageKey);
    try {
      if (saved == null) {
        _seed();
      } else {
        final decoded = jsonDecode(saved) as JsonMap;
        _apply(decoded, cloud: false);
        _blocks = _stringLists(decoded['blocks']);
        _reads = _stringLists(decoded['reads']);
      }
    } catch (_) {
      _demoWritable = false;
      _seed();
      error =
          'Data demo lama tidak terbaca dan tidak ditimpa. Sesi ini tidak disimpan.';
    }
    if (currentUserID.isEmpty ||
        user(currentUserID)?.text('name') == 'Pengguna dihapus') {
      currentUserID =
          users
              .where((row) => row.text('email').isNotEmpty)
              .firstOrNull
              ?.text('id') ??
          '';
    }
    try {
      await _saveDemo();
    } finally {
      if (generation == _generation) {
        loading = false;
        _notify();
      }
    }
  }

  Future<void> switchDemoUser(String id) async {
    if (!demoMode ||
        loading ||
        _mutating ||
        user(id) == null ||
        user(id)!.text('email').isEmpty) {
      throw const GrouplyException('Pengguna demo tidak valid.');
    }
    ++_generation;
    currentUserID = id;
    error = null;
    await _saveDemo();
    _notify();
  }

  Future<void> refresh() async {
    if (demoMode || _disposed || _mutating || _backend.currentUserID == null) {
      return;
    }
    final generation = _generation, order = ++_snapshotOrder;
    final actor = _backend.currentUserID;
    try {
      final snapshot = await _backend.snapshot();
      if (_disposed ||
          generation != _generation ||
          order != _snapshotOrder ||
          demoMode ||
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
      if (demoMode) {
        final backup = jsonEncode(_demoSnapshot());
        try {
          final result = _demoMutate(action, Map.of(payload));
          await _saveDemo();
          if (generation != _generation || !demoMode || _disposed) {
            throw const GrouplyException('Sesi telah berubah.');
          }
          _notify();
          return result;
        } catch (_) {
          final decoded = jsonDecode(backup) as JsonMap;
          if (generation == _generation && demoMode && !_disposed) {
            _apply(decoded, cloud: false);
            _blocks = _stringLists(decoded['blocks']);
            _reads = _stringLists(decoded['reads']);
          }
          rethrow;
        }
      }
      final actor = currentUserID;
      ++_snapshotOrder;
      final result = await _backend.mutate(action, Map.of(payload));
      if (_disposed ||
          generation != _generation ||
          actor != _backend.currentUserID ||
          demoMode) {
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
            actor != _backend.currentUserID ||
            demoMode) {
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
            demoMode ||
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
      if (generation == _generation) {
        if (!demoMode && _backend.currentUserID == null) {
          ++_generation;
          _clear();
        }
        error = failure is GrouplyException
            ? failure.message
            : 'Perubahan belum terkonfirmasi. Muat ulang sebelum mencoba lagi.';
        _notify();
      }
      throw GrouplyException(
        failure is GrouplyException
            ? failure.message
            : 'Perubahan belum terkonfirmasi. Muat ulang sebelum mencoba lagi.',
      );
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

  Future<void> _connect() async {
    if (!demoMode && authenticated && _active && !_disposed) {
      await _backend.connect(_scheduleRefresh);
    }
  }

  void _scheduleRefresh() {
    _refreshTimer?.cancel();
    _refreshTimer = Timer(const Duration(milliseconds: 120), () async {
      if (!_active || demoMode || _disposed) return;
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
    if (demoMode || _disposed) return;
    try {
      await _backend.foreground();
      await refresh();
      await _connect();
    } catch (_) {
      error = 'Sambungan belum pulih. Coba muat ulang.';
      _notify();
    }
  }

  Map<String, List<String>> _stringLists(dynamic value) =>
      (value as Map? ?? {}).map(
        (key, value) =>
            MapEntry(key as String, (value as List).cast<String>().toList()),
      );

  void _apply(JsonMap value, {bool cloud = true}) {
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
    final blocks = cloud
        ? (value['blockedUserIDs'] as List).cast<String>().toList()
        : <String>[];
    final reads = cloud
        ? (value['readMessageIDs'] as List).cast<String>().toList()
        : <String>[];
    final codes = {
      for (final invite in invites)
        if (invite.text('code').isNotEmpty)
          invite.text('id'): invite.text('code'),
    };
    if (cloud && actor == currentUserID) {
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
    currentUserID = actor;
    if (cloud) {
      _blocks = {actor: blocks};
      _reads = {actor: reads};
    }
  }

  JsonMap _demoSnapshot() => {
    'users': users,
    'groups': groups,
    'projects': projects,
    'tasks': tasks,
    'messages': messages,
    'invites': invites,
    'reports': reports,
    'currentUserID': currentUserID,
    'blocks': _blocks,
    'reads': _reads,
  };
  Future<void> _saveDemo() async {
    if (!demoMode || !_demoWritable) return;
    if (!await _preferences!.setString(
      demoStorageKey,
      jsonEncode(_demoSnapshot()),
    )) {
      throw const GrouplyException('Data demo belum tersimpan.');
    }
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
