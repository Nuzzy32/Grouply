import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grouply/app.dart';
import 'package:grouply/core/store.dart';
import 'package:grouply/ui/gupy.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'core_test.dart' show FakeBackend, cloudSnapshot;

/// Gupy lives in three places only: the two first-run empty states and the
/// "all done" moment (docs/DESIGN-onboarding-mascot.md §10).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<GrouplyStore> open(WidgetTester tester, FakeBackend backend) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(430, 932);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final store = GrouplyStore(backend: backend);
    addTearDown(store.dispose);
    await store.initialize();
    await store.signIn('ayu@example.com', 'rahasia123');
    await tester.pumpWidget(GrouplyApp(store: store, enableLinks: false));
    await tester.pumpAndSettle();
    return store;
  }

  testWidgets('a new account meets Gupy on empty Grup and Tugas Saya', (
    tester,
  ) async {
    await open(tester, FakeBackend());
    await tester.tap(find.byKey(const Key('tab-1')));
    await tester.pumpAndSettle(); // the hello wave ends, nothing keeps ticking
    expect(find.text('Belum ada grup'), findsOneWidget);
    expect(find.byType(GupyRig), findsOneWidget);

    await tester.tap(find.byKey(const Key('tab-3')));
    await tester.pumpAndSettle();
    expect(find.text('Belum ada tugas'), findsOneWidget);
    expect(find.byType(GupyStill), findsOneWidget);
  });

  testWidgets('Gupy cheers only when every task of yours is done', (
    tester,
  ) async {
    final backend = FakeBackend();
    var status = 'done';
    backend.read = () async => {
      ...cloudSnapshot('ayu@example.com'),
      'users': [
        {
          'id': 'ayu@example.com',
          'name': 'Ayu',
          'email': '',
          'tint': '#000000',
        },
        {'id': 'u2', 'name': 'Raka', 'email': '', 'tint': '#C9F2D6'},
      ],
      'groups': [
        {
          'id': 'g1',
          'name': 'Kelompok 1',
          'description': '',
          'course': 'Basis Data',
          'memberIDs': ['ayu@example.com', 'u2'],
          'coordinatorID': 'u2',
          'tint': '#D8EAF4',
          'icon': 'person.3',
        },
      ],
      'projects': [
        {
          'id': 'p1',
          'groupID': 'g1',
          'title': 'Proyek',
          'description': '',
          'dueAt': DateTime.now().toUtc().toIso8601String(),
          'status': 'active',
        },
      ],
      'tasks': [
        {
          'id': 't1',
          'projectID': 'p1',
          'title': 'Rekap data',
          'description': '',
          'assigneeID': 'ayu@example.com',
          'reviewerID': 'u2',
          'dueAt': DateTime.now().toUtc().toIso8601String(),
          'status': status,
          'version': 1,
          'submissions': <Map<String, Object?>>[],
        },
      ],
    };
    final store = await open(tester, backend);
    await tester.tap(find.byKey(const Key('tab-3')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('tasks-all-done')), findsOneWidget);
    expect(find.byType(GupyJump), findsOneWidget);

    status = 'in_progress';
    await store.refresh();
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('tasks-all-done')), findsNothing);
  });
}
