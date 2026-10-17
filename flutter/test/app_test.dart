import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grouply/app.dart';
import 'package:grouply/core/store.dart';
import 'package:grouply/ui/gl.dart' show GLSubmitButton;
import 'package:shared_preferences/shared_preferences.dart';

import 'core_test.dart' show FakeBackend;
import 'demo_backend.dart';

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

  testWidgets('welcome offers only real accounts, then four tabs', (
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
    await tester.tap(find.bySemanticsLabel('Tutup'));
    await tester.pumpAndSettle();
    // No demo personas: account sign-in and sign-up are the only ways in.
    expect(find.text('DEMO'), findsNothing);
    expect(find.text('Alex'), findsNothing);
    expect(find.byKey(const Key('welcome-signup')), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    store.dispose();
  });

  testWidgets('signed-in shell opens all four tabs', (tester) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(430, 932);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final store = GrouplyStore(backend: DemoBackend());
    await store.initialize();
    await store.signIn('u1', 'demo');
    await tester.pumpWidget(GrouplyApp(store: store, enableLinks: false));
    await tester.pumpAndSettle();
    expect(store.currentUserID, 'u1');
    expect(find.text('Akun server · Supabase'), findsOneWidget);
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
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpWidget(const SizedBox.shrink());
    store.dispose();
  });

  testWidgets('login sheet signs up and resets a password by emailed code', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(430, 932);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final backend = FakeBackend();
    final store = GrouplyStore(backend: backend);
    addTearDown(store.dispose);
    await store.initialize();
    await tester.pumpWidget(GrouplyApp(store: store, enableLinks: false));
    await tester.pumpAndSettle();

    Future<void> openSheet() async {
      await tester.tap(find.text('Masuk dengan Akun'));
      await tester.pumpAndSettle();
    }

    Future<void> tap(String key) async {
      await tester.ensureVisible(find.byKey(Key(key)));
      await tester.tap(find.byKey(Key(key)));
      await tester.pumpAndSettle();
    }

    bool enabled(String key) =>
        tester.widget<GLSubmitButton>(find.byKey(Key(key))).onPressed != null;

    // Sign-up waiting for confirmation returns to the sign-in form.
    backend.confirmEmail = true;
    await openSheet();
    await tap('auth-to-signup');
    expect(find.text('Buat akun'), findsOneWidget);
    expect(find.byKey(const Key('backend-name')), findsOneWidget);
    await tester.enterText(find.byKey(const Key('backend-name')), 'Ayu');
    await tester.enterText(
      find.byKey(const Key('backend-email')),
      'ayu@example.com',
    );
    await tester.enterText(find.byKey(const Key('backend-password')), 'pendek');
    await tester.pump();
    expect(enabled('backend-signUp'), isFalse, reason: 'password too short');
    await tester.enterText(
      find.byKey(const Key('backend-password')),
      'rahasia123',
    );
    await tester.pump();
    await tap('backend-signUp');
    expect(find.byKey(const Key('backend-login-notice')), findsOneWidget);
    expect(find.byKey(const Key('backend-signIn')), findsOneWidget);
    expect(store.authenticated, isFalse);

    // Forgot password: send code, wrong code shows error, right code signs in.
    await tap('auth-to-forgot');
    expect(find.byKey(const Key('backend-password')), findsNothing);
    await tap('backend-forgot');
    expect(backend.resetRequests, ['ayu@example.com']);
    await tester.enterText(find.byKey(const Key('backend-code')), '000000');
    await tester.enterText(
      find.byKey(const Key('backend-password')),
      'baru12345',
    );
    await tester.pump();
    await tap('backend-forgot-code');
    expect(
      find.descendant(
        of: find.byKey(const Key('backend-login-error')),
        matching: find.textContaining('Kode salah'),
      ),
      findsOneWidget,
    );
    await tester.enterText(find.byKey(const Key('backend-code')), '123456');
    await tester.pump();
    await tap('backend-forgot-code');
    expect(store.currentUserID, 'ayu@example.com');
    expect(find.text('Akun Grouply'), findsNothing);
  });

  testWidgets('home fits a narrow screen with enlarged text', (tester) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    tester.platformDispatcher.textScaleFactorTestValue = 1.5;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    final store = GrouplyStore(backend: DemoBackend());
    await store.initialize();
    await store.signIn('u1', 'demo');
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
    final store = GrouplyStore(backend: DemoBackend());
    await store.initialize();
    await store.signIn('u1', 'demo');
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
    expect(find.text('Akun server · Supabase'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    store.dispose();
  });
}
