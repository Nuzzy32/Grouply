import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
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

  test(
    'local organization plan: activation, division, roles, dashboard, exit',
    () async {
      var stage = 'private local configuration';
      final stores = <GrouplyStore>[];
      final backends = <SupabaseGrouplyBackend>[];
      addTearDown(() async {
        for (final backend in backends) {
          await backend.disconnect().timeout(const Duration(seconds: 5));
        }
        for (final store in stores) {
          store.dispose();
        }
      });
      try {
        final environment = Platform.environment;
        final path =
            environment['GROUPLY_LOCAL_ACCOUNTS_PATH'] ??
            '${environment['HOME']}/Library/Application Support/'
                'GrouplyDevelopment/accounts.json';
        final fixture = jsonDecode(await File(path).readAsString()) as JsonMap;
        final url = fixture['url'] as String;
        final key = fixture['publishableKey'] as String;
        _check(
          url == 'http://127.0.0.1:55321' || url == 'http://localhost:55321',
          'Only loopback HTTP port 55321 is allowed.',
        );
        SharedPreferences.setMockInitialValues({});
        GrouplyStore open() {
          final backend = SupabaseGrouplyBackend(
            url: url,
            anonKey: key,
            client: SupabaseClient(
              url,
              key,
              authOptions: AuthClientOptions(pkceAsyncStorage: _MemoryPKCE()),
            ),
            sessionStorage: _MemorySession(),
          );
          backends.add(backend);
          final store = GrouplyStore(backend: backend);
          stores.add(store);
          return store;
        }

        // A fresh founder each run: a ketua may lead at most 3 organizations.
        stage = 'fresh founder sign-up and two existing accounts';
        final founder = open(), alex = open(), raka = open();
        for (final store in stores) {
          await store.initialize();
        }
        final label = 'Org lokal ${DateTime.now().microsecondsSinceEpoch}';
        _check(
          await founder.signUp(
            'Uji Organisasi',
            'flutter-org-${DateTime.now().microsecondsSinceEpoch}@example.test',
            'Org-${_messageID()}',
          ),
          'Founder sign-up failed.',
        );
        final accounts = fixture['accounts'] as JsonMap;
        for (final (store, name) in [(alex, 'alex'), (raka, 'raka')]) {
          final account = accounts[name] as JsonMap;
          await store.signIn(
            account['email'] as String,
            account['password'] as String,
          );
        }

        stage = 'organization creation on an inactive plan';
        final created = await founder.mutate('createOrganization', {
          'name': label,
          'periodLabel': '2026/2027',
        });
        final org = created.text('id'), bph = created.text('groupID');
        _check(
          founder.orgRole(org) == 'ketua' &&
              founder.organization(org)?['planActive'] == false &&
              founder.isDivision(founder.group(bph)),
          'Organization was not created with its first division.',
        );
        await expectLater(
          founder.mutate('createDivision', {
            'organizationID': org,
            'name': 'Terlalu cepat',
          }),
          throwsA(
            isA<GrouplyException>().having(
              (e) => e.message,
              'message',
              contains('Paket organisasi belum aktif'),
            ),
          ),
        );
        await _denied(
          () => backends[0].mutate('generateInvite', {
            'groupID': bph,
            'maxUses': 10,
          }),
          'invalid_input',
        );

        // The real operator path: service-role RPC, key never printed.
        stage = 'operator plan activation';
        final status = await Process.run('supabase', [
          'status',
          '-o',
          'json',
        ], workingDirectory: '..');
        _check(status.exitCode == 0, 'Local Supabase status is unavailable.');
        final local = jsonDecode(status.stdout as String) as JsonMap;
        _check(
          Uri.parse(local['API_URL'] as String).port == 55321,
          'Only the Grouply local stack may be activated.',
        );
        final service = local['SERVICE_ROLE_KEY'] as String;
        final http = HttpClient();
        addTearDown(() => http.close(force: true));
        final request = await http.postUrl(
          Uri.parse('$url/rest/v1/rpc/grouply_billing'),
        );
        request.headers
          ..set('apikey', service)
          ..set('Authorization', 'Bearer $service')
          ..contentType = ContentType.json;
        request.write(
          jsonEncode({
            'action': 'activatePlan',
            'payload': {
              'organizationID': org,
              'seatLimit': 5,
              'expiresAt': DateTime.now()
                  .toUtc()
                  .add(const Duration(days: 30))
                  .toIso8601String(),
            },
          }),
        );
        final response = await request.close();
        await response.drain<void>();
        _check(response.statusCode == 200, 'Plan activation was rejected.');
        await founder.refresh();
        _check(
          founder.organization(org)?['planActive'] == true &&
              founder.organization(org)?.number('seatLimit') == 5,
          'Activated plan did not reach the snapshot.',
        );

        stage = 'division, multi-use invite and seats';
        final humas = (await founder.mutate('createDivision', {
          'organizationID': org,
          'name': 'Humas',
        })).text('id');
        final invite = await founder.mutate('generateInvite', {
          'groupID': humas,
          'maxUses': 10,
        });
        final code = (invite['invite'] as JsonMap).text('code');
        for (final store in [alex, raka]) {
          await store.mutate('joinGroup', {'code': code});
          _check(
            store.group(humas) != null && store.orgRole(org).isEmpty,
            'Member did not join the division through one shared code.',
          );
        }
        await founder.refresh();
        _check(
          founder.organization(org)?.number('seatsUsed') == 3,
          'Seats are not counted per unique person.',
        );

        stage = 'officer roles';
        await founder.mutate('setOrgRole', {
          'organizationID': org,
          'userID': raka.currentUserID,
          'role': 'bph',
        });
        await raka.refresh();
        final officers = raka.organization(org)?['roles'] as List? ?? [];
        _check(
          raka.orgRole(org) == 'bph' &&
              officers.any(
                (row) =>
                    (row as Map)['userID'] == founder.currentUserID &&
                    row['name'] == 'Uji Organisasi',
              ),
          'Officer role or officer names are missing.',
        );
        await _denied(
          () => backends[1].mutate('setOrgRole', {
            'organizationID': org,
            'userID': raka.currentUserID,
            'role': 'pembina',
          }),
          'forbidden',
        );

        stage = 'dashboard';
        final due = DateTime.now()
            .toUtc()
            .add(const Duration(days: 7))
            .toIso8601String();
        final project = (await founder.mutate('createProject', {
          'groupID': humas,
          'title': label,
          'dueAt': due,
        })).text('id');
        final task = (await founder.mutate('createTask', {
          'projectID': project,
          'title': label,
          'dueAt': due,
          'assigneeID': alex.currentUserID,
          'reviewerID': raka.currentUserID,
        })).text('id');
        JsonMap? humasRow(JsonMap overview) =>
            (overview['divisions'] as List<JsonMap>).firstWhere(
              (row) => row.text('id') == humas,
            );
        final overview = await founder.orgOverview(org);
        final projects = humasRow(overview)!['projects'] as List<JsonMap>;
        _check(
          humasRow(overview)!.number('memberCount') == 3 &&
              projects.single.number('total') == 1 &&
              projects.single.number('done') == 0,
          'Dashboard counts do not match.',
        );
        await raka.orgOverview(org);
        await expectLater(
          alex.orgOverview(org),
          throwsA(
            isA<GrouplyException>().having(
              (e) => e.message,
              'message',
              contains('tidak punya izin'),
            ),
          ),
        );

        stage = 'task completion';
        await alex.mutate('startTask', {'id': task, 'expectedVersion': 1});
        await alex.mutate('submitWork', {
          'taskID': task,
          'note': 'Organisasi lokal',
          'links': ['https://example.org/org-local'],
          'expectedVersion': 2,
        });
        await raka.mutate('review', {
          'taskID': task,
          'approve': true,
          'feedback': 'Oke',
          'expectedVersion': 3,
        });
        final done = humasRow(await founder.orgOverview(org))!['projects'];
        _check(
          (done as List<JsonMap>).single.number('done') == 1,
          'Dashboard did not count the approved task.',
        );

        // Officers leaving by themselves lose the role; then the founder is
        // the sole member and may delete the account, leaving no test account.
        stage = 'members leave and sole founder deletes the account';
        await raka.mutate('leaveGroup', {'id': humas});
        await raka.refresh();
        _check(raka.organization(org) == null, 'Leaver still sees the org.');
        await alex.mutate('leaveGroup', {'id': humas});
        await founder.refresh();
        _check(
          founder.organization(org)?.number('seatsUsed') == 1 &&
              (founder.organization(org)?['roles'] as List).length == 1,
          'Officer role survived leaving the last division.',
        );
        await founder.mutate('deleteAccount', {});
        _check(!founder.authenticated, 'Founder account was not removed.');
        debugPrint(
          'PASS: org create; inactive limits; operator activation; division; '
          'multi-use invite; seats; roles; dashboard + denial; self-leave role '
          'drop; sole founder deletion. Dormant org rows retained.',
        );
      } catch (_) {
        fail(
          'Local organization flow failed during $stage; details suppressed.',
        );
      }
    },
    skip: Platform.environment['GROUPLY_LOCAL_INTEGRATION'] != '1'
        ? 'Opt in with GROUPLY_LOCAL_INTEGRATION=1; existing localhost backend only.'
        : false,
    timeout: const Timeout(Duration(minutes: 2)),
  );

  test(
    'local organization plan tahap 2: committee, lead, meeting, approval, announcement',
    () async {
      var stage = 'private local configuration';
      final stores = <GrouplyStore>[];
      final backends = <SupabaseGrouplyBackend>[];
      addTearDown(() async {
        for (final backend in backends) {
          await backend.disconnect().timeout(const Duration(seconds: 5));
        }
        for (final store in stores) {
          store.dispose();
        }
      });
      try {
        final environment = Platform.environment;
        final path =
            environment['GROUPLY_LOCAL_ACCOUNTS_PATH'] ??
            '${environment['HOME']}/Library/Application Support/'
                'GrouplyDevelopment/accounts.json';
        final fixture = jsonDecode(await File(path).readAsString()) as JsonMap;
        final url = fixture['url'] as String;
        final key = fixture['publishableKey'] as String;
        _check(
          url == 'http://127.0.0.1:55321' || url == 'http://localhost:55321',
          'Only loopback HTTP port 55321 is allowed.',
        );
        SharedPreferences.setMockInitialValues({});
        GrouplyStore open() {
          final backend = SupabaseGrouplyBackend(
            url: url,
            anonKey: key,
            client: SupabaseClient(
              url,
              key,
              authOptions: AuthClientOptions(pkceAsyncStorage: _MemoryPKCE()),
            ),
            sessionStorage: _MemorySession(),
          );
          backends.add(backend);
          final store = GrouplyStore(backend: backend);
          stores.add(store);
          return store;
        }

        stage = 'fresh founder sign-up and two existing accounts';
        final founder = open(), alex = open(), raka = open();
        for (final store in stores) {
          await store.initialize();
        }
        final label = 'Kerja lokal ${DateTime.now().microsecondsSinceEpoch}';
        _check(
          await founder.signUp(
            'Uji Kerja',
            'flutter-work-${DateTime.now().microsecondsSinceEpoch}@example.test',
            'Org-${_messageID()}',
          ),
          'Founder sign-up failed.',
        );
        final accounts = fixture['accounts'] as JsonMap;
        for (final (store, name) in [(alex, 'alex'), (raka, 'raka')]) {
          final account = accounts[name] as JsonMap;
          await store.signIn(
            account['email'] as String,
            account['password'] as String,
          );
        }
        final org = (await founder.mutate('createOrganization', {
          'name': label,
        })).text('id');

        stage = 'operator plan activation';
        final status = await Process.run('supabase', [
          'status',
          '-o',
          'json',
        ], workingDirectory: '..');
        _check(status.exitCode == 0, 'Local Supabase status is unavailable.');
        final local = jsonDecode(status.stdout as String) as JsonMap;
        _check(
          Uri.parse(local['API_URL'] as String).port == 55321,
          'Only the Grouply local stack may be activated.',
        );
        final service = local['SERVICE_ROLE_KEY'] as String;
        final http = HttpClient();
        addTearDown(() => http.close(force: true));
        final request = await http.postUrl(
          Uri.parse('$url/rest/v1/rpc/grouply_billing'),
        );
        request.headers
          ..set('apikey', service)
          ..set('Authorization', 'Bearer $service')
          ..contentType = ContentType.json;
        request.write(
          jsonEncode({
            'action': 'activatePlan',
            'payload': {
              'organizationID': org,
              'seatLimit': 5,
              'expiresAt': DateTime.now()
                  .toUtc()
                  .add(const Duration(days: 30))
                  .toIso8601String(),
            },
          }),
        );
        final response = await request.close();
        await response.drain<void>();
        _check(response.statusCode == 200, 'Plan activation was rejected.');
        await founder.refresh();

        // The founder leads the committee so the persistent accounts can leave
        // afterwards and the founder can delete the account as the last member.
        stage = 'committee across divisions';
        final committee = (await founder.mutate('createDivision', {
          'organizationID': org,
          'name': 'Panitia Seminar',
          'committee': true,
        })).text('id');
        final invite = await founder.mutate('generateInvite', {
          'groupID': committee,
          'maxUses': 10,
        });
        for (final store in [alex, raka]) {
          await store.mutate('joinGroup', {
            'code': (invite['invite'] as JsonMap).text('code'),
          });
        }
        await founder.mutate('setOrgRole', {
          'organizationID': org,
          'userID': raka.currentUserID,
          'role': 'bph',
        });
        _check(
          alex.isCommittee(alex.group(committee)) &&
              (alex.organization(org)?['divisions'] as List).any(
                (row) =>
                    (row as Map)['id'] == committee &&
                    row['isCommittee'] == true,
              ),
          'Committee flag is missing from the snapshot.',
        );

        stage = 'project lead';
        final due = DateTime.now()
            .toUtc()
            .add(const Duration(days: 7))
            .toIso8601String();
        final sie = (await founder.mutate('createProject', {
          'groupID': committee,
          'title': 'Sie Publikasi',
          'dueAt': due,
        })).text('id');
        await founder.mutate('setProjectLead', {
          'projectID': sie,
          'userID': alex.currentUserID,
        });
        await alex.refresh();
        _check(
          alex.canManageTasks(alex.project(sie)),
          'Project lead cannot manage tasks.',
        );
        final first = (await alex.mutate('createTask', {
          'projectID': sie,
          'title': 'Poster',
          'description': '',
          'assigneeID': raka.currentUserID,
          'reviewerID': alex.currentUserID,
          'dueAt': due,
        })).text('id');

        stage = 'premium task batch and concurrent retry';
        FlutterSecureStorage.setMockInitialValues({});
        _check(alex.taskBatchAvailable, 'Batch capability missing.');
        final batch = {
          'projectID': sie,
          'requestID': '00000000-0000-4000-8000-000000000001',
          'tasks': [
            for (final title in ['Kartu peserta', 'Sertifikat'])
              {
                'title': title,
                'description': '',
                'assigneeID': raka.currentUserID,
                'reviewerID': alex.currentUserID,
                'dueAt': due,
              },
          ],
        };
        final receipts = await Future.wait([
          alex.publishTaskBatch(batch),
          backends[1].mutate('publishTaskBatch', batch),
        ]);
        final batchIDs = receipts.first.ids('ids');
        _check(
          batchIDs.length == 2 &&
              listEquals(batchIDs, receipts.last.ids('ids')) &&
              await alex.pendingTaskBatch(sie) == null,
          'Concurrent retry did not return the original tasks.',
        );
        await raka.refresh();
        _check(
          batchIDs.every((id) => raka.task(id) != null),
          'Batch tasks missing for assignee.',
        );

        stage = 'meeting minutes, attendance and a task from the meeting';
        final meeting = (await founder.mutate('createMeeting', {
          'groupID': committee,
          'title': 'Rapat perdana',
          'startsAt': DateTime.now()
              .toUtc()
              .subtract(const Duration(hours: 1))
              .toIso8601String(),
          'place': 'Sekre',
          'agenda': 'Pembagian sie',
          'noteTakerID': alex.currentUserID,
        })).text('id');
        await alex.refresh();
        await alex.mutate('recordMeeting', {
          'id': meeting,
          'expectedVersion': 1,
          'minutes': 'Poster dikerjakan Raka.',
          'attendance': [
            {'userID': alex.currentUserID, 'status': 'hadir'},
            {'userID': raka.currentUserID, 'status': 'izin'},
            {'userID': founder.currentUserID, 'status': 'hadir'},
          ],
        });
        final detail = await alex.meetingDetail(meeting);
        _check(
          detail.text('minutes') == 'Poster dikerjakan Raka.' &&
              (detail['attendance'] as List).length == 3,
          'Meeting detail does not match the recorded minutes.',
        );
        stage = 'meeting follow-up publication and retry';
        final followUp = {
          'meetingID': meeting,
          // Follow-up request IDs are global, and each run creates a fresh meeting.
          'requestID': meeting,
          'title': 'Periksa materi publikasi',
          'assigneeID': raka.currentUserID,
          'dueAt': due,
        };
        final followUpID = (await alex.mutate(
          'addMeetingFollowUp',
          followUp,
        )).text('id');
        _check(
          (await alex.mutate('addMeetingFollowUp', followUp)).text('id') ==
              followUpID,
          'Add retry changed follow-up ID.',
        );
        final publish = {
          'meetingID': meeting,
          'followUpID': followUpID,
          'projectID': sie,
          'reviewerID': alex.currentUserID,
        };
        final results = await Future.wait([
          alex.mutate('publishMeetingFollowUp', publish),
          backends[1].mutate('publishMeetingFollowUp', publish),
        ]);
        final followUpTask = results.first.text('id');
        final updated = await alex.meetingDetail(meeting);
        _check(
          followUpTask.isNotEmpty &&
              results.last.text('id') == followUpTask &&
              (updated['followUps'] as List).single['taskID'] == followUpTask,
          'Concurrent publish did not return the linked task.',
        );
        stage = 'meeting follow-up removal';
        // The sie ID is fresh per run, so it doubles as a unique follow-up ID.
        await alex.mutate('addMeetingFollowUp', {
          ...followUp,
          'requestID': sie,
          'title': 'Poin dibatalkan',
        });
        final remove = {'meetingID': meeting, 'followUpID': sie};
        await alex.mutate('removeMeetingFollowUp', remove);
        await alex.mutate('removeMeetingFollowUp', remove);
        final published = {'meetingID': meeting, 'followUpID': followUpID};
        final kept = await alex.meetingDetail(meeting);
        _check(
          (kept['followUps'] as List).single['id'] == followUpID,
          'Follow-up removal is not idempotent.',
        );
        await expectLater(
          alex.mutate('removeMeetingFollowUp', published),
          throwsA(isA<GrouplyException>()),
        );
        stage = 'manual task from meeting';
        final second = (await alex.mutate('createTask', {
          'projectID': sie,
          'title': 'Banner',
          'description': '',
          'assigneeID': raka.currentUserID,
          'reviewerID': alex.currentUserID,
          'dueAt': due,
          'meetingID': meeting,
        })).text('id');
        await founder.refresh();
        final listed = founder.meetings.firstWhere(
          (row) => row.text('id') == meeting,
        );
        _check(
          listed['status'] == 'done' &&
              listed.number('present') == 2 &&
              (listed['taskIDs'] as List).contains(second),
          'Meeting summary is not in the snapshot.',
        );

        stage = 'two-step approval';
        final approval = (await alex.mutate('requestApproval', {
          'groupID': committee,
          'title': 'Dana publikasi',
          'note': 'Cetak poster dan banner.',
          'amount': 500000,
          'links': ['https://example.org/rab'],
          'approverIDs': [raka.currentUserID, founder.currentUserID],
        })).text('id');
        await raka.refresh();
        _check(
          raka.pendingForMe(org).any((row) => row.text('id') == approval),
          'First approver does not see the request.',
        );
        await raka.mutate('decideApproval', {
          'id': approval,
          'approve': true,
          'note': '',
        });
        await founder.refresh();
        await founder.mutate('decideApproval', {
          'id': approval,
          'approve': true,
          'note': '',
        });
        await expectLater(
          raka.mutate('decideApproval', {
            'id': approval,
            'approve': true,
            'note': '',
          }),
          throwsA(
            isA<GrouplyException>().having(
              (e) => e.message,
              'message',
              contains('Pengajuan ini sudah diputuskan'),
            ),
          ),
        );
        await alex.refresh();
        final decided = (alex.organization(org)?['approvals'] as List)
            .cast<JsonMap>()
            .firstWhere((row) => row.text('id') == approval);
        _check(
          decided['status'] == 'approved' && decided.number('amount') == 500000,
          'Approval did not close as approved.',
        );

        stage = 'announcement read receipts';
        final post = (await founder.mutate('postAnnouncement', {
          'organizationID': org,
          'title': 'Rapat pleno',
          'body': 'Semua hadir Sabtu.',
        })).text('id');
        await alex.refresh();
        _check(
          alex.unreadAnnouncements(org).any((row) => row.text('id') == post),
          'Announcement is not unread for a member.',
        );
        await alex.mutate('markAnnouncementRead', {'id': post});
        await founder.refresh();
        final sent = (founder.organization(org)?['announcements'] as List)
            .cast<JsonMap>()
            .firstWhere((row) => row.text('id') == post);
        _check(
          sent.number('readCount') == 2 && sent.number('audienceCount') == 3,
          'Read counts do not match.',
        );

        // The operator dismisses it again so the local queue stays clean.
        stage = 'report organization content';
        final report = (await alex.mutate('reportContent', {
          'kind': 'announcement',
          'id': post,
          'reason': 'Uji laporan lokal',
        })).text('id');
        _check(
          alex.hasReported('announcement', post),
          'Report on organization content is not in the snapshot.',
        );
        await _denied(
          () => backends[0].mutate('reportContent', {
            'kind': 'announcement',
            'id': post,
            'reason': 'Punya sendiri',
          }),
          'forbidden',
        );
        final review = await http.postUrl(
          Uri.parse('$url/rest/v1/rpc/grouply_moderation'),
        );
        review.headers
          ..set('apikey', service)
          ..set('Authorization', 'Bearer $service')
          ..contentType = ContentType.json;
        review.write(
          jsonEncode({
            'action': 'review',
            'payload': {
              'id': report,
              'decision': 'dismissed',
              'note': 'Uji integrasi lokal',
            },
          }),
        );
        final reviewed = await review.close();
        await reviewed.drain<void>();
        _check(reviewed.statusCode == 200, 'Operator review was rejected.');

        // Finish the tasks so the persistent accounts hold no assignments.
        stage = 'cleanup';
        for (final task in [first, second, followUpTask, ...batchIDs]) {
          await raka.mutate('startTask', {'id': task, 'expectedVersion': 1});
          await raka.mutate('submitWork', {
            'taskID': task,
            'note': 'Selesai',
            'links': <String>[],
            'expectedVersion': 2,
          });
          await alex.mutate('review', {
            'taskID': task,
            'approve': true,
            'feedback': 'Oke',
            'expectedVersion': 3,
          });
        }
        await alex.mutate('leaveGroup', {'id': committee});
        await raka.mutate('leaveGroup', {'id': committee});
        await founder.mutate('deleteAccount', {});
        _check(!founder.authenticated, 'Founder account was not removed.');
        debugPrint(
          'PASS: committee; project lead tasks; premium batch concurrent retry; meeting minutes, attendance, '
          'meeting task; two-step approval + closed mapping; announcement '
          'read counts; cleanup.',
        );
      } catch (_) {
        fail('Local tahap 2 flow failed during $stage; details suppressed.');
      }
    },
    skip: Platform.environment['GROUPLY_LOCAL_INTEGRATION'] != '1'
        ? 'Opt in with GROUPLY_LOCAL_INTEGRATION=1; existing localhost backend only.'
        : false,
    timeout: const Timeout(Duration(minutes: 2)),
  );
}
