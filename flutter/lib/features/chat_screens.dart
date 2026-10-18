// 1:1 port of Grouply/Features/ChatViews.swift (Chat tab + group chat detail).
import 'dart:math';
import 'dart:ui' show PathMetric;

import 'package:flutter/cupertino.dart' show CupertinoActivityIndicator;
import 'package:flutter/gestures.dart' show TapGestureRecognizer;
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart' show CustomSemanticsAction;
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/store.dart';
import '../ui/gl.dart';
import 'workspace_screens.dart';

final _chip = GLTheme.chip;
final _dash = GLTheme.placeholder;

List<JsonMap> _thread(GrouplyStore store, String groupID) {
  final rows = store.messages
      .where(
        (message) =>
            message.text('groupID') == groupID &&
            message.text('taskID').isEmpty,
      )
      .toList();
  rows.sort((first, second) {
    final order = (first.date('createdAt') ?? DateTime(1970)).compareTo(
      second.date('createdAt') ?? DateTime(1970),
    );
    return order == 0 ? first.text('id').compareTo(second.text('id')) : order;
  });
  return rows;
}

bool _sent(JsonMap message) =>
    message.text('delivery').isEmpty || message.text('delivery') == 'sent';

DateTime _at(JsonMap message) =>
    message.date('createdAt') ?? DateTime.fromMillisecondsSinceEpoch(0);

/// `store.displayName`.
String _displayName(GrouplyStore store, String id) {
  if (id.isEmpty) return 'Pengguna terhapus';
  return id == store.currentUserID
      ? 'Kamu'
      : store.user(id)?.text('name') ?? 'Anggota';
}

/// `ChatFormat.day`: "Hari ini", "Kemarin", otherwise "Rab, 14 Okt".
String _day(DateTime value) {
  final a = value.toLocal(), b = DateTime.now();
  final n =
      (DateTime(
                a.year,
                a.month,
                a.day,
              ).difference(DateTime(b.year, b.month, b.day)).inHours /
              24)
          .round();
  if (n == 0) return 'Hari ini';
  if (n == -1) return 'Kemarin';
  return '${GLFormat.weekday(value)}, ${GLFormat.date(value)}';
}

/// Prototype `preview(gid)`.
String _preview(GrouplyStore store, JsonMap? m) {
  if (m == null) return 'Belum ada pesan. Sapa kelompokmu!';
  final senderID = m.text('senderID');
  final name = senderID == store.currentUserID
      ? 'Kamu'
      : store.user(senderID)?.text('name') ?? 'Anggota';
  var text = switch (m.text('kind')) {
    'activity' =>
      '$name ${m.text('text')} ${store.task(m.text('targetTaskID'))?.text('title') ?? ''}',
    'system' => '$name ${m.text('text')}',
    _ =>
      store.blockedUserIDs.contains(senderID) && senderID != store.currentUserID
          ? 'Pesan dari pengguna yang kamu blokir'
          : '$name: ${m.text('text')}',
  };
  if (m.text('delivery') == 'failed') text = 'Gagal terkirim · $text';
  return text;
}

/// `ActivityStyle`.
(String, Color) _activityStyle(String verb) => switch (verb) {
  _ when verb.startsWith('mengirim') => (
    'square.and.arrow.up',
    GLTheme.lavender,
  ),
  _ when verb.startsWith('menyetujui') => ('checkmark.circle', GLTheme.mint),
  _ when verb.startsWith('meminta') => ('arrow.uturn.backward', GLTheme.coral),
  _ when verb.startsWith('membuat') => ('checklist', GLTheme.sky),
  _ when verb.startsWith('mengalihkan') => (
    'arrow.left.arrow.right',
    GLTheme.sky,
  ),
  _ => ('pencil', GLTheme.butter),
};

/// Continuous rounded rect with per-corner radii (`UnevenRoundedRectangle`).
ShapeBorder _uneven(double tl, double tr, double bl, double br) =>
    RoundedSuperellipseBorder(
      borderRadius: BorderRadius.only(
        topLeft: Radius.circular(tl),
        topRight: Radius.circular(tr),
        bottomLeft: Radius.circular(bl),
        bottomRight: Radius.circular(br),
      ),
    );

/// `StrokeStyle(lineWidth: 1.5, dash: [4, 3])` along a shape.
class _DashedBorder extends CustomPainter {
  _DashedBorder(this.shape);
  final ShapeBorder shape;
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = _dash
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    final path = shape.getOuterPath((Offset.zero & size).deflate(0.75));
    for (final PathMetric metric in path.computeMetrics()) {
      for (double d = 0; d < metric.length; d += 7) {
        canvas.drawPath(
          metric.extractPath(d, min(d + 4, metric.length)),
          paint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(_DashedBorder old) => old.shape != shape;
}

/// Press state for SwiftUI ButtonStyles (`GLChatRowStyle`, `ChatPressStyle`).
class _Press extends StatefulWidget {
  const _Press({required this.builder, required this.onTap, this.label});
  final Widget Function(bool pressed) builder;
  final VoidCallback? onTap;
  final String? label;
  @override
  State<_Press> createState() => _PressState();
}

class _PressState extends State<_Press> {
  bool _down = false;
  void _set(bool value) {
    if (widget.onTap != null && value != _down) setState(() => _down = value);
  }

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    enabled: widget.onTap != null,
    label: widget.label,
    child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: widget.onTap,
      onTapDown: (_) => _set(true),
      onTapUp: (_) => _set(false),
      onTapCancel: () => _set(false),
      child: widget.builder(_down),
    ),
  );
}

// MARK: - Chat tab (`ChatsView`)

class ChatsScreen extends StatefulWidget {
  const ChatsScreen({super.key, required this.store});
  final GrouplyStore store;

  @override
  State<ChatsScreen> createState() => _ChatsScreenState();
}

class _ChatsScreenState extends State<ChatsScreen> {
  final _search = TextEditingController();
  String _query = '';
  String? _error;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    try {
      await widget.store.refresh();
      if (mounted) setState(() => _error = null);
    } catch (failure) {
      if (mounted) setState(() => _error = failure.toString());
    }
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.store,
    builder: (context, _) {
      final store = widget.store;
      final mine = store.groups
          .where(
            (group) => group.ids('memberIDs').contains(store.currentUserID),
          )
          .toList();
      final q = _query.trim().toLowerCase();
      final groups = mine
          .where(
            (group) =>
                q.isEmpty || group.text('name').toLowerCase().contains(q),
          )
          .toList();
      final insets = MediaQuery.paddingOf(context);
      return Scaffold(
        backgroundColor: GLTheme.background,
        body: RefreshIndicator.adaptive(
          onRefresh: _refresh,
          child: ListView(
            physics: AlwaysScrollableScrollPhysics(
              parent: BouncingScrollPhysics(),
            ),
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            padding: EdgeInsets.fromLTRB(
              20,
              insets.top + 10,
              20,
              insets.bottom + 20,
            ),
            children: [
              Text('Chat', style: gl(34, w700, -0.03)),
              SizedBox(height: 4),
              Text(
                'Satu ruang obrolan untuk tiap grup',
                style: gl(15, w400, 0, GLTheme.secondary),
              ),
              if (_error ?? store.error case final error?) ...[
                SizedBox(height: 16),
                GLFormError(error),
              ],
              if (mine.isNotEmpty) ...[SizedBox(height: 16), _searchField()],
              SizedBox(height: 16),
              ClipPath(
                clipper: ShapeBorderClipper(shape: glShape(28)),
                child: Container(
                  decoration: glBox(GLTheme.surface, 28, shadow: true),
                  child: Column(
                    children: [
                      for (final group in groups) _row(group),
                      if (mine.isEmpty)
                        _emptyChats()
                      else if (groups.isEmpty)
                        _noMatch(),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    },
  );

  Widget _searchField() => Container(
    height: 48,
    padding: EdgeInsets.only(left: 14, right: 4),
    decoration: glBox(GLTheme.surface, 16, border: GLTheme.border),
    child: Row(
      children: [
        GLIcon('magnifyingglass', size: 20, color: GLTheme.secondary),
        SizedBox(width: 8),
        Expanded(
          child: Semantics(
            label: 'Cari nama grup',
            textField: true,
            child: TextField(
              controller: _search,
              autocorrect: false,
              cursorColor: GLTheme.ink,
              style: gl(16, w400, 0, GLTheme.ink),
              decoration: InputDecoration.collapsed(
                hintText: 'Cari nama grup',
                hintStyle: gl(16, w400, 0, GLTheme.placeholder),
              ),
              onChanged: (value) => setState(() => _query = value),
            ),
          ),
        ),
        if (_query.isNotEmpty) ...[
          SizedBox(width: 8),
          GLTap(
            label: 'Hapus pencarian',
            onTap: () => setState(() {
              _search.clear();
              _query = '';
            }),
            child: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: GLTheme.muted,
                shape: BoxShape.circle,
              ),
              child: GLIcon('xmark', size: 18, color: GLTheme.ink),
            ),
          ),
        ],
      ],
    ),
  );

  Widget _row(JsonMap group) {
    final store = widget.store;
    final messages = _thread(store, group.text('id'));
    final unread = messages
        .where(
          (message) =>
              message.text('senderID') != store.currentUserID &&
              _sent(message) &&
              !store.readMessageIDs.contains(message.text('id')),
        )
        .length;
    final last = messages.lastOrNull;
    final bold = unread > 0;
    return _Press(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => ChatScreen(store: store, groupID: group.text('id')),
        ),
      ),
      builder: (pressed) => Container(
        color: pressed ? GLTheme.muted : Colors.transparent,
        padding: EdgeInsets.symmetric(vertical: 14, horizontal: 16),
        foregroundDecoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: GLTheme.border)),
        ),
        child: Row(
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: glBox(
                glTint(group.text('tint'), GLTheme.surface),
                20,
              ),
              child: GLIcon(
                group.text('icon').isEmpty ? 'person.3' : group.text('icon'),
                size: 26,
                color: GLTheme.ink,
              ),
            ),
            SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      Expanded(
                        child: Text(
                          group.text('name'),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: gl(16, bold ? w700 : w600),
                        ),
                      ),
                      if (last != null) ...[
                        SizedBox(width: 8),
                        Text(
                          GLFormat.chatStamp(_at(last), DateTime.now()),
                          style: gl(
                            13,
                            bold ? w700 : w400,
                            0,
                            bold ? GLTheme.ink : GLTheme.secondary,
                          ),
                        ),
                      ],
                    ],
                  ),
                  SizedBox(height: 3),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          _preview(store, last),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: gl(
                            14,
                            bold ? w500 : w400,
                            0,
                            bold ? GLTheme.ink : GLTheme.secondary,
                            2,
                          ),
                        ),
                      ),
                      if (bold) ...[
                        SizedBox(width: 8),
                        Semantics(
                          label: '$unread pesan belum dibaca',
                          child: ExcludeSemantics(
                            child: Container(
                              constraints: BoxConstraints(
                                minWidth: 24,
                                minHeight: 24,
                              ),
                              padding: EdgeInsets.symmetric(horizontal: 7),
                              alignment: Alignment.center,
                              decoration: ShapeDecoration(
                                color: GLTheme.ink,
                                shape: StadiumBorder(),
                              ),
                              child: Text(
                                '$unread',
                                style: gl(12, w700, 0, GLTheme.onInk),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _emptyChats() => Padding(
    padding: EdgeInsets.symmetric(vertical: 30, horizontal: 22),
    child: Column(
      children: [
        Container(
          width: 56,
          height: 56,
          decoration: glBox(GLTheme.lavender, 20),
          child: GLIcon(
            'bubble.left.and.bubble.right',
            size: 28,
            color: GLTheme.ink,
          ),
        ),
        SizedBox(height: 10),
        Text(
          'Belum ada chat',
          textAlign: TextAlign.center,
          style: gl(19, w700),
        ),
        SizedBox(height: 10),
        Text(
          'Chat grup dibuat otomatis saat kamu membuat atau bergabung ke grup.',
          textAlign: TextAlign.center,
          style: gl(15, w400, 0, GLTheme.secondary, 4),
        ),
      ],
    ),
  );

  Widget _noMatch() => Container(
    width: double.infinity,
    padding: EdgeInsets.symmetric(vertical: 28, horizontal: 20),
    child: Column(
      children: [
        GLIcon('magnifyingglass', size: 30, color: GLTheme.secondary),
        SizedBox(height: 6),
        Text(
          'Tidak ada grup “$_query”',
          textAlign: TextAlign.center,
          style: gl(16, w600),
        ),
        SizedBox(height: 6),
        Text(
          'Coba kata kunci lain.',
          textAlign: TextAlign.center,
          style: gl(14, w400, 0, GLTheme.secondary),
        ),
      ],
    ),
  );
}

// MARK: - Group chat screen (`ChatDetailView` + `ChatThread` + `ChatComposer`)

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key, required this.store, required this.groupID});
  final GrouplyStore store;
  final String groupID;

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> with WidgetsBindingObserver {
  final _draft = TextEditingController();
  final _viewport = GlobalKey();
  final _rows = <String, GlobalKey>{};
  final _attemptedReads = <String>{};
  final _revealed = <String>{};
  late String _actor;
  late String _blocked;
  String? _clientID, _error, _readError;
  bool _busy = false, _reading = false, _scheduled = false;
  bool get _canAccess =>
      widget.store.authenticated &&
      (widget.store
              .group(widget.groupID)
              ?.ids('memberIDs')
              .contains(widget.store.currentUserID) ??
          false);

  @override
  void initState() {
    super.initState();
    _actor = widget.store.currentUserID;
    _blocked = widget.store.blockedUserIDs.join(',');
    widget.store.addListener(_changed);
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didUpdateWidget(ChatScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.store != widget.store) {
      oldWidget.store.removeListener(_changed);
      widget.store.addListener(_changed);
    }
    if (oldWidget.store != widget.store ||
        oldWidget.groupID != widget.groupID) {
      _reset();
    }
  }

  void _reset() {
    _actor = widget.store.currentUserID;
    _draft.clear();
    _clientID = null;
    _error = null;
    _readError = null;
    _attemptedReads.clear();
    _revealed.clear();
    _rows.clear();
  }

  void _changed() {
    if (!mounted) return;
    if (_actor != widget.store.currentUserID || !_canAccess) _reset();
    final blocked = widget.store.blockedUserIDs.join(',');
    if (blocked != _blocked) {
      _blocked = blocked;
      _revealed.clear();
    }
    setState(() {});
  }

  @override
  void dispose() {
    widget.store.removeListener(_changed);
    WidgetsBinding.instance.removeObserver(this);
    _draft.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _scheduleRead();
  }

  void _scheduleRead() {
    if (_scheduled) return;
    _scheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scheduled = false;
      if (mounted) _markVisibleRead();
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  Future<void> _markVisibleRead() async {
    if (!_canAccess ||
        _busy ||
        _reading ||
        widget.store.loading ||
        ModalRoute.of(context)?.isCurrent != true ||
        !TickerMode.valuesOf(context).enabled ||
        (WidgetsBinding.instance.lifecycleState != null &&
            WidgetsBinding.instance.lifecycleState !=
                AppLifecycleState.resumed)) {
      return;
    }
    final viewport = _viewport.currentContext?.findRenderObject();
    if (viewport is! RenderBox || !viewport.attached || !viewport.hasSize) {
      return;
    }
    final visible = viewport.localToGlobal(Offset.zero) & viewport.size;
    final messageIDs = <String>[];
    for (final message in _thread(widget.store, widget.groupID)) {
      final id = message.text('id');
      if (id.isEmpty ||
          !_sent(message) ||
          _attemptedReads.contains(id) ||
          widget.store.readMessageIDs.contains(id)) {
        continue;
      }
      final row = _rows[id]?.currentContext?.findRenderObject();
      if (row is RenderBox &&
          row.attached &&
          row.hasSize &&
          visible.overlaps(row.localToGlobal(Offset.zero) & row.size)) {
        messageIDs.add(id);
      }
    }
    if (messageIDs.isEmpty) return;
    _attemptedReads.addAll(messageIDs);
    _reading = true;
    final actor = widget.store.currentUserID;
    try {
      await widget.store.markChatRead(widget.groupID, messageIDs);
    } catch (failure) {
      if (mounted && actor == widget.store.currentUserID) {
        setState(() => _readError = 'Status baca belum tersimpan: $failure');
      }
    } finally {
      _reading = false;
      if (mounted) _scheduleRead();
    }
  }

  String _uuid() {
    final random = Random.secure();
    final bytes = List.generate(16, (_) => random.nextInt(256));
    bytes[6] = (bytes[6] & 15) | 64;
    bytes[8] = (bytes[8] & 63) | 128;
    final hex = bytes
        .map((value) => value.toRadixString(16).padLeft(2, '0'))
        .join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
  }

  Future<void> _send([JsonMap? failedMessage]) async {
    if (!_canAccess || _busy || _reading || widget.store.loading) return;
    final text = failedMessage?.text('text') ?? _draft.text.trim();
    if (text.isEmpty) return;
    final actor = widget.store.currentUserID;
    final clientID = failedMessage?.text('id') ?? (_clientID ??= _uuid());
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.store.mutate('sendMessage', {
        'groupID': widget.groupID,
        'taskID': null,
        'text': text,
        'clientID': clientID,
      });
      if (widget.store.messages.any(
        (message) =>
            message.text('id') == clientID &&
            message.text('delivery') == 'failed',
      )) {
        throw GrouplyException(
          'Pesan gagal terkirim. Draf disimpan; coba kirim lagi.',
        );
      }
      if (mounted &&
          actor == widget.store.currentUserID &&
          failedMessage == null) {
        _draft.clear();
        _clientID = null;
      }
    } catch (failure) {
      if (mounted && actor == widget.store.currentUserID) {
        setState(() => _error = failure.toString());
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
        _scheduleRead();
      }
    }
  }

  Future<void> _refresh() async {
    try {
      await widget.store.refresh();
      if (mounted) {
        setState(() {
          _error = null;
          _readError = null;
          _attemptedReads.clear();
        });
        _scheduleRead();
      }
    } catch (failure) {
      if (mounted) setState(() => _error = failure.toString());
    }
  }

  /// Runs a moderation mutation for the current actor; errors flash a toast.
  Future<bool> _moderate(String action, JsonMap payload) async {
    final actor = widget.store.currentUserID;
    if (!_canAccess || _busy) return false;
    setState(() => _busy = true);
    try {
      await widget.store.mutate(action, payload);
      return mounted && actor == widget.store.currentUserID;
    } catch (failure) {
      if (mounted && actor == widget.store.currentUserID) {
        showGLToast(context, failure.toString(), kind: GLToastKind.err);
      }
      return false;
    } finally {
      if (mounted) {
        setState(() => _busy = false);
        _scheduleRead();
      }
    }
  }

  /// `ChatThread.handle(_:messageID:)`.
  Future<void> _options(JsonMap message) async {
    final store = widget.store;
    final action = await _showChatSheet<String>(
      context,
      (_) => _MessageSheet(store: store, message: message),
    );
    if (!mounted || action == null || !_canAccess) return _scheduleRead();
    final id = message.text('id'), who = message.text('senderID');
    final name = store.user(who)?.text('name') ?? 'Anggota';
    switch (action) {
      case 'copy':
        await Clipboard.setData(ClipboardData(text: message.text('text')));
        if (mounted) showGLToast(context, 'Teks disalin');
      case 'retry':
        await _send(message);
      case 'report':
        if (who == store.currentUserID) return;
        if (store.reports.any(
          (r) =>
              r.text('messageID') == id &&
              r.text('reporterID') == store.currentUserID,
        )) {
          showGLToast(
            context,
            'Kamu sudah melaporkan pesan ini.',
            kind: GLToastKind.err,
          );
          return;
        }
        await _showChatSheet<void>(
          context,
          (_) => _ModerationDialog(
            cloud: !store.demoMode,
            onSubmit: (reason) async {
              final actor = store.currentUserID;
              if (!_canAccess) throw GrouplyException('Akses ditolak.');
              await store.mutate('reportMessage', {'id': id, 'reason': reason});
              if (actor != store.currentUserID) {
                throw GrouplyException('Sesi berubah.');
              }
            },
          ),
        );
        _scheduleRead();
      case 'block':
        if (who.isEmpty || who == store.currentUserID) return;
        if (store.blockedUserIDs.contains(who)) {
          if (await _moderate('unblockUser', {'id': who}) && mounted) {
            showGLToast(
              context,
              '$name tidak lagi diblokir',
              kind: GLToastKind.info,
            );
          }
          return;
        }
        final ok = await showGLConfirm(
          context,
          title: 'Blokir $name?',
          text:
              'Pesan $name di chat dan diskusi akan disembunyikan untukmu. $name tetap anggota grup, tugas bersama tetap berjalan, dan $name tidak diberi tahu.',
          ok: 'Blokir',
          destructive: true,
        );
        if (!ok || !mounted) return _scheduleRead();
        if (await _moderate('blockUser', {'id': who}) && mounted) {
          showGLToast(context, '$name diblokir', kind: GLToastKind.info);
        }
    }
  }

  // MARK: Rows

  Widget _daySeparator(String label) => Padding(
    padding: EdgeInsets.only(top: 14, bottom: 6),
    child: Center(
      child: Semantics(
        header: true,
        child: Container(
          height: 26,
          padding: EdgeInsets.symmetric(horizontal: 12),
          alignment: Alignment.center,
          decoration: ShapeDecoration(color: _chip, shape: StadiumBorder()),
          child: Text(label, style: gl(12, w600, 0, GLTheme.text2)),
        ),
      ),
    ),
  );

  /// Two consecutive text messages from the same sender on the same day group together.
  bool _chains(JsonMap a, JsonMap b) =>
      a.text('kind') == 'text' &&
      b.text('kind') == 'text' &&
      a.text('senderID') == b.text('senderID') &&
      _day(_at(a)) == _day(_at(b));

  Widget _row(JsonMap m, JsonMap? prev, JsonMap? next, double width) {
    final key = _rows.putIfAbsent(m.text('id'), GlobalKey.new);
    final child = switch (m.text('kind')) {
      'system' => _systemRow(m, width),
      'activity' => _activityRow(m),
      _ =>
        m.text('senderID') == widget.store.currentUserID
            ? _mine(
                m,
                prev != null && _chains(prev, m),
                next != null && _chains(m, next),
                width,
              )
            : _other(
                m,
                prev != null && _chains(prev, m),
                next != null && _chains(m, next),
                width,
              ),
    };
    return KeyedSubtree(key: key, child: child);
  }

  Widget _systemRow(JsonMap m, double width) => Padding(
    padding: EdgeInsets.symmetric(vertical: 8),
    child: Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: width * 0.92),
        child: MergeSemantics(
          child: Container(
            padding: EdgeInsets.symmetric(vertical: 6, horizontal: 12),
            decoration: glBox(_chip, 14),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                GLIcon('bolt', size: 16, color: GLTheme.text3),
                SizedBox(width: 6),
                Flexible(
                  child: Text(
                    '${_displayName(widget.store, m.text('senderID'))} ${m.text('text')} · ${GLFormat.time(_at(m))}',
                    textAlign: TextAlign.center,
                    style: gl(13, w500, 0, GLTheme.text3),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );

  Widget _activityRow(JsonMap m) {
    final store = widget.store;
    final (icon, tint) = _activityStyle(m.text('text'));
    final targetID = m.text('targetTaskID');
    final task = store.task(targetID);
    final canOpen =
        task != null &&
        store.project(task.text('projectID'))?.text('groupID') ==
            widget.groupID;
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 10, horizontal: 6),
      child: Container(
        padding: EdgeInsets.fromLTRB(14, 12, 12, 12),
        decoration: glBox(GLTheme.surface, 20, border: GLTheme.border),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: glBox(tint, 14),
              child: GLIcon(icon, size: 20, color: GLTheme.ink),
            ),
            SizedBox(width: 12),
            Expanded(
              child: MergeSemantics(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${_displayName(store, m.text('senderID'))} ${m.text('text')} · ${GLFormat.activityStamp(_at(m), DateTime.now())}',
                      style: gl(13, w400, 0, GLTheme.text2),
                    ),
                    SizedBox(height: 1),
                    Text(
                      task?.text('title') ?? 'Tugas tidak tersedia',
                      style: gl(15, w600, 0, null, 1),
                    ),
                  ],
                ),
              ),
            ),
            SizedBox(width: 12),
            GLTap(
              onTap: !canOpen
                  ? null
                  : () async {
                      await Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) =>
                              TaskScreen(store: store, taskID: targetID),
                        ),
                      );
                      if (mounted) _scheduleRead();
                    },
              child: Opacity(
                opacity: canOpen ? 1 : 0.4,
                child: Container(
                  height: 44,
                  padding: EdgeInsets.symmetric(horizontal: 14),
                  alignment: Alignment.center,
                  decoration: ShapeDecoration(
                    shape: StadiumBorder(
                      side: BorderSide(color: GLTheme.ink, width: 1.5),
                    ),
                  ),
                  child: Text('Lihat tugas', style: gl(13, w600)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _other(JsonMap m, bool samePrev, bool sameNext, double width) {
    final store = widget.store;
    final shapeFixed = _uneven(samePrev ? 6 : 18, 18, sameNext ? 6 : 18, 18);
    final hidden =
        store.blockedUserIDs.contains(m.text('senderID')) &&
        !_revealed.contains(m.text('id'));
    final name = _displayName(store, m.text('senderID'));
    return Padding(
      padding: EdgeInsets.only(top: samePrev ? 2 : 10),
      child: Align(
        alignment: Alignment.centerLeft,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: width * 0.84),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              if (sameNext)
                SizedBox(width: 30, height: 1)
              else
                Padding(
                  padding: EdgeInsets.only(bottom: 22),
                  child: ExcludeSemantics(
                    child: GLAvatar(
                      user: store.user(m.text('senderID')),
                      size: 30,
                      fontSize: 11,
                    ),
                  ),
                ),
              SizedBox(width: 8),
              Flexible(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (!samePrev) ...[
                      Padding(
                        padding: EdgeInsets.only(left: 4),
                        child: ExcludeSemantics(
                          excluding: !hidden,
                          child: Text(
                            name,
                            style: gl(13, w600, 0, GLTheme.text2),
                          ),
                        ),
                      ),
                      SizedBox(height: 3),
                    ],
                    if (hidden)
                      _Press(
                        onTap: () =>
                            setState(() => _revealed.add(m.text('id'))),
                        builder: (pressed) => Opacity(
                          opacity: pressed ? 0.6 : 1,
                          child: CustomPaint(
                            painter: _DashedBorder(shapeFixed),
                            child: Container(
                              constraints: BoxConstraints(minHeight: 44),
                              padding: EdgeInsets.symmetric(
                                vertical: 8,
                                horizontal: 12,
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  GLIcon(
                                    'eye.slash',
                                    size: 17,
                                    color: GLTheme.text3,
                                  ),
                                  SizedBox(width: 6),
                                  Flexible(
                                    child: Text(
                                      'Pesan dari pengguna yang kamu blokir · Tampilkan',
                                      style: gl(14, w400, 0, GLTheme.text3),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      )
                    else
                      _bubble(
                        m,
                        color: GLTheme.surface,
                        link: GLTheme.link,
                        shape: shapeFixed,
                        shadow: true,
                      ),
                    if (!sameNext) ...[
                      SizedBox(height: 3),
                      Padding(
                        padding: EdgeInsets.only(left: 4),
                        child: ExcludeSemantics(
                          excluding: !hidden,
                          child: Text(
                            GLFormat.time(_at(m)),
                            style: gl(12, w400, 0, GLTheme.secondary),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _mine(JsonMap m, bool samePrev, bool sameNext, double width) {
    final delivery = m.text('delivery');
    final shape = _uneven(18, samePrev ? 6 : 18, 18, sameNext ? 6 : 18);
    return Padding(
      padding: EdgeInsets.only(top: samePrev ? 2 : 10),
      child: Align(
        alignment: Alignment.centerRight,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: width * 0.8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedOpacity(
                opacity: delivery == 'sending' ? 0.6 : 1,
                duration: Duration(milliseconds: 200),
                curve: Curves.easeOut,
                child: _bubble(
                  m,
                  color: GLTheme.lavender,
                  link: GLTheme.link,
                  shape: shape,
                ),
              ),
              if (delivery == 'failed') ...[
                SizedBox(height: 3),
                GLTap(
                  onTap: _busy || _reading ? null : () => _send(m),
                  child: Container(
                    constraints: BoxConstraints(minHeight: 40),
                    padding: EdgeInsets.all(2),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        GLIcon(
                          'exclamationmark.circle',
                          size: 16,
                          color: GLTheme.danger,
                        ),
                        SizedBox(width: 4),
                        Text(
                          'Gagal terkirim · Coba lagi',
                          style: gl(13, w600, 0, GLTheme.danger),
                        ),
                      ],
                    ),
                  ),
                ),
              ] else if (delivery == 'sending') ...[
                SizedBox(height: 3),
                ExcludeSemantics(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        width: 14,
                        height: 14,
                        child: CupertinoActivityIndicator(radius: 5),
                      ),
                      SizedBox(width: 4),
                      Text(
                        'Mengirim…',
                        style: gl(12, w400, 0, GLTheme.secondary),
                      ),
                    ],
                  ),
                ),
              ] else if (!sameNext) ...[
                SizedBox(height: 3),
                ExcludeSemantics(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '${GLFormat.time(_at(m))} · Terkirim',
                        style: gl(12, w400, 0, GLTheme.secondary),
                      ),
                      SizedBox(width: 3),
                      GLIcon('checkmark', size: 14, color: GLTheme.secondary),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _bubble(
    JsonMap m, {
    required Color color,
    required Color link,
    required ShapeBorder shape,
    bool shadow = false,
  }) {
    final store = widget.store;
    final mine = m.text('senderID') == store.currentUserID;
    final time = GLFormat.time(_at(m));
    final delivery = switch (m.text('delivery')) {
      'sending' => 'Mengirim',
      'failed' => 'Gagal terkirim',
      _ => 'Terkirim',
    };
    void open() => _options(m);
    return Semantics(
      value: mine
          ? 'Kamu, $time, $delivery'
          : 'Dari ${_displayName(store, m.text('senderID'))}, $time',
      customSemanticsActions: {
        CustomSemanticsAction(label: 'Opsi pesan'): open,
      },
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onLongPress: open,
        child: Container(
          padding: EdgeInsets.symmetric(vertical: 8, horizontal: 12),
          decoration: ShapeDecoration(
            color: color,
            shape: shape,
            shadows: shadow
                ? [
                    BoxShadow(
                      color: Color(0x0F000000),
                      blurRadius: 1.5,
                      offset: Offset(0, 1),
                    ),
                  ]
                : null,
          ),
          child: Text.rich(
            _linked(m.text('text'), link),
            style: gl(16, w400, 0, GLTheme.ink, 2.6),
          ),
        ),
      ),
    );
  }

  /// `ChatFormat.linked`: URLs drop their scheme and are underlined; only https is tappable.
  TextSpan _linked(String text, Color color) {
    final spans = <InlineSpan>[];
    var rest = 0;
    for (final match in RegExp(r'https?://\S+').allMatches(text)) {
      spans.add(TextSpan(text: text.substring(rest, match.start)));
      final raw = match.group(0)!;
      final url = Uri.tryParse(raw);
      if (raw.startsWith('https://') && url != null) {
        spans.add(
          TextSpan(
            text: raw.substring('https://'.length),
            style: TextStyle(
              color: color,
              decoration: TextDecoration.underline,
              decorationColor: color,
            ),
            // ponytail: recognizer is not disposed; move to a State-owned list if profiling shows leaks.
            recognizer: TapGestureRecognizer()
              ..onTap = () =>
                  launchUrl(url, mode: LaunchMode.externalApplication),
          ),
        );
      } else {
        spans.add(TextSpan(text: raw));
      }
      rest = match.end;
    }
    spans.add(TextSpan(text: text.substring(rest)));
    return TextSpan(children: spans);
  }

  Widget _empty() => Padding(
    padding: EdgeInsets.symmetric(vertical: 40, horizontal: 16),
    child: Column(
      children: [
        Container(
          width: 56,
          height: 56,
          decoration: glBox(GLTheme.lavender, 20),
          child: GLIcon('hand.wave', size: 28, color: GLTheme.ink),
        ),
        SizedBox(height: 8),
        Text(
          'Belum ada pesan',
          textAlign: TextAlign.center,
          style: gl(17, w600),
        ),
        SizedBox(height: 8),
        Text(
          'Sapa kelompokmu dan mulai koordinasi di sini.',
          textAlign: TextAlign.center,
          style: gl(14, w400, 0, GLTheme.secondary, 4),
        ),
      ],
    ),
  );

  /// Blurred header: back chevron, group tile, name + member count, group button.
  Widget _header(JsonMap? group) => Container(
    padding: EdgeInsets.fromLTRB(
      12,
      MediaQuery.paddingOf(context).top + 4,
      12,
      10,
    ),
    decoration: BoxDecoration(
      color: GLTheme.background.withValues(alpha: 0.94),
      border: Border(bottom: BorderSide(color: GLTheme.border)),
    ),
    child: Row(
      children: [
        GLTap(
          label: 'Kembali',
          onTap: () => Navigator.of(context).maybePop(),
          child: SizedBox(
            width: 44,
            height: 44,
            child: GLIcon('chevron.backward', size: 26, color: GLTheme.ink),
          ),
        ),
        SizedBox(width: 10),
        Container(
          width: 42,
          height: 42,
          decoration: glBox(glTint(group?.text('tint'), GLTheme.surface), 16),
          child: GLIcon(
            (group?.text('icon') ?? '').isEmpty
                ? 'person.3'
                : group!.text('icon'),
            size: 22,
            color: GLTheme.ink,
          ),
        ),
        SizedBox(width: 10),
        Expanded(
          child: MergeSemantics(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  group?.text('name') ?? '',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: gl(16, w700),
                ),
                Text(
                  '${group?.ids('memberIDs').length ?? 0} anggota',
                  style: gl(13, w400, 0, GLTheme.secondary),
                ),
              ],
            ),
          ),
        ),
        SizedBox(width: 10),
        GLCircleButton(
          icon: 'person.2',
          label: 'Buka detail grup',
          onTap: () async {
            await Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) =>
                    GroupScreen(store: widget.store, groupID: widget.groupID),
              ),
            );
            if (mounted) _scheduleRead();
          },
        ),
      ],
    ),
  );

  /// `ChatComposer` (group chat: never read-only).
  Widget _composer() {
    final store = widget.store;
    final retrying = _clientID != null;
    return Container(
      decoration: BoxDecoration(
        color: GLTheme.background,
        border: Border(top: BorderSide(color: GLTheme.border)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            children: [
              Expanded(
                child: Container(
                  height: 44,
                  padding: EdgeInsets.symmetric(horizontal: 16),
                  alignment: Alignment.centerLeft,
                  decoration: ShapeDecoration(
                    color: GLTheme.surface,
                    shape: StadiumBorder(
                      side: BorderSide(color: GLTheme.border),
                    ),
                  ),
                  child: TextField(
                    controller: _draft,
                    readOnly: _busy || retrying,
                    maxLength: 2000,
                    textInputAction: TextInputAction.send,
                    onSubmitted: (_) => _send(),
                    cursorColor: GLTheme.ink,
                    style: gl(16, w400, 0, GLTheme.ink),
                    decoration: InputDecoration.collapsed(
                      hintText: 'Tulis pesan…',
                      hintStyle: gl(16, w400, 0, GLTheme.placeholder),
                    ).copyWith(counterText: ''),
                  ),
                ),
              ),
              SizedBox(width: 8),
              ValueListenableBuilder(
                valueListenable: _draft,
                builder: (_, value, _) {
                  final hasText = value.text.trim().isNotEmpty;
                  final label = retrying ? 'Coba kirim lagi' : 'Kirim pesan';
                  return Tooltip(
                    message: label,
                    triggerMode: TooltipTriggerMode.manual,
                    excludeFromSemantics: true,
                    child: _Press(
                      label: label,
                      onTap: _busy || store.loading ? null : () => _send(),
                      builder: (pressed) => AnimatedScale(
                        scale: pressed ? 0.9 : 1,
                        duration: Duration(milliseconds: 120),
                        curve: Curves.easeOut,
                        child: AnimatedContainer(
                          duration: Duration(milliseconds: 150),
                          curve: Curves.easeOut,
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            color: hasText ? GLTheme.ink : GLTheme.faint,
                            shape: BoxShape.circle,
                          ),
                          child: GLIcon(
                            'arrow.up',
                            size: 22,
                            color: GLTheme.onInk,
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final store = widget.store;
    if (!_canAccess) return GLAccessDenied();
    _scheduleRead();
    final group = store.group(widget.groupID);
    final messages = _thread(store, widget.groupID);
    return Scaffold(
      backgroundColor: GLTheme.background,
      body: Column(
        children: [
          _header(group),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final width = constraints.maxWidth - 32;
                // Forward-ordered thread entries; the list is reversed so it anchors at the bottom.
                final entries = <Widget Function()>[
                  if (store.demoMode && store.simulateSendFailure)
                    () => Padding(
                      padding: EdgeInsets.only(bottom: 8),
                      child: Container(
                        padding: EdgeInsets.symmetric(
                          vertical: 10,
                          horizontal: 14,
                        ),
                        decoration: glBox(GLTheme.butter, 16),
                        child: Row(
                          children: [
                            GLIcon(
                              'icloud.slash',
                              size: 18,
                              color: GLTheme.ink,
                            ),
                            SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Kamu sedang offline. Pesan akan gagal terkirim.',
                                style: gl(14, w500),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  for (var i = 0; i < messages.length; i++) ...[
                    if (i == 0 ||
                        _day(_at(messages[i - 1])) != _day(_at(messages[i])))
                      () => _daySeparator(_day(_at(messages[i]))),
                    () => _row(
                      messages[i],
                      i > 0 ? messages[i - 1] : null,
                      i + 1 < messages.length ? messages[i + 1] : null,
                      width,
                    ),
                  ],
                  if (messages.isEmpty) _empty,
                ];
                return NotificationListener<ScrollNotification>(
                  onNotification: (_) {
                    _scheduleRead();
                    return false;
                  },
                  child: RefreshIndicator.adaptive(
                    onRefresh: _refresh,
                    child: ListView.builder(
                      key: _viewport,
                      reverse: true,
                      physics: AlwaysScrollableScrollPhysics(
                        parent: BouncingScrollPhysics(),
                      ),
                      padding: EdgeInsets.fromLTRB(16, 6, 16, 8),
                      keyboardDismissBehavior:
                          ScrollViewKeyboardDismissBehavior.onDrag,
                      itemCount: entries.length,
                      itemBuilder: (_, index) =>
                          entries[entries.length - 1 - index](),
                    ),
                  ),
                );
              },
            ),
          ),
          if (_error ?? store.error case final error?)
            Padding(
              padding: EdgeInsets.fromLTRB(12, 0, 12, 8),
              child: GLFormError(error),
            ),
          if (_readError != null)
            GLTap(
              onTap: () {
                setState(() {
                  _attemptedReads.clear();
                  _readError = null;
                });
                _scheduleRead();
              },
              child: Padding(
                padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Text(
                  '$_readError · Coba lagi',
                  style: gl(13, w400, 0, GLTheme.secondary),
                ),
              ),
            ),
          _composer(),
        ],
      ),
    );
  }
}

// MARK: - Sheets (`ChatSheetBody` / `ChatMessageSheet` / `ChatReportSheet`)

/// Sheet chrome without a title row: handle, 14pt gaps, height fits content.
Future<T?> _showChatSheet<T>(BuildContext context, WidgetBuilder builder) =>
    showModalBottomSheet<T>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: GLTheme.background,
      barrierColor: Color(0x66000000),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
      ),
      builder: (context) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(20, 10, 20, 34),
          child: DefaultTextStyle.merge(
            style: TextStyle(color: GLTheme.ink),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 38,
                    height: 5,
                    decoration: ShapeDecoration(
                      color: GLTheme.disabled,
                      shape: StadiumBorder(),
                    ),
                  ),
                ),
                SizedBox(height: 14),
                Builder(builder: builder),
              ],
            ),
          ),
        ),
      ),
    );

/// Pops with 'copy' | 'retry' | 'report' | 'block'.
class _MessageSheet extends StatelessWidget {
  const _MessageSheet({required this.store, required this.message});
  final GrouplyStore store;
  final JsonMap message;

  @override
  Widget build(BuildContext context) {
    final m = message;
    final who = m.text('senderID');
    final mine = who == store.currentUserID;
    final blocked = store.blockedUserIDs.contains(who);
    final name = store.user(who)?.text('name') ?? 'Anggota';
    final text = m.text('text');
    Widget action(String label, String icon, Color color, String value) =>
        GLTap(
          onTap: () => Navigator.of(context).pop(value),
          child: Container(
            constraints: BoxConstraints(minHeight: 56),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: GLTheme.border)),
            ),
            child: Row(
              children: [
                GLIcon(icon, size: 22, color: color),
                SizedBox(width: 12),
                Expanded(child: Text(label, style: gl(16, w600, 0, color))),
              ],
            ),
          ),
        );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        MergeSemantics(
          child: Container(
            padding: EdgeInsets.symmetric(vertical: 14, horizontal: 16),
            decoration: glBox(GLTheme.surface, 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${_displayName(store, who)} · ${_day(_at(m))}, ${GLFormat.time(_at(m))}',
                  style: gl(13, w600, 0, GLTheme.text2),
                ),
                SizedBox(height: 4),
                Text(
                  text.length > 140 ? '${text.substring(0, 140)}…' : text,
                  style: gl(15, w400, 0, null, 3),
                ),
              ],
            ),
          ),
        ),
        SizedBox(height: 14),
        Container(
          padding: EdgeInsets.symmetric(vertical: 4, horizontal: 16),
          decoration: glBox(GLTheme.surface, 24),
          child: Column(
            children: [
              action('Salin teks', 'doc.on.doc', GLTheme.ink, 'copy'),
              if (mine && m.text('delivery') == 'failed')
                action(
                  'Coba kirim lagi',
                  'arrow.clockwise',
                  GLTheme.ink,
                  'retry',
                ),
              if (!mine) ...[
                action('Laporkan pesan', 'flag', GLTheme.danger, 'report'),
                if (who.isNotEmpty)
                  action(
                    blocked ? 'Buka blokir $name' : 'Blokir $name',
                    'nosign',
                    GLTheme.danger,
                    'block',
                  ),
              ],
            ],
          ),
        ),
        SizedBox(height: 14),
        GLTap(
          onTap: () => Navigator.of(context).pop(),
          child: Container(
            height: 52,
            alignment: Alignment.center,
            decoration: glBox(_chip, 18),
            child: Text('Batal', style: gl(16, w600)),
          ),
        ),
      ],
    );
  }
}

/// `ChatReportSheet` — reason radio list, optional details, done state.
class _ModerationDialog extends StatefulWidget {
  const _ModerationDialog({required this.cloud, required this.onSubmit});
  final bool cloud;
  final Future<void> Function(String reason) onSubmit;

  @override
  State<_ModerationDialog> createState() => _ModerationDialogState();
}

class _ModerationDialogState extends State<_ModerationDialog> {
  static final _reasons = [
    'Pelecehan',
    'Spam',
    'Konten tidak pantas',
    'Lainnya',
  ];
  final _details = TextEditingController();
  String? _reason, _error;
  bool _busy = false, _done = false;

  @override
  void dispose() {
    _details.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final reason = _reason;
    if (reason == null) return setState(() => _error = 'Pilih alasan laporan.');
    final extra = _details.text.trim();
    if (reason == 'Lainnya' && extra.isEmpty) {
      return setState(() => _error = 'Ceritakan singkat alasannya.');
    }
    setState(() {
      _error = null;
      _busy = true;
    });
    // ponytail: details ride inside the single `reason` field (500 chars) until reports get their own column.
    final full = extra.isEmpty ? reason : '$reason — $extra';
    try {
      await widget.onSubmit(full.length > 500 ? full.substring(0, 500) : full);
      if (mounted) setState(() => _done = true);
    } catch (failure) {
      if (mounted) setState(() => _error = failure.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => _done ? _doneView() : _form();

  Widget _form() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Row(
        children: [
          Expanded(child: Text('Laporkan pesan', style: gl(22, w700, -0.02))),
          SizedBox(width: 8),
          GLTap(
            label: 'Tutup',
            onTap: () => Navigator.of(context).pop(),
            child: Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(color: _chip, shape: BoxShape.circle),
              child: GLIcon('xmark', size: 22, color: GLTheme.ink),
            ),
          ),
        ],
      ),
      SizedBox(height: 8),
      Text(
        'Pengirim tidak akan tahu siapa yang melapor.',
        style: gl(14, w400, 0, GLTheme.text3),
      ),
      SizedBox(height: 14),
      Container(
        padding: EdgeInsets.symmetric(vertical: 4, horizontal: 16),
        decoration: glBox(GLTheme.surface, 24),
        child: Column(
          children: [
            for (final r in _reasons)
              Semantics(
                selected: _reason == r,
                child: GLTap(
                  onTap: () => setState(() => _reason = r),
                  child: Container(
                    constraints: BoxConstraints(minHeight: 54),
                    decoration: BoxDecoration(
                      border: Border(bottom: BorderSide(color: GLTheme.border)),
                    ),
                    child: Row(
                      children: [
                        GLIcon(
                          _reason == r ? 'largecircle.fill.circle' : 'circle',
                          size: 22,
                          color: GLTheme.ink,
                        ),
                        SizedBox(width: 12),
                        Expanded(child: Text(r, style: gl(16, w500))),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
      SizedBox(height: 14),
      Text('Detail (opsional)', style: gl(14, w600)),
      SizedBox(height: 6),
      Container(
        padding: EdgeInsets.symmetric(vertical: 12, horizontal: 16),
        decoration: glBox(GLTheme.surface, 16, border: GLTheme.border),
        child: TextField(
          controller: _details,
          minLines: 3,
          maxLines: null,
          maxLength: 500,
          cursorColor: GLTheme.ink,
          style: gl(16, w400, 0, GLTheme.ink, 4),
          decoration: InputDecoration.collapsed(
            hintText: 'Ceritakan singkat apa yang terjadi',
            hintStyle: gl(16, w400, 0, GLTheme.placeholder, 4),
          ).copyWith(counterText: ''),
        ),
      ),
      if (_error case final error?) ...[
        SizedBox(height: 14),
        GLFormError(error),
      ],
      SizedBox(height: 14),
      GLSubmitButton(
        title: _busy ? 'Menyimpan…' : 'Kirim laporan',
        busy: _busy,
        background: GLTheme.danger,
        onPressed: _submit,
      ),
    ],
  );

  Widget _doneView() => Padding(
    padding: EdgeInsets.only(top: 8),
    child: Column(
      children: [
        Container(
          width: 64,
          height: 64,
          decoration: glBox(GLTheme.mint, 24),
          child: GLIcon('checkmark.circle', size: 32, color: GLTheme.ink),
        ),
        SizedBox(height: 12),
        Text(
          'Laporan tersimpan',
          textAlign: TextAlign.center,
          style: gl(21, w700),
        ),
        SizedBox(height: 12),
        Text(
          widget.cloud
              ? 'Laporan masuk antrean privat untuk ditinjau operator berwenang. Belum ada jaminan waktu respons.'
              : 'Terima kasih sudah menjaga grup tetap nyaman. Ini simulasi pelaporan lokal.',
          textAlign: TextAlign.center,
          style: gl(15, w400, 0, GLTheme.text3, 4),
        ),
        SizedBox(height: 12),
        CustomPaint(
          painter: _DashedBorder(glShape(14)),
          child: Padding(
            padding: EdgeInsets.symmetric(vertical: 10, horizontal: 12),
            child: Text(
              widget.cloud
                  ? 'Laporan berhasil tersimpan di server.'
                  : 'Simulasi: laporan hanya disimpan di prototipe ini dan tidak dikirim ke moderator sungguhan.',
              textAlign: TextAlign.center,
              style: gl(13, w400, 0, GLTheme.secondary, 3),
            ),
          ),
        ),
        SizedBox(height: 12),
        GLTap(
          onTap: () => Navigator.of(context).pop(),
          child: Container(
            height: 54,
            alignment: Alignment.center,
            decoration: glBox(GLTheme.ink, 18),
            child: Text('Selesai', style: gl(16, w600, 0, GLTheme.onInk)),
          ),
        ),
      ],
    ),
  );
}
