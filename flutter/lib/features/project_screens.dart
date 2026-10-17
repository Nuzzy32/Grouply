part of 'workspace_screens.dart';

// 1:1 port of Grouply/Features/ProjectViews.swift.

TextStyle _pjDigits(TextStyle style) =>
    style.copyWith(fontFeatures: const [FontFeature.tabularFigures()]);

/// `TaskStatus.projectRing` — pulse ring segment and legend ring colour.
Color _pjRing(String status) => switch (status) {
  'todo' => const Color(0xFFE6C25E),
  'in_progress' => const Color(0xFF86B8D6),
  'in_review' => const Color(0xFFA893EE),
  'needs_revision' => const Color(0xFFE08C94),
  _ => const Color(0xFF62C484),
};

/// `TaskStatus.projectOrder` (ring + legend).
const _pjOrder = ['done', 'in_review', 'in_progress', 'needs_revision', 'todo'];

List<JsonMap> _pjTasks(GrouplyStore store, String projectID) =>
    store.tasks.where((t) => t.text('projectID') == projectID).toList();

/// `DemoStore.reviewWaitHours` — hours since the active submission was sent.
int? _pjReviewWaitHours(JsonMap task) {
  if (task.text('status') != 'in_review') return null;
  final subs = _submissions(task);
  final sent = subs.isEmpty ? null : subs.last.date('createdAt');
  if (sent == null) return null;
  return DateTime.now().difference(sent).inHours;
}

/// `DemoStore.displayName`.
String _pjDisplayName(GrouplyStore store, String id) {
  if (id.isEmpty) return 'Pengguna terhapus';
  if (id == store.currentUserID) return 'Kamu';
  return store.user(id)?.text('name') ?? 'Anggota';
}

/// Inline capsule progress bar (`Capsule().fill(track)` + ink fill).
Widget _pjBar(double value, Color track) => ClipRRect(
  borderRadius: BorderRadius.circular(6),
  child: SizedBox(
    height: 6,
    child: Stack(
      children: [
        Positioned.fill(child: ColoredBox(color: track)),
        FractionallySizedBox(
          widthFactor: value.clamp(0, 1).toDouble(),
          child: const SizedBox.expand(child: ColoredBox(color: GLTheme.ink)),
        ),
      ],
    ),
  ),
);

/// Capsule with 1.5pt ink stroke used by banner/header buttons.
const _pjOutline = ShapeDecoration(
  shape: StadiumBorder(side: BorderSide(color: GLTheme.ink, width: 1.5)),
);

// MARK: - Project card (group detail list)

/// 28pt project status pill (`padding:0 10px 0 7px`, 12/600, 15pt icon).
class _ProjectStatusChip extends StatelessWidget {
  const _ProjectStatusChip(this.status);
  final String status;
  @override
  Widget build(BuildContext context) {
    final (label, bg, icon) = switch (status) {
      'archived' => ('Diarsipkan', 0xFFECEEEB, 'archivebox'),
      'completed' => ('Selesai', 0xFFC9F2D6, 'checkmark.circle'),
      _ => ('Aktif', 0xFFD8EAF4, 'bolt'),
    };
    return Container(
      height: 28,
      padding: const EdgeInsets.only(left: 7, right: 10),
      decoration: ShapeDecoration(
        color: Color(bg),
        shape: const StadiumBorder(),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        spacing: 4,
        children: [
          GLIcon(icon, size: 15),
          Text(label, maxLines: 1, style: gl(12, w600)),
        ],
      ),
    );
  }
}

/// `GLTaskRow` (TaskViews.swift) as used by the project task list.
class _ProjectTaskRow extends StatelessWidget {
  const _ProjectTaskRow({required this.store, required this.task});
  final GrouplyStore store;
  final JsonMap task;
  @override
  Widget build(BuildContext context) {
    final status = task.text('status');
    final due = task.date('dueAt');
    final now = DateTime.now();
    final overdue = due != null && GLFormat.isOverdue(due, status, now);
    final hours = _pjReviewWaitHours(task);
    final assignee = task.text('assigneeID'),
        reviewer = task.text('reviewerID');
    final pair = Row(
      mainAxisSize: MainAxisSize.min,
      spacing: 6,
      children: [
        GLAvatar(user: store.user(assignee), size: 28, fontSize: 11),
        const GLIcon('arrow.right', size: 16, color: GLTheme.secondary),
        GLAvatar(user: store.user(reviewer), size: 28, fontSize: 11),
        Text(
          '${_pjDisplayName(store, assignee)} → ${_pjDisplayName(store, reviewer)}',
          maxLines: 1,
          style: gl(13, w400, 0, GLTheme.text3),
        ),
      ],
    );
    final meta = Row(
      mainAxisSize: MainAxisSize.min,
      spacing: 4,
      children: [
        const GLIcon('clock', size: 17, color: GLTheme.text3),
        Text(
          due == null ? '' : GLFormat.due(due, status, now),
          style: gl(13, w400, 0, GLTheme.text3),
        ),
      ],
    );
    return MergeSemantics(
      child: GLSurface(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: 10,
          children: [
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                GLStatusChip(status: status),
                if (overdue)
                  const GLChip(
                    label: 'Terlambat',
                    icon: 'exclamationmark.circle',
                    background: GLTheme.coral,
                    outlined: true,
                  ),
                if (hours != null && hours > 48)
                  GLChip(
                    label: 'Menunggu $hours jam',
                    icon: 'list.bullet.clipboard',
                    background: GLTheme.lavender,
                    outlined: true,
                  ),
              ],
            ),
            Text(task.text('title'), style: gl(17, w600)),
            // ViewThatFits: one row when pair + meta fit, else stacked.
            SizedBox(
              width: double.infinity,
              child: Wrap(
                alignment: WrapAlignment.spaceBetween,
                spacing: 8,
                runSpacing: 10,
                children: [pair, meta],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// MARK: - Project detail

class _ProjectState extends _WorkspaceState<ProjectScreen> {
  String? filter;
  String? selectedMember;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: store,
    builder: (context, _) {
      final project = store.project(widget.projectID);
      final group = store.group(project?.text('groupID') ?? '');
      if (project == null || !_member(store, group)) {
        return const GLAccessDenied();
      }
      return _content(project, group!);
    },
  );

  Widget _content(JsonMap p, JsonMap group) {
    final tasks = _pjTasks(store, p.text('id'));
    final isCoord = _coordinator(store, group);
    final status = p.text('status');
    final shown = tasks
        .where((t) => filter == null || t.text('status') == filter)
        .toList();
    final stale = tasks.where((t) => (_pjReviewWaitHours(t) ?? 0) > 48).length;
    return GLDetailScaffold(
      title: 'Proyek',
      trailing: GLCircleButton(
        icon: 'ellipsis',
        label: 'Aksi proyek',
        iconSize: 24,
        onTap: () => _actionsSheet(p, group),
      ),
      onRefresh: () async {
        try {
          await store.refresh();
        } catch (_) {
          feedback(
            'Gagal memuat ulang. Periksa koneksi lalu coba lagi.',
            kind: GLToastKind.err,
          );
        }
      },
      children: [
        if (status == 'archived') _archivedBanner(p, group),
        if (status == 'completed') _doneBanner(p, group, isCoord),
        _hero(p, group),
        _pulse(p, group, tasks, isCoord, stale),
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Row(
            spacing: 8,
            children: [
              Expanded(child: Text('Tugas', style: gl(22, w700, -0.02))),
              GLTap(
                key: const ValueKey('add-task'),
                onTap: () => _openNewTask(p, group),
                child: Container(
                  height: 44,
                  padding: const EdgeInsets.only(left: 12, right: 16),
                  decoration: _pjOutline,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    spacing: 4,
                    children: [
                      GLIcon(
                        isCoord && status == 'active' ? 'plus' : 'lock',
                        size: 20,
                      ),
                      Text('Buat tugas', style: gl(15, w600)),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        _bleed(
          Row(
            spacing: 6,
            children: [
              _filterPill('Semua', null),
              _filterPill('Belum dimulai', 'todo'),
              _filterPill('Dikerjakan', 'in_progress'),
              _filterPill('Review', 'in_review'),
              _filterPill('Revisi', 'needs_revision'),
              _filterPill('Selesai', 'done'),
            ],
          ),
        ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: 10,
          children: [
            for (final task in shown)
              GLTap.card(
                onTap: () =>
                    open(TaskScreen(store: store, taskID: task.text('id'))),
                child: _ProjectTaskRow(store: store, task: task),
              ),
            if (shown.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Text(
                  tasks.isNotEmpty
                      ? 'Tidak ada tugas dengan status ini.'
                      : 'Belum ada tugas. ${isCoord ? 'Tambahkan tugas pertama.' : 'Koordinator akan menambahkan tugas.'}',
                  textAlign: TextAlign.center,
                  style: gl(15, w400, 0, GLTheme.secondary),
                ),
              ),
          ],
        ),
      ],
    );
  }

  /// Horizontal scroller whose content may slide into the 20pt screen margin
  /// (Swift `.padding(.horizontal, n)` inside `.padding(.horizontal, -n)`).
  /// ponytail: draws (not hit-tests) into the margin; enough for the look.
  Widget _bleed(Widget row) => SingleChildScrollView(
    scrollDirection: Axis.horizontal,
    clipBehavior: Clip.none,
    child: row,
  );

  // MARK: Banners & hero

  Widget _archivedBanner(JsonMap p, JsonMap group) => Container(
    padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 14),
    decoration: glBox(const Color(0xFFECEEEB), 18),
    child: Row(
      spacing: 10,
      children: [
        const GLIcon('archivebox', size: 20),
        Expanded(
          child: Text(
            'Proyek ini telah diarsipkan. Informasi dan riwayatnya tetap dapat dilihat.',
            style: gl(14, w400, 0, null, 2),
          ),
        ),
        // Flexible only guards huge text sizes; normally sized like `.fixedSize()`.
        Flexible(
          child: GLTap(
            onTap: () => _archive(p, group),
            child: Container(
              height: 44,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              alignment: Alignment.center,
              decoration: _pjOutline,
              child: Text(
                'Pulihkan Proyek',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: gl(13, w600),
              ),
            ),
          ),
        ),
      ],
    ),
  );

  Widget _doneBanner(JsonMap p, JsonMap group, bool isCoord) {
    final text = Text(
      'Proyek ini sudah selesai. Buka kembali proyek untuk mengubah tugas.',
      style: gl(14, w400, 0, null, 2),
    );
    final button = GLTap(
      onTap: () => _reopen(p, group),
      child: Container(
        height: 44,
        padding: const EdgeInsets.only(left: 10, right: 14),
        decoration: _pjOutline,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          spacing: 4,
          children: [
            GLIcon(isCoord ? 'arrow.counterclockwise' : 'lock', size: 17),
            Flexible(child: Text('Buka Kembali Proyek', style: gl(13, w600))),
          ],
        ),
      ),
    );
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 14),
      decoration: glBox(GLTheme.mint, 18),
      // ViewThatFits: icon + 160pt-min text + ~175pt button share a row only
      // when wide enough. ponytail: button width estimated, not measured.
      child: LayoutBuilder(
        builder: (context, c) => c.maxWidth >= 375
            ? Row(
                spacing: 10,
                children: [
                  const GLIcon('checkmark.circle', size: 20),
                  Expanded(child: text),
                  button,
                ],
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: 10,
                children: [
                  Row(
                    spacing: 10,
                    children: [
                      const GLIcon('checkmark.circle', size: 20),
                      Expanded(child: text),
                    ],
                  ),
                  button,
                ],
              ),
      ),
    );
  }

  Widget _hero(JsonMap p, JsonMap group) {
    final members = group.ids('memberIDs');
    final due = p.date('dueAt');
    final description = p.text('description');
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 22, horizontal: 20),
      decoration: glBox(Colors.white, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: 10,
        children: [
          Row(
            spacing: 8,
            children: [
              Flexible(
                child: GLTap(
                  onTap: () => open(
                    GroupScreen(store: store, groupID: group.text('id')),
                  ),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(minHeight: 32),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      spacing: 2,
                      children: [
                        Flexible(
                          child: Text(
                            group.text('name'),
                            style: gl(14, w600, 0, GLTheme.text2),
                          ),
                        ),
                        const GLIcon(
                          'chevron.right',
                          size: 18,
                          color: GLTheme.text2,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const Spacer(),
              _ProjectStatusChip(p.text('status')),
            ],
          ),
          Text(p.text('title'), style: gl(27, w700, -0.025)),
          Row(
            spacing: 6,
            children: [
              const GLIcon('calendar', size: 18, color: GLTheme.text3),
              Flexible(
                child: Text(
                  due == null
                      ? 'Deadline'
                      : 'Deadline ${GLFormat.weekday(due)}, ${GLFormat.date(due)} · 23:59',
                  style: gl(14, w400, 0, GLTheme.text3),
                ),
              ),
            ],
          ),
          Text(
            description.isEmpty ? 'Belum ada deskripsi.' : description,
            style: gl(15, w400, 0, GLTheme.text3, 4),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: SizedBox(
              height: 34,
              width: members.isEmpty ? 0 : 34.0 + (members.length - 1) * 26,
              child: Stack(
                children: [
                  for (final (i, id) in members.indexed)
                    Positioned(
                      left: i * 26.0,
                      child: Semantics(
                        label: _pjDisplayName(store, id),
                        child: ExcludeSemantics(
                          child: Container(
                            foregroundDecoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: Colors.white,
                                width: 2.5,
                              ),
                            ),
                            child: GLAvatar(
                              user: store.user(id),
                              size: 34,
                              fontSize: 11,
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // MARK: Group Pulse

  Widget _pulse(
    JsonMap p,
    JsonMap group,
    List<JsonMap> tasks,
    bool isCoord,
    int stale,
  ) {
    final n = tasks.length;
    int c(String s) => tasks.where((t) => t.text('status') == s).length;
    final stats = [
      ('Total', n),
      ('Selesai', c('done')),
      ('Berjalan', c('in_progress') + c('needs_revision')),
      ('Review', c('in_review')),
      ('Belum mulai', c('todo')),
    ];
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: glBox(Colors.white, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: 16,
        children: [
          Text('Group Pulse', style: gl(20, w700, -0.02)),
          Container(
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
            decoration: glBox(GLTheme.muted, 18),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: 4,
              children: [
                for (final (label, value) in stats)
                  Expanded(
                    child: MergeSemantics(
                      child: Column(
                        spacing: 1,
                        children: [
                          Text(
                            '$value',
                            textAlign: TextAlign.center,
                            style: _pjDigits(gl(19, w800)),
                          ),
                          Text(
                            label,
                            textAlign: TextAlign.center,
                            style: gl(11, w600, 0, GLTheme.text2),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
          if (n > 0)
            LayoutBuilder(
              builder: (context, box) {
                // `flex-wrap` row: 140pt ring + legend with an 18pt gap.
                final wide =
                    box.maxWidth >= 298 &&
                    MediaQuery.textScalerOf(context).scale(1) < 1.6;
                final ring = _PjRing(tasks: tasks);
                final legend = _legend(tasks);
                return wide
                    ? Row(
                        spacing: 18,
                        children: [
                          ring,
                          Expanded(child: legend),
                        ],
                      )
                    : Column(spacing: 18, children: [ring, legend]);
              },
            )
          else
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: SizedBox(
                width: double.infinity,
                child: Text(
                  'Belum ada tugas, jadi belum ada progres. Pulse muncul setelah tugas pertama dibuat.',
                  textAlign: TextAlign.center,
                  style: gl(15, w400, 0, GLTheme.secondary, 4),
                ),
              ),
            ),
          _members(group, tasks),
          if (isCoord && stale > 0)
            Container(
              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 14),
              decoration: glBox(
                GLTheme.lavender,
                18,
                border: GLTheme.ink,
                borderWidth: 1.5,
              ),
              child: Row(
                spacing: 10,
                children: [
                  const GLIcon('list.bullet.clipboard', size: 20),
                  Expanded(
                    child: Text(
                      '$stale tugas menunggu review lebih dari 48 jam',
                      style: gl(14, w500),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _legend(List<JsonMap> tasks) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    spacing: 7,
    children: [
      for (final s in _pjOrder)
        Builder(
          builder: (context) {
            final count = tasks.where((t) => t.text('status') == s).length;
            return Opacity(
              opacity: count > 0 ? 1 : 0.45,
              child: MergeSemantics(
                child: Row(
                  spacing: 8,
                  children: [
                    Container(
                      width: 24,
                      height: 24,
                      decoration: BoxDecoration(
                        color: GLStatus.tint(s),
                        shape: BoxShape.circle,
                        border: Border.all(color: _pjRing(s), width: 2),
                      ),
                      child: GLIcon(GLStatus.icon(s), size: 14),
                    ),
                    Expanded(
                      child: Text(
                        GLStatus.label(s),
                        style: gl(14, w400, 0, GLTheme.text3),
                      ),
                    ),
                    Text('$count', style: _pjDigits(gl(14, w700))),
                  ],
                ),
              ),
            );
          },
        ),
    ],
  );

  Widget _members(JsonMap group, List<JsonMap> tasks) {
    final ids = group.ids('memberIDs');
    final member = selectedMember;
    List<JsonMap> of(String id) =>
        tasks.where((t) => t.text('assigneeID') == id).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: 10,
      children: [
        Text(
          'Anggota · ketuk untuk melihat tugasnya',
          style: gl(13, w600, 0, GLTheme.text2),
        ),
        _bleed(
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              spacing: 6,
              children: [for (final id in ids) _memberButton(id, of(id))],
            ),
          ),
        ),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 250),
          transitionBuilder: (child, animation) => FadeTransition(
            opacity: animation,
            child: SlideTransition(
              position: Tween(
                begin: const Offset(0, 0.04),
                end: Offset.zero,
              ).animate(animation),
              child: child,
            ),
          ),
          child: member != null && ids.contains(member)
              ? KeyedSubtree(
                  key: ValueKey(member),
                  child: _memberPanel(member, of(member)),
                )
              : const SizedBox.shrink(),
        ),
      ],
    );
  }

  Widget _memberButton(String id, List<JsonMap> tasks) {
    final selected = selectedMember == id;
    final done = tasks.where((t) => t.text('status') == 'done').length;
    return Semantics(
      selected: selected,
      child: _PjPress(
        onTap: () => setState(() => selectedMember = selected ? null : id),
        child: AnimatedScale(
          scale: selected ? 1.06 : 1,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOutBack,
          child: SizedBox(
            width: 62,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Column(
                spacing: 5,
                children: [
                  SizedBox(
                    width: 48,
                    height: 48,
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        if (selected) ...[
                          const Positioned(
                            left: -4.5,
                            top: -4.5,
                            right: -4.5,
                            bottom: -4.5,
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                color: GLTheme.ink,
                                shape: BoxShape.circle,
                              ),
                            ),
                          ),
                          const Positioned(
                            left: -2.5,
                            top: -2.5,
                            right: -2.5,
                            bottom: -2.5,
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                color: Colors.white,
                                shape: BoxShape.circle,
                              ),
                            ),
                          ),
                        ],
                        GLAvatar(user: store.user(id), size: 48, fontSize: 14),
                        Positioned(
                          right: -4,
                          bottom: -4,
                          child: Container(
                            constraints: const BoxConstraints(
                              minWidth: 24,
                              minHeight: 20,
                            ),
                            padding: const EdgeInsets.symmetric(horizontal: 5),
                            alignment: Alignment.center,
                            decoration: const ShapeDecoration(
                              color: Colors.white,
                              shape: StadiumBorder(
                                side: BorderSide(
                                  color: GLTheme.border,
                                  strokeAlign: BorderSide.strokeAlignCenter,
                                ),
                              ),
                            ),
                            child: Text(
                              '$done/${tasks.length}',
                              style: gl(11, w700),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  SizedBox(
                    width: 60,
                    child: Text(
                      _pjDisplayName(store, id),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: gl(13, selected ? w700 : w500),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _memberPanel(String id, List<JsonMap> tasks) {
    final name = _pjDisplayName(store, id);
    final done = tasks.where((t) => t.text('status') == 'done').length;
    final now = DateTime.now();
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: glBox(GLTheme.muted, 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: 10,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: 6,
            children: [
              Text(
                '${id == store.currentUserID ? 'Tugasmu' : 'Tugas $name'} di proyek ini',
                style: gl(15, w700),
              ),
              Row(
                spacing: 10,
                children: [
                  Expanded(
                    child: _pjBar(
                      tasks.isEmpty ? 0 : done / tasks.length,
                      Colors.white,
                    ),
                  ),
                  Text(
                    '$done dari ${tasks.length} selesai · ${tasks.length - done} belum',
                    style: gl(13, w600),
                  ),
                ],
              ),
            ],
          ),
          for (final task in tasks)
            GLTap.card(
              onTap: () =>
                  open(TaskScreen(store: store, taskID: task.text('id'))),
              child: Container(
                constraints: const BoxConstraints(minHeight: 52),
                padding: const EdgeInsets.symmetric(
                  vertical: 10,
                  horizontal: 12,
                ),
                decoration: glBox(Colors.white, 16),
                child: Row(
                  spacing: 10,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        spacing: 2,
                        children: [
                          Text(task.text('title'), style: gl(15, w600)),
                          Text(
                            task.date('dueAt') == null
                                ? ''
                                : GLFormat.due(
                                    task.date('dueAt')!,
                                    task.text('status'),
                                    now,
                                  ),
                            style: gl(13, w400, 0, GLTheme.secondary),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      height: 26,
                      padding: const EdgeInsets.only(left: 6, right: 9),
                      decoration: ShapeDecoration(
                        color: GLStatus.tint(task.text('status')),
                        shape: const StadiumBorder(),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        spacing: 3,
                        children: [
                          GLIcon(GLStatus.icon(task.text('status')), size: 15),
                          Text(
                            GLStatus.label(task.text('status')),
                            maxLines: 1,
                            style: gl(12, w600),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          if (tasks.isEmpty)
            Text(
              'Belum ada tugas untuk $name di proyek ini.',
              style: gl(14, w400, 0, GLTheme.text3),
            ),
          Text(
            'Ringkasan pembagian tugas, bukan penilaian kontribusi.',
            style: gl(12, w400, 0, GLTheme.text2),
          ),
        ],
      ),
    );
  }

  Widget _filterPill(String label, String? status) {
    final on = filter == status;
    return Semantics(
      selected: on,
      child: GLTap(
        onTap: () => setState(() => filter = status),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
          height: 44,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          alignment: Alignment.center,
          decoration: ShapeDecoration(
            color: on ? GLTheme.ink : Colors.white,
            shape: const StadiumBorder(
              side: BorderSide(color: GLTheme.ink, width: 1.5),
            ),
          ),
          child: Text(
            label,
            style: gl(14, w600, 0, on ? Colors.white : GLTheme.ink),
          ),
        ),
      ),
    );
  }

  // MARK: Actions sheet

  Future<void> _actionsSheet(JsonMap p, JsonMap group) async {
    final coord = _coordinator(store, group);
    final archived = p.text('status') == 'archived';
    final completed =
        p.text('status') == 'completed' ||
        (archived && p.text('previousStatus') == 'completed');
    Widget row(
      BuildContext ctx,
      String key,
      String label,
      String sub,
      String icon,
    ) => GLTap(
      onTap: () => Navigator.of(ctx).pop(key),
      child: Container(
        constraints: const BoxConstraints(minHeight: 62),
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: GLTheme.border)),
        ),
        child: Row(
          spacing: 12,
          children: [
            GLIcon(icon, size: 22),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: gl(16, w600)),
                  Text(sub, style: gl(13, w400, 0, GLTheme.secondary)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
    final pick = await showGLSheet<String>(
      context,
      title: 'Aksi proyek',
      builder: (ctx) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: 16,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 16),
            decoration: glBox(Colors.white, 24),
            child: Column(
              children: [
                row(
                  ctx,
                  'edit',
                  'Edit proyek',
                  'Nama, deskripsi, deadline',
                  coord ? 'pencil' : 'lock',
                ),
                row(
                  ctx,
                  'status',
                  completed ? 'Buka kembali proyek' : 'Tandai proyek selesai',
                  completed
                      ? 'Status kembali Aktif, riwayat tetap ada'
                      : 'Bisa setelah semua tugas disetujui',
                  coord && !archived
                      ? (completed
                            ? 'arrow.counterclockwise'
                            : 'checkmark.circle')
                      : 'lock',
                ),
                row(
                  ctx,
                  'archive',
                  archived ? 'Pulihkan proyek' : 'Arsipkan proyek',
                  archived
                      ? 'Kembalikan ke daftar proyek'
                      : 'Riwayat tetap tersimpan',
                  coord
                      ? (archived ? 'tray.and.arrow.up' : 'archivebox')
                      : 'lock',
                ),
              ],
            ),
          ),
          if (!coord)
            Row(
              spacing: 6,
              children: [
                const GLIcon('lock', size: 16, color: GLTheme.text3),
                Expanded(
                  child: Text(
                    'Hanya koordinator yang bisa mengubah proyek.',
                    style: gl(13, w400, 0, GLTheme.text3),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
    if (!mounted) return;
    final fresh = store.project(p.text('id')) ?? p;
    switch (pick) {
      case 'edit':
        await _openEdit(fresh, group);
      case 'status':
        completed ? await _reopen(fresh, group) : await _complete(fresh, group);
      case 'archive':
        await _archive(fresh, group);
    }
  }

  // MARK: Rules (prototype copy)

  void _deny(String text) => feedback(text, kind: GLToastKind.err);

  Future<bool> _ask(
    String heading,
    String text,
    String ok, {
    bool info = false,
  }) => showGLConfirm(context, title: heading, text: text, ok: ok, info: info);

  Future<void> _run(String action, String id, String ok) async {
    if (busy || store.loading) return;
    setState(() => busy = true);
    try {
      await store.mutate(action, {'id': id});
      feedback(ok);
    } catch (error) {
      feedback(error.toString(), kind: GLToastKind.err);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _openEdit(JsonMap p, JsonMap group) async {
    if (!_coordinator(store, group)) {
      return _deny('Hanya koordinator yang bisa mengedit proyek.');
    }
    if (p.text('status') == 'archived') {
      await _ask(
        'Proyek diarsipkan',
        'Proyek ini telah diarsipkan. Pulihkan proyek dulu untuk mengubah detailnya.',
        'Mengerti',
        info: true,
      );
      return;
    }
    await _showProjectSheet(this, group, p);
  }

  Future<void> _openNewTask(JsonMap p, JsonMap group) async {
    if (!_coordinator(store, group)) {
      return _deny('Hanya koordinator yang bisa membuat tugas.');
    }
    switch (p.text('status')) {
      case 'archived':
        await _ask(
          'Proyek diarsipkan',
          'Proyek ini telah diarsipkan. Pulihkan proyek dulu untuk menambah tugas.',
          'Mengerti',
          info: true,
        );
      case 'completed':
        if (await _ask(
              'Proyek sudah selesai',
              'Proyek ini sudah selesai. Buka kembali proyek untuk menambah tugas.',
              'Buka kembali proyek',
            ) &&
            mounted) {
          await _reopen(p, group);
        }
      default:
        await _showTaskSheet(this, p, group);
    }
  }

  Future<void> _complete(JsonMap p, JsonMap group) async {
    if (!_coordinator(store, group)) {
      return _deny('Hanya koordinator yang bisa menandai proyek selesai.');
    }
    if (p.text('status') == 'archived') {
      return _deny('Pulihkan proyek dari arsip dulu.');
    }
    final ts = _pjTasks(store, p.text('id'));
    final open = ts.where((t) => t.text('status') != 'done').length;
    if (ts.isEmpty) {
      await _ask(
        'Belum bisa ditandai selesai',
        'Proyek ini belum punya tugas. Tambahkan dan selesaikan tugas dulu.',
        'Mengerti',
        info: true,
      );
      return;
    }
    if (open > 0) {
      final parts =
          [
                ('in_review', 'menunggu review'),
                ('needs_revision', 'perlu revisi'),
                ('in_progress', 'sedang dikerjakan'),
                ('todo', 'belum dimulai'),
              ]
              .map((e) {
                final n = ts.where((t) => t.text('status') == e.$1).length;
                return n > 0 ? '$n ${e.$2}' : null;
              })
              .nonNulls
              .join(', ');
      await _ask(
        'Belum bisa ditandai selesai',
        '$open dari ${ts.length} tugas belum disetujui ($parts). Proyek bisa ditandai selesai setelah semua tugas berstatus Selesai. Tugas tidak akan disetujui otomatis.',
        'Mengerti',
        info: true,
      );
      return;
    }
    if (await _ask(
          'Tandai proyek selesai?',
          'Semua ${ts.length} tugas sudah disetujui. Proyek pindah ke daftar Selesai di grup.',
          'Tandai selesai',
        ) &&
        mounted) {
      await _run(
        'completeProject',
        p.text('id'),
        'Proyek selesai. Kerja bagus, tim!',
      );
    }
  }

  Future<void> _reopen(JsonMap p, JsonMap group) async {
    if (!_coordinator(store, group)) {
      return _deny('Hanya koordinator yang bisa membuka kembali proyek.');
    }
    if (p.text('status') == 'archived') {
      return _deny('Pulihkan proyek dari arsip dulu.');
    }
    if (p.text('status') != 'completed') return;
    if (await _ask(
          'Buka kembali proyek?',
          'Proyek kembali berstatus Aktif. Tugas bisa ditambah, diedit, dan dialihkan lagi. Semua riwayat tugas tetap tersimpan.',
          'Buka kembali',
        ) &&
        mounted) {
      await _run('reopenProject', p.text('id'), 'Proyek aktif kembali');
    }
  }

  Future<void> _archive(JsonMap p, JsonMap group) async {
    if (!_coordinator(store, group)) {
      return _deny('Hanya koordinator yang bisa mengarsipkan proyek.');
    }
    if (p.text('status') == 'archived') {
      final label = p.text('previousStatus') == 'completed'
          ? 'Selesai'
          : 'Aktif';
      return _run(
        'restoreProject',
        p.text('id'),
        'Proyek dipulihkan · status $label',
      );
    }
    if (await _ask(
          'Arsipkan proyek?',
          'Proyek tidak lagi muncul di Beranda dan daftar aktif. Tugas, hasil kerja, dan diskusinya tetap tersimpan dan bisa dibuka dari filter Arsip di grup.',
          'Arsipkan',
        ) &&
        mounted) {
      await _run('archiveProject', p.text('id'), 'Proyek diarsipkan');
    }
  }
}

/// Pulse ring: 112pt track, 16pt segments with a 3pt gap, animated on appear.
class _PjRing extends StatelessWidget {
  const _PjRing({required this.tasks});
  final List<JsonMap> tasks;
  @override
  Widget build(BuildContext context) {
    final n = tasks.length;
    final done = tasks.where((t) => t.text('status') == 'done').length;
    const circumference = 2 * pi * 56;
    var acc = 0.0;
    final segments = <(Color, double, double)>[];
    for (final s in _pjOrder) {
      final len =
          tasks.where((t) => t.text('status') == s).length / n * circumference;
      segments.add((
        _pjRing(s),
        acc / circumference,
        len > 0 ? max(len - 3, 0.01) / circumference : 0,
      ));
      acc += len;
    }
    final sub = '$done dari $n disetujui';
    return Semantics(
      label: sub,
      child: ExcludeSemantics(
        child: SizedBox(
          width: 140,
          height: 140,
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: 1),
            duration: const Duration(milliseconds: 900),
            // 0.1s delay + timingCurve(0.2, 0.8, 0.2, 1) over 0.8s.
            curve: const Interval(0.111, 1, curve: Cubic(0.2, 0.8, 0.2, 1)),
            builder: (context, t, child) =>
                CustomPaint(painter: _PjRingPainter(segments, t), child: child),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                spacing: 1,
                children: [
                  Text(
                    '${(done / n * 100).round()}%',
                    style: _pjDigits(gl(30, w800, -0.04)),
                  ),
                  SizedBox(
                    width: 84,
                    child: Text(
                      sub,
                      textAlign: TextAlign.center,
                      style: gl(12, w400, 0, GLTheme.secondary),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PjRingPainter extends CustomPainter {
  _PjRingPainter(this.segments, this.t);
  final List<(Color, double, double)> segments;
  final double t;
  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromCircle(center: size.center(Offset.zero), radius: 56);
    Paint stroke(Color color) => Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 16;
    canvas.drawCircle(rect.center, 56, stroke(GLTheme.muted));
    for (final (color, start, length) in segments) {
      if (length <= 0) continue;
      final from = t * start, to = t * (start + length);
      if (to <= from) continue;
      canvas.drawArc(
        rect,
        -pi / 2 + from * 2 * pi,
        (to - from) * 2 * pi,
        false,
        stroke(color),
      );
    }
  }

  @override
  bool shouldRepaint(_PjRingPainter old) =>
      old.t != t || old.segments != segments;
}

/// `ProjectMemberButtonStyle`: scale .9 while pressed.
class _PjPress extends StatefulWidget {
  const _PjPress({required this.child, required this.onTap});
  final Widget child;
  final VoidCallback onTap;
  @override
  State<_PjPress> createState() => _PjPressState();
}

class _PjPressState extends State<_PjPress> {
  bool down = false;
  void _set(bool v) => v == down ? null : setState(() => down = v);
  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: widget.onTap,
      onTapDown: (_) => _set(true),
      onTapUp: (_) => _set(false),
      onTapCancel: () => _set(false),
      child: AnimatedScale(
        scale: down ? 0.9 : 1,
        duration: const Duration(milliseconds: 150),
        curve: Curves.easeOut,
        child: widget.child,
      ),
    ),
  );
}

// MARK: - Create / edit project sheet

/// `ProjectEditor` sheet. Create when [project] is null (the group chips let a
/// coordinator pick another group). Returns the store result (`{'id': …}` on
/// create) or null when dismissed; the caller decides navigation.
Future<JsonMap?> _showProjectSheet(
  _WorkspaceState state,
  JsonMap group, [
  JsonMap? project,
]) async {
  if (state.busy || state.store.loading) return null;
  final result = await showGLSheet<JsonMap>(
    state.context,
    title: project == null ? 'Buat proyek' : 'Edit proyek',
    builder: (_) => _ProjectEditor(
      store: state.store,
      groupID: group.text('id'),
      project: project,
    ),
  );
  if (result != null && state.mounted) {
    state.feedback(
      project == null
          ? 'Proyek dibuat. Tambahkan tugas pertama.'
          : 'Perubahan proyek disimpan',
    );
  }
  return result;
}

DateTime _pjDay(int n) {
  final now = DateTime.now();
  return DateTime(now.year, now.month, now.day + n);
}

bool _pjSameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

class _ProjectEditor extends StatefulWidget {
  const _ProjectEditor({
    required this.store,
    required this.groupID,
    this.project,
  });
  final GrouplyStore store;
  final String groupID;
  final JsonMap? project;
  @override
  State<_ProjectEditor> createState() => _ProjectEditorState();
}

class _ProjectEditorState extends State<_ProjectEditor> {
  static const _placeholder = Color(0xFF80868B);
  late final title = TextEditingController(
    text: widget.project?.text('title') ?? '',
  );
  late final description = TextEditingController(
    text: widget.project?.text('description') ?? '',
  );
  late String gid = widget.groupID;
  late DateTime dueAt;
  DateTime? originalDue;
  String? error;
  bool busy = false;

  GrouplyStore get store => widget.store;

  @override
  void initState() {
    super.initState();
    final due = widget.project?.date('dueAt')?.toLocal();
    if (due != null) {
      dueAt = DateTime(due.year, due.month, due.day);
      originalDue = dueAt;
    } else {
      dueAt = _pjDay(14);
    }
  }

  @override
  void dispose() {
    title.dispose();
    description.dispose();
    super.dispose();
  }

  bool _isCoordinator(String id) => _coordinator(store, store.group(id));

  Future<void> _save() async {
    final name = title.text.trim();
    final today = _pjDay(0);
    final unchanged = originalDue != null && _pjSameDay(originalDue!, dueAt);
    final maxDay = DateTime(2027, 12, 31);
    String? problem;
    if (name.length < 3) {
      problem = 'Nama proyek minimal 3 karakter.';
    } else if (name.length > 60) {
      problem = 'Nama proyek maksimal 60 karakter.';
    } else if (description.text.length > 300) {
      problem = 'Deskripsi maksimal 300 karakter.';
    } else if (widget.project != null &&
        store.project(widget.project!.text('id'))?.text('status') ==
            'archived') {
      problem = 'Proyek diarsipkan. Pulihkan dulu untuk mengubah detail.';
    } else if (!(unchanged ||
        (!dueAt.isBefore(today) && !dueAt.isAfter(maxDay)))) {
      problem = 'Pilih deadline yang valid, mulai hari ini.';
    } else if (!_isCoordinator(gid)) {
      problem = 'Hanya koordinator grup ini yang bisa mengelola proyek.';
    }
    if (problem != null) return setState(() => error = problem);
    final due = DateTime(dueAt.year, dueAt.month, dueAt.day, 23, 59);
    setState(() {
      error = null;
      busy = true;
    });
    try {
      final result = await store
          .mutate(widget.project == null ? 'createProject' : 'updateProject', {
            if (widget.project == null)
              'groupID': gid
            else
              'id': widget.project!.text('id'),
            'title': name,
            'description': description.text.trim(),
            'dueAt': due.toUtc().toIso8601String(),
          });
      if (mounted) Navigator.of(context).pop(result);
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _pickDate() async {
    final today = _pjDay(0);
    final first = originalDue != null && originalDue!.isBefore(today)
        ? originalDue!
        : today;
    await showGLSheet<void>(
      context,
      title: 'Pilih tanggal deadline proyek',
      builder: (ctx) => CalendarDatePicker(
        initialDate: dueAt.isBefore(first) ? first : dueAt,
        firstDate: first,
        lastDate: DateTime(2100),
        onDateChanged: (d) {
          setState(() => dueAt = DateTime(d.year, d.month, d.day));
          Navigator.of(ctx).pop();
        },
      ),
    );
  }

  Widget _choice(
    String label,
    bool on,
    VoidCallback onTap, {
    bool fill = false,
  }) => Semantics(
    selected: on,
    child: GLTap(
      onTap: onTap,
      child: Container(
        constraints: const BoxConstraints(minHeight: 44),
        padding: fill
            ? null
            : const EdgeInsets.symmetric(vertical: 8, horizontal: 14),
        alignment: fill ? Alignment.center : null,
        decoration: glBox(
          on ? GLTheme.ink : Colors.white,
          16,
          border: GLTheme.ink,
          borderWidth: 1.5,
        ),
        child: Text(
          label,
          maxLines: fill ? 1 : null,
          overflow: fill ? TextOverflow.ellipsis : null,
          style: gl(14, w600, 0, on ? Colors.white : GLTheme.ink),
        ),
      ),
    ),
  );

  Widget _quick(String label, int days) => Expanded(
    child: _choice(
      label,
      _pjSameDay(dueAt, _pjDay(days)),
      () => setState(() => dueAt = _pjDay(days)),
      fill: true,
    ),
  );

  InputDecoration _input(String hint, {bool multiline = false}) =>
      glInputDecoration(hint: hint).copyWith(
        hintStyle: gl(16, w400, 0, _placeholder),
        contentPadding: multiline
            ? const EdgeInsets.symmetric(horizontal: 16, vertical: 14)
            : null,
      );

  @override
  Widget build(BuildContext context) {
    final creating = widget.project == null;
    final groups = store.groups
        .where((g) => _isCoordinator(g.text('id')))
        .toList();
    final d = dueAt;
    return PopScope(
      canPop: !busy,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 16,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: 8,
            children: [
              Text('Grup', style: gl(14, w600)),
              if (creating)
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final g in groups)
                      _choice(
                        g.text('name'),
                        g.text('id') == gid,
                        () => setState(() => gid = g.text('id')),
                      ),
                  ],
                )
              else
                Text(
                  store.group(gid)?.text('name') ?? '',
                  style: gl(15, w400, 0, GLTheme.text3),
                ),
            ],
          ),
          GLField(
            'Nama proyek',
            required: true,
            trailing: '${title.text.characters.length}/60',
            child: TextField(
              key: const ValueKey('project-title'),
              controller: title,
              maxLength: 60,
              cursorColor: GLTheme.ink,
              style: gl(16, w400, 0, GLTheme.ink),
              textCapitalization: TextCapitalization.sentences,
              decoration: _input('Contoh: Aplikasi Kantin Kampus'),
              onChanged: (_) => setState(() {}),
            ),
          ),
          GLField(
            'Deskripsi',
            trailing: '${description.text.characters.length}/300',
            child: TextField(
              controller: description,
              maxLength: 300,
              minLines: 3,
              maxLines: null,
              keyboardType: TextInputType.multiline,
              cursorColor: GLTheme.ink,
              style: gl(16, w400, 0, GLTheme.ink, 5),
              textCapitalization: TextCapitalization.sentences,
              decoration: _input(
                'Tujuan proyek dan hasil akhir yang diharapkan',
                multiline: true,
              ),
              onChanged: (_) => setState(() {}),
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: 8,
            children: [
              Text.rich(
                const TextSpan(
                  text: 'Deadline',
                  children: [
                    TextSpan(
                      text: ' *',
                      style: TextStyle(color: GLTheme.danger),
                    ),
                  ],
                ),
                style: gl(14, w600),
              ),
              Row(
                spacing: 8,
                children: [
                  _quick('Besok', 1),
                  _quick('3 hari lagi', 3),
                  _quick('Minggu depan', 7),
                ],
              ),
              Container(
                height: 50,
                padding: const EdgeInsets.symmetric(horizontal: 14),
                decoration: glBox(Colors.white, 16, border: GLTheme.border),
                child: Row(
                  spacing: 10,
                  children: [
                    const GLIcon('calendar', size: 20),
                    // Compact DatePicker look: grey capsule with the date.
                    GLTap(
                      label: 'Pilih tanggal deadline proyek',
                      onTap: busy ? null : _pickDate,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 11,
                          vertical: 6,
                        ),
                        decoration: glBox(const Color(0x1F767680), 8),
                        child: Text(
                          '${d.day} ${GLFormat.months[d.month - 1]} ${d.year}',
                          style: gl(17),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Text(
                '${GLFormat.weekday(d)}, ${GLFormat.date(d)} · 23:59',
                style: gl(13, w400, 0, GLTheme.secondary),
              ),
            ],
          ),
          if (error != null) GLFormError(error!),
          GLSubmitButton(
            key: const ValueKey('project-save'),
            title: busy
                ? 'Menyimpan…'
                : (error?.contains('Gagal') ?? false)
                ? 'Coba lagi'
                : creating
                ? 'Buat proyek'
                : 'Simpan perubahan',
            busy: busy,
            onPressed: _save,
          ),
        ],
      ),
    );
  }
}
