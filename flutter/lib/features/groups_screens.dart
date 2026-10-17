part of 'workspace_screens.dart';

// 1:1 port of Grouply/Features/GroupsViews.swift.

const _maxMembers = 8;

List<JsonMap> _grProjects(GrouplyStore store, String groupID) => store.projects
    .where((project) => project.text('groupID') == groupID)
    .toList();

/// `DemoStore.unreadCount(groupID:)`.
int _grUnread(GrouplyStore store, String groupID) {
  final me = store.currentUserID;
  if (!_member(store, store.group(groupID))) return 0;
  return store.messages
      .where(
        (message) =>
            message.text('groupID') == groupID &&
            message.text('taskID').isEmpty &&
            message.text('senderID') != me &&
            (message.text('delivery').isEmpty ||
                message.text('delivery') == 'sent') &&
            !store.readMessageIDs.contains(message.text('id')),
      )
      .length;
}

int _grTaskCount(
  GrouplyStore store,
  String groupID,
  String userID, {
  required bool done,
}) {
  final pids = _grProjects(store, groupID).map((p) => p.text('id')).toSet();
  return store.tasks
      .where(
        (task) =>
            pids.contains(task.text('projectID')) &&
            task.text('assigneeID') == userID &&
            (task.text('status') == 'done') == done,
      )
      .length;
}

/// Prototype `invStatus`: valid / expired / revoked / used / nogroup.
String _grInviteStatus(GrouplyStore store, JsonMap invite) {
  if (store.group(invite.text('groupID')) == null) return 'nogroup';
  if (invite['revoked'] == true) return 'revoked';
  final expires = invite.date('expiresAt');
  if (expires == null || !DateTime.now().isBefore(expires)) return 'expired';
  if (invite.number('useCount') >= invite.number('maxUses')) return 'used';
  return 'valid';
}

/// Prototype `doJoin` messages, checked before the store call.
String? _grJoinError(GrouplyStore store, String code) {
  if (!store.demoMode) return code.trim().isEmpty ? 'Isi kode undangan.' : null;
  if (code.isEmpty) return 'Masukkan kode undangan.';
  final invite = store.invites
      .where((row) => row.text('code').toUpperCase() == code)
      .firstOrNull;
  if (invite == null) {
    return 'Kode tidak ditemukan. Periksa lagi huruf dan angkanya.';
  }
  final status = _grInviteStatus(store, invite);
  final group = store.group(invite.text('groupID'));
  if (status == 'nogroup') {
    return 'Undangan tidak berlaku. Grupnya sudah tidak ada.';
  }
  if (_member(store, group)) return 'Kamu sudah bergabung dengan grup ini.';
  if (status == 'revoked') {
    return 'Undangan tidak berlaku. Minta kode baru ke koordinator.';
  }
  if (status == 'expired') {
    return 'Undangan kedaluwarsa sejak ${GLFormat.date(invite.date('expiresAt') ?? DateTime.now())}. Minta kode baru ke koordinator.';
  }
  if (status == 'used') {
    return 'Undangan tidak berlaku. Kode sudah mencapai batas pemakaian.';
  }
  if (group!.ids('memberIDs').length >= _maxMembers) {
    return 'Grup ini sudah penuh (8 anggota).';
  }
  return null;
}

/// Button whose accessibility label replaces its visible text.
Widget _grButton({
  required String label,
  required VoidCallback? onTap,
  required Widget child,
  bool scale = false,
  bool selected = false,
  Key? key,
}) => Semantics(
  key: key,
  label: label,
  button: true,
  selected: selected,
  excludeSemantics: true,
  onTap: onTap,
  child: scale
      ? GLTap.card(onTap: onTap, child: child)
      : GLTap(onTap: onTap, child: child),
);

const _grHairline = BoxDecoration(
  border: Border(bottom: BorderSide(color: GLTheme.border)),
);

// MARK: - Shared group actions (invite, member sheet, leave)

mixin _GroupActions<T extends _WorkspaceScreen> on _WorkspaceState<T> {
  Future<void> reload() async {
    try {
      await store.refresh();
    } catch (_) {
      feedback(
        'Gagal memuat ulang. Periksa koneksi lalu coba lagi.',
        kind: GLToastKind.err,
      );
    }
  }

  /// `groupsRun`: mutation + Swift toast, or the store's error.
  Future<JsonMap?> run(
    String action,
    JsonMap payload, [
    String? success,
    GLToastKind kind = GLToastKind.ok,
  ]) async {
    if (busy || store.loading) return null;
    setState(() => busy = true);
    try {
      final result = await store.mutate(action, payload);
      if (success != null) feedback(success, kind: kind);
      return result;
    } catch (error) {
      feedback(error.toString(), kind: GLToastKind.err);
      return null;
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  void leftGroup() {
    if (mounted) Navigator.of(context).popUntil((route) => route.isFirst);
  }

  /// Pending review or unfinished assignments block leave/remove.
  String? memberLock(String groupID, String userID) {
    final pids = _grProjects(store, groupID).map((p) => p.text('id')).toSet();
    final tasks = store.tasks.where(
      (task) =>
          pids.contains(task.text('projectID')) &&
          (task.text('assigneeID') == userID ||
              task.text('reviewerID') == userID),
    );
    if (tasks.any((task) => task.text('status') == 'in_review')) {
      return 'Selesaikan review anggota ini sebelum keluar atau menghapus anggota.';
    }
    if (tasks.any((task) => task.text('status') != 'done')) {
      return 'Alihkan tugas aktif anggota ini terlebih dahulu.';
    }
    return null;
  }

  /// `groupsCreateInvite` → `GroupInviteSheet`.
  Future<void> createInvite(String groupID) async {
    final group = store.group(groupID);
    if (!_coordinator(store, group)) {
      return feedback(
        'Hanya koordinator yang bisa mengundang anggota.',
        kind: GLToastKind.err,
      );
    }
    if (group!.ids('memberIDs').length >= _maxMembers) {
      return feedback(
        'Grup sudah penuh (maksimal 8 anggota).',
        kind: GLToastKind.err,
      );
    }
    final result = await run('generateInvite', {'groupID': groupID});
    if (result == null || !mounted) return;
    final made = result['invite'] is JsonMap
        ? result['invite'] as JsonMap
        : <String, dynamic>{};
    final id = made.text('id').isNotEmpty ? made.text('id') : result.text('id');
    await showGLSheet<void>(
      context,
      title: 'Undang anggota',
      builder: (_) => ListenableBuilder(
        listenable: store,
        builder: (context, _) {
          final live = store.invites
              .where((row) => row.text('id') == id)
              .firstOrNull;
          // The plain code is only returned when minted (cloud keeps a hash).
          final invite = {...made, ...?live};
          if (live?.text('code').isEmpty ?? false) {
            invite['code'] = made.text('code');
          }
          return _inviteBody(invite);
        },
      ),
    );
  }

  Widget _inviteBody(JsonMap invite) {
    final status = _grInviteStatus(store, invite);
    final (label, background, icon) = switch (status) {
      'valid' => ('Undangan aktif', Colors.white, 'checkmark.circle'),
      'expired' => ('Undangan kedaluwarsa', GLTheme.coral, 'clock.badge.xmark'),
      'used' => (
        'Undangan tidak berlaku · sudah dipakai',
        GLTheme.coral,
        'nosign',
      ),
      _ => ('Undangan tidak berlaku', GLTheme.coral, 'nosign'),
    };
    final code = invite.text('code');
    final expires = invite.date('expiresAt') ?? DateTime.now();
    final share = Container(
      height: 52,
      decoration: glBox(GLTheme.ink, 18),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const GLIcon('square.and.arrow.up', size: 19, color: Colors.white),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              'Bagikan',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: gl(15, w600, 0, Colors.white),
            ),
          ),
        ],
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(22),
          decoration: glBox(GLTheme.mint, 28),
          child: Column(
            children: [
              Text(
                store.group(invite.text('groupID'))?.text('name') ?? '',
                textAlign: TextAlign.center,
                style: gl(14, w600, 0, GLTheme.text3),
              ),
              const SizedBox(height: 6),
              FittedBox(
                fit: BoxFit.scaleDown,
                child: SelectableText(
                  code,
                  maxLines: 1,
                  style: gl(34, w800, 0.08).copyWith(
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Container(
                height: 28,
                padding: const EdgeInsets.only(left: 8, right: 11),
                decoration: ShapeDecoration(
                  color: background,
                  shape: const StadiumBorder(),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    GLIcon(icon, size: 16),
                    const SizedBox(width: 4),
                    Flexible(child: Text(label, style: gl(13, w600))),
                  ],
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Berlaku sampai ${GLFormat.weekday(expires)}, ${GLFormat.date(expires)}, ${GLFormat.time(expires)} · ${invite.number('useCount')}/${invite.number('maxUses')} pemakaian',
                textAlign: TextAlign.center,
                style: gl(13, w400, 0, GLTheme.text3),
              ),
            ],
          ),
        ),
        if (status == 'valid') ...[
          const SizedBox(height: 16),
          Center(
            child: GLTap(
              onTap: () => _revoke(invite),
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 44),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const GLIcon('nosign', size: 18, color: GLTheme.danger),
                    const SizedBox(width: 6),
                    Text(
                      'Nonaktifkan kode',
                      style: gl(14, w600, 0, GLTheme.danger),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: GLOutlineButton(
                title: 'Salin',
                icon: 'doc.on.doc',
                height: 52,
                radius: 18,
                onPressed: () => _copy(code, 'Kode $code disalin'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: GLTap(
                onTap: status == 'valid'
                    ? () => _shareInvite(code)
                    : () => feedback(
                        'Kode ini sudah tidak berlaku. Buat kode baru.',
                        kind: GLToastKind.err,
                      ),
                child: share,
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Text(
          store.demoMode
              ? 'Demo: ganti persona di panel demo, lalu buka Grup → Gabung dengan kode. Kode prototipe dibuat acak secara lokal, bukan kode aman produksi.'
              : 'Bagikan kode ini kepada anggota yang ingin bergabung. Kode berlaku 7 hari dan sekali pakai.',
          style: gl(13, w400, 0, GLTheme.secondary, 3),
        ),
      ],
    );
  }

  Future<void> _copy(String text, String done) async {
    try {
      await Clipboard.setData(ClipboardData(text: text));
      feedback(done);
    } catch (_) {
      feedback('Kode tidak dapat disalin.', kind: GLToastKind.err);
    }
  }

  Future<void> _shareInvite(String code) async {
    final text = 'Gabung ke grup GROUPLY. Kode undangan: $code';
    try {
      final result = await SharePlus.instance.share(ShareParams(text: text));
      if (result.status == ShareResultStatus.unavailable) {
        await _copy(text, 'Teks undangan disalin');
      }
    } catch (_) {
      await _copy(text, 'Teks undangan disalin');
    }
  }

  void _revoke(JsonMap invite) {
    if (!_coordinator(store, store.group(invite.text('groupID')))) {
      return feedback(
        'Hanya koordinator yang bisa menonaktifkan undangan.',
        kind: GLToastKind.err,
      );
    }
    run(
      'revokeInvite',
      {'id': invite.text('id')},
      'Kode ${invite.text('code')} dinonaktifkan',
      GLToastKind.info,
    );
  }

  /// `GroupMemberSheet`: profile header + transfer / remove / block rows.
  void showMember(String groupID, String userID) {
    final group = store.group(groupID);
    if (group == null) return;
    showGLSheet<void>(
      context,
      title: '',
      builder: (sheet) => ListenableBuilder(
        listenable: store,
        builder: (sheet, _) => _memberBody(sheet, groupID, userID),
      ),
    );
  }

  Widget _memberBody(BuildContext sheet, String groupID, String userID) {
    final group = store.group(groupID);
    if (group == null) return const SizedBox.shrink();
    final coord = group.text('coordinatorID') == store.currentUserID;
    final isSelf = userID == store.currentUserID;
    final isC = userID == group.text('coordinatorID');
    final user = store.user(userID);
    final email = user?.text('email') ?? '';
    final name = user?.text('name') ?? 'Anggota';
    final blocked = store.blockedUserIDs.contains(userID);
    final rows = <(String, String, Color, VoidCallback)>[
      if (!isSelf && !isC) ...[
        (
          'Jadikan koordinator',
          coord ? 'person.badge.shield.checkmark' : 'lock',
          GLTheme.ink,
          () async {
            if (!coord) {
              return feedback(
                'Hanya koordinator yang bisa menyerahkan peran koordinator.',
                kind: GLToastKind.err,
              );
            }
            if (await confirm(
              'Jadikan $name koordinator?',
              '$name akan bisa mengelola anggota, proyek, dan tugas. Kamu tetap jadi anggota grup.',
              ok: 'Jadikan koordinator',
            )) {
              await run('transferCoordinator', {
                'groupID': groupID,
                'to': userID,
              }, '$name sekarang koordinator');
            }
          },
        ),
        (
          'Keluarkan dari grup',
          coord ? 'person.badge.minus' : 'lock',
          coord ? GLTheme.danger : GLTheme.ink,
          () async {
            if (!coord) {
              return feedback(
                'Hanya koordinator yang bisa mengeluarkan anggota.',
                kind: GLToastKind.err,
              );
            }
            final lock = memberLock(groupID, userID);
            if (lock != null) return feedback(lock, kind: GLToastKind.err);
            if (await confirm(
              'Keluarkan $name?',
              '$name tidak bisa lagi membuka proyek dan chat grup ini. Hasil kerja dan tugas yang sudah selesai tetap tercatat atas nama $name.',
              ok: 'Keluarkan',
              destructive: true,
            )) {
              await run(
                'removeMember',
                {'groupID': groupID, 'userID': userID},
                '$name dikeluarkan dari grup',
                GLToastKind.info,
              );
            }
          },
        ),
      ],
      if (!isSelf)
        (
          blocked ? 'Buka blokir' : 'Blokir $name',
          'nosign',
          GLTheme.danger,
          () async {
            if (blocked) {
              await run(
                'unblockUser',
                {'id': userID},
                '$name tidak lagi diblokir',
                GLToastKind.info,
              );
              return;
            }
            if (await confirm(
              'Blokir $name?',
              'Pesan $name di chat dan diskusi akan disembunyikan untukmu. $name tetap anggota grup, tugas bersama tetap berjalan, dan $name tidak diberi tahu.',
              ok: 'Blokir',
              destructive: true,
            )) {
              await run(
                'blockUser',
                {'id': userID},
                '$name diblokir',
                GLToastKind.info,
              );
            }
          },
        ),
    ];
    // ponytail: Swift pulls the header up 30pt under the close row with a
    // negative padding; translating leaves 30pt extra space at the bottom.
    return Transform.translate(
      offset: const Offset(0, -30),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Column(
            children: [
              GLAvatar(user: user, size: 72, fontSize: 22),
              const SizedBox(height: 6),
              Text(
                '${user?.text('name') ?? 'Pengguna'}${isSelf ? ' (kamu)' : ''}',
                textAlign: TextAlign.center,
                style: gl(20, w700),
              ),
              if (email.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(
                  email,
                  textAlign: TextAlign.center,
                  style: gl(14, w400, 0, GLTheme.secondary),
                ),
              ],
              const SizedBox(height: 6),
              Container(
                height: 28,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                alignment: Alignment.center,
                decoration: ShapeDecoration(
                  color: isC ? GLTheme.mint : GLTheme.muted,
                  shape: const StadiumBorder(),
                ),
                child: Text(
                  isC ? 'Koordinator' : 'Anggota',
                  style: gl(13, w600),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                '${_grTaskCount(store, groupID, userID, done: false)} tugas aktif · ${_grTaskCount(store, groupID, userID, done: true)} tugas selesai di grup ini',
                textAlign: TextAlign.center,
                style: gl(14, w400, 0, GLTheme.text3),
              ),
            ],
          ),
          if (rows.isNotEmpty) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 16),
              decoration: glBox(Colors.white, 24),
              child: Column(
                children: [
                  for (final (label, icon, color, go) in rows)
                    GLTap(
                      onTap: () {
                        Navigator.of(sheet).pop();
                        go();
                      },
                      child: Container(
                        constraints: const BoxConstraints(minHeight: 56),
                        decoration: _grHairline,
                        child: Row(
                          children: [
                            GLIcon(icon, size: 22, color: color),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(label, style: gl(16, w600, 0, color)),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
          if (!coord && !isSelf) ...[
            const SizedBox(height: 16),
            Text(
              'Aksi bertanda gembok hanya untuk koordinator.',
              textAlign: TextAlign.center,
              style: gl(13, w400, 0, GLTheme.text3),
            ),
          ],
        ],
      ),
    );
  }

  /// `groupsLeaveConfirmation`.
  Future<void> leave(String groupID, {VoidCallback? pickCoordinator}) async {
    final group = store.group(groupID);
    if (group == null || busy || store.loading) return;
    final count = group.ids('memberIDs').length;
    final name = group.text('name');
    if (_coordinator(store, group) && count > 1) {
      if (await confirm(
            'Serahkan peran koordinator dulu',
            'Grup harus selalu punya koordinator. Pilih anggota lain sebagai koordinator sebelum kamu keluar.',
            ok: 'Pilih koordinator',
          ) &&
          mounted) {
        pickCoordinator?.call();
      }
      return;
    }
    final lock = memberLock(groupID, store.currentUserID);
    if (lock != null) return feedback(lock, kind: GLToastKind.err);
    final ok = count == 1
        ? await confirm(
            'Kamu anggota terakhir',
            'Kalau kamu keluar, $name beserta proyek, tugas, dan chat-nya dihapus dari data demo. Di versi produksi, data diproses sesuai kebijakan retensi.',
            ok: 'Keluar & hapus grup',
            destructive: true,
          )
        : await confirm(
            'Keluar dari grup?',
            'Kamu tidak bisa lagi membuka proyek dan chat $name. Hasil kerja dan tugas yang sudah selesai tetap tercatat atas nama kamu.',
            ok: 'Keluar',
            destructive: true,
          );
    if (!ok || !mounted) return;
    final result = await run(
      'leaveGroup',
      {'id': groupID},
      count == 1 ? 'Grup dihapus' : 'Kamu keluar dari $name',
      GLToastKind.info,
    );
    if (result != null) leftGroup();
  }

  /// Screen chrome for the pushed group screens (`.glDetailScreen()`).
  Widget detailPage({
    required String title,
    Widget? trailing,
    required List<Widget> children,
  }) => Scaffold(
    backgroundColor: GLTheme.background,
    body: SafeArea(
      child: RefreshIndicator.adaptive(
        onRefresh: reload,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(
            parent: BouncingScrollPhysics(),
          ),
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
          children: [
            GLDetailHeader(title, trailing: trailing),
            for (final child in children) ...[
              const SizedBox(height: 16),
              child,
            ],
          ],
        ),
      ),
    ),
  );
}

// MARK: - Grup tab

class _GroupsState extends _WorkspaceState<GroupsScreen>
    with _GroupActions<GroupsScreen> {
  Future<void> _sheet({required bool joining}) async {
    final id = await showGLSheet<String>(
      context,
      title: joining ? 'Gabung ke grup' : 'Buat grup',
      builder: (_) => _GroupFormSheet(store: store, joining: joining),
    );
    if (id != null && id.isNotEmpty && mounted) {
      open(GroupScreen(store: store, groupID: id));
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: store,
    builder: (context, _) {
      final groups = store.groups.where((g) => _member(store, g)).toList();
      return Scaffold(
        backgroundColor: GLTheme.background,
        body: SafeArea(
          bottom: false,
          child: RefreshIndicator.adaptive(
            onRefresh: reload,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(
                parent: BouncingScrollPhysics(),
              ),
              padding: EdgeInsets.fromLTRB(
                20,
                10,
                20,
                MediaQuery.paddingOf(context).bottom,
              ),
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Semantics(
                        header: true,
                        child: Text('Grup', style: gl(34, w700, -0.03)),
                      ),
                    ),
                    _grButton(
                      key: const Key('group-create'),
                      label: 'Buat grup',
                      onTap: () => _sheet(joining: false),
                      child: Container(
                        width: 52,
                        height: 52,
                        decoration: const BoxDecoration(
                          color: GLTheme.ink,
                          shape: BoxShape.circle,
                        ),
                        child: const GLIcon(
                          'plus',
                          size: 28,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ],
                ),
                if (groups.isEmpty) ...[
                  const SizedBox(height: 16),
                  const GLEmptyState(
                    title: 'Belum ada grup',
                    message:
                        'Grup menyatukan proyek, tugas, dan chat kelompokmu. Buat grup dengan tombol + atau gabung pakai kode undangan.',
                    icon: 'person.3',
                  ),
                ],
                for (final group in groups) ...[
                  const SizedBox(height: 16),
                  GLTap.card(
                    onTap: () => open(
                      GroupScreen(store: store, groupID: group.text('id')),
                    ),
                    child: MergeSemantics(child: _GroupCard(store, group)),
                  ),
                ],
                const SizedBox(height: 16),
                GLTap(
                  onTap: () => _sheet(joining: true),
                  child: CustomPaint(
                    painter: const _DashedBorder(),
                    child: SizedBox(
                      height: 56,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const GLIcon('key', size: 20),
                          const SizedBox(width: 8),
                          Flexible(
                            child: Text(
                              'Gabung dengan kode undangan',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: gl(15, w600),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
}

/// 20pt continuous rounded rect, 1.5pt ink(40%) dash [5, 4].
class _DashedBorder extends CustomPainter {
  const _DashedBorder();
  @override
  void paint(Canvas canvas, Size size) {
    final path = glShape(20).getOuterPath((Offset.zero & size).deflate(0.75));
    final paint = Paint()
      ..color = GLTheme.ink.withValues(alpha: 0.4)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    for (final metric in path.computeMetrics()) {
      for (var d = 0.0; d < metric.length; d += 9) {
        canvas.drawPath(metric.extractPath(d, d + 5), paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Group card on the Grup tab (prototype `groupsVals`).
class _GroupCard extends StatelessWidget {
  const _GroupCard(this.store, this.group);
  final GrouplyStore store;
  final JsonMap group;
  @override
  Widget build(BuildContext context) {
    final id = group.text('id');
    final coord = group.text('coordinatorID') == store.currentUserID;
    final active = _grProjects(
      store,
      id,
    ).where((p) => p.text('status') == 'active').length;
    final unread = _grUnread(store, id);
    final members = group.ids('memberIDs');
    final faces = members.take(5).toList();
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: glBox(Colors.white, 28, shadow: true),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: glBox(glHex(group.text('tint')), 20),
                child: GLIcon(group.text('icon'), size: 26),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(group.text('name'), style: gl(18, w700, -0.015)),
                    const SizedBox(height: 2),
                    Text(
                      group.text('course'),
                      style: gl(14, w400, 0, GLTheme.secondary),
                    ),
                  ],
                ),
              ),
              const GLIcon('chevron.right', size: 22, color: GLTheme.secondary),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              SizedBox(
                width: faces.isEmpty ? 0 : 32 + (faces.length - 1) * 24,
                height: 32,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    for (var i = 0; i < faces.length; i++)
                      Positioned(
                        left: i * 24,
                        child: Container(
                          foregroundDecoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: Colors.white,
                              width: 2.5,
                              strokeAlign: BorderSide.strokeAlignCenter,
                            ),
                          ),
                          child: GLAvatar(
                            user: store.user(faces[i]),
                            size: 32,
                            fontSize: 11,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 18),
              Expanded(
                child: Text(
                  '${members.length} anggota · ${active > 0 ? '$active proyek aktif' : 'Belum ada proyek aktif'}',
                  style: gl(14, w400, 0, GLTheme.text3),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              GLChip(
                label: coord ? 'Koordinator' : 'Anggota',
                background: coord ? GLTheme.mint : GLTheme.muted,
                fontSize: 12,
              ),
              if (unread > 0)
                GLChip(
                  label: '$unread pesan baru',
                  icon: 'bubble.left',
                  background: GLTheme.ink,
                  foreground: Colors.white,
                  fontSize: 12,
                  iconSize: 15,
                ),
            ],
          ),
        ],
      ),
    );
  }
}

// MARK: - Group detail (prototype `isGroup` + `groupVals`)

class _GroupState extends _WorkspaceState<GroupScreen>
    with _GroupActions<GroupScreen> {
  String filter = 'active';
  String get groupID => widget.groupID;

  Future<void> _settings() async {
    final result = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) => _GroupSettingsScreen(store: store, groupID: groupID),
      ),
    );
    if (result == 'archived' && mounted) setState(() => filter = 'archived');
  }

  Future<void> _newProject(JsonMap group) async {
    if (!_coordinator(store, group)) {
      return feedback(
        'Hanya koordinator yang bisa membuat proyek.',
        kind: GLToastKind.err,
      );
    }
    final result = await _showProjectSheet(this, group);
    if (result != null && mounted && result.text('id').isNotEmpty) {
      open(ProjectScreen(store: store, projectID: result.text('id')));
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: store,
    builder: (context, _) {
      final group = store.group(groupID);
      if (!_member(store, group)) return const GLAccessDenied();
      return _content(group!);
    },
  );

  Widget _content(JsonMap group) {
    final coord = _coordinator(store, group);
    final all = _grProjects(store, groupID);
    List<JsonMap> having(String status) =>
        all.where((p) => p.text('status') == status).toList();
    final lists = [
      ('active', 'Aktif', having('active')),
      ('done', 'Selesai', having('completed')),
      ('archived', 'Arsip', having('archived')),
    ];
    final current = lists.firstWhere(
      (l) => l.$1 == filter,
      orElse: () => lists.first,
    );
    final liveIDs = all
        .where((p) => p.text('status') != 'archived')
        .map((p) => p.text('id'))
        .toSet();
    final running = store.tasks
        .where(
          (t) =>
              liveIDs.contains(t.text('projectID')) &&
              t.text('status') != 'done',
        )
        .length;
    final unread = _grUnread(store, groupID);
    final members = group.ids('memberIDs');

    return detailPage(
      title: 'Grup',
      trailing: GLCircleButton(
        icon: 'gearshape',
        label: 'Pengaturan grup',
        onTap: _settings,
      ),
      children: [
        // Group card
        Container(
          padding: const EdgeInsets.all(20),
          decoration: glBox(Colors.white, 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 58,
                    height: 58,
                    decoration: glBox(glHex(group.text('tint')), 22),
                    child: GLIcon(group.text('icon'), size: 28),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(group.text('name'), style: gl(23, w700, -0.02)),
                        const SizedBox(height: 2),
                        Text(
                          group.text('course'),
                          style: gl(14, w400, 0, GLTheme.secondary),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              if (group.text('description').isNotEmpty) ...[
                const SizedBox(height: 14),
                Text(
                  group.text('description'),
                  style: gl(15, w400, 0, GLTheme.text3, 4),
                ),
              ],
              const SizedBox(height: 14),
              Row(
                children: [
                  const GLIcon(
                    'chart.xyaxis.line',
                    size: 18,
                    color: GLTheme.text3,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      '${lists[0].$3.length} proyek aktif · $running tugas berjalan',
                      style: gl(14, w400, 0, GLTheme.text3),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: _grButton(
                      label: unread > 0
                          ? 'Chat grup, $unread pesan baru'
                          : 'Chat grup',
                      onTap: () =>
                          open(ChatScreen(store: store, groupID: groupID)),
                      child: Container(
                        height: 48,
                        decoration: glBox(GLTheme.ink, 16),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const GLIcon(
                              'bubble.left',
                              size: 19,
                              color: Colors.white,
                            ),
                            const SizedBox(width: 6),
                            Flexible(
                              child: Text(
                                'Chat grup',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: gl(15, w600, 0, Colors.white),
                              ),
                            ),
                            if (unread > 0) ...[
                              const SizedBox(width: 6),
                              Container(
                                constraints: const BoxConstraints(
                                  minWidth: 22,
                                  minHeight: 22,
                                ),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                ),
                                alignment: Alignment.center,
                                decoration: const ShapeDecoration(
                                  color: GLTheme.mint,
                                  shape: StadiumBorder(),
                                ),
                                child: Text(
                                  '$unread',
                                  style: gl(12, w700, 0, GLTheme.ink),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: GLOutlineButton(
                      title: 'Anggota',
                      icon: 'person.2',
                      onPressed: () => open(
                        _GroupMembersScreen(store: store, groupID: groupID),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),

        // Members
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Anggota', style: gl(21, w700, -0.02)),
                      Text(
                        '${members.length} dari 8 anggota',
                        style: gl(13, w400, 0, GLTheme.secondary),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                _grButton(
                  label: 'Undang anggota',
                  onTap: () => createInvite(groupID),
                  child: Container(
                    height: 44,
                    padding: const EdgeInsets.only(left: 10, right: 14),
                    decoration: const ShapeDecoration(
                      shape: StadiumBorder(
                        side: BorderSide(color: GLTheme.ink, width: 1.5),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        GLIcon(coord ? 'person.badge.plus' : 'lock', size: 19),
                        const SizedBox(width: 4),
                        Text('Undang', style: gl(14, w600)),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              clipBehavior: Clip.none,
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final id in members) ...[
                    if (id != members.first) const SizedBox(width: 4),
                    _memberChip(group, id),
                  ],
                ],
              ),
            ),
            if (members.length == 1) ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.symmetric(
                  vertical: 14,
                  horizontal: 16,
                ),
                decoration: glBox(Colors.white, 20),
                child: Text(
                  'Belum ada anggota lain. Undang teman sekelompok dengan kode undangan.',
                  style: gl(14, w400, 0, GLTheme.text3, 4),
                ),
              ),
            ],
          ],
        ),

        // Projects
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(child: Text('Proyek', style: gl(21, w700, -0.02))),
                  const SizedBox(width: 8),
                  _grButton(
                    key: const Key('create-project'),
                    label: 'Buat proyek',
                    onTap: () => _newProject(group),
                    child: Container(
                      height: 44,
                      padding: const EdgeInsets.only(left: 10, right: 14),
                      decoration: const ShapeDecoration(
                        color: GLTheme.ink,
                        shape: StadiumBorder(),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          GLIcon(
                            coord ? 'plus' : 'lock',
                            size: 19,
                            color: Colors.white,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            'Buat proyek',
                            style: gl(14, w600, 0, Colors.white),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                clipBehavior: Clip.none,
                child: Row(
                  children: [
                    for (final (key, label, items) in lists) ...[
                      if (key != 'active') const SizedBox(width: 6),
                      _grButton(
                        label: '$label · ${items.length}',
                        selected: key == current.$1,
                        onTap: () => setState(() => filter = key),
                        child: Container(
                          height: 44,
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          alignment: Alignment.center,
                          decoration: ShapeDecoration(
                            color: key == current.$1
                                ? GLTheme.ink
                                : Colors.white,
                            shape: const StadiumBorder(
                              side: BorderSide(color: GLTheme.ink, width: 1.5),
                            ),
                          ),
                          child: Text(
                            '$label · ${items.length}',
                            style: gl(
                              14,
                              w600,
                              0,
                              key == current.$1 ? Colors.white : GLTheme.ink,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              for (final project in current.$3) ...[
                const SizedBox(height: 10),
                GLTap.card(
                  onTap: () => open(
                    ProjectScreen(store: store, projectID: project.text('id')),
                  ),
                  child: MergeSemantics(
                    child: _GroupProjectCard(store, project),
                  ),
                ),
              ],
              if (all.isEmpty) ...[
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.symmetric(
                    vertical: 26,
                    horizontal: 22,
                  ),
                  decoration: glBox(Colors.white, 28),
                  child: Column(
                    children: [
                      Container(
                        width: 56,
                        height: 56,
                        decoration: glBox(GLTheme.butter, 20),
                        child: const GLIcon('folder', size: 28),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        'Belum ada proyek',
                        textAlign: TextAlign.center,
                        style: gl(19, w700),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        coord
                            ? 'Mulai proyek pertama untuk mengatur tugas dan kerja sama kelompokmu.'
                            : 'Koordinator belum membuat proyek. Proyek baru akan muncul di sini.',
                        textAlign: TextAlign.center,
                        style: gl(15, w400, 0, GLTheme.secondary, 4),
                      ),
                      if (coord) ...[
                        const SizedBox(height: 14),
                        GLTap(
                          onTap: () => _newProject(group),
                          child: Container(
                            height: 50,
                            padding: const EdgeInsets.symmetric(horizontal: 24),
                            decoration: glBox(GLTheme.ink, 16),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  'Buat Proyek',
                                  style: gl(15, w600, 0, Colors.white),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ] else if (current.$3.isEmpty) ...[
                const SizedBox(height: 10),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 20),
                  child: Text(
                    current.$1 == 'archived'
                        ? 'Belum ada proyek yang diarsipkan.'
                        : current.$1 == 'done'
                        ? 'Belum ada proyek yang selesai.'
                        : 'Tidak ada proyek aktif. Lihat tab Selesai atau Arsip.',
                    textAlign: TextAlign.center,
                    style: gl(15, w400, 0, GLTheme.secondary),
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _memberChip(JsonMap group, String id) {
    final isC = id == group.text('coordinatorID');
    final role = isC ? 'Koordinator' : 'Anggota';
    final name = id == store.currentUserID
        ? 'Kamu'
        : store.user(id)?.text('name') ?? 'Anggota';
    // ponytail: GLTap.card presses to .98; Swift uses .94 here.
    return _grButton(
      label: '$name, $role',
      scale: true,
      onTap: () => showMember(groupID, id),
      child: Container(
        width: 76,
        constraints: const BoxConstraints(minHeight: 96),
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Column(
          children: [
            GLAvatar(user: store.user(id), size: 48, fontSize: 14),
            const SizedBox(height: 4),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 72),
              child: Text(
                name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: gl(13, w600),
              ),
            ),
            const SizedBox(height: 4),
            Container(
              padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 7),
              decoration: ShapeDecoration(
                color: isC ? GLTheme.mint : Colors.transparent,
                shape: const StadiumBorder(),
              ),
              child: Text(
                role,
                maxLines: 1,
                softWrap: false,
                style: gl(11, w600, 0, GLTheme.text3),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Group-detail project card: 12×40 tint bar, status chip, progress bar.
class _GroupProjectCard extends StatelessWidget {
  const _GroupProjectCard(this.store, this.project);
  final GrouplyStore store;
  final JsonMap project;
  @override
  Widget build(BuildContext context) {
    final tasks = store.tasks
        .where((t) => t.text('projectID') == project.text('id'))
        .toList();
    final done = tasks.where((t) => t.text('status') == 'done').length;
    final (label, background, icon) = switch (project.text('status')) {
      'archived' => ('Diarsipkan', const Color(0xFFECEEEB), 'archivebox'),
      'completed' => ('Selesai', GLTheme.mint, 'checkmark.circle'),
      _ => ('Aktif', GLTheme.sky, 'bolt'),
    };
    final due = project.date('dueAt');
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: glBox(Colors.white, 24, shadow: true),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 12,
                height: 40,
                decoration: glBox(
                  glHex(
                    store.group(project.text('groupID'))?.text('tint'),
                    Colors.white,
                  ),
                  6,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(project.text('title'), style: gl(16, w600)),
                    const SizedBox(height: 2),
                    Text(
                      'Deadline ${due == null ? '-' : GLFormat.date(due)}',
                      style: gl(13, w400, 0, GLTheme.secondary),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Container(
                height: 28,
                padding: const EdgeInsets.only(left: 7, right: 10),
                decoration: ShapeDecoration(
                  color: background,
                  shape: const StadiumBorder(),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    GLIcon(icon, size: 15),
                    const SizedBox(width: 4),
                    Text(label, maxLines: 1, style: gl(12, w600)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: GLProgressBar(
                  value: tasks.isEmpty ? 0 : done / tasks.length,
                ),
              ),
              const SizedBox(width: 10),
              Text(
                '$done/${tasks.length} selesai',
                style: gl(
                  13,
                  w600,
                ).copyWith(fontFeatures: const [FontFeature.tabularFigures()]),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// MARK: - Members screen (prototype `isMembers` + `membersVals`)

class _GroupMembersScreen extends _WorkspaceScreen {
  const _GroupMembersScreen({required super.store, required this.groupID});
  final String groupID;
  @override
  State<_GroupMembersScreen> createState() => _GroupMembersState();
}

class _GroupMembersState extends _WorkspaceState<_GroupMembersScreen>
    with _GroupActions<_GroupMembersScreen> {
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: store,
    builder: (context, _) {
      final groupID = widget.groupID;
      final group = store.group(groupID);
      if (!_member(store, group)) return const GLAccessDenied();
      final coord = _coordinator(store, group);
      final members = group!.ids('memberIDs');
      return detailPage(
        title: 'Anggota',
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '${members.length} dari 8 anggota',
                  style: gl(15, w400, 0, GLTheme.text3),
                ),
              ),
              const SizedBox(width: 10),
              GLTap(
                onTap: () => createInvite(groupID),
                child: Container(
                  height: 44,
                  padding: const EdgeInsets.only(left: 12, right: 16),
                  decoration: const ShapeDecoration(
                    color: GLTheme.ink,
                    shape: StadiumBorder(),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      GLIcon(
                        coord ? 'person.badge.plus' : 'lock',
                        size: 19,
                        color: Colors.white,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'Undang anggota',
                        style: gl(14, w600, 0, Colors.white),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          Container(
            padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 14),
            decoration: glBox(Colors.white, 24),
            child: Column(
              children: [
                for (final id in members)
                  GLTap(
                    onTap: () => showMember(groupID, id),
                    child: MergeSemantics(child: _row(group, id)),
                  ),
              ],
            ),
          ),
          if (members.length == 1)
            Container(
              padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
              decoration: glBox(GLTheme.muted, 20),
              child: Text(
                'Belum ada anggota lain. Bagikan kode undangan supaya teman bisa bergabung.',
                style: gl(14, w400, 0, null, 4),
              ),
            ),
          _GroupLeaveButton(onTap: () => leave(groupID)),
        ],
      );
    },
  );

  Widget _row(JsonMap group, String id) {
    final isC = id == group.text('coordinatorID');
    final blocked = store.blockedUserIDs.contains(id);
    final name =
        '${store.user(id)?.text('name') ?? 'Pengguna'}${id == store.currentUserID ? ' (kamu)' : ''}';
    return Container(
      constraints: const BoxConstraints(minHeight: 64),
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: _grHairline,
      child: Row(
        children: [
          GLAvatar(user: store.user(id), size: 44, fontSize: 14),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name, style: gl(16, w600)),
                const SizedBox(height: 2),
                Text(
                  '${isC ? 'Koordinator' : 'Anggota'} · ${_grTaskCount(store, widget.groupID, id, done: false)} tugas aktif',
                  style: gl(13, w400, 0, GLTheme.secondary),
                ),
              ],
            ),
          ),
          if (isC) ...[
            const SizedBox(width: 12),
            const _GroupsSmallChip(
              label: 'Koordinator',
              icon: 'person.badge.shield.checkmark',
              background: GLTheme.mint,
            ),
          ],
          if (blocked) ...[
            const SizedBox(width: 12),
            const _GroupsSmallChip(
              label: 'Diblokir',
              icon: 'nosign',
              background: GLTheme.coral,
            ),
          ],
        ],
      ),
    );
  }
}

class _GroupsSmallChip extends StatelessWidget {
  const _GroupsSmallChip({
    required this.label,
    required this.icon,
    required this.background,
  });
  final String label;
  final String icon;
  final Color background;
  @override
  Widget build(BuildContext context) => Container(
    height: 26,
    padding: const EdgeInsets.only(left: 6, right: 9),
    decoration: ShapeDecoration(
      color: background,
      shape: const StadiumBorder(),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        GLIcon(icon, size: 15),
        const SizedBox(width: 3),
        Text(label, maxLines: 1, style: gl(12, w600)),
      ],
    ),
  );
}

/// `height:52px;border-radius:18px;border:1.5px solid #A8231B` "Keluar dari grup".
class _GroupLeaveButton extends StatelessWidget {
  const _GroupLeaveButton({required this.onTap});
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => GLTap(
    onTap: onTap,
    child: Container(
      height: 52,
      decoration: glBox(
        Colors.transparent,
        18,
        border: GLTheme.danger,
        borderWidth: 1.5,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const GLIcon(
            'rectangle.portrait.and.arrow.right',
            size: 19,
            color: GLTheme.danger,
          ),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              'Keluar dari grup',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: gl(15, w600, 0, GLTheme.danger),
            ),
          ),
        ],
      ),
    ),
  );
}

// MARK: - Settings screen (prototype `isSettings`)

class _GroupSettingsScreen extends _WorkspaceScreen {
  const _GroupSettingsScreen({required super.store, required this.groupID});
  final String groupID;
  @override
  State<_GroupSettingsScreen> createState() => _GroupSettingsState();
}

class _GroupSettingsState extends _WorkspaceState<_GroupSettingsScreen>
    with _GroupActions<_GroupSettingsScreen> {
  final name = TextEditingController();
  final desc = TextEditingController();
  String? error;

  @override
  void initState() {
    super.initState();
    final group = store.group(widget.groupID);
    name.text = group?.text('name') ?? '';
    desc.text = group?.text('description') ?? '';
  }

  @override
  void dispose() {
    name.dispose();
    desc.dispose();
    super.dispose();
  }

  Future<void> _save(JsonMap group) async {
    final trimmed = name.text.trim();
    if (!_coordinator(store, group)) {
      return feedback(
        'Hanya koordinator yang bisa mengubah pengaturan grup.',
        kind: GLToastKind.err,
      );
    }
    String? problem;
    if (trimmed.length < 3) problem = 'Nama grup minimal 3 karakter.';
    if (trimmed.length > 40) problem = 'Nama grup maksimal 40 karakter.';
    if (desc.text.length > 140) problem = 'Deskripsi maksimal 140 karakter.';
    setState(() => error = problem);
    if (problem != null || busy || store.loading) return;
    setState(() => busy = true);
    try {
      await store.mutate('updateGroup', {
        'id': widget.groupID,
        'name': trimmed,
        'course': group.text('course'),
        'description': desc.text.trim(),
      });
      feedback('Pengaturan grup disimpan');
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Widget _input(
    TextEditingController controller, {
    required bool enabled,
    required int max,
    String? hint,
    int lines = 1,
    ValueChanged<String>? onChanged,
  }) => TextField(
    controller: controller,
    enabled: enabled,
    maxLength: max,
    minLines: lines,
    maxLines: lines,
    onChanged: onChanged,
    keyboardType: lines > 1 ? TextInputType.multiline : TextInputType.text,
    textCapitalization: TextCapitalization.sentences,
    cursorColor: GLTheme.ink,
    style: gl(16, w400, 0, GLTheme.ink, lines > 1 ? 3 : 0),
    decoration: glInputDecoration(
      hint: hint,
    ).copyWith(fillColor: GLTheme.background),
  );

  Widget _settingsRow(
    String icon,
    String title, {
    required bool divider,
    required VoidCallback onTap,
  }) => GLTap(
    onTap: onTap,
    child: Container(
      constraints: const BoxConstraints(minHeight: 58),
      decoration: divider ? _grHairline : null,
      child: Row(
        children: [
          GLIcon(icon, size: 22),
          const SizedBox(width: 12),
          Expanded(child: Text(title, style: gl(16, w600))),
          const SizedBox(width: 12),
          const GLIcon('chevron.right', size: 22, color: GLTheme.secondary),
        ],
      ),
    ),
  );

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: store,
    builder: (context, _) {
      final groupID = widget.groupID;
      final group = store.group(groupID);
      if (!_member(store, group)) return const GLAccessDenied();
      final coord = _coordinator(store, group);
      return detailPage(
        title: 'Pengaturan grup',
        children: [
          Container(
            padding: const EdgeInsets.all(18),
            decoration: glBox(Colors.white, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                GLField(
                  'Nama grup',
                  child: _input(name, enabled: coord, max: 40),
                ),
                const SizedBox(height: 14),
                GLField(
                  'Deskripsi',
                  trailing: '${desc.text.length}/140',
                  child: _input(
                    desc,
                    enabled: coord,
                    max: 140,
                    lines: 3,
                    hint: 'Tujuan atau catatan singkat grup',
                    onChanged: (_) => setState(() {}),
                  ),
                ),
                if (error != null) ...[
                  const SizedBox(height: 14),
                  GLFormError(error!),
                ],
                const SizedBox(height: 14),
                if (coord)
                  GLTap(
                    onTap: busy ? null : () => _save(group!),
                    child: Opacity(
                      opacity: busy ? 0.6 : 1,
                      child: Container(
                        height: 50,
                        alignment: Alignment.center,
                        decoration: glBox(GLTheme.ink, 16),
                        child: Text(
                          busy ? 'Menyimpan…' : 'Simpan',
                          style: gl(16, w600, 0, Colors.white),
                        ),
                      ),
                    ),
                  )
                else
                  Row(
                    children: [
                      const GLIcon('lock', size: 18, color: GLTheme.text3),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          'Hanya koordinator yang bisa mengubah pengaturan grup.',
                          style: gl(14, w400, 0, GLTheme.text3),
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 16),
            decoration: glBox(Colors.white, 24),
            child: Column(
              children: [
                _settingsRow(
                  coord ? 'qrcode' : 'lock',
                  'Buat kode undangan',
                  divider: true,
                  onTap: () => createInvite(groupID),
                ),
                _settingsRow(
                  'archivebox',
                  'Proyek diarsipkan',
                  divider: false,
                  onTap: () => Navigator.of(context).pop('archived'),
                ),
              ],
            ),
          ),
          _GroupLeaveButton(
            onTap: () => leave(
              groupID,
              pickCoordinator: () =>
                  open(_GroupMembersScreen(store: store, groupID: groupID)),
            ),
          ),
        ],
      );
    },
  );
}

// MARK: - Sheets

/// "Buat grup" (`sheetNewGroup`) and "Gabung ke grup" (`sheetJoin`).
/// Pops with the created/joined group id.
class _GroupFormSheet extends StatefulWidget {
  const _GroupFormSheet({required this.store, required this.joining});
  final GrouplyStore store;
  final bool joining;
  @override
  State<_GroupFormSheet> createState() => _GroupFormSheetState();
}

class _GroupFormSheetState extends State<_GroupFormSheet> {
  final name = TextEditingController();
  final course = TextEditingController();
  final code = TextEditingController();
  String? error;
  bool saving = false;
  GrouplyStore get store => widget.store;

  @override
  void dispose() {
    name.dispose();
    course.dispose();
    code.dispose();
    super.dispose();
  }

  /// Demo sample codes (Swift lists its seed codes; ours come from the seed).
  List<(String, String)> get samples => [
    for (final invite in store.invites.where(
      (i) =>
          i.text('code').isNotEmpty &&
          !_member(store, store.group(i.text('groupID'))),
    ))
      (
        invite.text('code'),
        switch (_grInviteStatus(store, invite)) {
          'valid' => 'valid',
          'used' => 'sudah dipakai',
          'expired' => 'kedaluwarsa',
          _ => 'dinonaktifkan',
        },
      ),
  ].take(4).toList();

  Future<void> _submit(String action, JsonMap payload, String success) async {
    if (saving || store.loading) return;
    setState(() {
      saving = true;
      error = null;
    });
    try {
      final result = await store.mutate(action, payload);
      final id = result.text('id');
      if (!mounted) return;
      showGLToast(
        context,
        success.replaceFirst(
          '{group}',
          store.group(id)?.text('name') ?? 'grup',
        ),
      );
      Navigator.of(context).pop(id);
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  void _create() {
    final trimmed = name.text.trim();
    if (trimmed.length < 3) {
      return setState(() => error = 'Nama grup minimal 3 karakter.');
    }
    if (trimmed.length > 40) {
      return setState(() => error = 'Nama grup maksimal 40 karakter.');
    }
    final c = course.text.trim();
    _submit('createGroup', {
      'name': trimmed,
      'course': c.isEmpty ? 'Mata kuliah belum diisi' : c,
      'description': '',
    }, 'Grup dibuat. Undang anggota lewat kode undangan.');
  }

  void _join() {
    final raw = code.text.trim();
    final parts = raw.split('/invite/');
    final token = parts.length > 1 ? parts[1] : raw;
    // Cloud tokens are case-sensitive hex; demo codes are uppercase.
    final parsed = store.demoMode ? token.toUpperCase() : token;
    final problem = _grJoinError(store, parsed);
    if (problem != null) return setState(() => error = problem);
    _submit('joinGroup', {'code': parsed}, 'Kamu bergabung ke {group}');
  }

  Widget _field(
    TextEditingController controller,
    String hint, {
    required String key,
    int? max,
    TextStyle? style,
    double height = 50,
    bool code = false,
  }) => Semantics(
    textField: true,
    child: SizedBox(
      height: height,
      child: TextField(
        key: Key(key),
        controller: controller,
        maxLength: max,
        enabled: !saving,
        cursorColor: GLTheme.ink,
        autocorrect: !code,
        textCapitalization: code
            ? TextCapitalization.characters
            : TextCapitalization.sentences,
        style: style ?? gl(16, w400, 0, GLTheme.ink),
        textAlignVertical: TextAlignVertical.center,
        expands: true,
        maxLines: null,
        decoration: glInputDecoration(
          hint: hint,
        ).copyWith(contentPadding: const EdgeInsets.symmetric(horizontal: 16)),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final busy = saving;
    final children = widget.joining
        ? [
            GLField(
              'Kode atau link undangan',
              child: _field(
                code,
                'Contoh: STAT-K1Q',
                key: 'join-code',
                height: 54,
                code: true,
                style: gl(18, w600, 0.06, GLTheme.ink),
              ),
            ),
            if (store.demoMode && samples.isNotEmpty)
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        height: 20,
                        padding: const EdgeInsets.symmetric(horizontal: 7),
                        alignment: Alignment.center,
                        decoration: const ShapeDecoration(
                          color: GLTheme.butter,
                          shape: StadiumBorder(),
                        ),
                        child: Text('DEMO', style: gl(11, w700)),
                      ),
                      const SizedBox(width: 6),
                      Text('Coba kode contoh', style: gl(13, w600)),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final (value, label) in samples)
                        GLTap(
                          onTap: () => setState(() {
                            code.text = value;
                            error = null;
                          }),
                          child: Container(
                            height: 40,
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            alignment: Alignment.center,
                            decoration: const ShapeDecoration(
                              color: Colors.white,
                              shape: StadiumBorder(
                                side: BorderSide(color: GLTheme.border),
                              ),
                            ),
                            child: Text('$value · $label', style: gl(13, w600)),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            if (error != null) GLFormError(error!),
            GLSubmitButton(
              key: const Key('group-save'),
              title: busy ? 'Bergabung…' : 'Gabung',
              busy: busy,
              onPressed: _join,
            ),
          ]
        : [
            GLField(
              'Nama grup',
              required: true,
              child: _field(
                name,
                'Contoh: PPL · Kelompok 2',
                key: 'group-name',
                max: 40,
              ),
            ),
            GLField(
              'Mata kuliah',
              child: _field(
                course,
                'Contoh: Pengembangan Perangkat Lunak',
                key: 'group-course',
                max: 60,
              ),
            ),
            Text(
              'Kamu jadi koordinator. Maksimal 8 anggota. Chat grup dibuat otomatis.',
              style: gl(14, w400, 0, GLTheme.secondary, 4),
            ),
            if (error != null) GLFormError(error!),
            GLSubmitButton(
              key: const Key('group-save'),
              title: busy ? 'Membuat…' : 'Buat grup',
              busy: busy,
              onPressed: _create,
            ),
          ];
    return PopScope(
      canPop: !busy,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final child in children) ...[
            if (child != children.first) const SizedBox(height: 16),
            child,
          ],
        ],
      ),
    );
  }
}
