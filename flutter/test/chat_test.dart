import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grouply/core/store.dart';
import 'package:grouply/features/chat_screens.dart';
import 'package:grouply/features/profile_screen.dart';
import 'package:grouply/ui/gl.dart';

class _ChatStore extends GrouplyStore {
  _ChatStore() {
    currentUserID = 'me';
    users = [
      {'id': 'me', 'name': 'Dina', 'email': 'dina@example.test'},
      {'id': 'other', 'name': 'Bima', 'email': 'bima@example.test'},
    ];
    groups = [
      {
        'id': 'group',
        'name': 'Studio',
        'memberIDs': ['me', 'other'],
      },
      {
        'id': 'private',
        'name': 'Rahasia',
        'memberIDs': ['other'],
      },
    ];
  }

  final calls = <({String action, JsonMap payload})>[];
  final reads = <String>[];
  final blocks = <String>[];
  bool failSend = false;
  bool failDelete = false;

  @override
  List<String> get readMessageIDs => reads;
  @override
  List<String> get blockedUserIDs => blocks;

  @override
  Future<JsonMap> mutate(String action, [JsonMap payload = const {}]) async {
    calls.add((action: action, payload: Map.of(payload)));
    if (action == 'sendMessage' && failSend) {
      throw const GrouplyException('Koneksi terputus');
    }
    if (action == 'deleteAccount' && failDelete) {
      throw const GrouplyException(
        'Alihkan koordinator sebelum menghapus akun.',
      );
    }
    if (action == 'blockUser') blocks.add(payload.text('id'));
    if (action == 'unblockUser') blocks.remove(payload.text('id'));
    if (action == 'updateProfile') users.first['name'] = payload.text('name');
    notifyListeners();
    return {'id': payload['clientID'] ?? payload['id'] ?? 'result'};
  }

  @override
  Future<void> markChatRead(String groupID, List<String> messageIDs) async {
    calls.add((
      action: 'markChatRead',
      payload: {'groupID': groupID, 'messageIDs': List.of(messageIDs)},
    ));
    reads.addAll(messageIDs);
    notifyListeners();
  }

  @override
  Future<void> refresh() async => notifyListeners();

  void revoke() {
    groups.first['memberIDs'] = ['other'];
    notifyListeners();
  }
}

JsonMap _message(int index, {String kind = 'text'}) => {
  'id': 'message-$index',
  'groupID': 'group',
  'taskID': null,
  'senderID': 'other',
  'text': 'pesan $index',
  'kind': kind,
  'delivery': 'sent',
  'createdAt': DateTime.utc(2026, 10, 17, 10, index).toIso8601String(),
};

Future<void> _show(WidgetTester tester, Widget child) async {
  await tester.pumpWidget(MaterialApp(theme: GLTheme.data, home: child));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('chat list filters membership, search and unread', (
    tester,
  ) async {
    final store = _ChatStore()..messages = [_message(0)];
    addTearDown(store.dispose);
    await _show(tester, ChatsScreen(store: store));
    expect(find.text('Studio'), findsOneWidget);
    expect(find.text('Rahasia'), findsNothing);
    expect(
      find.bySemanticsLabel(RegExp('1 pesan belum dibaca')),
      findsOneWidget,
    );
    expect(store.reads, isEmpty);
    await tester.enterText(find.byType(TextField), 'missing');
    await tester.pumpAndSettle();
    expect(find.text('Studio'), findsNothing);
    expect(find.text('Tidak ada grup “missing”'), findsOneWidget);
  });

  testWidgets('only viewport-observed messages become read', (tester) async {
    final store = _ChatStore()..messages = List.generate(90, _message);
    addTearDown(store.dispose);
    await _show(tester, ChatScreen(store: store, groupID: 'group'));
    expect(store.reads, contains('message-89'));
    expect(store.reads, isNot(contains('message-0')));
    expect(store.reads.length, lessThan(90));
    expect(
      store.calls
          .where((call) => call.action == 'markChatRead')
          .every((call) => call.payload.text('groupID') == 'group'),
      isTrue,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('failed send retains draft and retries with same UUID clientID', (
    tester,
  ) async {
    final store = _ChatStore()..failSend = true;
    addTearDown(store.dispose);
    await _show(tester, ChatScreen(store: store, groupID: 'group'));
    await tester.enterText(find.byType(TextField), 'Halo kelompok');
    await tester.tap(find.byTooltip('Kirim pesan'));
    await tester.pumpAndSettle();
    expect(find.text('Koneksi terputus'), findsOneWidget);
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      'Halo kelompok',
    );
    final first = store.calls
        .firstWhere((call) => call.action == 'sendMessage')
        .payload;
    expect(
      first.text('clientID'),
      matches(
        RegExp(
          r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
        ),
      ),
    );
    expect(first['taskID'], isNull);
    store.failSend = false;
    await tester.tap(find.byTooltip('Coba kirim lagi'));
    await tester.pumpAndSettle();
    final sends = store.calls
        .where((call) => call.action == 'sendMessage')
        .toList();
    expect(sends.length, 2);
    expect(sends.last.payload, first);
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      isEmpty,
    );
  });

  testWidgets('membership revocation hides history and composer', (
    tester,
  ) async {
    final store = _ChatStore()..messages = [_message(0)];
    addTearDown(store.dispose);
    await _show(tester, ChatScreen(store: store, groupID: 'group'));
    store.revoke();
    await tester.pumpAndSettle();
    expect(find.text('Kamu tidak punya akses'), findsOneWidget);
    expect(find.text('pesan 0'), findsNothing);
    expect(find.byType(TextField), findsNothing);
  });

  testWidgets('report requires a nonblank reason and sends Swift payload', (
    tester,
  ) async {
    final store = _ChatStore()..messages = [_message(0)];
    addTearDown(store.dispose);
    await _show(tester, ChatScreen(store: store, groupID: 'group'));
    await tester.longPress(find.text('pesan 0'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Laporkan pesan'));
    await tester.pumpAndSettle();
    bool reported() =>
        store.calls.any((call) => call.action == 'reportMessage');
    // No reason chosen: rejected locally.
    await tester.tap(find.text('Kirim laporan'));
    await tester.pumpAndSettle();
    expect(find.text('Pilih alasan laporan.'), findsOneWidget);
    expect(reported(), isFalse);
    // "Lainnya" with blank details: still rejected.
    await tester.tap(find.text('Lainnya'));
    await tester.enterText(find.byType(TextField).last, '   ');
    await tester.tap(find.text('Kirim laporan'));
    await tester.pumpAndSettle();
    expect(find.text('Ceritakan singkat alasannya.'), findsOneWidget);
    expect(reported(), isFalse);
    await tester.enterText(find.byType(TextField).last, '  Spam berulang  ');
    await tester.tap(find.text('Kirim laporan'));
    await tester.pumpAndSettle();
    expect(
      store.calls.firstWhere((call) => call.action == 'reportMessage').payload,
      {'id': 'message-0', 'reason': 'Lainnya — Spam berulang'},
    );
    expect(find.text('Laporan tersimpan'), findsOneWidget);
  });

  testWidgets('blocking needs confirmation and hides message contents', (
    tester,
  ) async {
    final store = _ChatStore()..messages = [_message(0)];
    addTearDown(store.dispose);
    await _show(tester, ChatScreen(store: store, groupID: 'group'));
    Future<void> openBlock() async {
      await tester.longPress(find.text('pesan 0'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Blokir Bima'));
      await tester.pumpAndSettle();
      expect(find.text('Blokir Bima?'), findsOneWidget);
    }

    await openBlock();
    await tester.tap(find.text('Batal'));
    await tester.pumpAndSettle();
    expect(store.blocks, isEmpty);
    expect(store.calls.any((call) => call.action == 'blockUser'), isFalse);
    expect(find.text('pesan 0'), findsOneWidget);
    await openBlock();
    expect(store.blocks, isEmpty);
    await tester.tap(find.text('Blokir'));
    await tester.pumpAndSettle();
    expect(
      store.calls.firstWhere((call) => call.action == 'blockUser').payload,
      {'id': 'other'},
    );
    expect(find.text('pesan 0'), findsNothing);
    expect(
      find.textContaining('Pesan dari pengguna yang kamu blokir'),
      findsOneWidget,
    );
    await tester.pump(const Duration(seconds: 3));
  });

  testWidgets('profile shows current identity and truthful push status', (
    tester,
  ) async {
    final store = _ChatStore();
    addTearDown(store.dispose);
    await _show(tester, ProfileScreen(store: store));
    expect(find.text('Dina'), findsOneWidget);
    expect(find.text('dina@example.test'), findsOneWidget);
    // Permission is off by default; nothing claims push is active.
    expect(find.text('Izin belum aktif'), findsOneWidget);
    expect(find.text('Izin aktif'), findsNothing);
    await tester.tap(find.text('Notifikasi'));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Push notification belum tersedia'),
      findsOneWidget,
    );
    expect(find.textContaining('simulasi lokal'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('inactive chat does not mark messages read', (tester) async {
    final store = _ChatStore()..messages = [_message(0)];
    addTearDown(store.dispose);
    await _show(
      tester,
      TickerMode(
        enabled: false,
        child: ChatScreen(store: store, groupID: 'group'),
      ),
    );
    expect(store.reads, isEmpty);
  });

  testWidgets('profile edits use the canonical name payload', (tester) async {
    final store = _ChatStore();
    addTearDown(store.dispose);
    await _show(tester, ProfileScreen(store: store));
    await tester.tap(find.text('Edit'));
    await tester.pumpAndSettle();
    expect(find.text('Edit profil'), findsOneWidget);
    await tester.enterText(find.byType(TextField), '  Dina Baru  ');
    await tester.tap(find.text('Simpan'));
    await tester.pumpAndSettle();
    expect(store.calls.single.action, 'updateProfile');
    expect(store.calls.single.payload, {'name': 'Dina Baru'});
    expect(find.text('Dina Baru'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pump(const Duration(seconds: 3));
  });

  testWidgets('profile unblocks users with the canonical id payload', (
    tester,
  ) async {
    final store = _ChatStore()..blocks.add('other');
    addTearDown(store.dispose);
    await _show(tester, ProfileScreen(store: store));
    expect(find.text('1 pengguna'), findsOneWidget);
    await tester.tap(find.text('Pengguna diblokir'));
    await tester.pumpAndSettle();
    expect(find.text('Bima'), findsOneWidget);
    await tester.tap(find.text('Buka blokir'));
    await tester.pumpAndSettle();
    expect(store.calls.single.action, 'unblockUser');
    expect(store.calls.single.payload, {'id': 'other'});
    expect(store.blocks, isEmpty);
    expect(find.text('Belum ada yang kamu blokir'), findsOneWidget);
    await tester.pump(const Duration(seconds: 3));
  });

  testWidgets(
    'account deletion requires confirmation and preserves rejection',
    (tester) async {
      final store = _ChatStore()..failDelete = true;
      addTearDown(store.dispose);
      await _show(tester, ProfileScreen(store: store));
      final confirm = find.byKey(const ValueKey('confirm-delete-account'));
      await tester.ensureVisible(find.byKey(const ValueKey('delete-account')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('delete-account')));
      await tester.pumpAndSettle();
      expect(confirm, findsNothing);
      await tester.tap(find.text('Lanjutkan'));
      await tester.pumpAndSettle();
      await tester.tap(confirm);
      await tester.pumpAndSettle();
      expect(store.calls, isEmpty);
      expect(
        find.widgetWithText(GLFormError, 'Ketik HAPUS untuk konfirmasi.'),
        findsOneWidget,
      );
      await tester.enterText(find.byType(TextField), 'HAPUS');
      await tester.tap(confirm);
      await tester.pumpAndSettle();
      expect(store.calls.single.action, 'deleteAccount');
      expect(store.calls.single.payload, isEmpty);
      expect(store.currentUserID, 'me');
      expect(find.textContaining('Alihkan koordinator'), findsWidgets);
      expect(tester.takeException(), isNull);
    },
  );
}
