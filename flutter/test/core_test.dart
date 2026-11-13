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

  Future<JsonMap> Function(String id) meeting = (_) async => {};
  @override
  Future<JsonMap> meetingDetail(String id) => meeting(id);

  final reads = <String>[];
  Future<List<JsonMap>> Function(String id) templateList = (_) async => [];
  @override
  Future<List<JsonMap>> templates(String orgID) {
    reads.add('templates:$orgID');
    return templateList(orgID);
  }

  Future<JsonMap> Function(String id) templateDetail = (_) async => {};
  @override
  Future<JsonMap> template(String id) {
    reads.add('template:$id');
    return templateDetail(id);
  }

  Future<JsonMap> Function(String id) archive = (_) async => {};
  @override
  Future<JsonMap> orgArchive(String orgID) {
    reads.add('archive:$orgID');
    return archive(orgID);
  }

  Future<JsonMap> Function(String, String?, List<String>?) reportData =
      (_, _, _) async => {};
  @override
  Future<JsonMap> report(
    String groupID, {
    String? periodID,
    List<String>? projectIDs,
  }) {
    reads.add('report:$groupID:$periodID:$projectIDs');
    return reportData(groupID, periodID, projectIDs);
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
    'an overtaken refresh resolves only after the newer state applies',
    () async {
      backend.actor = 'u1';
      await store.initialize();
      final older = Completer<JsonMap>(), newer = Completer<JsonMap>();
      backend.read = () => older.future;
      final first = store.refresh();
      backend.read = () => newer.future;
      final second = store.refresh();
      var resolved = false;
      unawaited(first.then((_) => resolved = true));
      older.complete(cloudSnapshot('u1', name: 'Old'));
      await Future<void>.delayed(Duration.zero);
      expect(resolved, isFalse);
      newer.complete(cloudSnapshot('u1', name: 'New'));
      await first;
      expect(store.user('u1')!.text('name'), 'New');
      await second;
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
          'approval_closed',
          'meeting_closed',
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

  group('Organization Plan Tahap 2', () {
    JsonMap approval({
      String status = 'pending',
      bool eligible = true,
      String approver = 'u1',
    }) => {
      'id': 'a1',
      'groupID': 'g1',
      'groupName': 'Humas',
      'title': 'Dana publikasi',
      'note': 'Cetak poster',
      'amount': 750000,
      'links': <String>[],
      'status': status,
      'createdAt': '2026-11-10T00:00:00Z',
      'closedAt': null,
      'requesterID': 'u2',
      'requesterName': 'Raka',
      'steps': [
        {
          'position': 1,
          'approverID': 'k1',
          'name': 'Rani',
          'eligible': true,
          'decision': 'approved',
          'note': '',
          'decidedAt': '2026-11-11T00:00:00Z',
        },
        {
          'position': 2,
          'approverID': approver,
          'name': 'Ayu',
          'eligible': eligible,
          'decision': null,
          'note': '',
          'decidedAt': null,
        },
      ],
    };
    JsonMap announcement(String id, bool read) => {
      'id': id,
      'groupID': '',
      'title': 'Info',
      'body': 'Isi',
      'createdAt': '2026-11-12T00:00:00Z',
      'authorID': 'k1',
      'authorName': 'Rani',
      'read': read,
      'readCount': 0,
      'audienceCount': 0,
      'unreadIDs': <String>[],
    };
    JsonMap org({List<JsonMap>? approvals, List<JsonMap>? announcements}) => {
      'id': 'o1',
      'name': 'BEM FST',
      'description': '',
      'periodLabel': '',
      'planActive': true,
      'planExpiresAt': null,
      'seatLimit': 120,
      'seatsUsed': 3,
      'myRole': '',
      'roles': <JsonMap>[],
      'divisions': [
        {
          'id': 'g1',
          'name': 'Humas',
          'memberCount': 3,
          'isMember': true,
          'isCommittee': false,
        },
      ],
      'approvals': ?approvals,
      'announcements': ?announcements,
    };
    JsonMap group(String id, {Object? committee}) => {
      'id': id,
      'name': id,
      'description': '',
      'course': '',
      'coordinatorID': 'k1',
      'tint': '',
      'icon': '',
      'memberIDs': ['u1', 'k1'],
      'organizationID': 'o1',
      'isCommittee': ?committee,
    };
    JsonMap project(String id, Object? lead) => {
      'id': id,
      'groupID': 'g1',
      'title': id,
      'description': '',
      'dueAt': '2026-12-01T00:00:00Z',
      'status': 'active',
      'leadID': ?lead,
    };
    JsonMap meeting({String status = 'scheduled'}) => {
      'id': 'm1',
      'groupID': 'g1',
      'title': 'Rapat mingguan',
      'startsAt': '2026-11-14T09:00:00Z',
      'place': 'Sekre',
      'status': status,
      'version': 1,
      'createdBy': 'k1',
      'noteTakerID': '',
      'hasMinutes': false,
      'present': 0,
      'excused': 0,
      'myStatus': '',
      'taskIDs': <String>[],
    };
    JsonMap snapshot({
      JsonMap? organization,
      List<JsonMap>? meetings,
      Object? committee = true,
    }) => cloudSnapshot('u1')
      ..['groups'] = [group('g1'), group('g2', committee: committee)]
      ..['projects'] = [project('p1', 'u1'), project('p2', '')]
      ..addAll({
        'organizations': [organization ?? org()],
        'meetings': ?meetings,
      });

    test('decodes Tahap 2 keys with helpers', () async {
      backend.actor = 'u1';
      backend.read = () async => snapshot(
        organization: org(
          approvals: [
            approval(),
            approval(eligible: false)..['id'] = 'a2',
            approval(status: 'approved')..['id'] = 'a3',
            approval(approver: 'x9')..['id'] = 'a4',
          ],
          announcements: [announcement('n1', false), announcement('n2', true)],
        ),
        meetings: [meeting()],
      );
      await store.initialize();
      expect(store.isCommittee(store.group('g2')), isTrue);
      expect(store.isCommittee(store.group('g1')), isFalse);
      expect(store.isCommittee(null), isFalse);
      // u1 is not the coordinator (k1) but leads p1.
      expect(store.canManageTasks(store.project('p1')), isTrue);
      expect(store.canManageTasks(store.project('p2')), isFalse);
      expect(store.canManageTasks(null), isFalse);
      expect(store.pendingForMe('o1').map((a) => a['id']), ['a1']);
      expect(store.unreadAnnouncements('o1').map((a) => a['id']), ['n1']);
      expect(store.meeting('m1')!.text('title'), 'Rapat mingguan');
      expect(
        GrouplyStore.currentStep(store.approvals('o1').first)!['position'],
        2,
      );
    });

    test('a database without Tahap 2 decodes as empty', () async {
      backend.actor = 'u1';
      backend.read = () async =>
          snapshot(committee: null)..['projects'] = [project('p1', null)];
      await store.initialize();
      expect(store.meetings, isEmpty);
      expect(store.approvals('o1'), isEmpty);
      expect(store.announcements('o1'), isEmpty);
      expect(store.pendingForMe('o1'), isEmpty);
      expect(store.isCommittee(store.group('g2')), isFalse);
      expect(store.canManageTasks(store.project('p1')), isFalse);
    });

    test('malformed Tahap 2 keys never partially apply', () async {
      backend.actor = 'u1';
      backend.read = () async => snapshot(meetings: [meeting()]);
      await store.initialize();
      for (final bad in <JsonMap>[
        snapshot(meetings: [meeting(status: 'postponed')]),
        snapshot(meetings: [meeting()..['version'] = '1']),
        snapshot()..['meetings'] = {'m1': meeting()},
        snapshot(committee: 'yes'),
        snapshot()..['projects'] = [project('p1', 7)],
        snapshot(
          organization: org(approvals: [approval(status: 'open')]),
        ),
        snapshot(
          organization: org(approvals: [approval()..['amount'] = '750000']),
        ),
        snapshot(
          organization: org(
            approvals: [
              approval()
                ..['steps'] = [
                  {'position': 1, 'approverID': 'u1'},
                ],
            ],
          ),
        ),
        snapshot(
          organization: org(
            announcements: [announcement('n1', false)..['read'] = 'no'],
          ),
        ),
      ]) {
        backend.read = () async => bad..['users'][0]['name'] = 'Partial';
        await expectLater(store.refresh(), throwsFormatException);
      }
      expect(store.meeting('m1'), isNotNull);
      expect(store.user('u1')!.text('name'), 'Ayu');
    });

    test('closed approval, closed meeting and stale version reload', () async {
      backend.actor = 'u1';
      await store.initialize();
      for (final code in [
        'approval_closed',
        'meeting_closed',
        'stale_version',
      ]) {
        final before = backend.snapshots;
        backend.write = (_, _) async =>
            throw PostgrestException(message: code, code: 'P0001');
        await expectLater(
          store.mutate('decideApproval', {'id': 'a1'}),
          throwsA(isA<GrouplyException>()),
        );
        // Mutation failed before its own snapshot; the reload is scheduled.
        expect(backend.snapshots, before);
        await Future<void>.delayed(const Duration(milliseconds: 200));
        expect(backend.snapshots, before + 1, reason: code);
      }
      final before = backend.snapshots;
      backend.write = (_, _) async =>
          throw const PostgrestException(message: 'forbidden', code: 'P0001');
      await expectLater(
        store.mutate('decideApproval', {'id': 'a1'}),
        throwsA(isA<GrouplyException>()),
      );
      await Future<void>.delayed(const Duration(milliseconds: 200));
      expect(backend.snapshots, before);
    });

    test('rate limits name their own limit per action', () {
      String text(String action) =>
          GrouplyStore.codeText('rate_limited', action);
      expect(
        text('requestApproval'),
        startsWith('Maksimal 5 pengajuan terbuka'),
      );
      expect(text('postAnnouncement'), contains('5 per jam'));
      for (final action in [
        'createMeeting',
        'updateMeeting',
        'cancelMeeting',
        'recordMeeting',
      ]) {
        expect(text(action), contains('30 perubahan rapat'), reason: action);
      }
      expect(
        text('sendMessage'),
        'Terlalu banyak permintaan. Coba lagi sebentar.',
      );
    });

    test('forbidden on a task action reloads; elsewhere it does not', () async {
      backend.actor = 'u1';
      await store.initialize();
      backend.write = (_, _) async =>
          throw const PostgrestException(message: 'forbidden', code: 'P0001');
      for (final (action, reloads) in [
        ('createTask', true),
        ('updateTask', true),
        ('reassignTask', true),
        ('reopenTask', true),
        ('updateProject', false),
      ]) {
        final before = backend.snapshots;
        await expectLater(
          store.mutate(action, {}),
          throwsA(isA<GrouplyException>()),
        );
        await Future<void>.delayed(const Duration(milliseconds: 200));
        expect(backend.snapshots, before + (reloads ? 1 : 0), reason: action);
      }
    });

    test('meeting detail decodes, maps codes and rejects bad shapes', () async {
      backend.actor = 'u1';
      await store.initialize();
      final requested = <String>[];
      backend.meeting = (id) async {
        requested.add(id);
        return {
          'id': id,
          'version': 3,
          'agenda': 'Evaluasi',
          'minutes': '',
          'attendance': [
            {'userID': 'u1', 'status': 'hadir'},
          ],
        };
      };
      final value = await store.meetingDetail('m1');
      expect(requested, ['m1']);
      expect(value['attendance'], [
        {'userID': 'u1', 'status': 'hadir'},
      ]);
      backend.meeting = (_) async => {
        'version': 3,
        'agenda': '',
        'minutes': '',
        'attendance': [
          {'userID': 'u1', 'status': 'alpa'},
        ],
      };
      await expectLater(
        store.meetingDetail('m1'),
        throwsA(
          isA<GrouplyException>().having(
            (e) => e.message,
            'message',
            startsWith('Detail rapat belum dapat dimuat'),
          ),
        ),
      );
      backend.meeting = (_) async =>
          throw const PostgrestException(message: 'forbidden', code: 'P0001');
      await expectLater(
        store.meetingDetail('m1'),
        throwsA(
          isA<GrouplyException>().having(
            (e) => e.message,
            'message',
            'Kamu tidak punya izin untuk tindakan ini.',
          ),
        ),
      );
    });
  });

  group('Organization Plan Tahap 3a', () {
    JsonMap org({Object? periods, Object? closed}) => {
      'id': 'o1',
      'name': 'BEM FST',
      'description': '',
      'periodLabel': '2027/2028',
      'planActive': false,
      'planExpiresAt': null,
      'seatLimit': 0,
      'seatsUsed': 3,
      'myRole': 'ketua',
      'roles': <JsonMap>[],
      'divisions': [
        {
          'id': 'g1',
          'name': 'Panitia',
          'memberCount': 3,
          'isMember': true,
          'isCommittee': true,
          'closed': ?closed,
        },
      ],
      'periods': ?periods,
    };
    JsonMap period = {
      'id': 'pe1',
      'label': '2026/2027',
      'startedAt': null,
      'closedAt': '2026-11-01T00:00:00Z',
    };
    JsonMap item(String id, int position) => {
      'id': id,
      'position': position,
      'title': 'Butir $id',
      'description': '',
      'dueAt': '2026-11-20T16:59:00Z',
    };
    JsonMap project({Object? label, Object? items}) => {
      'id': 'p1',
      'groupID': 'g1',
      'title': 'Sie Acara',
      'description': '',
      'dueAt': '2026-12-01T00:00:00Z',
      'status': 'active',
      'periodLabel': ?label,
      'planItems': ?items,
    };
    JsonMap snapshot({
      Object? closed,
      Object? periods,
      Object? label,
      Object? items,
      Object? divisionClosed,
    }) => cloudSnapshot('u1')
      ..['groups'] = [
        {
          'id': 'g1',
          'name': 'Panitia',
          'description': '',
          'course': '',
          'coordinatorID': 'u1',
          'tint': '',
          'icon': '',
          'memberIDs': ['u1'],
          'organizationID': 'o1',
          'isCommittee': true,
          'closed': ?closed,
        },
      ]
      ..['projects'] = [project(label: label, items: items)]
      ..['organizations'] = [org(periods: periods, closed: divisionClosed)];

    test('decodes Tahap 3a keys; plan items sort by position', () async {
      backend.actor = 'u1';
      backend.read = () async => snapshot(
        closed: true,
        divisionClosed: true,
        periods: [period],
        label: '2026/2027',
        items: [item('b', 2), item('a', 1)],
      );
      await store.initialize();
      expect(store.isClosed(store.group('g1')), isTrue);
      expect(store.isClosed(null), isFalse);
      expect(store.periods('o1').single['label'], '2026/2027');
      expect(store.project('p1')!['periodLabel'], '2026/2027');
      expect(store.planItems(store.project('p1')).map((i) => i['id']), [
        'a',
        'b',
      ]);
      expect(
        (store.organization('o1')!['divisions'] as List).single['closed'],
        isTrue,
      );
    });

    test('a database without Tahap 3a decodes as empty', () async {
      backend.actor = 'u1';
      backend.read = () async => snapshot();
      await store.initialize();
      expect(store.isClosed(store.group('g1')), isFalse);
      expect(store.periods('o1'), isEmpty);
      expect(store.project('p1')!['periodLabel'], '');
      expect(store.planItems(store.project('p1')), isEmpty);
      expect(store.planItems(null), isEmpty);
    });

    test('malformed Tahap 3a keys never partially apply', () async {
      backend.actor = 'u1';
      backend.read = () async => snapshot();
      await store.initialize();
      for (final bad in <JsonMap>[
        snapshot(closed: 'yes'),
        snapshot(divisionClosed: 1),
        snapshot(label: 2026),
        snapshot(items: {'a': item('a', 1)}),
        snapshot(items: [item('a', 1)..['position'] = '1']),
        snapshot(items: [item('a', 1)..['dueAt'] = 'besok']),
        snapshot(items: [item('', 1)]),
        snapshot(
          periods: [
            {...period, 'closedAt': null},
          ],
        ),
        snapshot(
          periods: [
            {...period, 'label': null},
          ],
        ),
        snapshot(periods: 'pe1'),
      ]) {
        backend.read = () async => bad..['users'][0]['name'] = 'Partial';
        await expectLater(store.refresh(), throwsFormatException);
      }
      expect(store.user('u1')!.text('name'), 'Ayu');
    });

    test('new error codes have their own text and reload when stale', () async {
      expect(
        GrouplyStore.codeText('group_closed'),
        startsWith('Kepanitiaan ini sudah ditutup'),
      );
      expect(
        GrouplyStore.codeText('committee_busy'),
        startsWith('Kepanitiaan belum bisa ditutup'),
      );
      expect(
        GrouplyStore.codeText('plan_item_used'),
        startsWith('Butir rencana ini sudah dijadikan tugas'),
      );
      expect(
        GrouplyStore.codeText('period_exists'),
        startsWith('Label periode itu sudah pernah ditutup'),
      );
      expect(
        GrouplyStore.codeText('rate_limited', 'applyTemplate'),
        contains('5 kali per jam'),
      );
      expect(
        GrouplyStore.codeText('rate_limited', 'createTemplate'),
        contains('50 template'),
      );
      backend.actor = 'u1';
      await store.initialize();
      for (final (code, reloads) in [
        ('group_closed', true),
        ('plan_item_used', true),
        ('committee_busy', false),
        ('period_exists', false),
      ]) {
        final before = backend.snapshots;
        backend.write = (_, _) async =>
            throw PostgrestException(message: code, code: 'P0001');
        await expectLater(
          store.mutate('createTask', {}),
          throwsA(isA<GrouplyException>()),
        );
        await Future<void>.delayed(const Duration(milliseconds: 200));
        expect(backend.snapshots, before + (reloads ? 1 : 0), reason: code);
      }
    });

    test('read RPCs pass parameters, decode lists and map codes', () async {
      backend.actor = 'u1';
      await store.initialize();
      backend.templateList = (_) async => [
        {
          'id': 't1',
          'name': 'Seminar',
          'description': '',
          'builtIn': true,
          'sectionCount': 2,
          'itemCount': 3,
          'createdAt': '2026-01-01T00:00:00Z',
          'mine': false,
        },
      ];
      expect((await store.templates('o1')).single['name'], 'Seminar');
      backend.templateDetail = (id) async => {
        'id': id,
        'name': 'Seminar',
        'description': '',
        'builtIn': true,
        'sections': [
          {
            'title': 'Sie Acara',
            'description': '',
            'offsetDays': -1,
            'items': [
              {'title': 'Rundown', 'description': '', 'offsetDays': -7},
            ],
          },
        ],
      };
      final detail = await store.template('t1');
      expect((detail['sections'] as List).single['items'], hasLength(1));
      backend.archive = (_) async => {
        'periods': [
          {
            ...period,
            'projects': [
              {
                'id': 'p1',
                'groupID': 'g1',
                'title': 'A',
                'total': 1,
                'done': 1,
              },
            ],
            'committees': <JsonMap>[],
          },
        ],
      };
      expect(
        ((await store.orgArchive('o1'))['periods'] as List).single['label'],
        '2026/2027',
      );
      backend.reportData = (_, _, _) async => {
        'generatedAt': '2026-11-13T00:00:00Z',
        'organization': 'BEM FST',
        'period': '2026/2027',
        'group': {'name': 'Panitia', 'isCommittee': true, 'coordinator': 'Ayu'},
        'projects': [
          {'title': 'Sie Acara', 'tasks': <JsonMap>[]},
        ],
        'meetings': <JsonMap>[],
        'totals': {'tasks': 0, 'done': 0, 'approvedAmount': 0},
      };
      final report = await store.report(
        'g1',
        periodID: 'pe1',
        projectIDs: ['p1'],
      );
      // A koordinator sie's report has no `approvals` key: empty, not null.
      expect(report['approvals'], isEmpty);
      expect(backend.reads, [
        'templates:o1',
        'template:t1',
        'archive:o1',
        'report:g1:pe1:[p1]',
      ]);
      // Server codes keep their text; a bad shape gets the fallback.
      backend.templateList = (_) async =>
          throw const PostgrestException(message: 'forbidden', code: 'P0001');
      await expectLater(
        store.templates('o1'),
        throwsA(
          isA<GrouplyException>().having(
            (e) => e.message,
            'message',
            GrouplyStore.codeText('forbidden'),
          ),
        ),
      );
      backend.templateList = (_) async => [
        {'id': 't1', 'name': 'Seminar', 'builtIn': 'ya'},
      ];
      await expectLater(
        store.templates('o1'),
        throwsA(
          isA<GrouplyException>().having(
            (e) => e.message,
            'message',
            startsWith('Template belum dapat dimuat'),
          ),
        ),
      );
      backend.reportData = (_, _, _) async => {'projects': 'none'};
      await expectLater(
        store.report('g1'),
        throwsA(
          isA<GrouplyException>().having(
            (e) => e.message,
            'message',
            startsWith('Rekap belum dapat dimuat'),
          ),
        ),
      );
    });
  });
}
