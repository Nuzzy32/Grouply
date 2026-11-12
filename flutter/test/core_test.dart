import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grouply/core/backend.dart';
import 'package:grouply/ui/gl.dart';
import 'package:grouply/core/store.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart'
    show AuthException, PostgrestException;

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

  Future<JsonMap> Function(String id) overview = (_) async => {};
  @override
  Future<JsonMap> orgOverview(String id) => overview(id);

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

  group('Organization Plan', () {
    JsonMap org({Object? myRole = 'bph'}) => {
      'id': 'o1',
      'name': 'BEM FST',
      'description': '',
      'periodLabel': '2026/2027',
      'planActive': true,
      'planExpiresAt': '2027-08-31T00:00:00Z',
      'seatLimit': 120,
      'seatsUsed': 87,
      'myRole': myRole,
      'roles': [
        {'userID': 'k1', 'name': 'Rani', 'role': 'ketua'},
      ],
      'divisions': [
        {'id': 'g1', 'name': 'Humas', 'memberCount': 14, 'isMember': true},
      ],
    };
    JsonMap group(String id, Object? orgID) => {
      'id': id,
      'name': id,
      'description': '',
      'course': '',
      'coordinatorID': 'u1',
      'tint': '',
      'icon': '',
      'memberIDs': ['u1'],
      'organizationID': orgID,
    };
    JsonMap snapshot([List<JsonMap>? organizations]) => cloudSnapshot('u1')
      ..['groups'] = [group('g1', 'o1'), group('g2', '')]
      ..addAll({'organizations': ?organizations});

    test('organizations decode with helpers; a missing key is empty', () async {
      backend.actor = 'u1';
      backend.read = () async => snapshot([org()]);
      await store.initialize();
      expect(store.organization('o1')!.text('name'), 'BEM FST');
      expect(store.orgRole('o1'), 'bph');
      expect(store.isDivision(store.group('g1')), isTrue);
      expect(store.isDivision(store.group('g2')), isFalse);
      expect(store.isDivision(null), isFalse);

      backend.read = () async => snapshot([org(myRole: null)]);
      await store.refresh();
      expect(store.orgRole('o1'), '');

      // A database without the migration sends no key at all.
      backend.read = () async => cloudSnapshot('u1');
      await store.refresh();
      expect(store.organizations, isEmpty);
      expect(store.organization('o1'), isNull);
      expect(store.orgRole('o1'), '');
    });

    test('malformed organizations never partially apply', () async {
      backend.actor = 'u1';
      backend.read = () async => snapshot([org()]);
      await store.initialize();
      for (final bad in <JsonMap>[
        snapshot([org()..remove('planActive')]),
        snapshot([org(myRole: 'kadiv')]),
        snapshot([org()..['seatsUsed'] = '87']),
        snapshot([
          org()
            ..['divisions'] = [
              {'id': 'g1', 'name': 'Humas'},
            ],
        ]),
        snapshot([
          org()
            ..['roles'] = [
              {'userID': 'k1', 'name': 'Rani', 'role': 'kadiv'},
            ],
        ]),
        snapshot()..['organizations'] = {'o1': org()},
        snapshot([org()])..['groups'] = [group('g1', 7)],
      ]) {
        backend.read = () async => bad..['users'][0]['name'] = 'Partial';
        await expectLater(store.refresh(), throwsFormatException);
      }
      expect(store.orgRole('o1'), 'bph');
      expect(store.user('u1')!.text('name'), 'Ayu');
    });

    test(
      'server error codes become Indonesian; other failures stay unconfirmed',
      () async {
        backend.actor = 'u1';
        await store.initialize();
        Future<String> failWith(Object error, [String action = 'x']) async {
          backend.write = (_, _) async => throw error;
          try {
            await store.mutate(action, {});
          } on GrouplyException catch (failure) {
            return failure.message;
          }
          throw StateError('mutate should fail');
        }

        PostgrestException raised(String code) =>
            PostgrestException(message: code, code: 'P0001');
        expect(
          await failWith(raised('org_full')),
          'Kursi organisasi sudah penuh. Minta ketua menambah kursi paket.',
        );
        expect(store.error, startsWith('Kursi organisasi sudah penuh'));
        expect(
          await failWith(raised('rate_limited'), 'createOrganization'),
          'Satu orang maksimal menjadi ketua di 3 organisasi.',
        );
        expect(
          await failWith(raised('rate_limited')),
          'Terlalu banyak permintaan. Coba lagi sebentar.',
        );
        const unconfirmed =
            'Perubahan belum terkonfirmasi. Muat ulang sebelum mencoba lagi.';
        expect(await failWith(StateError('offline')), unconfirmed);
        expect(
          await failWith(
            const PostgrestException(message: 'org_full', code: '500'),
          ),
          unconfirmed,
        );
        expect(await failWith(raised('something_new')), unconfirmed);
        for (final code in [
          'org_full',
          'plan_inactive',
          'ketua_transfer_required',
          'org_role_holder',
          'group_full',
          'invite_full',
          'invite_expired',
          'active_assignment',
          'coordinator_transfer_required',
          'stale_version',
          'project_read_only',
          'already_reviewed',
          'rate_limited',
          'forbidden',
          'invalid_input',
          'unauthorized',
        ]) {
          expect(
            GrouplyStore.serverMessage(raised(code)),
            allOf(isNotNull, isNot(contains('_'))),
            reason: code,
          );
        }
      },
    );

    test('overview maps server codes and rejects a malformed shape', () async {
      backend.actor = 'u1';
      await store.initialize();
      backend.overview = (_) async => throw const PostgrestException(
        message: 'plan_inactive',
        code: 'P0001',
      );
      await expectLater(
        store.orgOverview('o1'),
        throwsA(
          isA<GrouplyException>().having(
            (e) => e.message,
            'message',
            startsWith('Paket organisasi belum aktif'),
          ),
        ),
      );
      backend.overview = (_) async => {'divisions': 'bad'};
      await expectLater(
        store.orgOverview('o1'),
        throwsA(
          isA<GrouplyException>().having(
            (e) => e.message,
            'message',
            startsWith('Dashboard belum dapat dimuat'),
          ),
        ),
      );
      final requested = <String>[];
      backend.overview = (id) async {
        requested.add(id);
        return {
          'generatedAt': '2026-10-17T00:00:00Z',
          'divisions': [
            {
              'id': 'g1',
              'projects': [
                {'id': 'p1', 'total': 3},
              ],
            },
          ],
          'attention': <JsonMap>[],
          'users': <JsonMap>[],
        };
      };
      final value = await store.orgOverview('o1');
      expect(requested, ['o1']);
      expect((value['divisions'] as List).single['projects'], [
        {'id': 'p1', 'total': 3},
      ]);
    });
  });
}
