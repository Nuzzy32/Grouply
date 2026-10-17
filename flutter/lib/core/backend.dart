import 'dart:async';
import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

abstract class GrouplyBackend {
  bool get configured;
  String? get currentUserID;
  Stream<String?> get authChanges;
  Future<void> initialize();
  Future<void> signIn(String email, String password);
  Future<bool> signUp(String name, String email, String password);
  Future<void> signOut();
  Future<Map<String, dynamic>> snapshot();
  Future<Map<String, dynamic>> mutate(
    String action,
    Map<String, dynamic> payload,
  );
  Future<void> connect(void Function() onChange);
  Future<void> disconnect();
  Future<void> foreground();
  void dispose();
}

class SecureSessionStorage extends LocalStorage {
  SecureSessionStorage({required this.key, FlutterSecureStorage? storage})
    : storage = storage ?? const FlutterSecureStorage();

  final String key;
  final FlutterSecureStorage storage;
  SharedPreferences? _preferences;
  String get signedOutKey => '$key.signedOut';

  Future<SharedPreferences> _prefs() async =>
      _preferences ??= await SharedPreferences.getInstance();

  @override
  Future<void> initialize() async {
    await _prefs();
  }

  @override
  Future<String?> accessToken() async {
    if ((await _prefs()).getBool(signedOutKey) == true) return null;
    return storage.read(key: key);
  }

  @override
  Future<bool> hasAccessToken() async => await accessToken() != null;
  @override
  Future<void> persistSession(String persistSessionString) async {
    await storage.write(key: key, value: persistSessionString);
    if (!await (await _prefs()).remove(signedOutKey)) {
      throw StateError('Status penyimpanan sesi belum terkonfirmasi.');
    }
  }

  @override
  Future<void> removePersistedSession() async {
    if (!await (await _prefs()).setBool(signedOutKey, true)) {
      throw StateError('Status keluar belum tersimpan.');
    }
    await storage.delete(key: key);
  }
}

class _SecurePKCEStorage extends GotrueAsyncStorage {
  _SecurePKCEStorage(this.storage);
  final SecureSessionStorage storage;
  @override
  Future<String?> getItem({required String key}) =>
      storage.storage.read(key: '${storage.key}.$key');
  @override
  Future<void> setItem({required String key, required String value}) =>
      storage.storage.write(key: '${storage.key}.$key', value: value);
  @override
  Future<void> removeItem({required String key}) =>
      storage.storage.delete(key: '${storage.key}.$key');
}

class SupabaseGrouplyBackend implements GrouplyBackend {
  SupabaseGrouplyBackend({
    String? url,
    String? anonKey,
    SupabaseClient? client,
    LocalStorage? sessionStorage,
  }) : _url = url ?? const String.fromEnvironment('SUPABASE_URL'),
       _key =
           anonKey ??
           const String.fromEnvironment(
             'SUPABASE_PUBLISHABLE_KEY',
             defaultValue: String.fromEnvironment('SUPABASE_ANON_KEY'),
           ),
       _client = client,
       _providedStorage = sessionStorage;

  final String _url, _key;
  final LocalStorage? _providedStorage;
  SupabaseClient? _client;
  late LocalStorage _storage;
  final _changes = StreamController<String?>.broadcast(sync: true);
  StreamSubscription<AuthState>? _auth;
  RealtimeChannel? _channel;
  String? _channelActor;
  Future<void> _writes = Future.value();
  bool _initialized = false, _disposed = false;
  Object? _storageFailure;

  @override
  bool get configured {
    if (_client != null) return true;
    final uri = Uri.tryParse(_url);
    final authority = RegExp(
      r'^[a-zA-Z][a-zA-Z0-9+.-]*://([^/?#]*)',
    ).firstMatch(_url)?.group(1);
    if (uri == null ||
        authority == null ||
        authority.contains('@') ||
        authority.contains('%') ||
        uri.host.isEmpty ||
        !uri.hasAuthority ||
        uri.authority.contains('@') ||
        uri.hasQuery ||
        uri.hasFragment ||
        _url.trim() != _url ||
        _key.contains(r'$(') ||
        _key.startsWith('sb_secret_')) {
      return false;
    }
    final local = [
      'localhost',
      '127.0.0.1',
      '::1',
      '10.0.2.2',
      '10.0.3.2',
    ].contains(uri.host);
    if (uri.scheme != 'https' && !(uri.scheme == 'http' && local)) return false;
    if (RegExp(r'^sb_publishable_[A-Za-z0-9_-]+$').hasMatch(_key)) return true;
    final segments = _key.split('.');
    if (segments.length != 3 || segments.any((segment) => segment.isEmpty)) {
      return false;
    }
    try {
      final payload = jsonDecode(
        utf8.decode(base64Url.decode(base64Url.normalize(segments[1]))),
      );
      return payload is Map && payload['role'] == 'anon';
    } catch (_) {
      return false;
    }
  }

  @override
  String? get currentUserID => _client?.auth.currentSession?.isExpired == false
      ? _client?.auth.currentUser?.id
      : null;
  @override
  Stream<String?> get authChanges => _changes.stream;

  SupabaseClient get _sdk {
    if (!_initialized || _client == null || _disposed) {
      throw StateError('Backend belum dikonfigurasi.');
    }
    return _client!;
  }

  @override
  Future<void> initialize() async {
    if (_initialized || _disposed || !configured) return;
    _storage =
        _providedStorage ??
        SecureSessionStorage(key: 'grouply.auth.${Uri.encodeComponent(_url)}');
    await _storage.initialize();
    if (_disposed) return;
    _client ??= SupabaseClient(
      _url,
      _key,
      authOptions: AuthClientOptions(
        pkceAsyncStorage: _storage is SecureSessionStorage
            ? _SecurePKCEStorage(_storage as SecureSessionStorage)
            : null,
      ),
    );
    _initialized = true;
    _auth = _sdk.auth.onAuthStateChange.listen(
      (state) {
        if (_disposed) return;
        _changes.add(currentUserID);
        final encoded = state.session == null
            ? null
            : jsonEncode(state.session!.toJson());
        _writes = _writes
            .then((_) async {
              if (encoded == null) {
                await _storage.removePersistedSession();
              } else {
                await _storage.persistSession(encoded);
              }
              _storageFailure = null;
            })
            .catchError((Object failure) {
              _storageFailure = failure;
            });
      },
      onError: (Object _, StackTrace _) {
        if (_disposed) return;
        if (currentUserID == null) {
          _changes.add(null);
        } else {
          _changes.addError(StateError('Sesi belum dapat diperbarui.'));
        }
      },
    );
    final persisted = await _storage.accessToken();
    if (persisted != null) {
      try {
        await _sdk.auth.recoverSession(persisted);
      } on FormatException {
        await _storage.removePersistedSession();
        throw const FormatException('Sesi tersimpan tidak valid.');
      }
    }
    await _flushStorage();
  }

  Future<void> _flushStorage() async {
    await _writes;
    if (_storageFailure != null) {
      throw StateError('Penyimpanan sesi aman gagal.');
    }
  }

  @override
  Future<void> signIn(String email, String password) async {
    await initialize();
    await _sdk.auth.signInWithPassword(email: email, password: password);
    try {
      await _flushStorage();
    } catch (_) {
      await signOut();
      rethrow;
    }
  }

  @override
  Future<bool> signUp(String name, String email, String password) async {
    await initialize();
    final response = await _sdk.auth.signUp(
      email: email,
      password: password,
      data: {'name': name},
    );
    try {
      await _flushStorage();
    } catch (_) {
      if (response.session != null) await signOut();
      rethrow;
    }
    return response.session != null;
  }

  @override
  Future<void> signOut() async {
    if (!_initialized) return;
    await disconnect();
    try {
      await _sdk.auth.signOut();
    } finally {
      try {
        await _flushStorage();
      } finally {
        await _storage.removePersistedSession();
      }
    }
  }

  Map<String, dynamic> _object(dynamic value) {
    if (value is! Map) {
      throw const FormatException('Respons server tidak valid.');
    }
    return Map<String, dynamic>.from(value);
  }

  @override
  Future<Map<String, dynamic>> snapshot() async =>
      _object(await _sdk.rpc('grouply_snapshot', params: {}));
  @override
  Future<Map<String, dynamic>> mutate(
    String action,
    Map<String, dynamic> payload,
  ) async => _object(
    await _sdk.rpc(
      'grouply_mutate',
      params: {'action': action, 'payload': payload},
    ),
  );

  @override
  Future<void> connect(void Function() onChange) async {
    final actor = currentUserID;
    if (actor == null || _disposed || _channelActor == actor) return;
    await disconnect();
    if (actor != currentUserID || _disposed || _channelActor == actor) return;
    _channelActor = actor;
    _sdk.auth.startAutoRefresh();
    final channel = _sdk.channel('grouply:$actor');
    _channel = channel;
    void changed() {
      if (!_disposed &&
          identical(_channel, channel) &&
          currentUserID == actor) {
        onChange();
      }
    }

    channel.onPostgresChanges(
      event: PostgresChangeEvent.insert,
      schema: 'public',
      table: 'chat_messages',
      callback: (_) => changed(),
    );
    channel.onPostgresChanges(
      event: PostgresChangeEvent.insert,
      schema: 'public',
      table: 'chat_reads',
      filter: PostgresChangeFilter(
        type: PostgresChangeFilterType.eq,
        column: 'user_id',
        value: actor,
      ),
      callback: (_) => changed(),
    );
    for (final event in [
      PostgresChangeEvent.insert,
      PostgresChangeEvent.update,
    ]) {
      channel.onPostgresChanges(
        event: event,
        schema: 'public',
        table: 'user_sync_state',
        filter: PostgresChangeFilter(
          type: PostgresChangeFilterType.eq,
          column: 'user_id',
          value: actor,
        ),
        callback: (_) => changed(),
      );
    }
    channel.subscribe((status, _) {
      if (status == RealtimeSubscribeStatus.subscribed) changed();
    });
  }

  @override
  Future<void> disconnect() async {
    final channel = _channel;
    _channel = null;
    _channelActor = null;
    _client?.auth.stopAutoRefresh();
    if (channel != null) await _client?.removeChannel(channel);
  }

  @override
  Future<void> foreground() async {
    if (!_initialized || _sdk.auth.currentSession == null) return;
    _sdk.auth.startAutoRefresh();
    if (_sdk.auth.currentSession?.isExpired == true) {
      await _sdk.auth.refreshSession();
    }
    await _flushStorage();
  }

  @override
  void dispose() {
    _disposed = true;
    unawaited(_auth?.cancel());
    unawaited(
      disconnect().then((_) async {
        await _writes;
        await _client?.dispose();
        await _changes.close();
      }),
    );
  }
}
