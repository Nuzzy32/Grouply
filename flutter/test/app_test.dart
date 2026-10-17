import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grouply/app.dart';
import 'package:grouply/core/store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('task links accept only a single explicit task target', () {
    expect(taskIDFromLink(Uri.parse('grouply://task/task-1')), 'task-1');
    for (final link in [
      'https://task/task-1',
      'grouply://profile/task-1',
      'grouply://task/',
      'grouply://task/one/two',
      'grouply://task/task-1?actor=other',
      'grouply://task/task-1#other',
    ]) {
      expect(taskIDFromLink(Uri.parse(link)), isNull, reason: link);
    }
  });

  testWidgets('welcome enters a clearly labelled local demo and four tabs', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(430, 932);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final store = GrouplyStore();
    await store.initialize();
    await tester.pumpWidget(GrouplyApp(store: store, enableLinks: false));
    await tester.pumpAndSettle();
    expect(find.text('Masuk dengan Akun'), findsOneWidget);
    // Without a configured backend the login sheet says so instead of offering a form.
    await tester.tap(find.text('Masuk dengan Akun'));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Konfigurasi server belum tersedia'),
      findsOneWidget,
    );
    expect(find.byKey(const Key('backend-email')), findsNothing);
    await tester.tap(find.text('Batal'));
    await tester.pumpAndSettle();
    expect(store.demoMode, isFalse);
    // Demo personas are labelled as demo before entering.
    expect(find.text('DEMO'), findsOneWidget);
    await tester.tap(find.text('Alex'));
    await tester.pumpAndSettle();
    expect(store.demoMode, isTrue);
    expect(store.currentUserID, 'u1');
    expect(find.text('Demo lokal · data contoh'), findsOneWidget);
    for (var i = 0; i < 4; i++) {
      expect(find.byKey(Key('tab-$i')), findsOneWidget);
    }
    for (final (i, label) in [
      (1, 'Grup'),
      (2, 'Chat'),
      (3, 'Tugas Saya'),
      (0, 'Beranda'),
    ]) {
      expect(
        find.descendant(
          of: find.byKey(Key('tab-$i')),
          matching: find.text(label),
        ),
        findsOneWidget,
      );
      await tester.tap(find.byKey(Key('tab-$i')));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    }
    expect(find.text('Demo lokal · data contoh'), findsOneWidget);
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpWidget(const SizedBox.shrink());
    store.dispose();
  });

  testWidgets('home fits a narrow screen with enlarged text', (tester) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    tester.platformDispatcher.textScaleFactorTestValue = 1.5;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    final store = GrouplyStore();
    await store.initialize();
    await store.startDemo();
    await tester.pumpWidget(GrouplyApp(store: store, enableLinks: false));
    await tester.pumpAndSettle();
    for (var i = 0; i < 4; i++) {
      expect(find.byKey(Key('tab-$i')), findsOneWidget);
    }
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    store.dispose();
  });

  testWidgets('home header consumes the status inset only once', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(430, 932);
    tester.view.devicePixelRatio = 1;
    tester.view.padding = const FakeViewPadding(top: 24);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPadding);
    final store = GrouplyStore();
    await store.initialize();
    await store.startDemo();
    await tester.pumpWidget(GrouplyApp(store: store, enableLinks: false));
    await tester.pumpAndSettle();
    final header = find
        .ancestor(
          of: find.byKey(const Key('open-profile')),
          matching: find.byType(Row),
        )
        .first;
    // 24pt inset + 10pt list padding; a second inset would put it at 58.
    expect(tester.getTopLeft(header).dy, 34);
    expect(find.text('Demo lokal · data contoh'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    store.dispose();
  });
}
