import 'dart:async';
import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grouply/core/backend.dart';
import 'package:grouply/ui/gl.dart';
import 'package:grouply/core/store.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
  bool signUpHasSession = true;
  String? signUpName, signUpEmail, signUpPassword;
  String? resetEmail;
  String recoveryCode = '123456';
  String? recoveryPassword;
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

  @override
  Future<bool> signUp(String name, String email, String password) async {
    signUpName = name;
    signUpEmail = email;
    signUpPassword = password;
    if (!signUpHasSession) return false;
    actor = email;
    changes.add(actor);
    return true;
  }

  @override
  Future<void> requestPasswordReset(String email) async {
    resetEmail = email;
  }

  @override
  Future<void> recoverPassword(
    String email,
    String token,
    String password,
  ) async {
    if (token != recoveryCode) throw StateError('wrong code');
    recoveryPassword = password;
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
  final due = now.add(const Duration(days: 10)).toIso8601String();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    backend = FakeBackend();
    store = GrouplyStore(backend: backend, clock: () => now);
  });
  tearDown(() => store.dispose());

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
    'sign-up sends name and signs in when server returns a session',
    () async {
      final signedIn = await store.signUp('Ayu', 'ayu@example.com', 'password');
      expect(signedIn, isTrue);
      expect(backend.signUpName, 'Ayu');
      expect(backend.signUpEmail, 'ayu@example.com');
      expect(backend.signUpPassword, 'password');
      expect(store.currentUserID, 'ayu@example.com');
    },
  );

  test('sign-up without a session leaves the store signed out', () async {
    backend.signUpHasSession = false;
    expect(await store.signUp('Ayu', 'ayu@example.com', 'password'), isFalse);
    expect(store.authenticated, isFalse);
    expect(store.loading, isFalse);
  });

  test(
    'password recovery sends reset email and signs in after valid OTP',
    () async {
      await store.requestPasswordReset('ayu@example.com');
      expect(backend.resetEmail, 'ayu@example.com');
      await store.recoverPassword('ayu@example.com', '123456', 'newpass');
      expect(backend.recoveryPassword, 'newpass');
      expect(store.currentUserID, 'ayu@example.com');
    },
  );

  test('password recovery rejects an incorrect OTP', () async {
    await expectLater(
      store.recoverPassword('ayu@example.com', '000000', 'newpass'),
      throwsA(isA<GrouplyException>()),
    );
    expect(store.authenticated, isFalse);
    expect(store.loading, isFalse);
  });

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
      expect(store.demoMode, isFalse);
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

  Future<
    ({
      String coordinator,
      String assignee,
      String reviewer,
      String groupID,
      String projectID,
      String taskID,
    })
  >
  workflow() async {
    await store.initialize();
    await store.startDemo();
    final coordinator = store.currentUserID;
    final others = store.users
        .where(
          (row) =>
              row.text('id') != coordinator && row.text('email').isNotEmpty,
        )
        .toList();
    final assignee = others[0].text('id'), reviewer = others[1].text('id');
    final groupID = (await store.mutate('createGroup', {
      'name': 'Core test',
      'description': '',
      'course': 'Tests',
    })).text('id');
    for (final actor in [assignee, reviewer]) {
      final invite = await store.mutate('generateInvite', {'groupID': groupID});
      final code = (invite['invite'] as JsonMap).text('code');
      await store.switchDemoUser(actor);
      await store.mutate('joinGroup', {'code': code});
      await store.switchDemoUser(coordinator);
    }
    final projectID = (await store.mutate('createProject', {
      'groupID': groupID,
      'title': 'Project',
      'description': '',
      'dueAt': due,
    })).text('id');
    final taskID = (await store.mutate('createTask', {
      'projectID': projectID,
      'title': 'Task',
      'description': '',
      'assigneeID': assignee,
      'reviewerID': reviewer,
      'dueAt': due,
    })).text('id');
    return (
      coordinator: coordinator,
      assignee: assignee,
      reviewer: reviewer,
      groupID: groupID,
      projectID: projectID,
      taskID: taskID,
    );
  }

  test(
    'demo constraints, versioned review, append-only revisions and persistence',
    () async {
      final flow = await workflow();
      await expectLater(
        store.mutate('startTask', {'id': flow.taskID, 'expectedVersion': 1}),
        throwsA(isA<GrouplyException>()),
      );
      await store.switchDemoUser(flow.assignee);
      await store.mutate('startTask', {
        'id': flow.taskID,
        'expectedVersion': 1,
      });
      final version = store.task(flow.taskID)!.number('version');
      await expectLater(
        store.mutate('submitWork', {
          'taskID': flow.taskID,
          'note': '',
          'links': [],
          'expectedVersion': version,
        }),
        throwsA(isA<GrouplyException>()),
      );
      await expectLater(
        store.mutate('submitWork', {
          'taskID': flow.taskID,
          'note': 'Unsafe',
          'links': ['http://example.com'],
          'expectedVersion': version,
        }),
        throwsA(isA<GrouplyException>()),
      );
      await expectLater(
        store.mutate('submitWork', {
          'taskID': flow.taskID,
          'note': 'Too many',
          'links': List.filled(6, 'https://example.com'),
          'expectedVersion': version,
        }),
        throwsA(isA<GrouplyException>()),
      );
      for (final invalid in [
        'https://%',
        'https://@example.com',
        'https://user@example.com',
      ]) {
        await expectLater(
          store.mutate('submitWork', {
            'taskID': flow.taskID,
            'note': 'Invalid authority',
            'links': [invalid],
            'expectedVersion': version,
          }),
          throwsA(isA<GrouplyException>()),
          reason: invalid,
        );
      }
      await store.mutate('submitWork', {
        'taskID': flow.taskID,
        'note': 'Revision one',
        'links': ['https://example.com/work'],
        'expectedVersion': version,
      });
      await expectLater(
        store.mutate('review', {
          'taskID': flow.taskID,
          'approve': true,
          'feedback': '',
          'expectedVersion': version + 1,
        }),
        throwsA(isA<GrouplyException>()),
      );
      await store.switchDemoUser(flow.reviewer);
      await expectLater(
        store.mutate('review', {
          'taskID': flow.taskID,
          'approve': true,
          'feedback': '',
          'expectedVersion': version,
        }),
        throwsA(isA<GrouplyException>()),
      );
      await store.mutate('review', {
        'taskID': flow.taskID,
        'approve': false,
        'feedback': 'Add evidence',
        'expectedVersion': version + 1,
      });
      await store.switchDemoUser(flow.assignee);
      await store.mutate('submitWork', {
        'taskID': flow.taskID,
        'note': 'Revision two',
        'links': [],
        'expectedVersion': version + 2,
      });
      await store.switchDemoUser(flow.reviewer);
      await store.mutate('review', {
        'taskID': flow.taskID,
        'approve': true,
        'feedback': '',
        'expectedVersion': version + 3,
      });
      final task = store.task(flow.taskID)!;
      expect(task.text('status'), 'done');
      expect((task['submissions'] as List).length, 2);
      expect((task['submissions'] as List).first['note'], 'Revision one');
      final saved = (await SharedPreferences.getInstance()).getString(
        GrouplyStore.demoStorageKey,
      )!;
      expect(jsonDecode(saved)['currentUserID'], flow.reviewer);
      final restored = GrouplyStore(backend: FakeBackend(), clock: () => now);
      await restored.initialize();
      await restored.startDemo();
      expect(restored.task(flow.taskID)!.text('status'), 'done');
      expect(restored.currentUserID, flow.reviewer);
      restored.dispose();
      await store.switchDemoUser(flow.coordinator);
      await store.mutate('completeProject', {'id': flow.projectID});
      await expectLater(
        store.mutate('reopenTask', {
          'id': flow.taskID,
          'expectedVersion': task.number('version'),
        }),
        throwsA(isA<GrouplyException>()),
      );
      await store.mutate('archiveProject', {'id': flow.projectID});
      await store.mutate('restoreProject', {'id': flow.projectID});
      expect(store.project(flow.projectID)!.text('status'), 'completed');
    },
  );

  test(
    'demo chat retries retain identity and read/block state is account scoped',
    () async {
      final flow = await workflow();
      store.simulateSendFailure = true;
      final payload = {
        'groupID': flow.groupID,
        'taskID': null,
        'text': 'Hello',
        'clientID': 'stable-message',
      };
      await store.mutate('sendMessage', payload);
      store.simulateSendFailure = false;
      await store.mutate('sendMessage', payload);
      expect(
        store.messages.where((row) => row['id'] == 'stable-message').length,
        1,
      );
      expect(
        store.messages
            .firstWhere((row) => row['id'] == 'stable-message')
            .text('delivery'),
        'sent',
      );
      await store.switchDemoUser(flow.assignee);
      await store.markChatRead(flow.groupID, ['stable-message']);
      await store.mutate('blockUser', {'id': flow.coordinator});
      await store.mutate('reportMessage', {
        'id': 'stable-message',
        'reason': 'Spam',
      });
      expect(store.blockedUserIDs, contains(flow.coordinator));
      expect(store.readMessageIDs, contains('stable-message'));
      await store.switchDemoUser(flow.reviewer);
      expect(store.blockedUserIDs, isEmpty);
      expect(store.readMessageIDs, isNot(contains('stable-message')));
      await expectLater(
        store.mutate('sendMessage', payload),
        throwsA(isA<GrouplyException>()),
      );
    },
  );

  test(
    'demo prevents assigned members leaving even archived projects',
    () async {
      final flow = await workflow();
      await store.mutate('archiveProject', {'id': flow.projectID});
      await expectLater(
        store.mutate('removeMember', {
          'groupID': flow.groupID,
          'userID': flow.assignee,
        }),
        throwsA(isA<GrouplyException>()),
      );
      await store.switchDemoUser(flow.assignee);
      await expectLater(
        store.mutate('leaveGroup', {'id': flow.groupID}),
        throwsA(isA<GrouplyException>()),
      );
      await expectLater(
        store.mutate('deleteAccount'),
        throwsA(isA<GrouplyException>()),
      );
    },
  );

  test(
    'demo seed mirrors Swift DemoSeed personas, history and unread',
    () async {
      await store.initialize();
      await store.startDemo();
      expect(store.currentUserID, 'u1');
      expect(store.user('u1')!.text('name'), 'Alex');
      expect(store.users.map((row) => row['id']), [
        for (final persona in demoPersonas) persona.id,
      ]);
      expect(store.groups.map((row) => row['id']), ['g3', 'g1', 'g2']);
      expect(store.task('t1')!.text('status'), 'in_review');
      expect(store.task('t1')!.text('reviewerID'), 'u1');
      expect(store.project('p3')!.text('status'), 'completed');
      expect(
        store.messages.every((row) => row.date('createdAt')!.isBefore(now)),
        isTrue,
      );
      int unread(String groupID) => store.messages
          .where(
            (row) =>
                row['groupID'] == groupID &&
                row['taskID'] == null &&
                row['senderID'] != store.currentUserID &&
                !store.readMessageIDs.contains(row['id']),
          )
          .length;
      expect([unread('g1'), unread('g2')], [2, 0]);
      await store.switchDemoUser('u4');
      expect(unread('g1'), 3);
    },
  );

  test('corrupt persisted demo is never overwritten', () async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(GrouplyStore.demoStorageKey, '{corrupt');
    await store.initialize();
    await store.startDemo();
    expect(store.error, contains('tidak ditimpa'));
    await store.mutate('updateProfile', {'name': 'Unsaved session'});
    expect(preferences.getString(GrouplyStore.demoStorageKey), '{corrupt');
  });

  test(
    'demo invites enforce expiry, revocation, single use and eight members',
    () async {
      await store.initialize();
      await store.startDemo();
      final coordinator = store.currentUserID;
      for (var index = 1; index <= 8; index++) {
        store.users.add({
          'id': 'extra-$index',
          'name': 'Member $index',
          'email': 'member$index@example.com',
          'tint': '#DED2FF',
        });
      }
      final groupID = (await store.mutate('createGroup', {
        'name': 'Capacity',
      })).text('id');
      final expired = await store.mutate('generateInvite', {
        'groupID': groupID,
      });
      store.invites.firstWhere(
        (row) => row['id'] == expired['id'],
      )['expiresAt'] = now
          .toIso8601String();
      await store.switchDemoUser('extra-1');
      await expectLater(
        store.mutate('joinGroup', {
          'code': (expired['invite'] as JsonMap)['code'],
        }),
        throwsA(isA<GrouplyException>()),
      );
      await store.switchDemoUser(coordinator);
      final revoked = await store.mutate('generateInvite', {
        'groupID': groupID,
      });
      await store.mutate('revokeInvite', {'id': revoked['id']});
      await store.switchDemoUser('extra-1');
      await expectLater(
        store.mutate('joinGroup', {
          'code': (revoked['invite'] as JsonMap)['code'],
        }),
        throwsA(isA<GrouplyException>()),
      );
      await store.switchDemoUser(coordinator);
      for (var index = 1; index <= 7; index++) {
        final invite = await store.mutate('generateInvite', {
          'groupID': groupID,
        });
        await store.switchDemoUser('extra-$index');
        await store.mutate('joinGroup', {
          'code': (invite['invite'] as JsonMap)['code'],
        });
        await store.switchDemoUser(coordinator);
      }
      expect(store.group(groupID)!.ids('memberIDs').length, 8);
      final finalInvite = await store.mutate('generateInvite', {
        'groupID': groupID,
      });
      await store.switchDemoUser('extra-8');
      await expectLater(
        store.mutate('joinGroup', {
          'code': (finalInvite['invite'] as JsonMap)['code'],
        }),
        throwsA(isA<GrouplyException>()),
      );
      expect(store.group(groupID)!.ids('memberIDs').length, 8);
    },
  );

  test(
    'demo deletion preserves history and remains readable after reload',
    () async {
      final flow = await workflow();
      store.groups.removeWhere((row) => row['id'] != flow.groupID);
      store.projects.removeWhere((row) => row['id'] != flow.projectID);
      store.tasks.removeWhere((row) => row['id'] != flow.taskID);
      await store.mutate('sendMessage', {
        'groupID': flow.groupID,
        'taskID': null,
        'text': 'Shared history',
        'clientID': 'historic-message',
      });
      await store.switchDemoUser(flow.assignee);
      await store.mutate('reportMessage', {
        'id': 'historic-message',
        'reason': 'Report',
      });
      await store.switchDemoUser(flow.coordinator);
      await store.mutate('reassignTask', {
        'id': flow.taskID,
        'assigneeID': flow.coordinator,
        'reviewerID': flow.reviewer,
        'expectedVersion': 1,
      });
      await store.switchDemoUser(flow.assignee);
      final soleGroup = (await store.mutate('createGroup', {
        'name': 'Sole owner',
      })).text('id');
      final invite = await store.mutate('generateInvite', {
        'groupID': soleGroup,
      });
      expect(await store.mutate('deleteAccount'), {'deleted': true});
      expect(store.authenticated, isFalse);
      expect(store.user(flow.assignee), isNull);
      expect(store.group(soleGroup)!.text('coordinatorID'), '');
      expect(
        store.invites.firstWhere((row) => row['id'] == invite['id'])['revoked'],
        isTrue,
      );
      expect(
        store.messages.any((row) => row['id'] == 'historic-message'),
        isTrue,
      );
      final restored = GrouplyStore(backend: FakeBackend(), clock: () => now);
      await restored.initialize();
      await restored.startDemo();
      expect(restored.error, isNull);
      expect(restored.user(flow.assignee), isNull);
      expect(restored.task(flow.taskID), isNotNull);
      restored.dispose();
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
