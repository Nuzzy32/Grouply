import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:grouply/core/store.dart';
import 'package:grouply/features/workspace_screens.dart';
import 'package:grouply/ui/gl.dart';

class _DemoStore extends GrouplyStore {
  final calls = <({String action, JsonMap payload})>[];
  Completer<void>? gate;

  @override
  Future<JsonMap> mutate(String action, [JsonMap payload = const {}]) async {
    calls.add((action: action, payload: Map.of(payload)));
    await gate?.future;
    return super.mutate(action, payload);
  }
}

Future<void> _show(WidgetTester tester, Widget screen) async {
  tester.view.physicalSize = const Size(800, 1800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(MaterialApp(theme: GLTheme.data, home: screen));
  await tester.pumpAndSettle();
}

Future<void> _tapOn(WidgetTester tester, Finder target) async {
  await tester.ensureVisible(target);
  await tester.tap(target);
  await tester.pumpAndSettle();
}

Future<void> _tap(WidgetTester tester, String label) =>
    _tapOn(tester, find.text(label).last);

/// GLTap / GLCircleButton carrying an accessibility [label].
Finder _labelled(String label) =>
    find.byWidgetPredicate((w) => w is GLTap && w.label == label);

Finder _icon(Finder within, String name) => find.descendant(
  of: within,
  matching: find.byWidgetPredicate((w) => w is GLIcon && w.name == name),
);

Future<void> _fill(WidgetTester tester, Finder field, String value) async {
  await tester.ensureVisible(field);
  await tester.enterText(field, value);
  await tester.pump();
}

final _linkFields = find.byWidgetPredicate(
  (w) => w is TextField && w.keyboardType == TextInputType.url,
);

/// Lets the 2.4s toast timer fire so no timer is pending at test end.
Future<void> _settleToasts(WidgetTester tester) async {
  await tester.pump(const Duration(seconds: 3));
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _DemoStore store;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    store = _DemoStore();
    await store.startDemo();
  });

  tearDown(() => store.dispose());

  testWidgets(
    'create group validates then sends the Swift payload and opens detail',
    (tester) async {
      await _show(tester, GroupsScreen(store: store));
      expect(find.text('Basis Data · Kelompok 3'), findsOneWidget);
      expect(find.text('Statistika · Kelompok 1'), findsNothing);
      await _tapOn(tester, find.byKey(const Key('group-create')));
      await _tapOn(tester, find.byKey(const Key('group-save')));
      expect(find.text('Nama grup minimal 3 karakter.'), findsOneWidget);
      expect(store.calls, isEmpty);
      await _fill(tester, find.byKey(const Key('group-name')), 'Tim Flutter');
      await _fill(
        tester,
        find.byKey(const Key('group-course')),
        'Pemrograman Mobile',
      );
      await _tapOn(tester, find.byKey(const Key('group-save')));
      expect(store.calls.single.action, 'createGroup');
      expect(store.calls.single.payload, {
        'name': 'Tim Flutter',
        'course': 'Pemrograman Mobile',
        'description': '',
      });
      expect(find.byType(GroupScreen), findsOneWidget);
      expect(find.text('Tim Flutter'), findsOneWidget);
      expect(
        store.groups.any((group) => group.text('name') == 'Tim Flutter'),
        isTrue,
      );
      expect(tester.takeException(), isNull);
      await _settleToasts(tester);
    },
  );

  testWidgets('start task sends expectedVersion and guards duplicate taps', (
    tester,
  ) async {
    await _show(tester, TaskScreen(store: store, taskID: 't10'));
    store.gate = Completer<void>();
    final start = find.text('Mulai kerjakan');
    await tester.tap(start);
    await tester.pump();
    await tester.tap(start, warnIfMissed: false);
    await tester.pump();
    expect(store.calls.length, 1);
    expect(store.calls.single.action, 'startTask');
    expect(store.calls.single.payload, {'id': 't10', 'expectedVersion': 1});
    store.gate!.complete();
    await tester.pumpAndSettle();
    expect(store.task('t10')!.text('status'), 'in_progress');
    expect(find.text('Kirim hasil'), findsOneWidget);
    await _settleToasts(tester);
  });

  testWidgets(
    'submission validates HTTPS then preserves note, links and version',
    (tester) async {
      await store.mutate('startTask', {'id': 't10', 'expectedVersion': 1});
      store.calls.clear();
      await _show(tester, TaskScreen(store: store, taskID: 't10'));
      await _tap(tester, 'Kirim hasil');
      await _fill(
        tester,
        find.byKey(const Key('submission-note')),
        'Alur sudah siap direview.',
      );
      const invalidLink =
          'Link harus diawali https:// dan berupa alamat lengkap.';
      for (final invalid in [
        'http://example.com/hasil',
        'https://%',
        'https://@example.com',
      ]) {
        await _fill(tester, _linkFields.first, invalid);
        await _tapOn(tester, find.byKey(const Key('submit-work')));
        expect(find.text(invalidLink), findsOneWidget);
        expect(store.calls, isEmpty);
      }
      await _fill(tester, _linkFields.first, 'https://example.com/hasil');
      await _tap(tester, 'Tambah link');
      await _fill(tester, _linkFields.last, 'https://example.com/demo');
      await _tapOn(tester, find.byKey(const Key('submit-work')));
      expect(store.calls.single.action, 'submitWork');
      expect(store.calls.single.payload, {
        'taskID': 't10',
        'expectedVersion': 2,
        'note': 'Alur sudah siap direview.',
        'links': ['https://example.com/hasil', 'https://example.com/demo'],
      });
      expect(store.task('t10')!.text('status'), 'in_review');
      expect(find.text('Kirim hasil'), findsNothing);
      expect(find.byKey(const Key('open-review')), findsNothing);
      expect(find.text('Alur sudah siap direview.'), findsOneWidget);
      await _settleToasts(tester);
    },
  );

  testWidgets(
    'review requires feedback; revision history and approval remain append-only',
    (tester) async {
      // t11: Raka (u2) executes, Nadia (u3, not coordinator of g1) reviews.
      await store.switchDemoUser('u2');
      await store.mutate('startTask', {'id': 't11', 'expectedVersion': 1});
      await store.mutate('submitWork', {
        'taskID': 't11',
        'note': 'Ringkasan awal.',
        'links': <String>[],
        'expectedVersion': 2,
      });
      await store.switchDemoUser('u3');
      store.calls.clear();
      await _show(tester, TaskScreen(store: store, taskID: 't11'));
      // Reviewer is not coordinator: reassign is locked and sends nothing.
      final reassign = _labelled('Alihkan pelaksana');
      expect(_icon(reassign, 'lock'), findsOneWidget);
      await _tapOn(tester, reassign);
      expect(find.text('Pilih anggota lain'), findsNothing);
      expect(store.calls, isEmpty);
      await _settleToasts(tester);

      await _tapOn(tester, find.byKey(const Key('open-review')));
      await _tap(tester, 'Minta revisi');
      await _tap(tester, 'Kirim ke Raka');
      expect(find.text('Jelaskan apa yang perlu diubah.'), findsOneWidget);
      expect(store.calls, isEmpty);
      await _fill(
        tester,
        find.byKey(const Key('review-feedback')),
        'Tambahkan kesimpulan.',
      );
      await _tap(tester, 'Kirim ke Raka');
      expect(store.calls.single.action, 'review');
      expect(store.calls.single.payload, {
        'taskID': 't11',
        'approve': false,
        'expectedVersion': 3,
        'feedback': 'Tambahkan kesimpulan.',
      });
      expect(store.task('t11')!.text('status'), 'needs_revision');

      await store.switchDemoUser('u2');
      await tester.pumpAndSettle();
      await _tap(tester, 'Kirim revisi');
      await _fill(
        tester,
        find.byKey(const Key('submission-note')),
        'Kesimpulan sudah ditambahkan.',
      );
      await _tapOn(tester, find.byKey(const Key('submit-work')));
      expect(store.calls.last.action, 'submitWork');
      expect(store.calls.last.payload['expectedVersion'], 4);

      await store.switchDemoUser('u3');
      await tester.pumpAndSettle();
      await _tapOn(tester, find.byKey(const Key('open-review')));
      await _tapOn(tester, find.byKey(const Key('approve-work')));
      expect(store.calls.last.action, 'review');
      expect(store.calls.last.payload, {
        'taskID': 't11',
        'approve': true,
        'feedback': '',
        'expectedVersion': 5,
      });
      expect(store.task('t11')!.text('status'), 'done');
      final history = store.task('t11')!['submissions'] as List;
      expect(history.length, 2);
      expect(history.first['decision'], 'changes_requested');
      expect(history.first['note'], 'Ringkasan awal.');
      expect(history.last['decision'], 'approved');
      expect(tester.takeException(), isNull);
      await _settleToasts(tester);
    },
  );

  testWidgets(
    'archived and missing membership screens expose no write actions',
    (tester) async {
      await store.mutate('archiveProject', {'id': 'p3'});
      store.calls.clear();
      await _show(tester, TaskScreen(store: store, taskID: 't12'));
      expect(
        find.text('Proyek diarsipkan · tugas hanya bisa dilihat'),
        findsOneWidget,
      );
      for (final label in [
        'Mulai kerjakan',
        'Kirim hasil',
        'Kirim revisi',
        'Alihkan',
      ]) {
        expect(find.text(label), findsNothing);
      }
      expect(find.byKey(const Key('open-review')), findsNothing);
      await _tapOn(tester, _labelled('Opsi tugas'));
      expect(find.text('Buka kembali tugas'), findsNothing);
      await _tap(tester, 'Edit tugas');
      expect(find.text('Proyek diarsipkan'), findsOneWidget);
      expect(find.byKey(const Key('task-title')), findsNothing);
      await _tap(tester, 'Mengerti');
      await _tap(tester, 'Diskusi');
      expect(
        find.text('Diskusi hanya-baca karena proyek diarsipkan.'),
        findsOneWidget,
      );
      expect(find.text('Komentari tugas ini…'), findsNothing);
      expect(store.calls, isEmpty);

      await tester.pumpWidget(
        MaterialApp(
          theme: GLTheme.data,
          home: ProjectScreen(store: store, projectID: 'p3'),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Pulihkan Proyek'), findsOneWidget);
      final addTask = find.byKey(const ValueKey('add-task'));
      expect(_icon(addTask, 'lock'), findsOneWidget);
      await _tapOn(tester, addTask);
      expect(find.text('Proyek diarsipkan'), findsOneWidget);
      expect(find.byKey(const Key('task-title')), findsNothing);
      await _tap(tester, 'Mengerti');
      await store.switchDemoUser('u3');
      await tester.pumpAndSettle();
      await _tap(tester, 'Pulihkan Proyek');
      expect(store.calls, isEmpty);
      expect(store.project('p3')!.text('status'), 'archived');
      await _settleToasts(tester);

      await tester.pumpWidget(
        MaterialApp(
          theme: GLTheme.data,
          home: GroupScreen(store: store, groupID: 'not-visible'),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Kamu tidak punya akses'), findsOneWidget);
      expect(find.text('Buat proyek'), findsNothing);
    },
  );

  testWidgets('invites create, copy and revoke with exact action keys', (
    tester,
  ) async {
    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied = (call.arguments as Map)['text'] as String;
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    await _show(tester, GroupScreen(store: store, groupID: 'g1'));
    await _tap(tester, 'Undang');
    expect(store.calls.single.action, 'generateInvite');
    expect(store.calls.single.payload, {'groupID': 'g1'});
    expect(find.text('Undangan aktif'), findsOneWidget);
    await _tap(tester, 'Salin');
    expect(copied, store.invites.last.text('code'));
    await _tap(tester, 'Nonaktifkan kode');
    expect(store.calls.last.action, 'revokeInvite');
    expect(store.calls.last.payload, {'id': store.invites.last.text('id')});
    expect(store.invites.last['revoked'], isTrue);
    expect(find.text('Undangan tidak berlaku'), findsOneWidget);
    expect(find.text('Nonaktifkan kode'), findsNothing);
    expect(tester.takeException(), isNull);
    await _settleToasts(tester);
  });

  testWidgets('discussion uses task context and one UUID across submission', (
    tester,
  ) async {
    store.simulateSendFailure = true;
    await _show(tester, TaskScreen(store: store, taskID: 't1'));
    await _tap(tester, 'Diskusi');
    await _fill(
      tester,
      find.widgetWithText(TextField, 'Komentari tugas ini…'),
      'Mari cek alurnya bersama.',
    );
    await _tapOn(tester, _labelled('Kirim pesan'));
    final call = store.calls.single;
    expect(call.action, 'sendMessage');
    expect(call.payload['groupID'], 'g1');
    expect(call.payload['taskID'], 't1');
    expect(call.payload['text'], 'Mari cek alurnya bersama.');
    expect(
      call.payload.text('clientID'),
      matches(
        RegExp(
          r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
        ),
      ),
    );
    expect(store.messages.last.text('text'), 'Mari cek alurnya bersama.');
    expect(store.messages.last.text('delivery'), 'failed');
    store.simulateSendFailure = false;
    await _tap(tester, 'Gagal terkirim · Coba lagi');
    expect(store.calls.last.action, 'sendMessage');
    expect(store.calls.last.payload, call.payload);
    expect(
      store.messages
          .where(
            (message) => message.text('id') == call.payload.text('clientID'),
          )
          .length,
      1,
    );
    expect(store.messages.last.text('delivery'), 'sent');
  });

  testWidgets(
    'stale expectedVersion displays the server error without overwriting task',
    (tester) async {
      await _show(tester, TaskScreen(store: store, taskID: 't11'));
      await _tapOn(tester, _labelled('Opsi tugas'));
      await _tap(tester, 'Edit tugas');
      await _fill(
        tester,
        find.byKey(const Key('task-title')),
        'Judul yang belum tersimpan',
      );
      store.task('t11')!['version'] = 99;
      await _tap(tester, 'Simpan perubahan');
      expect(find.byKey(const Key('form-error')), findsOneWidget);
      expect(
        find.text('Tugas telah berubah. Tutup editor dan coba lagi.'),
        findsOneWidget,
      );
      expect(store.calls.single.action, 'updateTask');
      expect(store.calls.single.payload['expectedVersion'], 1);
      expect(store.task('t11')!.text('title'), 'Kamus data');
      expect(store.task('t11')!.number('version'), 99);
      expect(find.byKey(const Key('task-title')), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('join normalizes invitation code and opens the joined group', (
    tester,
  ) async {
    await _show(tester, GroupsScreen(store: store));
    await _tap(tester, 'Gabung dengan kode undangan');
    await _fill(tester, find.byKey(const Key('join-code')), ' stat-k1q ');
    await _tapOn(tester, find.byKey(const Key('group-save')));
    expect(store.calls.single.action, 'joinGroup');
    expect(store.calls.single.payload, {'code': 'STAT-K1Q'});
    expect(store.group('g3')!.ids('memberIDs'), contains('u1'));
    expect(find.byType(GroupScreen), findsOneWidget);
    expect(find.text('Statistika · Kelompok 1'), findsOneWidget);
    await _settleToasts(tester);
  });

  testWidgets(
    'project and task editors create, edit and reassign through the store',
    (tester) async {
      await _show(tester, GroupScreen(store: store, groupID: 'g1'));
      await _tapOn(tester, find.byKey(const Key('create-project')));
      await _fill(
        tester,
        find.byKey(const ValueKey('project-title')),
        'Proyek Flutter',
      );
      await _fill(
        tester,
        find.byWidgetPredicate((w) => w is TextField && w.maxLength == 300),
        'Uji kolaborasi.',
      );
      await _tapOn(tester, find.byKey(const ValueKey('project-save')));
      final project = store.projects.last;
      expect(store.calls.last.action, 'createProject');
      expect(store.calls.last.payload['groupID'], 'g1');
      expect(store.calls.last.payload['description'], 'Uji kolaborasi.');
      expect(store.calls.last.payload.date('dueAt'), isNotNull);
      expect(find.byType(ProjectScreen), findsOneWidget);

      await _tapOn(tester, find.byKey(const ValueKey('add-task')));
      await _fill(
        tester,
        find.byKey(const Key('task-title')),
        'Susun layar tugas',
      );
      // Pelaksana chips precede the reviewer chips.
      Finder inSheet(String text) => find.descendant(
        of: find.byType(BottomSheet),
        matching: find.text(text),
      );
      await _tapOn(tester, inSheet('Raka').first);
      await _tapOn(tester, inSheet('Nadia').last);
      await _tapOn(tester, find.widgetWithText(GLSubmitButton, 'Buat tugas'));
      final task = store.tasks.last;
      expect(store.calls.last.action, 'createTask');
      expect(store.calls.last.payload['projectID'], project.text('id'));
      expect(store.calls.last.payload['assigneeID'], 'u2');
      expect(store.calls.last.payload['reviewerID'], 'u3');

      await _tap(tester, 'Susun layar tugas');
      expect(find.byType(TaskScreen), findsOneWidget);
      await _tapOn(tester, _labelled('Opsi tugas'));
      await _tap(tester, 'Edit tugas');
      await _fill(
        tester,
        find.byKey(const Key('task-title')),
        'Susun layar detail',
      );
      await _tap(tester, 'Simpan perubahan');
      expect(store.calls.last.action, 'updateTask');
      expect(store.calls.last.payload['expectedVersion'], 1);
      expect(store.calls.last.payload.containsKey('assigneeID'), isFalse);

      await _tapOn(tester, _labelled('Alihkan pelaksana'));
      await _tap(tester, 'Kamu');
      expect(store.calls.last.action, 'reassignTask');
      expect(store.calls.last.payload, {
        'id': task.text('id'),
        'expectedVersion': 2,
        'assigneeID': 'u1',
        'reviewerID': 'u3',
      });
      expect(store.task(task.text('id'))!.text('assigneeID'), 'u1');
      expect(tester.takeException(), isNull);
      await _settleToasts(tester);
    },
  );

  testWidgets(
    'project restore preserves completed status before explicit reopen',
    (tester) async {
      await store.mutate('archiveProject', {'id': 'p3'});
      store.calls.clear();
      await _show(tester, ProjectScreen(store: store, projectID: 'p3'));
      final addTask = find.byKey(const ValueKey('add-task'));
      await _tap(tester, 'Pulihkan Proyek');
      expect(store.calls.last.action, 'restoreProject');
      expect(store.calls.last.payload, {'id': 'p3'});
      expect(store.project('p3')!.text('status'), 'completed');
      expect(_icon(addTask, 'lock'), findsOneWidget);
      await _tap(tester, 'Buka Kembali Proyek');
      await _tap(tester, 'Buka kembali');
      expect(store.calls.last.action, 'reopenProject');
      expect(store.calls.last.payload, {'id': 'p3'});
      expect(store.project('p3')!.text('status'), 'active');
      expect(_icon(addTask, 'plus'), findsOneWidget);
      await _tapOn(tester, _labelled('Aksi proyek'));
      await _tap(tester, 'Arsipkan proyek');
      await _tap(tester, 'Arsipkan');
      expect(store.calls.last.action, 'archiveProject');
      expect(store.project('p3')!.text('status'), 'archived');
      expect(_icon(addTask, 'lock'), findsOneWidget);
      await _settleToasts(tester);
    },
  );

  testWidgets('narrow screen with large text and keyboard remains scrollable', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: GLTheme.data,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: const TextScaler.linear(1.5)),
          child: child!,
        ),
        home: GroupsScreen(store: store),
      ),
    );
    await tester.pumpAndSettle();
    await _tapOn(tester, find.byKey(const Key('group-create')));
    await _fill(tester, find.byKey(const Key('group-name')), 'Tim kecil');
    tester.view.viewInsets = const FakeViewPadding(bottom: 240);
    addTearDown(tester.view.resetViewInsets);
    await tester.pumpAndSettle();
    await _tapOn(tester, find.byKey(const Key('group-save')));
    expect(store.calls.single.action, 'createGroup');
    expect(tester.takeException(), isNull);
    await _settleToasts(tester);
  });
}
