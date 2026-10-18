import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grouply/core/backend.dart';
import 'package:grouply/ui/gl.dart';
import 'package:grouply/core/store.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show AuthException;

JsonMap cloudSnapshot(String actor, {String name = 'Ayu'}) => {
  'currentUserID': actor,
  'users': [
    {'id': actor, 'name': name, 'email': '', 'tint': '#000000'},
  ],
  'groups': <JsonMap>[],
  'projects': <JsonMap>[],
  'tasks': <JsonMap>[],
  'messages': <JsonMap>[],
  'invites': <JsonMap>[],
  'reports': <JsonMap>[],
  'blockedUserIDs': <String>[],
  'readMessageIDs': <String>[],
};

class FakeBackend implements GrouplyBackend {
  FakeBackend({this.actor});
  String? actor;
  bool available = true;
  int mutations = 0, snapshots = 0, connections = 0;
  Completer<void>? loginGate;
  Future<JsonMap> Function()? read;
  Future<JsonMap> Function(String, JsonMap)? write;
  final changes = StreamController<String?>.broadcast(sync: true);
  @override
  bool get configured => available;
  @override
  String? get currentUserID => actor;
  @override
  Stream<String?> get authChanges => changes.stream;
  @override
  Future<void> initialize() async {}
  @override
  Future<void> signIn(String email, String password) async {
    await loginGate?.future;
    actor = email;
    changes.add(actor);
  }

  bool confirmEmail = false;
  Object? authFailure;
  String resetCode = '123456';
  final signUps = <String>[], resetRequests = <String>[];
  @override
  Future<bool> signUp(String name, String email, String password) async {
    if (authFailure != null) throw authFailure!;
    signUps.add('$name|$email');
    if (confirmEmail) return false;
    actor = email;
    changes.add(actor);
    return true;
  }

  @override
  Future<void> sendPasswordReset(String email) async {
    if (authFailure != null) throw authFailure!;
    resetRequests.add(email);
  }

  @override
  Future<void> resetPassword(String email, String code, String password) async {
    if (code != resetCode) {
      throw const AuthException('Token expired', code: 'otp_expired');
    }
    actor = email;
    changes.add(actor);
  }

  @override
  Future<void> signOut() async {
    actor = null;
    changes.add(null);
  }

  @override
  Future<JsonMap> snapshot() async {
    snapshots++;
    return read == null ? snapshotFixture() : read!();
  }

  JsonMap snapshotFixture() => cloudSnapshot(actor!);
  @override
  Future<JsonMap> mutate(String action, JsonMap payload) async {
    mutations++;
    return write == null ? {} : write!(action, payload);
  }

  @override
  Future<void> connect(void Function() onChange) async {
    connections++;
  }

  @override
  Future<void> disconnect() async {}
  @override
  Future<void> foreground() async {}
  @override
  void dispose() {
    unawaited(changes.close());
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late FakeBackend backend;
  late GrouplyStore store;
  final now = DateTime.utc(2026, 10, 17);

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    backend = FakeBackend();
    store = GrouplyStore(backend: backend, clock: () => now);
  });
  tearDown(() => store.dispose());

  test(
    'sign-up with a session trims input, loads the snapshot and connects',
    () async {
      expect(
        await store.signUp('  Ayu  ', ' ayu@example.com ', 'rahasia123'),
        isTrue,
      );
      expect(backend.signUps, ['Ayu|ayu@example.com']);
      expect(store.currentUserID, 'ayu@example.com');
      expect(backend.snapshots, 1);
      expect(backend.connections, 1);
      expect(store.loading, isFalse);
    },
  );

  test('sign-up awaiting email confirmation stays signed out', () async {
    backend.confirmEmail = true;
    expect(await store.signUp('Ayu', 'ayu@example.com', 'rahasia123'), isFalse);
    expect(store.authenticated, isFalse);
    expect(backend.snapshots, 0);
    expect(store.loading, isFalse);
    expect(store.error, isNull);
  });

  test('auth failures become readable messages without signing in', () async {
    backend.authFailure = const AuthException(
      'exists',
      code: 'user_already_exists',
    );
    await expectLater(
      store.signUp('Ayu', 'ayu@example.com', 'rahasia123'),
      throwsA(
        isA<GrouplyException>().having(
          (e) => e.message,
          'message',
          'Email sudah terdaftar. Silakan masuk.',
        ),
      ),
    );
    expect(store.authenticated, isFalse);
    expect(store.loading, isFalse);
    backend.authFailure = const AuthException(
      'slow down',
      code: 'over_email_send_rate_limit',
    );
    await expectLater(
      store.sendPasswordReset('ayu@example.com'),
      throwsA(
        isA<GrouplyException>().having(
          (e) => e.message,
          'message',
          'Terlalu banyak percobaan. Coba lagi nanti.',
        ),
      ),
    );
    backend.authFailure = StateError('offline');
    await expectLater(
      store.sendPasswordReset('ayu@example.com'),
      throwsA(
        isA<GrouplyException>().having(
          (e) => e.message,
          'message',
          'Kode belum dapat dikirim. Periksa email dan koneksi.',
        ),
      ),
    );
  });

  test(
    'password reset rejects a wrong code, then signs in with the right one',
    () async {
      await store.sendPasswordReset(' ayu@example.com ');
      expect(backend.resetRequests, ['ayu@example.com']);
      await expectLater(
        store.resetPassword('ayu@example.com', '000000', 'baru12345'),
        throwsA(
          isA<GrouplyException>().having(
            (e) => e.message,
            'message',
            'Kode salah atau kedaluwarsa. Minta kode baru.',
          ),
        ),
      );
      expect(store.authenticated, isFalse);
      await store.resetPassword('ayu@example.com', ' 123456 ', 'baru12345');
      expect(store.currentUserID, 'ayu@example.com');
      expect(backend.snapshots, 1);
    },
  );

  test('JSON helpers preserve Swift camelCase, numbers, IDs and dates', () {
    final row = <String, dynamic>{
      'currentUserID': 'u1',
      'version': 2,
      'memberIDs': ['u1', 'u2'],
      'dueAt': '2026-10-17T10:20:30.123456Z',
    };
    expect(row.text('currentUserID'), 'u1');
    expect(row.number('version'), 2);
    expect(row.ids('memberIDs'), ['u1', 'u2']);
    expect(row.date('dueAt')?.microsecond, 456);
    expect(row.text('missing'), '');
    expect(row.date('missing'), isNull);
  });

  test(
    'server snapshot and personal state never persist to demo storage',
    () async {
      backend.actor = 'u1';
      backend.read = () async => cloudSnapshot('u1')
        ..['blockedUserIDs'] = ['u2']
        ..['readMessageIDs'] = ['m1'];
      await store.initialize();
      expect(store.authenticated, isTrue);
      expect(store.blockedUserIDs, ['u2']);
      expect(store.readMessageIDs, ['m1']);
      expect((await SharedPreferences.getInstance()).getKeys(), isEmpty);
      await store.signOut();
      expect(store.users, isEmpty);
      expect(store.blockedUserIDs, isEmpty);
      expect(store.readMessageIDs, isEmpty);
    },
  );

  test(
    'out-of-order refresh and stale errors cannot replace newer state',
    () async {
      backend.actor = 'u1';
      await store.initialize();
      final older = Completer<JsonMap>(), newer = Completer<JsonMap>();
      backend.read = () => older.future;
      final first = store.refresh();
      backend.read = () => newer.future;
      final second = store.refresh();
      newer.complete(cloudSnapshot('u1', name: 'New'));
      await second;
      older.completeError(StateError('old request'));
      await expectLater(first, throwsStateError);
      expect(store.user('u1')!.text('name'), 'New');
      expect(store.error, isNull);
    },
  );

  test(
    'sign-out invalidates in-flight snapshots across account boundaries',
    () async {
      backend.actor = 'u1';
      await store.initialize();
      final pending = Completer<JsonMap>();
      backend.read = () => pending.future;
      final reading = store.refresh();
      await store.signOut();
      pending.complete(cloudSnapshot('u1', name: 'Private'));
      await reading;
      expect(store.authenticated, isFalse);
      expect(store.users, isEmpty);
      backend.read = null;
      await store.signIn('u2', 'password');
      expect(store.currentUserID, 'u2');
      expect(store.user('u1'), isNull);
    },
  );

  test(
    'sign-out waits for delayed sign-in and leaves no live SDK account',
    () async {
      await store.initialize();
      backend.loginGate = Completer<void>();
      final signingIn = store.signIn('u1', 'password');
      await Future<void>.delayed(Duration.zero);
      final signingOut = store.signOut();
      backend.loginGate!.complete();
      await signingIn;
      await signingOut;
      expect(backend.actor, isNull);
      expect(store.authenticated, isFalse);
      expect(store.loading, isFalse);
    },
  );

  test(
    'mutation uses raw RPC result then separate snapshot, never local fallback',
    () async {
      backend.actor = 'u1';
      await store.initialize();
      backend.write = (action, payload) async {
        expect(action, 'createGroup');
        expect(payload, {'name': 'Group', 'description': '', 'course': ''});
        return {'id': 'created'};
      };
      expect(
        await store.mutate('createGroup', {
          'name': 'Group',
          'description': '',
          'course': '',
        }),
        {'id': 'created'},
      );
      expect(backend.snapshots, 2);
      backend.write = (_, _) async => throw StateError('offline');
      await expectLater(
        store.mutate('createGroup', {'name': 'Not local'}),
        throwsA(isA<GrouplyException>()),
      );
      expect(store.groups, isEmpty);
    },
  );

  test(
    'saved mutation returns its ID even when subsequent snapshot fails',
    () async {
      backend.actor = 'u1';
      await store.initialize();
      backend.write = (_, _) async => {'id': 'saved-on-server'};
      backend.read = () async => throw StateError('offline');
      expect(
        (await store.mutate('createGroup', {'name': 'Saved'}))['id'],
        'saved-on-server',
      );
      expect(store.error, contains('tersimpan di server'));
      expect(backend.mutations, 1);
    },
  );

  test('malformed and wrong-account snapshots never partially apply', () async {
    backend.actor = 'u1';
    await store.initialize();
    backend.read = () async => cloudSnapshot('u2');
    await expectLater(store.refresh(), throwsFormatException);
    expect(store.currentUserID, 'u1');
    backend.read = () async =>
        cloudSnapshot('u1', name: 'Partial')
          ..['tasks'] = [
            {'id': 'bad'},
          ];
    await expectLater(store.refresh(), throwsFormatException);
    expect(store.user('u1')!.text('name'), 'Ayu');
  });

  test(
    'delete confirmation signs out without fetching deleted profile',
    () async {
      backend.actor = 'u1';
      await store.initialize();
      backend.write = (_, _) async => {'deleted': true};
      expect(await store.mutate('deleteAccount'), {'deleted': true});
      expect(backend.snapshots, 1);
      expect(store.authenticated, isFalse);
    },
  );

  test(
    'background disconnects and foreground refreshes the missed gap',
    () async {
      backend.actor = 'u1';
      await store.initialize();
      store.didChangeAppLifecycleState(AppLifecycleState.paused);
      backend.read = () async =>
          cloudSnapshot('u1', name: 'Updated while away');
      store.didChangeAppLifecycleState(AppLifecycleState.resumed);
      await Future<void>.delayed(Duration.zero);
      expect(store.user('u1')!.text('name'), 'Updated while away');
    },
  );
  test(
    'glTint maps pastel data colors and blends unknown colors in dark mode',
    () {
      final previous = GLTheme.dark;
      try {
        GLTheme.dark = true;
        expect(glTint('#DED2FF'), const Color(0xFF3A3354));
        // Same blend as Swift `Color(tint:)`: 28% over 1C1E20 per channel.
        expect(glTint('D6E4FF'), const Color(0xFF50555E));
      } finally {
        GLTheme.dark = previous;
      }
    },
  );
}
