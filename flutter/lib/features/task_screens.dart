part of 'workspace_screens.dart';

// 1:1 port of Grouply/Features/TaskViews.swift (MyTasksView, GLTaskRow,
// TaskDetailView and its sheets). Store actions and payload keys are unchanged.

// MARK: - Store helpers (TaskViews.swift `extension DemoStore`)

/// `store.displayName`: "Kamu" for the current user, "Pengguna terhapus" for deleted accounts.
String _taskName(GrouplyStore store, String id) {
  if (id.isEmpty) return 'Pengguna terhapus';
  return id == store.currentUserID
      ? 'Kamu'
      : store.user(id)?.text('name') ?? 'Anggota';
}

/// Plain user name (Swift `store.user(id)?.name ?? fallback`).
String _taskUserName(GrouplyStore store, String id, String fallback) =>
    store.user(id)?.text('name') ?? fallback;

DateTime _taskDue(JsonMap task) => task.date('dueAt') ?? DateTime(9999);

/// Hours since the active submission was sent, while a task waits in review.
int? _taskWaitHours(JsonMap task, DateTime now) {
  if (task.text('status') != 'in_review') return null;
  final sent = _submissions(task).lastOrNull?.date('createdAt');
  return sent == null ? null : now.difference(sent).inHours;
}

/// `store.messages(groupID:taskID:)`: thread rows, own unsent rows included.
List<JsonMap> _taskMessages(GrouplyStore store, String groupID, String taskID) {
  final rows = store.messages.where((m) {
    final delivery = m.text('delivery');
    return m.text('groupID') == groupID &&
        m.text('taskID') == taskID &&
        (delivery.isEmpty ||
            delivery == 'sent' ||
            m.text('senderID') == store.currentUserID);
  }).toList();
  rows.sort(
    (a, b) => (a.date('createdAt') ?? DateTime(1970)).compareTo(
      b.date('createdAt') ?? DateTime(1970),
    ),
  );
  return rows;
}

int _taskCommentCount(GrouplyStore store, JsonMap task) {
  final groupID = store.project(task.text('projectID'))?.text('groupID') ?? '';
  return _taskMessages(
    store,
    groupID,
    task.text('id'),
  ).where((m) => m.text('kind') == 'text' || m.text('kind').isEmpty).length;
}

/// "Rab 14 Okt, 15:20".
String _taskStamp(DateTime? date) => date == null
    ? ''
    : '${GLFormat.weekday(date)} ${GLFormat.date(date)}, ${GLFormat.time(date)}';

/// Prototype `projLock`.
String? _taskProjectLock(JsonMap project, [String verb = 'mengubah tugas']) =>
    switch (project.text('status')) {
      'archived' =>
        'Proyek ini telah diarsipkan. Pulihkan proyek dulu untuk $verb.',
      'completed' =>
        'Proyek ini sudah selesai. Buka kembali proyek untuk $verb.',
      _ => null,
    };

/// Prototype `editLock`: (dialog title, message) when editing is not allowed.
(String, String)? _taskEditLock(GrouplyStore store, JsonMap task) {
  final project = store.project(task.text('projectID'));
  if (project == null) {
    return ('Tidak bisa mengedit', 'Proyek tidak ditemukan.');
  }
  if (!_coordinator(store, store.group(project.text('groupID')))) {
    return (
      'Tidak bisa mengedit',
      'Hanya koordinator yang bisa mengedit detail tugas.',
    );
  }
  final status = project.text('status');
  if (status == 'archived') {
    return ('Proyek diarsipkan', _taskProjectLock(project, 'mengedit tugas')!);
  }
  if (status == 'completed') {
    return (
      'Proyek sudah selesai',
      _taskProjectLock(project, 'mengedit tugas')!,
    );
  }
  if (task.text('status') == 'in_review') {
    return (
      'Sedang Menunggu Review',
      'Edit dikunci sementara karena hasil pekerjaan sedang diperiksa. Coba lagi setelah review selesai.',
    );
  }
  if (task.text('status') == 'done') {
    return (
      'Tugas sudah selesai',
      'Tugas yang sudah disetujui tidak bisa diedit.',
    );
  }
  return null;
}

/// Deadlines are stored as 23:59 on the chosen day.
DateTime _taskEndOfDay(DateTime d) {
  final l = d.toLocal();
  return DateTime(l.year, l.month, l.day, 23, 59);
}

bool _taskSameDay(DateTime a, DateTime b) {
  final x = a.toLocal(), y = b.toLocal();
  return x.year == y.year && x.month == y.month && x.day == y.day;
}

// Getters, not finals: a final would freeze the colour of the first theme.
Color get _taskTrack => GLTheme.chip;
final _taskOutline = StadiumBorder(
  side: BorderSide(color: GLTheme.ink, width: 1.5),
);

Widget _taskRequiredLabel(String label, {bool required = true}) => Text.rich(
  TextSpan(
    text: label,
    children: [
      if (required)
        TextSpan(
          text: ' *',
          style: TextStyle(color: GLTheme.danger),
        ),
    ],
  ),
  style: gl(14, w600),
);

Future<void> _taskLaunch(BuildContext context, String link) async {
  void fail(String text) {
    if (context.mounted) showGLToast(context, text, kind: GLToastKind.err);
  }

  if (!_https(link)) return fail('Hanya tautan HTTPS yang valid dapat dibuka.');
  try {
    if (!await launchUrl(
      Uri.parse(link),
      mode: LaunchMode.externalApplication,
    )) {
      fail('Tautan tidak dapat dibuka.');
    }
  } catch (_) {
    fail('Tautan tidak dapat dibuka.');
  }
}

// MARK: - GLTaskRow

/// Task card used on Tugas Saya and Project Detail (prototype `vmTask`).
class _TaskRow extends StatelessWidget {
  const _TaskRow({
    required this.store,
    required this.task,
    this.showProject = false,
  });
  final GrouplyStore store;
  final JsonMap task;
  final bool showProject;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final status = task.text('status');
    final due = _taskDue(task);
    final hours = _taskWaitHours(task, now);
    final pair = Row(
      mainAxisSize: MainAxisSize.min,
      spacing: 6,
      children: [
        GLAvatar(
          user: store.user(task.text('assigneeID')),
          size: 28,
          fontSize: 11,
        ),
        GLIcon('arrow.right', size: 16, color: GLTheme.secondary),
        GLAvatar(
          user: store.user(task.text('reviewerID')),
          size: 28,
          fontSize: 11,
        ),
        Flexible(
          child: Text(
            '${_taskName(store, task.text('assigneeID'))} → ${_taskName(store, task.text('reviewerID'))}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: gl(13, w400, 0, GLTheme.text3),
          ),
        ),
      ],
    );
    final meta = Row(
      mainAxisSize: MainAxisSize.min,
      spacing: 12,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          spacing: 4,
          children: [
            GLIcon('clock', size: 17, color: GLTheme.text3),
            Text(
              GLFormat.due(due, status, now),
              style: gl(13, w400, 0, GLTheme.text3),
            ),
          ],
        ),
        if (showProject)
          Row(
            mainAxisSize: MainAxisSize.min,
            spacing: 4,
            children: [
              GLIcon('bubble.left', size: 17, color: GLTheme.text3),
              Text(
                '${_taskCommentCount(store, task)}',
                style: gl(13, w400, 0, GLTheme.text3),
              ),
            ],
          ),
      ],
    );
    return MergeSemantics(
      child: Container(
        width: double.infinity,
        padding: EdgeInsets.all(16),
        decoration: glBox(GLTheme.surface, 24, shadow: true),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: 10,
          children: [
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                GLStatusChip(status: status),
                if (GLFormat.isOverdue(due, status, now))
                  GLChip(
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
            if (showProject)
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: 3,
                children: [
                  Text(task.text('title'), style: gl(17, w600)),
                  Text(
                    store.project(task.text('projectID'))?.text('title') ?? '',
                    style: gl(13, w400, 0, GLTheme.secondary),
                  ),
                ],
              )
            else
              Text(task.text('title'), style: gl(17, w600)),
            // ViewThatFits: one row (pair … meta) or stacked.
            SizedBox(
              width: double.infinity,
              child: Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
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

// MARK: - MyTasksView

class _MyTasksState extends _WorkspaceState<MyTasksScreen> {
  String filter = 'all';
  Widget _chip(String key, String label, int n) {
    final on = filter == key;
    return Semantics(
      button: true,
      selected: on,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => setState(() => filter = key),
        child: AnimatedContainer(
          duration: Duration(milliseconds: 200),
          curve: Curves.easeOut,
          height: 44,
          padding: EdgeInsets.only(left: 16, right: 7),
          decoration: ShapeDecoration(
            color: on ? GLTheme.ink : GLTheme.surface,
            shape: _taskOutline,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            spacing: 8,
            children: [
              Text(
                label,
                style: gl(15, w600, 0, on ? GLTheme.onInk : GLTheme.ink),
              ),
              Container(
                constraints: BoxConstraints(minWidth: 28, minHeight: 28),
                padding: EdgeInsets.symmetric(horizontal: 8),
                decoration: ShapeDecoration(
                  color: on
                      ? GLTheme.mint
                      // muted vanishes on a dark surface pill
                      : (GLTheme.dark ? GLTheme.segment : GLTheme.muted),
                  shape: StadiumBorder(),
                ),
                child: Center(
                  widthFactor: 1,
                  heightFactor: 1,
                  child: Text('$n', style: gl(13, w400, 0, GLTheme.ink)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: store,
    builder: (context, _) {
      final now = DateTime.now();
      final me = store.currentUserID;
      final live = store.tasks.where((task) {
        final p = store.project(task.text('projectID'));
        return p != null &&
            p.text('status') != 'archived' &&
            _member(store, store.group(p.text('groupID')));
      }).toList();
      final mine = live.where((t) => t.text('assigneeID') == me).toList();
      final toReview = live
          .where(
            (t) =>
                t.text('reviewerID') == me && t.text('status') == 'in_review',
          )
          .toList();
      bool overdue(JsonMap t) =>
          GLFormat.isOverdue(_taskDue(t), t.text('status'), now);
      final action = [
        ...mine.where(
          (t) =>
              t.text('status') == 'needs_revision' ||
              (overdue(t) && t.text('status') != 'in_review'),
        ),
        ...toReview,
      ];
      final ids = action.map((t) => t.text('id')).toSet();
      final soon = mine
          .where(
            (t) =>
                !ids.contains(t.text('id')) &&
                GLFormat.isSoon(_taskDue(t), t.text('status'), now) &&
                t.text('status') != 'in_review',
          )
          .toList();
      final soonIDs = soon.map((t) => t.text('id')).toSet();
      final rest = mine
          .where(
            (t) =>
                !ids.contains(t.text('id')) &&
                !soonIDs.contains(t.text('id')) &&
                t.text('status') != 'done',
          )
          .toList();
      final done = mine.where((t) => t.text('status') == 'done').toList();
      final active = mine
          .where((t) => t.text('status') == 'in_progress')
          .toList();
      final sections = <(String, List<JsonMap>)>[
        ...switch (filter) {
          'review' => [('Perlu review', toReview)],
          'active' => [('Dikerjakan', active)],
          'done' => [('Selesai', done)],
          _ => [
            ('Perlu tindakan', action),
            ('Segera', soon),
            ('Sedang berjalan', rest),
            ('Selesai', done),
          ].where((s) => s.$2.isNotEmpty),
        },
      ];
      final none = mine.isEmpty && toReview.isEmpty;
      return Scaffold(
        backgroundColor: GLTheme.background,
        body: SafeArea(
          bottom: false,
          child: RefreshIndicator.adaptive(
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
            child: ListView(
              physics: AlwaysScrollableScrollPhysics(
                parent: BouncingScrollPhysics(),
              ),
              padding: EdgeInsets.only(
                top: 10,
                bottom: MediaQuery.paddingOf(context).bottom + 16,
              ),
              children: [
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: 20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    spacing: 4,
                    children: [
                      Semantics(
                        header: true,
                        child: Text('Tugas Saya', style: gl(34, w700, -0.03)),
                      ),
                      Text(
                        none
                            ? 'Belum ada tugas untukmu'
                            : '${mine.length - done.length} terbuka · ${toReview.length} menunggu review kamu',
                        style: gl(15, w400, 0, GLTheme.secondary),
                      ),
                    ],
                  ),
                ),
                SizedBox(height: 18),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  padding: EdgeInsets.symmetric(horizontal: 20),
                  child: Row(
                    spacing: 8,
                    children: [
                      _chip('all', 'Semua', mine.length + toReview.length),
                      _chip('review', 'Perlu review', toReview.length),
                      _chip('active', 'Dikerjakan', active.length),
                      _chip('done', 'Selesai', done.length),
                    ],
                  ),
                ),
                SizedBox(height: 18),
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: 20),
                  child: none
                      ? GLEmptyState(
                          title: 'Belum ada tugas',
                          message:
                              'Belum ada tugas yang ditugaskan ke kamu atau menunggu review kamu. Saat koordinator membagi tugas, semuanya muncul di sini.',
                          icon: 'checkmark.circle',
                          tint: GLTheme.sky,
                        )
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          spacing: 22,
                          children: [
                            for (final (title, items) in sections)
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                spacing: 10,
                                children: [
                                  Row(
                                    spacing: 8,
                                    children: [
                                      Text(
                                        title.toUpperCase(),
                                        style: gl(
                                          14,
                                          w700,
                                          0.04,
                                          GLTheme.text2,
                                        ),
                                      ),
                                      Text(
                                        '${items.length}',
                                        style: gl(
                                          14,
                                          w400,
                                          0,
                                          GLTheme.secondary,
                                        ),
                                      ),
                                    ],
                                  ),
                                  for (final task in items)
                                    GLTap.card(
                                      onTap: () => open(
                                        TaskScreen(
                                          store: store,
                                          taskID: task.text('id'),
                                        ),
                                      ),
                                      child: _TaskRow(
                                        store: store,
                                        task: task,
                                        showProject: true,
                                      ),
                                    ),
                                  if (items.isEmpty)
                                    Padding(
                                      padding: EdgeInsets.symmetric(
                                        vertical: 22,
                                      ),
                                      child: Text(
                                        'Tidak ada tugas di kategori ini.',
                                        textAlign: TextAlign.center,
                                        style: gl(
                                          15,
                                          w400,
                                          0,
                                          GLTheme.secondary,
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                          ],
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

// MARK: - TaskDetailView (prototype `isTask`)

class _TaskState extends _WorkspaceState<TaskScreen> {
  int tab = 0; // 0 overview, 1 submission, 2 discussion
  bool refreshing = false;
  final revealed = <String>{};

  Future<bool> _act(String action, JsonMap payload, String success) async {
    if (busy || store.loading) return false;
    setState(() => busy = true);
    try {
      await store.mutate(action, payload);
      feedback(success);
      return true;
    } catch (error) {
      feedback('$error', kind: GLToastKind.err);
      return false;
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  int _version(JsonMap task) => task.number('version').toInt();

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: store,
    builder: (context, _) {
      final task = store.task(widget.taskID);
      final project = store.project(task?.text('projectID') ?? '');
      final group = store.group(project?.text('groupID') ?? '');
      if (task == null || project == null || !_member(store, group)) {
        return GLAccessDenied();
      }
      return _content(task, project, group!);
    },
  );

  Widget _content(JsonMap task, JsonMap project, JsonMap group) {
    final readOnly = project.text('status') != 'active';
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    final body = switch (tab) {
      0 => Padding(
        padding: EdgeInsets.symmetric(horizontal: 20),
        child: _overview(task, project, group),
      ),
      1 => Padding(
        padding: EdgeInsets.symmetric(horizontal: 20),
        child: _submissionsTab(task),
      ),
      _ => _discussion(task, project),
    };
    final scroll = RefreshIndicator.adaptive(
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
      child: CustomScrollView(
        physics: AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.fromLTRB(20, 4, 20, 0),
              child: GLDetailHeader(
                'Tugas',
                trailing: GLCircleButton(
                  icon: 'ellipsis',
                  label: 'Opsi tugas',
                  iconSize: 24,
                  onTap: () => _actions(task, project, group),
                ),
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.fromLTRB(22, 16, 22, 14),
              child: _heading(task, project),
            ),
          ),
          PinnedHeaderSliver(
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: 20),
              child: _tabs(task),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.only(top: 14, bottom: tab == 2 ? 16 : 120),
              child: body,
            ),
          ),
        ],
      ),
    );
    final Widget footer;
    if (tab != 2) {
      footer = SizedBox.shrink();
    } else if (readOnly) {
      footer = MergeSemantics(
        child: Container(
          width: double.infinity,
          padding: EdgeInsets.fromLTRB(16, 12, 16, 8 + bottomInset),
          decoration: BoxDecoration(
            color: GLTheme.background,
            border: Border(top: BorderSide(color: GLTheme.border)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            spacing: 8,
            children: [
              GLIcon('lock', size: 18, color: GLTheme.text3),
              Flexible(
                child: Text(
                  project.text('status') == 'archived'
                      ? 'Diskusi hanya-baca karena proyek diarsipkan.'
                      : 'Diskusi hanya-baca karena proyek sudah selesai.',
                  textAlign: TextAlign.center,
                  style: gl(14, w500, 0, GLTheme.text3),
                ),
              ),
            ],
          ),
        ),
      );
    } else {
      footer = _TaskComposer(
        store: store,
        groupID: project.text('groupID'),
        taskID: widget.taskID,
      );
    }
    return Scaffold(
      backgroundColor: GLTheme.background,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            Expanded(
              child: Stack(
                children: [
                  Positioned.fill(child: scroll),
                  if (tab != 2)
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      child: _ctaBar(task, project, bottomInset),
                    ),
                ],
              ),
            ),
            footer,
          ],
        ),
      ),
    );
  }

  // MARK: Heading & tabs

  Widget _heading(JsonMap task, JsonMap project) {
    final now = DateTime.now();
    final status = task.text('status');
    final hours = _taskWaitHours(task, now);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: 8,
      children: [
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            _headerChip(
              GLStatus.label(status),
              GLStatus.icon(status),
              GLStatus.tint(status),
              false,
            ),
            if (GLFormat.isOverdue(_taskDue(task), status, now))
              _headerChip(
                'Terlambat',
                'exclamationmark.circle',
                GLTheme.coral,
                true,
              ),
            if (hours != null && hours > 48)
              _headerChip(
                'Menunggu $hours jam',
                'list.bullet.clipboard',
                GLTheme.lavender,
                true,
              ),
          ],
        ),
        Semantics(
          header: true,
          child: Text(task.text('title'), style: gl(28, w700, -0.03)),
        ),
        GLTap(
          label: 'Buka proyek',
          onTap: () =>
              open(ProjectScreen(store: store, projectID: project.text('id'))),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: 36),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              spacing: 2,
              children: [
                Flexible(
                  child: Text(
                    project.text('title'),
                    style: gl(14, w400, 0, GLTheme.text3),
                  ),
                ),
                GLIcon('chevron.right', size: 18, color: GLTheme.text3),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _headerChip(String label, String icon, Color bg, bool outlined) =>
      AnimatedContainer(
        duration: Duration(milliseconds: 300),
        curve: Curves.easeOut,
        height: 30,
        padding: EdgeInsets.only(left: 9, right: 12),
        decoration: ShapeDecoration(
          color: bg,
          shape: outlined ? _taskOutline : StadiumBorder(),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          spacing: 5,
          children: [
            GLIcon(icon, size: 17),
            Text(label, maxLines: 1, style: gl(13, w600)),
          ],
        ),
      );

  Widget _tabs(JsonMap task) {
    final items = [
      (0, 'Ringkasan', 0),
      (1, 'Hasil kerja', _submissions(task).length),
      (2, 'Diskusi', _taskCommentCount(store, task)),
    ];
    return Container(
      padding: EdgeInsets.all(4),
      decoration: glBox(_taskTrack, 18),
      child: Row(
        spacing: 2,
        children: [
          for (final (key, label, count) in items)
            Expanded(
              child: Semantics(
                button: true,
                selected: tab == key,
                label: count > 0 && key != 0 ? '$label, $count' : label,
                child: ExcludeSemantics(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => setState(() => tab = key),
                    child: AnimatedContainer(
                      duration: Duration(milliseconds: 180),
                      curve: Curves.easeOut,
                      height: 44,
                      padding: EdgeInsets.symmetric(horizontal: 4),
                      decoration: ShapeDecoration(
                        color: tab == key
                            ? GLTheme.segment
                            : Colors.transparent,
                        shape: glShape(14),
                        shadows: tab == key
                            ? [
                                BoxShadow(
                                  color: Color(0x14000000),
                                  blurRadius: 3,
                                  offset: Offset(0, 1),
                                ),
                              ]
                            : null,
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        spacing: 5,
                        children: [
                          Flexible(
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Text(
                                label,
                                maxLines: 1,
                                style: gl(14, w600),
                              ),
                            ),
                          ),
                          if (count > 0 && key != 0)
                            Container(
                              constraints: BoxConstraints(
                                minWidth: 20,
                                minHeight: 20,
                              ),
                              padding: EdgeInsets.symmetric(horizontal: 6),

                              decoration: ShapeDecoration(
                                color: GLTheme.lavender,
                                shape: StadiumBorder(),
                              ),
                              child: Center(
                                widthFactor: 1,
                                heightFactor: 1,
                                child: Text('$count', style: gl(12, w600)),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  // MARK: Overview tab

  Widget _overview(JsonMap task, JsonMap project, JsonMap group) {
    final status = task.text('status');
    final last = _submissions(task).lastOrNull;
    final feedbackText = last?.text('feedback') ?? '';
    Widget infoText(String label, String value) => Expanded(
      child: MergeSemantics(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: gl(13, w400, 0, GLTheme.secondary)),
            Text(value, style: gl(16, w600)),
          ],
        ),
      ),
    );
    final canReassign = _coordinator(store, group) && status != 'in_review';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 12,
      children: [
        if (status == 'needs_revision' &&
            last != null &&
            feedbackText.isNotEmpty)
          MergeSemantics(
            child: Container(
              padding: EdgeInsets.symmetric(vertical: 16, horizontal: 18),
              decoration: glBox(GLTheme.coral, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: 6,
                children: [
                  Row(
                    spacing: 6,
                    children: [
                      GLIcon('arrow.uturn.backward', size: 18),
                      Flexible(
                        child: Text(
                          '${_taskName(store, last.text('reviewerID').isEmpty ? task.text('reviewerID') : last.text('reviewerID'))} meminta revisi',
                          style: gl(14, w700),
                        ),
                      ),
                    ],
                  ),
                  Text(feedbackText, style: gl(15, w400, 0, null, 3)),
                ],
              ),
            ),
          ),
        Container(
          padding: EdgeInsets.symmetric(vertical: 4, horizontal: 18),
          decoration: glBox(GLTheme.surface, 24),
          child: Column(
            children: [
              Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Row(
                  spacing: 12,
                  children: [
                    GLAvatar(
                      user: store.user(task.text('assigneeID')),
                      size: 40,
                      fontSize: 13,
                    ),
                    infoText(
                      'Pelaksana',
                      _taskName(store, task.text('assigneeID')),
                    ),
                    if (status != 'done' && project.text('status') == 'active')
                      GLTap(
                        label: 'Alihkan pelaksana',
                        onTap: () => _openReassign(task, project, group),
                        child: Container(
                          height: 44,
                          padding: EdgeInsets.only(left: 10, right: 12),
                          decoration: ShapeDecoration(shape: _taskOutline),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            spacing: 4,
                            children: [
                              GLIcon(
                                canReassign ? 'arrow.left.arrow.right' : 'lock',
                                size: 18,
                              ),
                              Text('Alihkan', style: gl(14, w600)),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              GLHairline(),
              Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Row(
                  spacing: 12,
                  children: [
                    GLAvatar(
                      user: store.user(task.text('reviewerID')),
                      size: 40,
                      fontSize: 13,
                    ),
                    infoText(
                      'Reviewer',
                      _taskName(store, task.text('reviewerID')),
                    ),
                  ],
                ),
              ),
              GLHairline(),
              Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Row(
                  spacing: 12,
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: GLTheme.muted,
                        shape: BoxShape.circle,
                      ),
                      child: GLIcon('clock', size: 20),
                    ),
                    infoText(
                      'Deadline',
                      GLFormat.due(_taskDue(task), status, DateTime.now()),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        Container(
          padding: EdgeInsets.all(18),
          decoration: glBox(GLTheme.surface, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: 8,
            children: [
              Text('DESKRIPSI', style: gl(13, w700, 0.04, GLTheme.text2)),
              SelectableText(
                task.text('description').isEmpty
                    ? 'Belum ada deskripsi.'
                    : task.text('description'),
                style: gl(15, w400, 0, GLTheme.ink, 5),
              ),
            ],
          ),
        ),
        GLTap.card(
          onTap: () => setState(() => tab = 2),
          child: MergeSemantics(
            child: Container(
              padding: EdgeInsets.symmetric(vertical: 16, horizontal: 18),
              decoration: glBox(GLTheme.lavender, 24),
              child: Row(
                spacing: 14,
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: glBox(
                      Colors.transparent,
                      16,
                      border: GLTheme.ink,
                      borderWidth: 1.5,
                    ),
                    child: GLIcon('bubble.left.and.bubble.right', size: 22),
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      spacing: 1,
                      children: [
                        Text('Diskusi tugas ini', style: gl(16, w600)),
                        Text(
                          '${_taskCommentCount(store, task)} komentar · khusus tugas ini',
                          style: gl(13, w400, 0, GLTheme.text3),
                        ),
                      ],
                    ),
                  ),
                  GLIcon('chevron.right', size: 22),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  // MARK: Submission tab

  Widget _submissionsTab(JsonMap task) {
    final subs = _submissions(task);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 12,
      children: [
        for (final sub in subs.reversed)
          _submissionCard(sub, task, subs.length),
        if (subs.isEmpty)
          Container(
            padding: EdgeInsets.symmetric(vertical: 28, horizontal: 20),
            decoration: glBox(GLTheme.surface, 24),
            child: Column(
              spacing: 8,
              children: [
                Container(
                  width: 52,
                  height: 52,
                  decoration: glBox(GLTheme.butter, 18),
                  child: GLIcon('archivebox', size: 26),
                ),
                Text(
                  'Belum ada hasil kerja',
                  textAlign: TextAlign.center,
                  style: gl(17, w600),
                ),
                Text(
                  'Pelaksana mengirim catatan dan maksimal 5 link https. Semua revisi tersimpan di sini.',
                  textAlign: TextAlign.center,
                  style: gl(14, w400, 0, GLTheme.secondary, 4),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _submissionCard(JsonMap sub, JsonMap task, int count) {
    final decision = sub['decision'];
    final pending =
        decision == null &&
        sub.number('revision') == count &&
        task.text('status') == 'in_review';
    final (label, icon, color) = decision == 'approved'
        ? ('Disetujui', 'checkmark.circle', GLTheme.mint)
        : decision != null
        ? ('Perlu revisi', 'arrow.uturn.backward', GLTheme.coral)
        : (pending ? 'Menunggu review' : 'Terkirim', 'eye', GLTheme.lavender);
    final mine = task.text('assigneeID') == store.currentUserID;
    final feedbackText = sub.text('feedback');
    final divider = BoxDecoration(
      border: Border(top: BorderSide(color: GLTheme.border)),
    );
    return Container(
      padding: EdgeInsets.all(18),
      decoration: glBox(GLTheme.surface, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 12,
        children: [
          Row(
            spacing: 8,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  spacing: 1,
                  children: [
                    Text(
                      'Revisi ${sub.number('revision')}',
                      style: gl(16, w700),
                    ),
                    Text(
                      '${_taskName(store, sub.text('authorID'))} · ${_taskStamp(sub.date('createdAt'))}',
                      style: gl(13, w400, 0, GLTheme.secondary),
                    ),
                  ],
                ),
              ),
              GLChip(label: label, icon: icon, background: color, fontSize: 12),
            ],
          ),
          SelectableText(
            sub.text('note'),
            style: gl(15, w400, 0, GLTheme.ink, 4),
          ),
          for (final link in sub.ids('links'))
            _TaskLinkRow(url: link, external: true),
          if (feedbackText.isNotEmpty)
            Container(
              padding: EdgeInsets.only(top: 12),
              decoration: divider,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: 4,
                children: [
                  Text(
                    'Catatan ${_taskName(store, sub.text('reviewerID').isEmpty ? task.text('reviewerID') : sub.text('reviewerID'))}',
                    style: gl(13, w600, 0, GLTheme.secondary),
                  ),
                  Text(feedbackText, style: gl(15, w400, 0, null, 3)),
                ],
              ),
            ),
          if (pending && task.text('reviewerID') != store.currentUserID)
            Container(
              padding: EdgeInsets.only(top: 12),
              decoration: divider,
              child: LayoutBuilder(
                builder: (context, box) {
                  final text = Text(
                    mine
                        ? 'Kamu tidak bisa menyetujui hasil kerjamu sendiri.'
                        : 'Hanya ${_taskName(store, task.text('reviewerID'))} yang bisa mereview.',
                    style: gl(13, w400, 0, GLTheme.text3, 2),
                  );
                  final button = _lockButton(task);
                  // ViewThatFits: side by side when the text keeps ≥150pt.
                  return box.maxWidth >= 270
                      ? Row(
                          spacing: 10,
                          children: [
                            Expanded(child: text),
                            button,
                          ],
                        )
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          spacing: 10,
                          children: [text, button],
                        );
                },
              ),
            ),
        ],
      ),
    );
  }

  Widget _lockButton(JsonMap task) => GLTap(
    label: 'Setujui, terkunci',
    onTap: () {
      final reviewer = _taskUserName(
        store,
        task.text('reviewerID'),
        'Reviewer',
      );
      feedback(
        task.text('assigneeID') == store.currentUserID
            ? 'Kamu tidak bisa menyetujui hasil kerjamu sendiri. $reviewer yang akan mereview.'
            : 'Hanya $reviewer (reviewer) yang bisa menyetujui tugas ini.',
        kind: GLToastKind.err,
      );
    },
    child: CustomPaint(
      painter: _TaskDashedBorder(radius: 22),
      child: Container(
        height: 44,
        padding: EdgeInsets.only(left: 10, right: 14),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          spacing: 4,
          children: [
            GLIcon('lock', size: 18, color: GLTheme.text2),
            Text('Setujui', style: gl(14, w600, 0, GLTheme.text2)),
          ],
        ),
      ),
    ),
  );

  // MARK: Discussion tab

  Future<void> _refreshComments() async {
    if (refreshing) return;
    setState(() => refreshing = true);
    var failed = false;
    try {
      await store.refresh();
    } catch (_) {
      failed = true;
    }
    if (!mounted) return;
    setState(() => refreshing = false);
    if (failed || store.error != null) {
      feedback(
        'Gagal memuat ulang. Kamu sedang offline.',
        kind: GLToastKind.err,
      );
    } else {
      feedback('Komentar sudah terbaru');
    }
  }

  Widget _discussion(JsonMap task, JsonMap project) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Padding(
        padding: EdgeInsets.symmetric(horizontal: 20),
        child: Row(
          spacing: 8,
          children: [
            Expanded(
              child: Text(
                'Komentar di sini hanya untuk tugas ini. Tekan lama pesan untuk opsi.',
                style: gl(13, w400, 0, GLTheme.secondary, 2),
              ),
            ),
            GLTap(
              label: 'Muat ulang komentar',
              onTap: _refreshComments,
              child: Container(
                height: 44,
                padding: EdgeInsets.symmetric(horizontal: 12),
                decoration: ShapeDecoration(
                  color: GLTheme.surface,
                  shape: StadiumBorder(),
                  shadows: [
                    BoxShadow(
                      color: Color(0x0F000000),
                      blurRadius: 2,
                      offset: Offset(0, 1),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  spacing: 5,
                  children: [
                    AnimatedRotation(
                      turns: refreshing ? 1 : 0,
                      duration: refreshing
                          ? Duration(seconds: 1)
                          : Duration.zero,
                      child: GLIcon('arrow.clockwise', size: 18),
                    ),
                    Text(
                      refreshing ? 'Memuat…' : 'Muat ulang',
                      style: gl(13, w600),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
      _thread(project.text('groupID'), task.text('id')),
    ],
  );

  static String _day(DateTime date) {
    final d = date.toLocal(), n = DateTime.now();
    final diff = DateTime(
      d.year,
      d.month,
      d.day,
    ).difference(DateTime(n.year, n.month, n.day)).inHours;
    final days = (diff / 24).round();
    if (days == 0) return 'Hari ini';
    if (days == -1) return 'Kemarin';
    return '${GLFormat.weekday(date)}, ${GLFormat.date(date)}';
  }

  Widget _thread(String groupID, String taskID) {
    final list = _taskMessages(store, groupID, taskID);
    DateTime at(JsonMap m) => m.date('createdAt') ?? DateTime(1970);
    bool isText(JsonMap m) =>
        m.text('kind') == 'text' || m.text('kind').isEmpty;
    bool chains(JsonMap a, JsonMap b) =>
        isText(a) &&
        isText(b) &&
        a.text('senderID') == b.text('senderID') &&
        _day(at(a)) == _day(at(b));
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 6, 16, 8),
      child: LayoutBuilder(
        builder: (context, box) {
          final width = box.maxWidth;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < list.length; i++) ...[
                if (i == 0 || _day(at(list[i - 1])) != _day(at(list[i])))
                  Padding(
                    padding: EdgeInsets.only(top: 14, bottom: 6),
                    child: Center(
                      child: Semantics(
                        header: true,
                        child: Container(
                          height: 26,
                          padding: EdgeInsets.symmetric(horizontal: 12),
                          alignment: Alignment.center,
                          decoration: ShapeDecoration(
                            color: _taskTrack,
                            shape: StadiumBorder(),
                          ),
                          child: Text(
                            _day(at(list[i])),
                            style: gl(12, w600, 0, GLTheme.text2),
                          ),
                        ),
                      ),
                    ),
                  ),
                if (!isText(list[i]))
                  _systemRow(list[i], width)
                else if (list[i].text('senderID') == store.currentUserID)
                  _mine(
                    list[i],
                    width,
                    samePrev: i > 0 && chains(list[i - 1], list[i]),
                    sameNext:
                        i + 1 < list.length && chains(list[i], list[i + 1]),
                    groupID: groupID,
                    taskID: taskID,
                  )
                else
                  _other(
                    list[i],
                    width,
                    samePrev: i > 0 && chains(list[i - 1], list[i]),
                    sameNext:
                        i + 1 < list.length && chains(list[i], list[i + 1]),
                    groupID: groupID,
                    taskID: taskID,
                  ),
              ],
              if (list.isEmpty)
                Padding(
                  padding: EdgeInsets.symmetric(vertical: 40, horizontal: 16),
                  child: Column(
                    spacing: 8,
                    children: [
                      Container(
                        width: 56,
                        height: 56,
                        decoration: glBox(GLTheme.lavender, 20),
                        child: GLIcon('hand.wave', size: 28),
                      ),
                      Text('Mulai diskusi', style: gl(17, w600)),
                      Text(
                        'Pertanyaan soal tugas ini tetap di sini, tidak tenggelam di chat grup.',
                        textAlign: TextAlign.center,
                        style: gl(14, w400, 0, GLTheme.secondary, 4),
                      ),
                    ],
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  Widget _systemRow(JsonMap m, double width) {
    final at = m.date('createdAt') ?? DateTime(1970);
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 8),
      child: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: width * 0.92),
          child: MergeSemantics(
            child: Container(
              padding: EdgeInsets.symmetric(vertical: 6, horizontal: 12),
              decoration: glBox(_taskTrack, 14),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                spacing: 6,
                children: [
                  GLIcon('bolt', size: 16, color: GLTheme.text3),
                  Flexible(
                    child: Text(
                      '${_taskName(store, m.text('senderID'))} ${m.text('text')} · ${GLFormat.time(at)}',
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
  }

  ShapeBorder _bubbleShape(double tl, double tr, double bl, double br) =>
      RoundedSuperellipseBorder(
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(tl),
          topRight: Radius.circular(tr),
          bottomLeft: Radius.circular(bl),
          bottomRight: Radius.circular(br),
        ),
      );

  /// `ChatFormat.linked`: https links drop their scheme, underlined and tappable.
  TextSpan _linked(String text, Color link) {
    final spans = <InlineSpan>[];
    var rest = 0;
    for (final match in RegExp(r'https?://\S+').allMatches(text)) {
      spans.add(TextSpan(text: text.substring(rest, match.start)));
      final raw = match.group(0)!;
      if (raw.startsWith('https://')) {
        spans.add(
          WidgetSpan(
            alignment: PlaceholderAlignment.baseline,
            baseline: TextBaseline.alphabetic,
            child: GestureDetector(
              onTap: () => _taskLaunch(context, raw),
              child: Text(
                raw.substring('https://'.length),
                style: gl(16, w400, 0, link, 2.6).copyWith(
                  decoration: TextDecoration.underline,
                  decorationColor: link,
                ),
              ),
            ),
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

  Widget _bubble(
    JsonMap m, {
    required Color color,
    required Color link,
    required ShapeBorder shape,
    required String groupID,
    required String taskID,
    List<BoxShadow>? shadows,
  }) {
    final at = m.date('createdAt') ?? DateTime(1970);
    final mine = m.text('senderID') == store.currentUserID;
    final delivery = switch (m.text('delivery')) {
      'sending' => 'Mengirim',
      'failed' => 'Gagal terkirim',
      _ => 'Terkirim',
    };
    return Semantics(
      value: mine
          ? 'Kamu, ${GLFormat.time(at)}, $delivery'
          : 'Dari ${_taskName(store, m.text('senderID'))}, ${GLFormat.time(at)}',
      onLongPressHint: 'Opsi pesan',
      child: GestureDetector(
        onLongPress: () => _messageOptions(m, groupID, taskID),
        child: Container(
          padding: EdgeInsets.symmetric(vertical: 8, horizontal: 12),
          decoration: ShapeDecoration(
            color: color,
            shape: shape,
            shadows: shadows,
          ),
          child: Text.rich(
            _linked(m.text('text'), link),
            style: gl(16, w400, 0, GLTheme.ink, 2.6),
          ),
        ),
      ),
    );
  }

  Widget _other(
    JsonMap m,
    double width, {
    required bool samePrev,
    required bool sameNext,
    required String groupID,
    required String taskID,
  }) {
    final at = m.date('createdAt') ?? DateTime(1970);
    final sender = m.text('senderID');
    final hidden =
        store.blockedUserIDs.contains(sender) &&
        !revealed.contains(m.text('id'));
    final shape = _bubbleShape(samePrev ? 6 : 18, 18, sameNext ? 6 : 18, 18);
    return Padding(
      padding: EdgeInsets.only(top: samePrev ? 2 : 10),
      child: Align(
        alignment: Alignment.centerLeft,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: width * 0.84),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.end,
            spacing: 8,
            children: [
              if (sameNext)
                SizedBox(width: 30, height: 1)
              else
                Padding(
                  padding: EdgeInsets.only(bottom: 22),
                  child: ExcludeSemantics(
                    child: GLAvatar(
                      user: store.user(sender),
                      size: 30,
                      fontSize: 11,
                    ),
                  ),
                ),
              Flexible(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  spacing: 3,
                  children: [
                    if (!samePrev)
                      Padding(
                        padding: EdgeInsets.only(left: 4),
                        child: Text(
                          _taskName(store, sender),
                          style: gl(13, w600, 0, GLTheme.text2),
                        ),
                      ),
                    if (hidden)
                      GLTap(
                        onTap: () => setState(() => revealed.add(m.text('id'))),
                        child: CustomPaint(
                          painter: _TaskDashedBorder(radius: 18),
                          child: Container(
                            constraints: BoxConstraints(minHeight: 44),
                            padding: EdgeInsets.symmetric(
                              vertical: 8,
                              horizontal: 12,
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              spacing: 6,
                              children: [
                                GLIcon(
                                  'eye.slash',
                                  size: 17,
                                  color: GLTheme.text3,
                                ),
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
                      )
                    else
                      _bubble(
                        m,
                        color: GLTheme.surface,
                        link: GLTheme.link,
                        shape: shape,
                        groupID: groupID,
                        taskID: taskID,
                        shadows: [
                          BoxShadow(
                            color: Color(0x0F000000),
                            blurRadius: 1.5,
                            offset: Offset(0, 1),
                          ),
                        ],
                      ),
                    if (!sameNext)
                      Padding(
                        padding: EdgeInsets.only(left: 4),
                        child: Text(
                          GLFormat.time(at),
                          style: gl(12, w400, 0, GLTheme.secondary),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _mine(
    JsonMap m,
    double width, {
    required bool samePrev,
    required bool sameNext,
    required String groupID,
    required String taskID,
  }) {
    final at = m.date('createdAt') ?? DateTime(1970);
    final delivery = m.text('delivery');
    final shape = _bubbleShape(18, samePrev ? 6 : 18, 18, sameNext ? 6 : 18);
    return Padding(
      padding: EdgeInsets.only(top: samePrev ? 2 : 10),
      child: Align(
        alignment: Alignment.centerRight,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: width * 0.8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            spacing: 3,
            children: [
              AnimatedOpacity(
                opacity: delivery == 'sending' ? 0.6 : 1,
                duration: Duration(milliseconds: 200),
                child: _bubble(
                  m,
                  color: GLTheme.lavender,
                  link: GLTheme.link,
                  shape: shape,
                  groupID: groupID,
                  taskID: taskID,
                ),
              ),
              if (delivery == 'failed')
                GLTap(
                  onTap: () => _retry(m, groupID, taskID),
                  child: Container(
                    constraints: BoxConstraints(minHeight: 40),
                    padding: EdgeInsets.all(2),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      spacing: 4,
                      children: [
                        GLIcon(
                          'exclamationmark.circle',
                          size: 16,
                          color: GLTheme.danger,
                        ),
                        Text(
                          'Gagal terkirim · Coba lagi',
                          style: gl(13, w600, 0, GLTheme.danger),
                        ),
                      ],
                    ),
                  ),
                )
              else if (delivery == 'sending')
                ExcludeSemantics(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    spacing: 4,
                    children: [
                      SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator.adaptive(
                          strokeWidth: 1.5,
                        ),
                      ),
                      Text(
                        'Mengirim…',
                        style: gl(12, w400, 0, GLTheme.secondary),
                      ),
                    ],
                  ),
                )
              else if (!sameNext)
                ExcludeSemantics(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    spacing: 3,
                    children: [
                      Text(
                        '${GLFormat.time(at)} · Terkirim',
                        style: gl(12, w400, 0, GLTheme.secondary),
                      ),
                      GLIcon('checkmark', size: 14, color: GLTheme.secondary),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _retry(JsonMap m, String groupID, String taskID) async {
    try {
      await store.mutate('sendMessage', {
        'groupID': groupID,
        'taskID': taskID,
        'text': m.text('text'),
        'clientID': m.text('id'),
      });
    } catch (error) {
      feedback('$error', kind: GLToastKind.err);
    }
  }

  Future<void> _messageOptions(JsonMap m, String groupID, String taskID) async {
    final failed =
        m.text('delivery') == 'failed' &&
        m.text('senderID') == store.currentUserID;
    final pick = await showGLSheet<String>(
      context,
      title: 'Opsi pesan',
      builder: (context) => _TaskOptionList(
        rows: [
          ('copy', 'Salin teks', 'Salin isi pesan', 'doc.on.doc'),
          if (failed)
            (
              'retry',
              'Coba kirim lagi',
              'Kirim ulang pesan yang gagal',
              'arrow.clockwise',
            ),
        ],
      ),
    );
    if (!mounted) return;
    if (pick == 'copy') {
      await Clipboard.setData(ClipboardData(text: m.text('text')));
      feedback('Teks disalin');
    } else if (pick == 'retry') {
      await _retry(m, groupID, taskID);
    }
  }

  // MARK: CTA bar (prototype `hasCtaBar`)

  Widget _ctaBar(JsonMap task, JsonMap project, double bottomInset) {
    final cta = _ctaAction(task, project);
    final Widget child;
    if (cta != null) {
      child = DecoratedBox(
        decoration: ShapeDecoration(
          shape: glShape(20),
          shadows: [
            BoxShadow(
              color: Color(0x38000000),
              blurRadius: 24,
              offset: Offset(0, 12),
            ),
          ],
        ),
        child: GLPrimaryButton(
          key: Key(cta.$3),
          title: cta.$1,
          icon: cta.$2,
          onPressed: busy ? null : cta.$4,
        ),
      );
    } else {
      final (text, icon) = _infoLine(task, project);
      child = MergeSemantics(
        child: Container(
          constraints: BoxConstraints(minHeight: 54),
          padding: EdgeInsets.symmetric(vertical: 8, horizontal: 16),
          decoration: glBox(GLTheme.surface, 20, border: GLTheme.border),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            spacing: 8,
            children: [
              GLIcon(icon, size: 20),
              Flexible(
                child: Text(
                  text,
                  textAlign: TextAlign.center,
                  style: gl(15, w500),
                ),
              ),
            ],
          ),
        ),
      );
    }
    return Container(
      padding: EdgeInsets.fromLTRB(20, 16, 20, 4 + bottomInset),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [GLTheme.background.withValues(alpha: 0), GLTheme.background],
          stops: [0, 0.28],
        ),
      ),
      child: child,
    );
  }

  (String, String, String, VoidCallback)? _ctaAction(
    JsonMap task,
    JsonMap project,
  ) {
    if (project.text('status') != 'active') return null;
    final me = store.currentUserID;
    final status = task.text('status');
    final version = _version(task);
    if (task.text('assigneeID') == me) {
      switch (status) {
        case 'todo':
          return (
            'Mulai kerjakan',
            'play.fill',
            'Mulai Kerjakan',
            () => _act('startTask', {
              'id': widget.taskID,
              'expectedVersion': version,
            }, 'Tugas dimulai. Semangat!'),
          );
        case 'in_progress':
        case 'needs_revision':
          return (
            status == 'in_progress' ? 'Kirim hasil' : 'Kirim revisi',
            'square.and.arrow.up',
            'Kirim Hasil',
            () => _openSubmit(task),
          );
      }
    }
    final latest = _submissions(task).lastOrNull;
    if (task.text('reviewerID') == me &&
        status == 'in_review' &&
        task.text('assigneeID') != me &&
        latest != null &&
        latest.text('authorID') != me &&
        latest['decision'] == null) {
      return (
        'Review revisi ${_submissions(task).length}',
        'square.and.pencil',
        'open-review',
        () => _openReview(task),
      );
    }
    return null;
  }

  (String, String) _infoLine(JsonMap task, JsonMap project) {
    if (project.text('status') == 'archived') {
      return ('Proyek diarsipkan · tugas hanya bisa dilihat', 'archivebox');
    }
    if (project.text('status') == 'completed') {
      return ('Proyek selesai · tugas hanya bisa dilihat', 'checkmark.circle');
    }
    return switch (task.text('status')) {
      'done' => (
        'Disetujui oleh ${switch (_submissions(task).lastOrNull?.text('reviewerID') ?? '') {
          '' => 'reviewer',
          final id => _taskName(store, id).replaceAll('Kamu', 'kamu'),
        }}',
        'checkmark.circle',
      ),
      'in_review' => (
        'Menunggu review dari ${_taskName(store, task.text('reviewerID'))}',
        'hourglass',
      ),
      'needs_revision' => (
        'Menunggu revisi dari ${_taskName(store, task.text('assigneeID'))}',
        'hourglass',
      ),
      'in_progress' => (
        'Sedang dikerjakan ${_taskName(store, task.text('assigneeID'))}',
        'arrow.triangle.2.circlepath',
      ),
      _ => (
        'Belum dimulai oleh ${_taskName(store, task.text('assigneeID'))}',
        'hourglass',
      ),
    };
  }

  // MARK: Actions

  Future<void> _info(String heading, String text) => showGLConfirm(
    context,
    title: heading,
    text: text,
    ok: 'Mengerti',
    info: true,
  );

  Future<void> _actions(JsonMap task, JsonMap project, JsonMap group) async {
    final coord = _coordinator(store, group);
    final status = task.text('status');
    final active = project.text('status') == 'active';
    final lock = _taskEditLock(store, task);
    final reassignOpen =
        coord && status != 'in_review' && status != 'done' && active;
    final deleted =
        task.text('assigneeID').isEmpty || task.text('reviewerID').isEmpty;
    final pick = await showGLSheet<String>(
      context,
      title: 'Opsi tugas',
      builder: (context) => _TaskOptionList(
        rows: [
          (
            'edit',
            'Edit tugas',
            lock?.$1 ?? 'Judul, deskripsi, deadline, reviewer',
            lock == null ? 'pencil' : 'lock',
          ),
          (
            'reassign',
            'Alihkan pelaksana',
            !coord
                ? 'Khusus koordinator'
                : status == 'in_review'
                ? 'Terkunci selama review'
                : status == 'done'
                ? 'Tugas sudah selesai'
                : !active
                ? 'Proyek tidak aktif'
                : 'Pilih anggota lain',
            reassignOpen ? 'arrow.left.arrow.right' : 'lock',
          ),
          (
            'share',
            'Bagikan tugas',
            'Kirim tautan ke WhatsApp',
            'square.and.arrow.up',
          ),
          if (coord && status == 'done' && active && !deleted)
            (
              'reopen',
              'Buka kembali tugas',
              'Riwayat hasil dan review tetap disimpan',
              'arrow.counterclockwise',
            ),
        ],
        footer: coord && status == 'done' && active && deleted
            ? GLNotice(
                text:
                    'Pelaksana atau reviewer telah menghapus akun. Buat tugas pengganti; riwayat ini tetap disimpan.',
                icon: 'person.crop.circle.badge.minus',
              )
            : null,
      ),
    );
    if (!mounted || pick == null) return;
    final current = store.task(widget.taskID);
    if (current == null) return;
    switch (pick) {
      case 'edit':
        final editLock = _taskEditLock(store, current);
        if (editLock != null) {
          await _info(editLock.$1, editLock.$2);
        } else {
          await _showTaskSheet(this, project, group, current);
        }
      case 'reassign':
        await _openReassign(current, project, group);
      case 'share':
        // ponytail: no share plugin installed; copies the ShareLink text instead.
        await Clipboard.setData(
          ClipboardData(
            text:
                '${current.text('title')} · ${GLStatus.label(current.text('status'))}\n'
                'grouply://task/${current.text('id')}\n'
                'Buka dengan GROUPLY menggunakan akun anggota grup.',
          ),
        );
        feedback('Tautan tugas disalin');
      case 'reopen':
        if (await confirm(
              'Buka kembali tugas?',
              'Riwayat hasil dan keputusan review tetap disimpan.',
              ok: 'Buka kembali',
            ) &&
            mounted) {
          await _act('reopenTask', {
            'id': widget.taskID,
            'expectedVersion': _version(current),
          }, 'Tugas dibuka kembali');
        }
    }
  }

  Future<void> _openReassign(
    JsonMap task,
    JsonMap project,
    JsonMap group,
  ) async {
    final lock = _taskProjectLock(project);
    if (lock != null) return feedback(lock, kind: GLToastKind.err);
    if (!_coordinator(store, group)) {
      return feedback(
        'Hanya koordinator yang bisa mengalihkan tugas.',
        kind: GLToastKind.err,
      );
    }
    final status = task.text('status');
    if (status == 'in_review') {
      return _info(
        'Sedang Menunggu Review',
        'Tugas ini tidak dapat dialihkan karena hasil pekerjaan sedang diperiksa. Selesaikan atau batalkan proses review terlebih dahulu.',
      );
    }
    if (status == 'done') {
      return _info(
        'Tugas sudah selesai',
        'Tugas yang sudah disetujui tidak bisa dialihkan.',
      );
    }
    final members = group.ids('memberIDs');
    final coordinatorID = group.text('coordinatorID');
    final assignee = await showGLSheet<String>(
      context,
      title: 'Alihkan pelaksana',
      builder: (context) => _TaskReassignList(
        store: store,
        rows: [
          for (final id in members)
            (
              id,
              id == task.text('reviewerID')
                  ? 'Reviewer saat ini · perlu reviewer pengganti'
                  : id == task.text('assigneeID')
                  ? 'Pelaksana saat ini'
                  : id == coordinatorID
                  ? 'Koordinator'
                  : 'Anggota',
              id == task.text('assigneeID'),
            ),
        ],
        note: status == 'needs_revision'
            ? 'Tugas ini punya riwayat revisi. Hasil kerja dan catatan review sebelumnya tetap tersimpan untuk pelaksana baru.'
            : 'Status tugas tidak berubah. Riwayat pesan dan hasil kerja tetap tersimpan.',
      ),
    );
    if (!mounted || assignee == null || assignee == task.text('assigneeID')) {
      return;
    }
    String? reviewer;
    if (assignee == task.text('reviewerID')) {
      reviewer = await showGLSheet<String>(
        context,
        title: 'Pilih reviewer baru',
        builder: (context) => _TaskReassignList(
          store: store,
          rows: [
            for (final id in members.where((id) => id != assignee))
              (id, id == coordinatorID ? 'Koordinator' : 'Anggota', false),
          ],
          note:
              '${_taskUserName(store, assignee, 'Anggota')} saat ini reviewer tugas ini. Pilih reviewer lain supaya pelaksana dan reviewer tetap berbeda.',
        ),
      );
      if (!mounted || reviewer == null) return;
    }
    if (reviewer == assignee) {
      return feedback(
        'Reviewer harus berbeda dari pelaksana.',
        kind: GLToastKind.err,
      );
    }
    if (status == 'needs_revision' &&
        !(await confirm(
          'Alihkan tugas revisi?',
          'Tugas ini memiliki riwayat revisi. Pelaksana baru akan melanjutkan pekerjaan tanpa menghapus hasil sebelumnya.',
          ok: 'Alihkan',
        ))) {
      return;
    }
    if (!mounted) return;
    await _act(
      'reassignTask',
      {
        'id': widget.taskID,
        'expectedVersion': _version(task),
        'assigneeID': assignee,
        'reviewerID': reviewer ?? task.text('reviewerID'),
      },
      'Pelaksana diganti ke ${_taskUserName(store, assignee, 'Anggota')}'
          '${reviewer == null ? '' : ' · reviewer ${_taskUserName(store, reviewer, 'Anggota')}'}',
    );
  }

  Future<void> _openSubmit(JsonMap task) async {
    if (busy) return;
    final sent = await showGLSheet<bool>(
      context,
      title: task.text('status') == 'needs_revision'
          ? 'Kirim revisi'
          : 'Kirim hasil',
      subtitle:
          '${task.text('title')} · ${_taskUserName(store, task.text('reviewerID'), 'Reviewer')} akan diberi tahu untuk mereview.',
      builder: (context) => _TaskSubmissionSheet(store: store, task: task),
    );
    if (sent == true && mounted) setState(() => tab = 1);
  }

  Future<void> _openReview(JsonMap task) async {
    if (busy) return;
    final done = await showGLSheet<bool>(
      context,
      title: 'Review hasil kerja',
      builder: (context) => _TaskReviewSheet(store: store, task: task),
    );
    if (done == true && mounted) setState(() => tab = 1);
  }
}

// MARK: - Shared sheet pieces

/// Dashed 1.5pt #9AA0A6 rounded outline (`StrokeStyle(dash: [4, 3])`).
class _TaskDashedBorder extends CustomPainter {
  _TaskDashedBorder({required this.radius});
  final double radius;
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = GLTheme.placeholder
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;
    final r = radius.clamp(0, size.height / 2).toDouble();
    final path = Path()
      ..addRRect(
        RRect.fromRectAndRadius(
          (Offset.zero & size).deflate(0.75),
          Radius.circular(r),
        ),
      );
    for (final metric in path.computeMetrics()) {
      for (var d = 0.0; d < metric.length; d += 7) {
        canvas.drawPath(metric.extractPath(d, d + 4), paint);
      }
    }
  }

  @override
  bool shouldRepaint(_TaskDashedBorder old) => old.radius != radius;
}

/// Link pill used in submission cards and the review sheet.
class _TaskLinkRow extends StatelessWidget {
  const _TaskLinkRow({required this.url, this.external = false});
  final String url;
  final bool external;
  @override
  Widget build(BuildContext context) {
    final label = Container(
      constraints: BoxConstraints(minHeight: 44),
      padding: EdgeInsets.symmetric(horizontal: 12),
      decoration: glBox(GLTheme.muted, 14),
      child: Row(
        spacing: 8,
        children: [
          GLIcon('link', size: 18),
          Expanded(
            child: Text(
              url.replaceAll('https://', ''),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: gl(14, w500),
            ),
          ),
          if (external)
            GLIcon('arrow.up.right.square', size: 17, color: GLTheme.secondary),
        ],
      ),
    );
    if (external && _https(url)) {
      return GLTap(
        label: 'Buka tautan $url',
        onTap: () => _taskLaunch(context, url),
        child: ExcludeSemantics(child: label),
      );
    }
    return label;
  }
}

/// Multiline input box (`TaskTextArea`): white, 1pt border.
class _TaskTextArea extends StatelessWidget {
  const _TaskTextArea({
    super.key,
    required this.controller,
    required this.placeholder,
    required this.maxLength,
    this.rows = 3,
    this.radius = 16,
    this.vertical = 12,
    this.semanticLabel,
    this.onChanged,
  });
  final TextEditingController controller;
  final String placeholder;
  final int maxLength, rows;
  final double radius, vertical;
  final String? semanticLabel;
  final ValueChanged<String>? onChanged;
  @override
  Widget build(BuildContext context) => Semantics(
    label: semanticLabel,
    textField: true,
    child: TextField(
      controller: controller,
      minLines: rows,
      maxLines: rows > 10 ? rows : 10,
      maxLength: maxLength,
      onChanged: onChanged,
      keyboardType: TextInputType.multiline,
      textCapitalization: TextCapitalization.sentences,
      cursorColor: GLTheme.ink,
      style: gl(16, w400, 0, GLTheme.ink),
      decoration: glInputDecoration(hint: placeholder, radius: radius).copyWith(
        contentPadding: EdgeInsets.symmetric(
          horizontal: 16,
          vertical: vertical,
        ),
      ),
    ),
  );
}

/// Sheet list card with icon rows (`TaskActionsSheet` / message options).
class _TaskOptionList extends StatelessWidget {
  const _TaskOptionList({required this.rows, this.footer});
  final List<(String, String, String, String)> rows; // key, label, sub, icon
  final Widget? footer;
  @override
  Widget build(BuildContext context) => Container(
    padding: EdgeInsets.symmetric(vertical: 4, horizontal: 16),
    decoration: glBox(GLTheme.surface, 24),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final (key, label, sub, icon) in rows)
          GLTap(
            onTap: () => Navigator.of(context).pop(key),
            child: MergeSemantics(
              child: Container(
                constraints: BoxConstraints(minHeight: 62),
                padding: EdgeInsets.symmetric(vertical: 8),
                decoration: BoxDecoration(
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
            ),
          ),
        if (footer != null)
          Padding(padding: EdgeInsets.symmetric(vertical: 8), child: footer),
      ],
    ),
  );
}

/// Reassign sheet body (prototype `sheetReassign`): member rows + footnote.
class _TaskReassignList extends StatelessWidget {
  const _TaskReassignList({
    required this.store,
    required this.rows,
    required this.note,
  });
  final GrouplyStore store;
  final List<(String, String, bool)> rows; // id, subtitle, current
  final String note;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    spacing: 16,
    children: [
      Container(
        padding: EdgeInsets.symmetric(vertical: 4, horizontal: 14),
        decoration: glBox(GLTheme.surface, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final (id, sub, current) in rows)
              Semantics(
                selected: current,
                child: GLTap(
                  onTap: () => Navigator.of(context).pop(id),
                  child: MergeSemantics(
                    child: Container(
                      constraints: BoxConstraints(minHeight: 60),
                      padding: EdgeInsets.symmetric(vertical: 8),
                      decoration: BoxDecoration(
                        border: Border(
                          bottom: BorderSide(color: GLTheme.border),
                        ),
                      ),
                      child: Row(
                        spacing: 12,
                        children: [
                          GLAvatar(
                            user: store.user(id),
                            size: 40,
                            fontSize: 13,
                          ),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(_taskName(store, id), style: gl(16, w600)),
                                Text(
                                  sub,
                                  style: gl(13, w400, 0, GLTheme.secondary),
                                ),
                              ],
                            ),
                          ),
                          if (current) GLIcon('checkmark', size: 22),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
      Text(note, style: gl(13, w400, 0, GLTheme.text3, 3)),
    ],
  );
}

/// Member pick chip (prototype `ntAssignees` / `ntReviewers`).
class _TaskMemberChip extends StatelessWidget {
  const _TaskMemberChip({
    required this.store,
    required this.id,
    required this.on,
    required this.pick,
    this.dimmed = false,
  });
  final GrouplyStore store;
  final String id;
  final bool on, dimmed;
  final VoidCallback pick;
  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    selected: on,
    child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: pick,
      child: Opacity(
        opacity: dimmed ? 0.4 : 1,
        child: AnimatedContainer(
          duration: Duration(milliseconds: 150),
          curve: Curves.easeOut,
          height: 44,
          padding: EdgeInsets.only(left: 5, right: 14),
          decoration: ShapeDecoration(
            color: on ? GLTheme.ink : GLTheme.surface,
            shape: _taskOutline,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            spacing: 7,
            children: [
              GLAvatar(user: store.user(id), size: 32, fontSize: 11),
              Text(
                _taskName(store, id),
                style: gl(14, w600, 0, on ? GLTheme.onInk : GLTheme.ink),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

// MARK: - New / edit task sheet (prototype `sheetNewTask` / `sheetEditTask`)

/// Opens the Swift `TaskEditor` sheet. Creates a task when [task] is null,
/// otherwise edits it. Resolves to the store result after a successful save.
Future<JsonMap?> _showTaskSheet(
  _WorkspaceState state,
  JsonMap project,
  JsonMap group, [
  JsonMap? task,
]) => showGLSheet<JsonMap>(
  state.context,
  title: task == null ? 'Buat tugas' : 'Edit tugas',
  builder: (context) => _TaskEditorSheet(
    store: state.store,
    project: project,
    group: group,
    task: task,
  ),
);

class _TaskEditorSheet extends StatefulWidget {
  const _TaskEditorSheet({
    required this.store,
    required this.project,
    required this.group,
    this.task,
  });
  final GrouplyStore store;
  final JsonMap project, group;
  final JsonMap? task;
  @override
  State<_TaskEditorSheet> createState() => _TaskEditorSheetState();
}

class _TaskEditorSheetState extends State<_TaskEditorSheet> {
  late final title = TextEditingController(text: widget.task?.text('title'));
  late final description = TextEditingController(
    text: widget.task?.text('description'),
  );
  late DateTime dueAt = widget.task == null
      ? _taskEndOfDay(DateTime.now().add(Duration(days: 3)))
      : _taskDue(widget.task!).toLocal();
  late String? assigneeID = widget.task?.text('assigneeID');
  late String? reviewerID = widget.task?.text('reviewerID');
  // Captured when the editor opens (not lazily on save) so a concurrent
  // change surfaces as a stale-version error instead of being overwritten.
  late final int version;
  String? error;
  bool busy = false;

  @override
  void initState() {
    super.initState();
    version = widget.task?.number('version').toInt() ?? 0;
  }

  GrouplyStore get store => widget.store;
  bool get editing => widget.task != null;
  List<String> get members => widget.group.ids('memberIDs');
  bool get retry => error?.contains('Gagal') ?? false;

  @override
  void dispose() {
    title.dispose();
    description.dispose();
    super.dispose();
  }

  DateTime get minimum {
    final n = DateTime.now();
    final today = DateTime(n.year, n.month, n.day);
    final original = widget.task?.date('dueAt')?.toLocal();
    if (original == null) return today;
    final o = DateTime(original.year, original.month, original.day);
    return o.isBefore(today) ? o : today;
  }

  Widget _picker(
    String label,
    String? selected,
    bool Function(String) dimmed,
    void Function(String) pick,
  ) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    spacing: 8,
    children: [
      _taskRequiredLabel(label),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final id in members)
            _TaskMemberChip(
              store: store,
              id: id,
              on: selected == id,
              dimmed: dimmed(id),
              pick: () => setState(() => pick(id)),
            ),
        ],
      ),
    ],
  );

  Widget _counted(String label, String count, {bool required = false}) => Row(
    children: [
      Expanded(child: _taskRequiredLabel(label, required: required)),
      Text(count, style: gl(14, w400, 0, GLTheme.secondary)),
    ],
  );

  Widget _projectCard(String heading, String sub) => MergeSemantics(
    child: Container(
      padding: EdgeInsets.symmetric(vertical: 12, horizontal: 14),
      decoration: glBox(GLTheme.surface, 18, border: GLTheme.border),
      child: Row(
        spacing: 10,
        children: [
          GLIcon('folder', size: 20),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(heading, style: gl(15, w600)),
                Text(sub, style: gl(13, w400, 0, GLTheme.secondary)),
              ],
            ),
          ),
        ],
      ),
    ),
  );

  Future<void> _pickDate() async {
    final last = DateTime(2027, 12, 31);
    final first = minimum;
    var initial = dueAt;
    if (initial.isBefore(first)) initial = first;
    if (initial.isAfter(last)) initial = last;
    final picked = await showGLSheet<DateTime>(
      context,
      title: 'Pilih tanggal deadline',
      builder: (context) => Container(
        decoration: glBox(GLTheme.surface, 24),
        child: CalendarDatePicker(
          initialDate: initial,
          firstDate: first,
          lastDate: last.isBefore(first) ? first : last,
          onDateChanged: (d) => Navigator.of(context).pop(d),
        ),
      ),
    );
    if (picked != null && mounted) {
      setState(() => dueAt = _taskEndOfDay(picked));
    }
  }

  Widget _deadline() {
    final projectDue = widget.project.date('dueAt');
    final n = DateTime.now();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 8,
      children: [
        _taskRequiredLabel('Deadline'),
        Row(
          spacing: 8,
          children: [
            for (final (days, label) in [
              (1, 'Besok'),
              (3, '3 hari lagi'),
              (7, 'Minggu depan'),
            ])
              Expanded(
                child: Builder(
                  builder: (context) {
                    final value = _taskEndOfDay(
                      DateTime(n.year, n.month, n.day + days),
                    );
                    final on = _taskSameDay(value, dueAt);
                    return Semantics(
                      button: true,
                      selected: on,
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () => setState(() => dueAt = value),
                        child: Container(
                          height: 44,
                          alignment: Alignment.center,
                          decoration: glBox(
                            on ? GLTheme.ink : GLTheme.surface,
                            16,
                            border: GLTheme.ink,
                            borderWidth: 1.5,
                          ),
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(
                              label,
                              maxLines: 1,
                              style: gl(
                                14,
                                w600,
                                0,
                                on ? GLTheme.onInk : GLTheme.ink,
                              ),
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
          ],
        ),
        Semantics(
          button: true,
          label: 'Pilih tanggal deadline',
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _pickDate,
            child: Container(
              height: 50,
              padding: EdgeInsets.symmetric(horizontal: 14),
              decoration: glBox(GLTheme.surface, 16, border: GLTheme.border),
              child: Row(
                spacing: 10,
                children: [
                  GLIcon('calendar', size: 20),
                  // Compact DatePicker pill.
                  Container(
                    padding: EdgeInsets.symmetric(horizontal: 11, vertical: 6),
                    decoration: glBox(
                      GLTheme.disabled.withValues(alpha: 0.12),
                      8,
                    ),
                    child: Text(
                      '${dueAt.day} ${GLFormat.months[dueAt.month - 1]} ${dueAt.year}',
                      style: gl(16, w400),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        Text(
          '${GLFormat.weekday(dueAt)}, ${GLFormat.date(dueAt)} · 23:59',
          style: gl(13, w400, 0, GLTheme.secondary),
        ),
        if (projectDue != null &&
            DateTime(dueAt.year, dueAt.month, dueAt.day).isAfter(
              DateTime(
                projectDue.toLocal().year,
                projectDue.toLocal().month,
                projectDue.toLocal().day,
              ),
            ))
          Container(
            padding: EdgeInsets.symmetric(vertical: 12, horizontal: 14),
            decoration: glBox(GLTheme.butter, 16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: 8,
              children: [
                GLIcon('exclamationmark.triangle', size: 18),
                Expanded(
                  child: Text(
                    'Deadline tugas melewati deadline proyek (${GLFormat.date(projectDue)}). Tetap bisa disimpan, pastikan ini disengaja.',
                    style: gl(14, w400, 0, null, 3),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Future<void> _save() async {
    if (busy) return;
    final clean = title.text.trim().split(RegExp(r'\s+')).join(' ');
    final desc = description.text.trim();
    void fail(String text) => setState(() => error = text);

    final JsonMap payload;
    final String success;
    final task = widget.task;
    if (task != null) {
      final current = store.task(task.text('id')) ?? task;
      final lock = _taskEditLock(store, current);
      if (lock != null) return fail(lock.$2);
      if (clean.isEmpty) return fail('Judul tugas wajib diisi.');
      if (clean.length > 120) return fail('Judul tugas maksimal 120 karakter.');
      if (desc.length > 2000) return fail('Deskripsi maksimal 2000 karakter.');
      final r = reviewerID;
      if (r == null || !members.contains(r)) {
        return fail('Reviewer harus anggota aktif grup.');
      }
      if (r == task.text('assigneeID')) {
        return fail('Reviewer harus berbeda dari pelaksana.');
      }
      final sameDay = _taskSameDay(dueAt, _taskDue(task));
      if (clean == task.text('title') &&
          desc == task.text('description') &&
          sameDay &&
          r == task.text('reviewerID')) {
        showGLToast(context, 'Tidak ada perubahan', kind: GLToastKind.info);
        Navigator.of(context).pop();
        return;
      }
      payload = {
        'id': task.text('id'),
        'expectedVersion': version,
        'title': clean,
        'description': desc,
        'reviewerID': r,
        'dueAt': sameDay
            ? task.text('dueAt')
            : _taskEndOfDay(dueAt).toUtc().toIso8601String(),
      };
      success = 'Tugas diperbarui';
    } else {
      if (clean.length < 3) return fail('Judul tugas minimal 3 karakter.');
      if (clean.length > 120) return fail('Judul tugas maksimal 120 karakter.');
      if (desc.length > 2000) return fail('Deskripsi maksimal 2000 karakter.');
      final lock = _taskProjectLock(widget.project, 'menambah tugas');
      if (lock != null) return fail(lock);
      final a = assigneeID, r = reviewerID;
      if (a == null) return fail('Pilih pelaksana tugas.');
      if (r == null) return fail('Pilih reviewer tugas.');
      if (a == r) return fail('Pelaksana dan reviewer harus orang berbeda.');
      payload = {
        'projectID': widget.project.text('id'),
        'title': clean,
        'description': desc,
        'assigneeID': a,
        'reviewerID': r,
        'dueAt': _taskEndOfDay(dueAt).toUtc().toIso8601String(),
      };
      success =
          'Tugas dibuat. ${a == store.currentUserID ? 'Ditugaskan ke kamu.' : '${_taskUserName(store, a, 'Anggota')} akan diberi tahu.'}';
    }
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final result = await store.mutate(
        task == null ? 'createTask' : 'updateTask',
        payload,
      );
      if (!mounted) return;
      showGLToast(context, success);
      Navigator.of(context).pop(result);
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final task = widget.task;
    final reviewerPicker = _picker(
      'Reviewer',
      reviewerID,
      (id) => id == (editing ? task!.text('assigneeID') : assigneeID),
      (id) {
        if (id == (editing ? task!.text('assigneeID') : assigneeID)) {
          error = editing
              ? 'Reviewer harus berbeda dari pelaksana.'
              : 'Pelaksana dan reviewer harus orang berbeda.';
        } else {
          reviewerID = id;
          error = null;
        }
      },
    );
    final projectDue = widget.project.date('dueAt');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 16,
      children: [
        if (task != null) ...[
          _projectCard(
            widget.project.text('title'),
            '${GLStatus.label(task.text('status'))} · Pelaksana: ${_taskName(store, task.text('assigneeID'))} (ubah lewat Alihkan pelaksana)',
          ),
          if (task.text('status') == 'needs_revision')
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: 6,
              children: [
                GLIcon(
                  'clock.arrow.circlepath',
                  size: 17,
                  color: GLTheme.text3,
                ),
                Expanded(
                  child: Text(
                    'Riwayat hasil kerja dan review tetap tersimpan.',
                    style: gl(13, w400, 0, GLTheme.text3, 3),
                  ),
                ),
              ],
            ),
        ] else
          _projectCard(
            widget.project.text('title'),
            projectDue == null
                ? ''
                : 'Deadline proyek ${GLFormat.weekday(projectDue)}, ${GLFormat.date(projectDue)}',
          ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: 6,
          children: [
            _counted('Judul', '${title.text.length}/120', required: true),
            GLTextField(
              key: Key('task-title'),
              controller: title,
              hint: editing ? null : 'Contoh: Buat use case diagram',
              maxLength: 120,
              semanticLabel: 'Judul tugas',
              textCapitalization: TextCapitalization.sentences,
              onChanged: (_) => setState(() {}),
            ),
          ],
        ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: 6,
          children: [
            _counted('Deskripsi', '${description.text.length}/2000'),
            _TaskTextArea(
              controller: description,
              placeholder:
                  'Jelaskan apa yang perlu dikerjakan dan hasil yang diharapkan...',
              maxLength: 2000,
              rows: editing ? 4 : 3,
              semanticLabel: 'Deskripsi tugas',
              onChanged: (_) => setState(() {}),
            ),
          ],
        ),
        if (!editing) ...[
          _picker('Pelaksana', assigneeID, (_) => false, (id) {
            assigneeID = id;
            if (reviewerID == id) reviewerID = null;
            error = null;
          }),
          reviewerPicker,
          _deadline(),
        ] else ...[
          _deadline(),
          reviewerPicker,
        ],
        if (error != null) GLFormError(error!, key: Key('form-error')),
        if (!editing)
          GLSubmitButton(
            title: busy
                ? 'Menyimpan…'
                : retry
                ? 'Coba lagi'
                : 'Buat tugas',
            busy: busy,
            onPressed: _save,
          )
        else
          Row(
            spacing: 10,
            children: [
              Expanded(
                child: GLTap(
                  onTap: () => Navigator.of(context).pop(),
                  child: Container(
                    height: 56,
                    alignment: Alignment.center,
                    decoration: glBox(_taskTrack, 20),
                    child: Text('Batal', style: gl(16, w600)),
                  ),
                ),
              ),
              Expanded(
                flex: 2,
                child: Semantics(
                  button: true,
                  enabled: !busy,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: busy ? null : _save,
                    child: Opacity(
                      opacity: busy ? 0.6 : 1,
                      child: Container(
                        height: 56,
                        alignment: Alignment.center,
                        decoration: glBox(GLTheme.ink, 20),
                        child: Text(
                          busy
                              ? 'Menyimpan…'
                              : retry
                              ? 'Coba lagi'
                              : 'Simpan perubahan',
                          style: gl(16, w600, 0, GLTheme.onInk),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
      ],
    );
  }
}

// MARK: - Submit sheet (prototype `sheetSubmit`)

class _TaskSubmissionSheet extends StatefulWidget {
  const _TaskSubmissionSheet({required this.store, required this.task});
  final GrouplyStore store;
  final JsonMap task;
  @override
  State<_TaskSubmissionSheet> createState() => _TaskSubmissionSheetState();
}

class _TaskSubmissionSheetState extends State<_TaskSubmissionSheet> {
  // Swift snapshots the task when the sheet opens; a concurrent edit must
  // then fail with a stale-version error instead of being overwritten.
  late final int _openedVersion;

  @override
  void initState() {
    super.initState();
    _openedVersion = widget.task.number('version').toInt();
  }

  final note = TextEditingController();
  final links = [TextEditingController()];
  String? error;
  bool busy = false;

  @override
  void dispose() {
    note.dispose();
    for (final c in links) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _submit() async {
    if (busy) return;
    final text = note.text.trim();
    final clean = links
        .map((c) => c.text.trim())
        .where((l) => l.isNotEmpty)
        .toList();
    String? problem;
    if (text.isEmpty) {
      problem = 'Tulis catatan singkat tentang yang kamu kerjakan.';
    } else if (text.length > 1000) {
      problem = 'Catatan maksimal 1000 karakter.';
    } else if (clean.length > 5) {
      problem = 'Maksimal 5 tautan HTTPS.';
    } else if (clean.any(
      (l) => !RegExp(r'^https://[^\s]+\.[^\s]+').hasMatch(l) || !_https(l),
    )) {
      problem = 'Link harus diawali https:// dan berupa alamat lengkap.';
    }
    if (problem != null) return setState(() => error = problem);
    setState(() {
      busy = true;
      error = null;
    });
    final task = widget.task;
    try {
      await widget.store.mutate('submitWork', {
        'taskID': task.text('id'),
        'expectedVersion': _openedVersion,
        'note': text,
        'links': clean,
      });
      if (!mounted) return;
      showGLToast(
        context,
        'Terkirim. ${_taskUserName(widget.store, task.text('reviewerID'), 'Reviewer')} akan diberi tahu.',
      );
      Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    spacing: 16,
    children: [
      GLField(
        'Apa yang kamu kerjakan?',
        required: true,
        child: _TaskTextArea(
          key: Key('submission-note'),
          controller: note,
          placeholder:
              'Contoh: Tabel sudah 3NF, alasan dekomposisi ada di halaman 2.',
          maxLength: 1000,
          rows: 4,
          radius: 18,
          vertical: 14,
          semanticLabel: 'Apa yang kamu kerjakan?',
        ),
      ),
      Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 8,
        children: [
          Row(
            children: [
              Expanded(child: Text('Link (opsional)', style: gl(14, w600))),
              Text(
                '${links.length}/5',
                style: gl(13, w400, 0, GLTheme.secondary),
              ),
            ],
          ),
          for (final c in links)
            Container(
              height: 48,
              padding: EdgeInsets.symmetric(horizontal: 14),
              decoration: glBox(GLTheme.surface, 16, border: GLTheme.border),
              child: Row(
                spacing: 8,
                children: [
                  GLIcon('link', size: 18, color: GLTheme.secondary),
                  Expanded(
                    child: Semantics(
                      label: 'Link hasil kerja',
                      textField: true,
                      child: TextField(
                        controller: c,
                        keyboardType: TextInputType.url,
                        autocorrect: false,
                        enableSuggestions: false,
                        maxLength: 2048,
                        cursorColor: GLTheme.ink,
                        onChanged: (_) {
                          if (error != null) setState(() => error = null);
                        },
                        style: gl(16, w400, 0, GLTheme.ink),
                        decoration: InputDecoration(
                          isCollapsed: true,
                          border: InputBorder.none,
                          counterText: '',
                          hintText: 'https://docs.google.com/…',
                          hintStyle: gl(16, w400, 0, GLTheme.placeholder),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          if (links.length < 5)
            Align(
              alignment: Alignment.centerLeft,
              child: GLTap(
                onTap: () => setState(() => links.add(TextEditingController())),
                child: SizedBox(
                  height: 44,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    spacing: 4,
                    children: [
                      GLIcon('plus', size: 20),
                      Text('Tambah link', style: gl(15, w600)),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
      if (error != null) GLFormError(error!),
      GLSubmitButton(
        key: Key('submit-work'),
        title: busy
            ? 'Mengirim…'
            : (error?.contains('Gagal') ?? false)
            ? 'Coba lagi'
            : 'Kirim untuk direview',
        busy: busy,
        onPressed: _submit,
      ),
    ],
  );
}

// MARK: - Review sheet (prototype `sheetReview`)

class _TaskReviewSheet extends StatefulWidget {
  const _TaskReviewSheet({required this.store, required this.task});
  final GrouplyStore store;
  final JsonMap task;
  @override
  State<_TaskReviewSheet> createState() => _TaskReviewSheetState();
}

class _TaskReviewSheetState extends State<_TaskReviewSheet> {
  // Swift snapshots the task when the sheet opens; a concurrent edit must
  // then fail with a stale-version error instead of being overwritten.
  late final int _openedVersion;

  @override
  void initState() {
    super.initState();
    _openedVersion = widget.task.number('version').toInt();
  }

  final feedbackText = TextEditingController();
  bool changes = false;
  bool? pending;
  String? error;

  @override
  void dispose() {
    feedbackText.dispose();
    super.dispose();
  }

  Future<void> _decide(bool approve) async {
    if (pending != null) return;
    final store = widget.store, task = widget.task;
    final text = feedbackText.text.trim();
    if (!approve && text.isEmpty) {
      return setState(() => error = 'Jelaskan apa yang perlu diubah.');
    }
    if (task.text('assigneeID') == store.currentUserID) {
      return setState(
        () => error = 'Kamu tidak bisa menyetujui hasil kerjamu sendiri.',
      );
    }
    setState(() {
      pending = approve;
      error = null;
    });
    try {
      await store.mutate('review', {
        'taskID': task.text('id'),
        'approve': approve,
        'feedback': approve ? '' : text,
        'expectedVersion': _openedVersion,
      });
      if (!mounted) return;
      showGLToast(
        context,
        approve
            ? 'Disetujui. Tugas selesai.'
            : 'Revisi diminta. ${_taskUserName(store, task.text('assigneeID'), 'Pelaksana')} akan diberi tahu.',
      );
      Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    } finally {
      if (mounted) setState(() => pending = null);
    }
  }

  Widget _button({
    required Widget child,
    required VoidCallback onTap,
    required Decoration decoration,
    double height = 56,
    bool dim = false,
    Key? key,
  }) => Semantics(
    key: key,
    button: true,
    enabled: pending == null,
    child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: pending == null ? onTap : null,
      child: Opacity(
        opacity: dim ? 0.6 : 1,
        child: Container(
          height: height,
          alignment: Alignment.center,
          decoration: decoration,
          child: child,
        ),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final store = widget.store, task = widget.task;
    final sub = _submissions(task).lastOrNull;
    final busy = pending != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 16,
      children: [
        if (sub != null)
          Container(
            padding: EdgeInsets.symmetric(vertical: 16, horizontal: 18),
            decoration: glBox(GLTheme.surface, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: 10,
              children: [
                Text(
                  'Revisi ${sub.number('revision')} · ${_taskName(store, sub.text('authorID'))} · ${_taskStamp(sub.date('createdAt'))}',
                  style: gl(13, w600, 0, GLTheme.secondary),
                ),
                SelectableText(
                  sub.text('note'),
                  style: gl(15, w400, 0, GLTheme.ink, 4),
                ),
                for (final link in sub.ids('links'))
                  _TaskLinkRow(url: link, external: true),
              ],
            ),
          ),
        if (error != null) GLFormError(error!),
        if (changes)
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: 10,
            children: [
              _taskRequiredLabel('Apa yang perlu diubah?'),
              _TaskTextArea(
                key: Key('review-feedback'),
                controller: feedbackText,
                placeholder:
                    'Spesifik dan ramah, misal: pisahkan Fine jadi entity sendiri.',
                maxLength: 1000,
                radius: 18,
                vertical: 14,
                semanticLabel: 'Apa yang perlu diubah?',
              ),
              Row(
                spacing: 10,
                children: [
                  Expanded(
                    child: _button(
                      height: 54,
                      onTap: () => setState(() {
                        changes = false;
                        error = null;
                      }),
                      decoration: glBox(_taskTrack, 20),
                      child: Text('Kembali', style: gl(16, w600)),
                    ),
                  ),
                  Expanded(
                    flex: 2,
                    child: _button(
                      height: 54,
                      dim: busy,
                      onTap: () => _decide(false),
                      decoration: glBox(GLTheme.ink, 20),
                      child: Padding(
                        padding: EdgeInsets.symmetric(horizontal: 8),
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            busy
                                ? 'Mengirim…'
                                : 'Kirim ke ${_taskUserName(store, task.text('assigneeID'), 'Pelaksana')}',
                            maxLines: 1,
                            style: gl(16, w600, 0, GLTheme.onInk),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          )
        else
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: 10,
            children: [
              _button(
                key: Key('approve-work'),
                dim: busy,
                onTap: () => _decide(true),
                decoration: glBox(GLTheme.ink, 20),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  spacing: 8,
                  children: [
                    if (pending == true)
                      SizedBox(
                        width: 22,
                        height: 22,
                        child: Center(
                          child: CircularProgressIndicator.adaptive(
                            valueColor: AlwaysStoppedAnimation(GLTheme.onInk),
                          ),
                        ),
                      )
                    else
                      GLIcon(
                        'checkmark.circle',
                        size: 22,
                        color: GLTheme.onInk,
                      ),
                    Text(
                      pending == true ? 'Menyimpan…' : 'Setujui',
                      style: gl(17, w600, 0, GLTheme.onInk),
                    ),
                  ],
                ),
              ),
              _button(
                onTap: () => setState(() {
                  changes = true;
                  error = null;
                }),
                decoration: glBox(
                  GLTheme.surface,
                  20,
                  border: GLTheme.ink,
                  borderWidth: 1.5,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  spacing: 8,
                  children: [
                    GLIcon('arrow.uturn.backward', size: 22),
                    Text('Minta revisi', style: gl(17, w600)),
                  ],
                ),
              ),
            ],
          ),
      ],
    );
  }
}

// MARK: - Task discussion composer (`ChatComposer` with taskID)

class _TaskComposer extends StatefulWidget {
  const _TaskComposer({
    required this.store,
    required this.groupID,
    required this.taskID,
  });
  final GrouplyStore store;
  final String groupID, taskID;
  @override
  State<_TaskComposer> createState() => _TaskComposerState();
}

class _TaskComposerState extends State<_TaskComposer> {
  final draft = TextEditingController();

  @override
  void initState() {
    super.initState();
    draft.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    draft.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = draft.text.trim();
    if (text.isEmpty) return;
    if (text.length > 2000) {
      showGLToast(
        context,
        'Pesan maksimal 2000 karakter.',
        kind: GLToastKind.err,
      );
      return;
    }
    draft.clear();
    try {
      await widget.store.mutate('sendMessage', {
        'groupID': widget.groupID,
        'taskID': widget.taskID,
        'clientID': _clientID(),
        'text': text,
      });
    } catch (e) {
      if (!mounted) return;
      if (draft.text.isEmpty) draft.text = text;
      showGLToast(context, '$e', kind: GLToastKind.err);
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasText = draft.text.trim().isNotEmpty;
    return Container(
      padding: EdgeInsets.fromLTRB(
        12,
        8,
        12,
        8 + MediaQuery.paddingOf(context).bottom,
      ),
      decoration: BoxDecoration(
        color: GLTheme.background,
        border: Border(top: BorderSide(color: GLTheme.border)),
      ),
      child: Row(
        spacing: 8,
        children: [
          Expanded(
            child: Container(
              height: 44,
              padding: EdgeInsets.symmetric(horizontal: 16),
              alignment: Alignment.centerLeft,
              decoration: ShapeDecoration(
                color: GLTheme.surface,
                shape: StadiumBorder(side: BorderSide(color: GLTheme.border)),
              ),
              child: TextField(
                controller: draft,
                maxLength: 2000,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => _send(),
                textCapitalization: TextCapitalization.sentences,
                cursorColor: GLTheme.ink,
                style: gl(16, w400, 0, GLTheme.ink),
                decoration: InputDecoration(
                  isCollapsed: true,
                  border: InputBorder.none,
                  counterText: '',
                  hintText: 'Komentari tugas ini…',
                  hintStyle: gl(16, w400, 0, GLTheme.placeholder),
                ),
              ),
            ),
          ),
          GLTap.card(
            label: 'Kirim pesan',
            onTap: _send,
            child: AnimatedContainer(
              duration: Duration(milliseconds: 150),
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: hasText ? GLTheme.ink : GLTheme.faint,
                shape: BoxShape.circle,
              ),
              child: GLIcon('arrow.up', size: 22, color: GLTheme.onInk),
            ),
          ),
        ],
      ),
    );
  }
}

// MARK: - Shared validators (kept from the previous port)

bool _https(String value) {
  final uri = Uri.tryParse(value);
  final authority = RegExp(
    r'^https://([^/?#]*)',
    caseSensitive: false,
  ).firstMatch(value)?.group(1);
  return value.length <= 2048 &&
      authority != null &&
      !authority.contains('@') &&
      !authority.contains('%') &&
      uri != null &&
      uri.scheme.toLowerCase() == 'https' &&
      uri.host.isNotEmpty &&
      !uri.host.contains('%') &&
      !uri.authority.contains('@') &&
      uri.userInfo.isEmpty &&
      !value.contains(RegExp(r'\s'));
}

String _clientID() {
  final bytes = List<int>.generate(16, (_) => _random.nextInt(256));
  bytes[6] = (bytes[6] & 15) | 64;
  bytes[8] = (bytes[8] & 63) | 128;
  final hex = bytes
      .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
      .join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
}
