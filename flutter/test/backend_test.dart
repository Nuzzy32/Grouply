import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grouply/core/backend.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  final binding = _BackendTestBinding();
  const secureChannel = MethodChannel(
    'plugins.it_nomads.com/flutter_secure_storage',
  );
  const sessionKey = 'grouply.auth.backend-test';
  const encodedSession =
      '{"access_token":"test-access-token","refresh_token":"test-refresh-token"}';
  late Map<String, String> secureValues;
  late List<MethodCall> secureCalls;
  late SharedPreferences preferences;
  late List<bool?> tombstonesAtDelete;
  String? failingMethod;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    preferences = await SharedPreferences.getInstance();
    secureValues = {};
    secureCalls = [];
    tombstonesAtDelete = [];
    failingMethod = null;
    binding.defaultBinaryMessenger.setMockMethodCallHandler(secureChannel, (
      call,
    ) async {
      secureCalls.add(call);
      final arguments = Map<String, dynamic>.from(call.arguments as Map);
      final key = arguments['key'] as String;
      if (call.method == 'delete') {
        tombstonesAtDelete.add(preferences.getBool('$key.signedOut'));
      }
      if (call.method == failingMethod) {
        throw PlatformException(code: 'secure-storage-unavailable');
      }
      switch (call.method) {
        case 'read':
          return secureValues[key];
        case 'write':
          secureValues[key] = arguments['value'] as String;
          return null;
        case 'delete':
          secureValues.remove(key);
          return null;
        default:
          throw UnsupportedError(
            'Unexpected secure storage call: ${call.method}',
          );
      }
    });
  });

  tearDown(() {
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      secureChannel,
      null,
    );
  });

  group('SecureSessionStorage', () {
    late SecureSessionStorage storage;

    setUp(() {
      storage = SecureSessionStorage(
        key: sessionKey,
        storage: const FlutterSecureStorage(),
      );
    });

    test(
      'initialization does not touch storage and missing session stays null',
      () async {
        await storage.initialize();
        expect(secureCalls, isEmpty);
        expect(await storage.accessToken(), isNull);
        expect(await storage.hasAccessToken(), isFalse);
        expect(secureValues, isEmpty);
        expect(preferences.getKeys(), isEmpty);
      },
    );

    test(
      'round trips the entire session through the exact secure key',
      () async {
        await storage.persistSession(encodedSession);
        expect(secureValues, {sessionKey: encodedSession});
        final write = secureCalls.single;
        expect(write.method, 'write');
        expect((write.arguments as Map)['key'], sessionKey);
        expect((write.arguments as Map)['value'], encodedSession);

        final restored = SecureSessionStorage(key: sessionKey);
        await restored.initialize();
        expect(await restored.accessToken(), encodedSession);
        expect(await restored.hasAccessToken(), isTrue);
        expect(secureCalls.map((call) => call.method), [
          'write',
          'read',
          'read',
        ]);
        expect(preferences.getKeys(), isEmpty);
      },
    );

    test(
      'overwrites only its session and deletes without clearing other keys',
      () async {
        secureValues['unrelated-key'] = 'keep';
        await storage.persistSession(encodedSession);
        await storage.persistSession('replacement-session');
        expect(await storage.accessToken(), 'replacement-session');
        await storage.removePersistedSession();
        await storage.removePersistedSession();
        expect(await storage.accessToken(), isNull);
        expect(await storage.hasAccessToken(), isFalse);
        expect(secureValues, {'unrelated-key': 'keep'});
        expect(tombstonesAtDelete, [true, true]);
        expect(storage.signedOutKey, '$sessionKey.signedOut');
        expect(preferences.getKeys(), {storage.signedOutKey});
        expect(preferences.get(storage.signedOutKey), isTrue);
        expect(
          secureCalls.every(
            (call) => (call.arguments as Map)['key'] == sessionKey,
          ),
          isTrue,
        );
      },
    );

    for (final operation in ['read', 'hasAccessToken', 'write', 'delete']) {
      test('$operation propagates secure storage failure', () async {
        secureValues[sessionKey] = encodedSession;
        failingMethod = operation == 'hasAccessToken' ? 'read' : operation;
        final Future<Object?> result;
        switch (operation) {
          case 'read':
            result = storage.accessToken();
          case 'hasAccessToken':
            result = storage.hasAccessToken();
          case 'write':
            result = storage.persistSession('replacement-session');
          default:
            result = storage.removePersistedSession();
        }
        await expectLater(
          result,
          throwsA(
            isA<PlatformException>().having(
              (error) => error.code,
              'code',
              'secure-storage-unavailable',
            ),
          ),
        );
        expect(secureValues, {sessionKey: encodedSession});
        expect(secureCalls, hasLength(1));
        if (operation == 'delete') {
          expect(tombstonesAtDelete, [true]);
          expect(preferences.get(storage.signedOutKey), isTrue);
          final restored = SecureSessionStorage(key: sessionKey);
          await restored.initialize();
          expect(await restored.accessToken(), isNull);
          expect(await restored.hasAccessToken(), isFalse);
          expect(await storage.accessToken(), isNull);
          expect(secureCalls, hasLength(1));
          expect(preferences.getKeys(), {storage.signedOutKey});
        } else {
          expect(preferences.getKeys(), isEmpty);
        }
      });
    }

    test('failed secure write cannot clear the signed-out tombstone', () async {
      secureValues[sessionKey] = encodedSession;
      await preferences.setBool(storage.signedOutKey, true);
      failingMethod = 'write';

      await expectLater(
        storage.persistSession('replacement-session'),
        throwsA(isA<PlatformException>()),
      );

      expect(secureValues, {sessionKey: encodedSession});
      expect(preferences.getKeys(), {storage.signedOutKey});
      expect(preferences.get(storage.signedOutKey), isTrue);
      expect(await storage.accessToken(), isNull);
      final restored = SecureSessionStorage(key: sessionKey);
      await restored.initialize();
      expect(await restored.accessToken(), isNull);
      expect(await restored.hasAccessToken(), isFalse);
      expect(secureCalls, hasLength(1));

      failingMethod = null;
      await restored.persistSession('replacement-session');
      expect(await restored.accessToken(), 'replacement-session');
      expect(secureValues, {sessionKey: 'replacement-session'});
      expect(preferences.getKeys(), isEmpty);
    });
  });

  group('Supabase configuration validation', () {
    final anonJWT = _jwt({'role': 'anon'});
    const publishableKey = 'sb_publishable_test-public-key_123';

    for (final url in [
      'https://example.supabase.co',
      'https://localhost:54321',
      'http://localhost:54321',
      'http://127.0.0.1:54321',
      'http://[::1]:54321',
      'http://10.0.2.2:54321',
      'http://10.0.3.2:54321',
    ]) {
      for (final key in [anonJWT, publishableKey]) {
        test(
          'accepts $url with ${key == anonJWT ? 'anon JWT' : 'publishable key'}',
          () {
            final backend = SupabaseGrouplyBackend(url: url, anonKey: key);
            addTearDown(backend.dispose);
            expect(backend.configured, isTrue);
          },
        );
      }
    }

    for (final url in [
      '',
      'not-a-url',
      '/relative',
      'https://',
      'https://%',
      'https://user:password@example.supabase.co',
      'https://user@example.supabase.co',
      'https://@example.supabase.co',
      'http://user:password@localhost:54321',
      'https://example.supabase.co?token=not-allowed',
      'https://example.supabase.co?',
      'https://example.supabase.co#not-allowed',
      'https://example.supabase.co#',
      ' https://example.supabase.co',
      'https://example.supabase.co ',
      'http://example.supabase.co',
      'http://localhost.example.com',
      'http://127.0.0.2:54321',
      'http://192.168.1.1:54321',
      'ftp://localhost:54321',
      'file:///localhost',
    ]) {
      test('rejects URL ${jsonEncode(url)}', () {
        final backend = SupabaseGrouplyBackend(
          url: url,
          anonKey: publishableKey,
        );
        addTearDown(backend.dispose);
        expect(backend.configured, isFalse);
      });
    }

    final invalidKeys = {
      'empty': '',
      'secret': 'sb_secret_test-key',
      'service role JWT': _jwt({'role': 'service_role'}),
      'authenticated JWT': _jwt({'role': 'authenticated'}),
      'missing role JWT': _jwt({}),
      'non-object JWT': _jwt(['anon']),
      'invalid JSON JWT': 'header.bm90LWpzb24.signature',
      'invalid base64 JWT': 'header.%.signature',
      'missing signature JWT':
          '${anonJWT.substring(0, anonJWT.lastIndexOf('.'))}.',
      'extra JWT segment': '$anonJWT.extra',
      'unresolved setting': r'$(SUPABASE_ANON_KEY)',
      'empty publishable key': 'sb_publishable_',
      'publishable key with whitespace': 'sb_publishable_test key',
    };
    for (final entry in invalidKeys.entries) {
      test('rejects ${entry.key}', () {
        final backend = SupabaseGrouplyBackend(
          url: 'https://example.supabase.co',
          anonKey: entry.value,
        );
        addTearDown(backend.dispose);
        expect(backend.configured, isFalse);
      });
    }

    test('an injected client bypasses URL and key validation', () async {
      final client = SupabaseClient(
        'http://127.0.0.1:54321',
        'test-only-key',
        authOptions: const AuthClientOptions(autoRefreshToken: false),
      );
      final backend = SupabaseGrouplyBackend(
        url: 'http://user:password@remote.example.com?token=no#fragment',
        anonKey: _jwt({'role': 'service_role'}),
        client: client,
        sessionStorage: SecureSessionStorage(key: sessionKey),
      );
      addTearDown(() async {
        backend.dispose();
        await pumpEventQueue();
      });
      expect(backend.configured, isTrue);
      await backend.initialize();
      expect(backend.currentUserID, isNull);
    });
  });

  group('Supabase SDK RPC over HTTP', () {
    late HttpServer server;
    late SupabaseGrouplyBackend backend;
    late SupabaseClient client;
    late List<({String method, String path, Object? body})> requests;
    Object? response;
    var responseStatus = HttpStatus.ok;
    const payload = {
      'taskID': 'task-1',
      'note': 'Hasil revisi',
      'links': ['https://example.com/work'],
      'metadata': {'reviewerID': 'reviewer-1', 'decision': null},
    };
    const snapshot = {
      'currentUserID': 'author-1',
      'tasks': [
        {
          'id': 'task-1',
          'projectID': 'project-1',
          'assigneeID': 'author-1',
          'reviewerID': 'reviewer-1',
          'dueAt': '2026-10-20T12:00:00Z',
          'status': 'in_review',
          'version': 2,
          'submissions': [
            {
              'id': 'submission-1',
              'revision': 2,
              'authorID': 'author-1',
              'createdAt': '2026-10-17T12:00:00Z',
              'note': 'Hasil revisi',
              'links': ['https://example.com/work'],
              'decision': null,
              'reviewerID': null,
            },
          ],
        },
      ],
    };

    setUp(() async {
      requests = [];
      response = snapshot;
      responseStatus = HttpStatus.ok;
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((request) async {
        final body = await utf8.decoder.bind(request).join();
        requests.add((
          method: request.method,
          path: request.uri.path,
          body: body.isEmpty ? null : jsonDecode(body),
        ));
        request.response
          ..statusCode = responseStatus
          ..headers.contentType = ContentType.json
          ..write(jsonEncode(response));
        await request.response.close();
      });
      final url = 'http://${server.address.address}:${server.port}';
      client = SupabaseClient(
        url,
        'test-anon-key',
        authOptions: const AuthClientOptions(autoRefreshToken: false),
      );
      backend = SupabaseGrouplyBackend(
        url: url,
        client: client,
        sessionStorage: SecureSessionStorage(key: sessionKey),
      );
      await backend.initialize();
    });

    tearDown(() async {
      backend.dispose();
      await pumpEventQueue();
      await server.close(force: true);
    });

    Future<void> restoreAccount() => client.auth.setInitialSession(
      jsonEncode({
        'access_token': _jwt({
          'sub': 'author-1',
          'role': 'authenticated',
          'exp':
              DateTime.now()
                  .add(const Duration(hours: 1))
                  .millisecondsSinceEpoch ~/
              1000,
        }),
        'refresh_token': 'test-refresh-token',
        'token_type': 'bearer',
        'user': {
          'id': 'author-1',
          'aud': 'authenticated',
          'app_metadata': <String, dynamic>{},
          'user_metadata': <String, dynamic>{},
          'created_at': '2026-10-17T12:00:00Z',
        },
      }),
    );

    test('expired SDK session does not authorize its cached user', () async {
      await restoreAccount();
      await pumpEventQueue();
      expect(backend.currentUserID, 'author-1');
      client.auth.currentSession!.expiresAt =
          DateTime.now()
              .subtract(const Duration(minutes: 1))
              .millisecondsSinceEpoch ~/
          1000;

      expect(client.auth.currentSession!.isExpired, isTrue);
      expect(client.auth.currentUser!.id, 'author-1');
      expect(backend.currentUserID, isNull);
      expect(requests, isEmpty);
    });

    for (final expired in [true, false]) {
      test(
        'SDK auth error with ${expired ? 'expired' : 'valid'} session never re-emits an authorized account',
        () async {
          final events = <String?>[];
          final backendErrors = <Object>[];
          final sdkErrors = <Object>[];
          final backendSubscription = backend.authChanges.listen(
            events.add,
            onError: (Object error) => backendErrors.add(error),
          );
          final sdkSubscription = client.auth.onAuthStateChange.listen(
            (_) {},
            onError: (Object error) => sdkErrors.add(error),
          );
          addTearDown(backendSubscription.cancel);
          addTearDown(sdkSubscription.cancel);
          await restoreAccount();
          await pumpEventQueue();
          expect(events, ['author-1']);
          expect(backend.currentUserID, 'author-1');
          events.clear();
          if (expired) {
            client.auth.currentSession!.expiresAt =
                DateTime.now()
                    .subtract(const Duration(minutes: 1))
                    .millisecondsSinceEpoch ~/
                1000;
          }
          response = {
            'access_token': 'invalid-session',
            'user': 'not-an-object',
          };

          await expectLater(
            client.auth.refreshSession(),
            throwsA(isA<FormatException>()),
          );
          await pumpEventQueue();

          expect(sdkErrors, [isA<FormatException>()]);
          expect(client.auth.currentUser!.id, 'author-1');
          expect(backend.currentUserID, expired ? isNull : 'author-1');
          expect(events, expired ? [null] : isEmpty);
          expect(backendErrors, expired ? isEmpty : [isA<StateError>()]);
          expect(requests, hasLength(1));
          expect(requests.single.method, 'POST');
          expect(requests.single.path, '/auth/v1/token');
          expect(requests.single.body, {'refresh_token': 'test-refresh-token'});
        },
      );
    }

    for (final rpc in ['grouply_snapshot', 'grouply_mutate']) {
      Future<Map<String, dynamic>> invoke() => rpc == 'grouply_snapshot'
          ? backend.snapshot()
          : backend.mutate('submitWork', payload);

      void expectRequest() {
        expect(requests, hasLength(1));
        expect(requests.single.method, 'POST');
        expect(requests.single.path, '/rest/v1/rpc/$rpc');
        expect(
          requests.single.body,
          rpc == 'grouply_snapshot'
              ? <String, dynamic>{}
              : {'action': 'submitWork', 'payload': payload},
        );
      }

      test(
        '$rpc returns the raw object and preserves nested camelCase',
        () async {
          final result = await invoke();
          expectRequest();
          expect(result, snapshot);
          expect(result.containsKey('data'), isFalse);
          final task = (result['tasks'] as List).single as Map;
          expect(task['projectID'], 'project-1');
          expect(task['assigneeID'], 'author-1');
          expect(task['reviewerID'], 'reviewer-1');
          expect(task['dueAt'], '2026-10-20T12:00:00Z');
          final submission = (task['submissions'] as List).single as Map;
          expect(submission['authorID'], 'author-1');
          expect(submission['createdAt'], '2026-10-17T12:00:00Z');
          expect(submission['links'], ['https://example.com/work']);
          expect(submission.containsKey('reviewerID'), isTrue);
          expect(submission['reviewerID'], isNull);
        },
      );

      test(
        '$rpc accepts an empty object without substituting demo data',
        () async {
          response = <String, dynamic>{};
          expect(await invoke(), isEmpty);
          expectRequest();
        },
      );

      for (final invalid in [
        null,
        [],
        [snapshot],
        'not-an-object',
        42,
        true,
      ]) {
        test(
          '$rpc rejects non-object ${jsonEncode(invalid)} without fallback',
          () async {
            response = invalid;
            await expectLater(invoke(), throwsA(isA<FormatException>()));
            expectRequest();
          },
        );
      }

      for (final status in [401, 403, 500]) {
        test('$rpc propagates HTTP $status without fallback', () async {
          responseStatus = status;
          response = {
            'code': '42501',
            'message': 'RPC denied',
            'details': 'test-only failure',
            'hint': 'Do not use demo data',
          };
          await expectLater(
            invoke(),
            throwsA(
              isA<PostgrestException>()
                  .having((error) => error.code, 'code', '42501')
                  .having((error) => error.message, 'message', 'RPC denied')
                  .having(
                    (error) => error.details,
                    'details',
                    'test-only failure',
                  )
                  .having(
                    (error) => error.hint,
                    'hint',
                    'Do not use demo data',
                  ),
            ),
          );
          expectRequest();
        });
      }
    }
  });
}

class _BackendTestBinding extends AutomatedTestWidgetsFlutterBinding {
  @override
  bool get overrideHttpClient => false;
}

String _jwt(Object claims) {
  String encode(Object value) =>
      base64Url.encode(utf8.encode(jsonEncode(value))).replaceAll('=', '');
  return '${encode({'alg': 'HS256', 'typ': 'JWT'})}.${encode(claims)}.test-signature';
}
