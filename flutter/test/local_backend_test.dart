import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grouply/core/backend.dart';
import 'package:grouply/core/store.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class _LocalBinding extends AutomatedTestWidgetsFlutterBinding {
  @override
  bool get overrideHttpClient => false;
}

class _MemorySession extends LocalStorage {
  String? _session;

  @override
  Future<void> initialize() async {}
  @override
  Future<String?> accessToken() async => _session;
  @override
  Future<bool> hasAccessToken() async => _session != null;
  @override
  Future<void> persistSession(String persistSessionString) async {
    _session = persistSessionString;
  }

  @override
  Future<void> removePersistedSession() async => _session = null;
}

class _MemoryPKCE extends GotrueAsyncStorage {
  final _items = <String, String>{};
  @override
  Future<String?> getItem({required String key}) async => _items[key];
  @override
  Future<void> setItem({required String key, required String value}) async =>
      _items[key] = value;
  @override
  Future<void> removeItem({required String key}) async => _items.remove(key);
}

void _check(bool condition, String message) {
  if (!condition) throw TestFailure(message);
}

Future<void> _eventually(bool Function() condition) async {
  final deadline = DateTime.now().add(const Duration(seconds: 15));
  while (!condition()) {
    _check(DateTime.now().isBefore(deadline), 'Local realtime timed out.');
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }
}

Future<void> _denied(Future<JsonMap> Function() action, String reason) async {
  var denied = false;
  try {
    await action();
  } on PostgrestException catch (failure) {
    denied = failure.message.contains(reason);
  }
  _check(denied, 'Expected server denial was not confirmed.');
}

String _messageID() {
  final random = Random.secure();
  final suffix = List.generate(
    6,
    (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
  ).join();
  return '00000000-0000-4000-8000-$suffix';
}

void main() {
  _LocalBinding();
  test(
    'local Auth/RPC/realtime three-account integration smoke',
    () async {
      var stage = 'private local configuration';
      final stores = <GrouplyStore>[];
      final backends = <SupabaseGrouplyBackend>[];
      final clients = <SupabaseClient>[];
      addTearDown(() async {
        for (final backend in backends) {
          try {
            await backend.disconnect().timeout(const Duration(seconds: 5));
          } catch (_) {
            fail('Local realtime teardown failed; details suppressed.');
          }
        }
        for (final store in stores) {
          store.dispose();
        }
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });

      try {
        final environment = Platform.environment;
        final path =
            environment['GROUPLY_LOCAL_ACCOUNTS_PATH'] ??
            '${environment['HOME']}/Library/Application Support/'
                'GrouplyDevelopment/accounts.json';
        final fixture = jsonDecode(await File(path).readAsString()) as JsonMap;
        final url = fixture['url'] as String;
        final uri = Uri.parse(url);
        _check(
          uri.scheme == 'http' &&
              ['localhost', '127.0.0.1', '::1'].contains(uri.host) &&
              uri.port == 55321 &&
              uri.userInfo.isEmpty &&
              !uri.hasQuery &&
              !uri.hasFragment &&
              (uri.path.isEmpty || uri.path == '/') &&
              url.trim() == url,
          'Only loopback HTTP port 55321 is allowed.',
        );
        final key = fixture['publishableKey'] as String;
        _check(
          SupabaseGrouplyBackend(url: url, anonKey: key).configured,
          'A public local client key is required.',
        );
        stage = 'backend availability (no services started)';
        final probe = HttpClient()
          ..connectionTimeout = const Duration(seconds: 4);
        try {
          final request = await probe.getUrl(uri.resolve('/auth/v1/health'));
          request.followRedirects = false;
          final response = await request.close().timeout(
            const Duration(seconds: 4),
          );
          _check(response.statusCode == 200, 'Local backend is not healthy.');
          await response.drain<void>();
        } finally {
          probe.close(force: true);
        }

        stage = 'three real email sign-ins';
        SharedPreferences.setMockInitialValues({});
        final accounts = fixture['accounts'] as JsonMap;
        for (final name in ['alex', 'raka', 'nadia']) {
          final account = accounts[name] as JsonMap;
          final client = SupabaseClient(url, key);
          final backend = SupabaseGrouplyBackend(
            url: url,
            anonKey: key,
            client: client,
            sessionStorage: _MemorySession(),
          );
          final store = GrouplyStore(backend: backend);
          clients.add(client);
          backends.add(backend);
          stores.add(store);
          await store.initialize();
          await store.signIn(
            account['email'] as String,
            account['password'] as String,
          );
          _check(
            store.authenticated &&
                store.currentUserID == account['id'] &&
                store.error == null,
            'Real account identity was not confirmed.',
          );
        }
        _check(
          stores.map((store) => store.currentUserID).toSet().length == 3,
          'Three distinct identities are required.',
        );
        final alex = stores[0], raka = stores[1], nadia = stores[2];
        final label =
            'Flutter local smoke ${DateTime.now().microsecondsSinceEpoch}';
        stage = 'isolated group creation and unauthorized access';
        final group = (await alex.mutate('createGroup', {
          'name': label,
        })).text('id');
        _check(
          group.isNotEmpty && alex.group(group) != null,
          'Group creation failed.',
        );
        debugPrint('Local fixture retained: $label; groupID=$group');
        await _denied(
          () => backends[1].mutate('updateGroup', {
            'id': group,
            'name': 'Must not change',
          }),
          'forbidden',
        );
        await raka.refresh();
        _check(
          raka.group(group) == null,
          'Nonmember could read isolated group.',
        );

        stage = 'invite join and project/task creation';
        for (final store in [raka, nadia]) {
          stage = 'single-use invitation creation';
          final invitation = await alex.mutate('generateInvite', {
            'groupID': group,
          });
          final code = (invitation['invite'] as JsonMap).text('code');
          _check(code.isNotEmpty, 'Invite was not generated.');
          stage = 'single-use invitation join';
          await store.mutate('joinGroup', {'code': code});
          _check(store.group(group) != null, 'Joined group is missing.');
        }
        final due = DateTime.now()
            .toUtc()
            .add(const Duration(days: 7))
            .toIso8601String();
        stage = 'project creation';
        final project = (await alex.mutate('createProject', {
          'groupID': group,
          'title': label,
          'dueAt': due,
        })).text('id');
        stage = 'task creation';
        final task = (await alex.mutate('createTask', {
          'projectID': project,
          'title': label,
          'dueAt': due,
          'assigneeID': raka.currentUserID,
          'reviewerID': nadia.currentUserID,
        })).text('id');
        _check(
          project.isNotEmpty && task.isNotEmpty,
          'Fixture IDs are missing.',
        );

        stage = 'assignee start and stale-version denial';
        await raka.mutate('startTask', {'id': task, 'expectedVersion': 1});
        _check(
          raka.task(task)?.text('status') == 'in_progress' &&
              raka.task(task)?.number('version') == 2,
          'Task start was not persisted.',
        );
        await _denied(
          () => backends[1].mutate('startTask', {
            'id': task,
            'expectedVersion': 1,
          }),
          'stale_version',
        );
        await raka.refresh();
        _check(
          raka.task(task)?.number('version') == 2,
          'Stale mutation changed task.',
        );
        await _denied(
          () => backends[2].mutate('startTask', {
            'id': task,
            'expectedVersion': 2,
          }),
          'forbidden',
        );

        stage = 'submission, reviewer revision, resubmission and approval';
        await raka.mutate('submitWork', {
          'taskID': task,
          'note': 'Local integration first submission',
          'links': ['https://example.org/local-smoke'],
          'expectedVersion': 2,
        });
        _check(
          raka.task(task)?.text('status') == 'in_review',
          'Submission failed.',
        );
        await nadia.mutate('review', {
          'taskID': task,
          'approve': false,
          'feedback': 'Please revise',
          'expectedVersion': 3,
        });
        _check(
          nadia.task(task)?.text('status') == 'needs_revision',
          'Revision failed.',
        );
        await raka.mutate('submitWork', {
          'taskID': task,
          'note': 'Local integration revised submission',
          'links': <String>[],
          'expectedVersion': 4,
        });
        await nadia.mutate('review', {
          'taskID': task,
          'approve': true,
          'feedback': 'Approved',
          'expectedVersion': 5,
        });
        await raka.refresh();
        final finished = raka.task(task)!;
        final submissions = finished['submissions'] as List;
        _check(
          finished.text('status') == 'done' &&
              finished.number('version') == 6 &&
              submissions.length == 2 &&
              (submissions[0] as Map)['decision'] == 'changes_requested' &&
              (submissions[1] as Map)['decision'] == 'approved',
          'Review history failed.',
        );

        stage = 'realtime subscription and cross-store message delivery';
        for (final client in clients) {
          final ready = Completer<void>();
          final probe = client.channel('smoke-ready-${_messageID()}');
          probe.subscribe((status, _) {
            if (status == RealtimeSubscribeStatus.subscribed &&
                !ready.isCompleted) {
              ready.complete();
            }
          });
          try {
            await ready.future.timeout(const Duration(seconds: 15));
          } finally {
            await client.removeChannel(probe);
          }
        }
        final first = _messageID(), second = _messageID();
        for (final id in [first, second]) {
          await alex.mutate('sendMessage', {
            'groupID': group,
            'clientID': id,
            'text': 'Local integration message',
          });
        }
        await _eventually(
          () => [first, second].every(
            (id) => nadia.messages.any((message) => message.text('id') == id),
          ),
        );
        _check(
          !nadia.readMessageIDs.contains(first) &&
              !nadia.readMessageIDs.contains(second),
          'New message was already read.',
        );
        stage = 'explicit read IDs preserve other unread messages';
        await nadia.markChatRead(group, [first]);
        await nadia.refresh();
        _check(
          nadia.readMessageIDs.contains(first) &&
              !nadia.readMessageIDs.contains(second),
          'Read IDs were not selective.',
        );

        stage = 'membership revoke realtime removal and server denial';
        await alex.mutate('removeMember', {
          'groupID': group,
          'userID': nadia.currentUserID,
        });
        await _eventually(
          () =>
              nadia.group(group) == null &&
              nadia.project(project) == null &&
              nadia.task(task) == null &&
              !nadia.messages.any(
                (message) => message.text('groupID') == group,
              ) &&
              !nadia.readMessageIDs.contains(first),
        );
        await nadia.refresh();
        _check(
          nadia.group(group) == null && nadia.task(task) == null,
          'Revoked membership still has snapshot access.',
        );
        await _denied(
          () => backends[2].mutate('sendMessage', {
            'groupID': group,
            'clientID': _messageID(),
            'text': 'Must not be stored',
          }),
          'forbidden',
        );
        await alex.refresh();
        _check(
          alex.group(group)?.text('name') == label &&
              alex.messages
                      .where(
                        (message) =>
                            message.text('groupID') == group &&
                            message.text('kind') == 'text',
                      )
                      .length ==
                  2,
          'Denied mutations changed fixtures.',
        );
        debugPrint(
          'PASS: Auth x3; invite/join; project/task; revision/approval; '
          'stale/unauthorized denial; realtime delivery; selective unread; '
          'membership revoke. Fixtures retained; no account changes or cleanup.',
        );
      } catch (_) {
        fail('Local smoke failed during $stage; sensitive details suppressed.');
      }
    },
    skip: Platform.environment['GROUPLY_LOCAL_INTEGRATION'] != '1'
        ? 'Opt in with GROUPLY_LOCAL_INTEGRATION=1; existing localhost backend only.'
        : false,
    timeout: const Timeout(Duration(minutes: 3)),
  );

  test(
    'local sign-up and emailed-code password reset',
    () async {
      final environment = Platform.environment;
      final path =
          environment['GROUPLY_LOCAL_ACCOUNTS_PATH'] ??
          '${environment['HOME']}/Library/Application Support/'
              'GrouplyDevelopment/accounts.json';
      final fixture = jsonDecode(await File(path).readAsString()) as JsonMap;
      final url = fixture['url'] as String, key = fixture['publishableKey'];
      _check(
        url == 'http://127.0.0.1:55321' || url == 'http://localhost:55321',
        'Only loopback HTTP port 55321 is allowed.',
      );
      SharedPreferences.setMockInitialValues({});
      final backend = SupabaseGrouplyBackend(
        url: url,
        anonKey: key as String,
        // Sign-up and recovery use PKCE, which needs code-verifier storage.
        client: SupabaseClient(
          url,
          key,
          authOptions: AuthClientOptions(pkceAsyncStorage: _MemoryPKCE()),
        ),
        sessionStorage: _MemorySession(),
      );
      final store = GrouplyStore(backend: backend);
      addTearDown(store.dispose);
      await store.initialize();
      final email =
          'flutter-auth-${DateTime.now().microsecondsSinceEpoch}@example.test';
      final first = 'Pertama-${_messageID()}', second = 'Kedua-${_messageID()}';

      _check(await store.signUp('Uji Daftar', email, first), 'No session.');
      _check(
        store.user(store.currentUserID)?.text('name') == 'Uji Daftar',
        'Sign-up name did not reach the profile.',
      );
      await store.signOut();
      await expectLater(
        store.signUp('Uji Daftar', email, first),
        throwsA(
          isA<GrouplyException>().having(
            (e) => e.message,
            'message',
            'Email sudah terdaftar. Silakan masuk.',
          ),
        ),
      );

      await store.sendPasswordReset(email);
      final mail = HttpClient();
      addTearDown(() => mail.close(force: true));
      Future<JsonMap> mailpit(String route) async {
        final request = await mail.getUrl(
          Uri.parse('http://127.0.0.1:55324/api/v1/$route'),
        );
        final response = await request.close();
        return jsonDecode(await response.transform(utf8.decoder).join())
            as JsonMap;
      }

      String? code;
      final deadline = DateTime.now().add(const Duration(seconds: 15));
      while (code == null && DateTime.now().isBefore(deadline)) {
        final list = await mailpit(
          'search?query=to:${Uri.encodeComponent(email)}',
        );
        final messages = list['messages'] as List;
        if (messages.isNotEmpty) {
          final id = (messages.first as Map)['ID'] as String;
          final text = (await mailpit('message/$id'))['Text'] as String;
          code = RegExp(r'\b\d{6}\b').firstMatch(text)?.group(0);
        } else {
          await Future<void>.delayed(const Duration(milliseconds: 200));
        }
      }
      _check(code != null, 'Recovery code email did not arrive.');

      await expectLater(
        store.resetPassword(
          email,
          code == '000000' ? '111111' : '000000',
          second,
        ),
        throwsA(isA<GrouplyException>()),
      );
      _check(!store.authenticated, 'Wrong code signed in.');
      await store.resetPassword(email, code!, second);
      _check(store.authenticated, 'Correct code did not sign in.');
      await store.signOut();
      await expectLater(store.signIn(email, first), throwsA(anything));
      await store.signIn(email, second);
      _check(store.authenticated, 'New password was not accepted.');

      await store.mutate('deleteAccount', {});
      _check(!store.authenticated, 'Test account was not removed.');
      debugPrint(
        'PASS: sign-up, duplicate, reset code, new password, cleanup.',
      );
    },
    skip: Platform.environment['GROUPLY_LOCAL_INTEGRATION'] != '1'
        ? 'Opt in with GROUPLY_LOCAL_INTEGRATION=1; existing localhost backend only.'
        : false,
    timeout: const Timeout(Duration(minutes: 1)),
  );
}
