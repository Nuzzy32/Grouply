import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grouply/core/store.dart';
import 'package:grouply/features/workspace_screens.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'core_test.dart' show FakeBackend, cloudSnapshot;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('a submission shows its attached files from the server', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(430, 932);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final backend = FakeBackend()
      ..files = {
        's1': [
          {
            'path': 't1/f1',
            'name': 'ERD.pdf',
            'size': 2048,
            'type': 'application/pdf',
          },
        ],
      };
    backend.read = () async => {
      ...cloudSnapshot('ayu@example.com'),
      'submissionFilesAvailable': true,
      'users': [
        {'id': 'ayu@example.com', 'name': 'Ayu', 'email': '', 'tint': '#000'},
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
          'title': 'Rancang ERD',
          'description': '',
          'assigneeID': 'ayu@example.com',
          'reviewerID': 'u2',
          'dueAt': DateTime.now().toUtc().toIso8601String(),
          'status': 'in_review',
          'version': 2,
          'submissions': [
            {
              'id': 's1',
              'revision': 1,
              'authorID': 'ayu@example.com',
              'note': 'ERD terlampir',
              'links': <String>[],
              'createdAt': DateTime.now().toUtc().toIso8601String(),
            },
          ],
        },
      ],
    };
    final store = GrouplyStore(backend: backend);
    addTearDown(store.dispose);
    await store.initialize();
    await store.signIn('ayu@example.com', 'rahasia123');
    expect(store.submissionFilesAvailable, isTrue);

    await tester.pumpWidget(
      MaterialApp(
        home: TaskScreen(store: store, taskID: 't1'),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Hasil kerja'));
    await tester.pumpAndSettle();
    expect(find.text('ERD.pdf'), findsOneWidget);
    expect(find.text('2 KB'), findsOneWidget);
    expect(find.bySemanticsLabel('Buka ERD.pdf'), findsOneWidget);
  });
}
