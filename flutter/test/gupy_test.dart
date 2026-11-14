import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grouply/app.dart';
import 'package:grouply/core/store.dart';
import 'package:grouply/features/workspace_screens.dart';
import 'package:grouply/ui/gupy.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'core_test.dart' show FakeBackend, cloudSnapshot;

/// pumpAndSettle never settles while the idle Gupy breathes; pump a while.
Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 12; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<(GrouplyStore, FakeBackend)> openWelcome(WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(402, 874);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final backend = FakeBackend();
    final store = GrouplyStore(backend: backend);
    addTearDown(store.dispose);
    await store.initialize();
    await tester.pumpWidget(GrouplyApp(store: store, enableLinks: false));
    await tester.pump(const Duration(seconds: 2));
    return (store, backend);
  }

  testWidgets('welcome is one screen: Gupy, the invite path, Masuk/Daftar', (
    tester,
  ) async {
    await openWelcome(tester);
    expect(find.byType(GupyRig), findsOneWidget);
    expect(find.text('Punya kode undangan?'), findsOneWidget);
    expect(find.text('Masuk dengan Akun'), findsOneWidget);
    expect(find.byKey(const Key('welcome-signup')), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('an invite code entered on Welcome is joined after sign-up', (
    tester,
  ) async {
    final (store, backend) = await openWelcome(tester);
    var joined = false;
    final codes = <Object?>[];
    backend.write = (action, payload) async {
      expect(action, 'joinGroup');
      codes.add(payload['code']);
      joined = true;
      return {'id': 'g1'};
    };
    backend.read = () async => {
      ...cloudSnapshot(backend.actor!),
      'groups': [
        if (joined)
          {
            'id': 'g1',
            'name': 'Kelompok 3',
            'description': '',
            'course': 'Basis Data',
            'memberIDs': [backend.actor, 'u2'],
            'coordinatorID': 'u2',
            'tint': '#D8EAF4',
            'icon': 'person.3',
          },
      ],
    };

    await tester.tap(find.byKey(const Key('welcome-invite')));
    await settle(tester);
    await tester.ensureVisible(find.byKey(const Key('invite-continue')));
    await tester.tap(find.byKey(const Key('invite-continue')));
    await settle(tester);
    expect(find.text('Isi kode undangan.'), findsOneWidget);
    // A pasted link is trimmed to its code.
    await tester.enterText(
      find.byKey(const Key('invite-code')),
      'https://grouply.app/invite/ABC123',
    );
    await tester.ensureVisible(find.byKey(const Key('invite-continue')));
    await tester.tap(find.byKey(const Key('invite-continue')));
    await settle(tester);
    // The sign-up form opens right away.
    expect(find.byKey(const Key('backend-signUp')), findsOneWidget);
    await tester.enterText(find.byKey(const Key('backend-name')), 'Ayu');
    await tester.enterText(
      find.byKey(const Key('backend-email')),
      'ayu@example.com',
    );
    await tester.enterText(
      find.byKey(const Key('backend-password')),
      'rahasia123',
    );
    await tester.pump();
    await tester.ensureVisible(find.byKey(const Key('backend-signUp')));
    await tester.tap(find.byKey(const Key('backend-signUp')));
    await settle(tester);
    await settle(tester);
    expect(store.authenticated, isTrue);
    expect(codes, ['ABC123']);
    expect(find.byType(GroupScreen), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('a saved invite code can be cleared before signing in', (
    tester,
  ) async {
    await openWelcome(tester);
    await tester.tap(find.byKey(const Key('welcome-invite')));
    await settle(tester);
    await tester.enterText(find.byKey(const Key('invite-code')), 'ABC123');
    await tester.ensureVisible(find.byKey(const Key('invite-continue')));
    await tester.tap(find.byKey(const Key('invite-continue')));
    await settle(tester);
    // Close the account sheet without signing in.
    await tester.tapAt(const Offset(200, 20));
    await settle(tester);
    expect(find.text('Kode undangan siap dipakai'), findsOneWidget);
    await tester.tap(find.byKey(const Key('welcome-invite-clear')));
    await settle(tester);
    expect(find.text('Punya kode undangan?'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('a Gupy hint shows once; Mengerti remembers it', (tester) async {
    SharedPreferences.setMockInitialValues({});
    Widget hint() => MaterialApp(
      home: Scaffold(
        body: ListView(
          children: const [GupyHint(id: 'demo', title: 'Judul', text: 'Isi')],
        ),
      ),
    );
    await tester.pumpWidget(hint());
    await tester.pumpAndSettle();
    expect(find.byType(GupyPeek), findsOneWidget);
    await tester.tap(find.byKey(const Key('hint-demo-ok')));
    await tester.pumpAndSettle();
    expect(find.text('Judul'), findsNothing);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool(GupyHint.prefKey('demo')), isTrue);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpWidget(hint());
    await tester.pumpAndSettle();
    expect(find.text('Judul'), findsNothing);
  });

  testWidgets('reduced motion: invite and peeking Gupy stand still', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(disableAnimations: true),
          child: child!,
        ),
        home: const Column(
          children: [
            GupyPose(pose: 'undangan', size: 120),
            GupyPeek(width: 120),
          ],
        ),
      ),
    );
    await tester.pump();
    expect(tester.binding.hasScheduledFrame, isFalse);
  });

  test('motion curves pass through their keys and land', () {
    const keys = [(0.0, 0.0), (0.5, 10.0), (1.0, 0.0)];
    expect(spline(keys, 0.5), 10);
    expect(spline(keys, 0), 0);
    expect(spline(keys, 2), 0);
    expect(GupyJump.lift(0), 0);
    expect(GupyJump.lift((0.17 + 0.64) / 2), closeTo(1, 1e-9)); // apex
    expect(GupyJump.lift(0.7), 0); // landed
  });

  testWidgets('empty-state Gupy waves once, then stands still', (tester) async {
    await tester.pumpWidget(
      const Directionality(
        textDirection: TextDirection.ltr,
        child: Center(
          child: GupyRig(size: 140, idle: false, waveOnStart: true),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 500));
    expect(tester.binding.hasScheduledFrame, isTrue); // waving
    await tester.pumpAndSettle(); // ends: no idle loop left running
    await tester.tap(find.byType(GupyRig));
    await tester.pump(const Duration(milliseconds: 100));
    expect(tester.binding.hasScheduledFrame, isTrue); // a tap waves again
    await tester.pumpAndSettle();
  });
}
