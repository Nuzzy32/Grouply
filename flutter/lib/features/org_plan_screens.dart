part of 'workspace_screens.dart';

// Organization Plan Tahap 3a (docs/DESIGN-org-tahap3.md §5): template proker,
// rencana, tutup kepanitiaan, serah terima, arsip, rekap LPJ. Role-only
// buttons are hidden; plan-locked ones keep a lock and a toast. The server
// enforces every rule (§3).

bool _orgOfficer(GrouplyStore store, String orgID) =>
    store.orgRole(orgID).isNotEmpty;

/// Open organization groups the viewer coordinates (template targets).
List<JsonMap> _coordinatedGroups(GrouplyStore store, String orgID) => [
  for (final group in store.groups)
    if (group.text('organizationID') == orgID &&
        _coordinator(store, group) &&
        !store.isClosed(group))
      group,
];

/// Ketua, BPH, or coordinator of any group of the organization (§3).
bool _canSaveTemplate(GrouplyStore store, String orgID) =>
    ['ketua', 'bph'].contains(store.orgRole(orgID)) ||
    store.groups.any(
      (group) =>
          group.text('organizationID') == orgID && _coordinator(store, group),
    );

/// Officers see every group's recap; a coordinator their group; a
/// koordinator sie their own sie (§3).
bool _canReport(GrouplyStore store, JsonMap group) =>
    _orgOfficer(store, group.text('organizationID')) ||
    _coordinator(store, group) ||
    (_member(store, group) &&
        _grProjects(
          store,
          group.text('id'),
        ).any((p) => p.text('leadID') == store.currentUserID));

String _offsetLabel(int days) => days == 0
    ? 'Hari H'
    : days < 0
    ? 'H-${-days}'
    : 'H+$days';

DateTime _day(DateTime value) {
  final local = value.toLocal();
  return DateTime(local.year, local.month, local.day);
}

Future<DateTime?> _pickDay(
  BuildContext context, {
  required String title,
  required DateTime initial,
  required DateTime first,
}) {
  final last = DateTime(first.year + 3, 12, 31);
  return showGLSheet<DateTime>(
    context,
    title: title,
    builder: (sheet) => Container(
      decoration: glBox(GLTheme.surface, 24),
      child: CalendarDatePicker(
        initialDate: initial.isBefore(first) ? first : initial,
        firstDate: first,
        lastDate: last,
        onDateChanged: (d) => Navigator.of(sheet).pop(d),
      ),
    ),
  );
}

Widget _dayButton({
  Key? key,
  required String label,
  required DateTime? value,
  required VoidCallback onTap,
}) => GLTap(
  key: key,
  label: label,
  onTap: onTap,
  child: Container(
    height: 50,
    padding: EdgeInsets.symmetric(horizontal: 14),
    decoration: glBox(GLTheme.surface, 16, border: GLTheme.border),
    child: Row(
      spacing: 10,
      children: [
        GLIcon('calendar', size: 20),
        Expanded(
          child: Text(
            value == null
                ? 'Pilih tanggal'
                : '${GLFormat.weekday(value)}, ${GLFormat.longDate(value)}',
            style: gl(16, w500),
          ),
        ),
      ],
    ),
  ),
);

// MARK: - Organization screen

/// "Template proker", "Arsip & rekap LPJ" (officers), "Serah terima" (Ketua).
Widget _orgPlanLinks(_WorkspaceState state, JsonMap org) {
  final store = state.store;
  final orgID = org.text('id');
  final role = store.orgRole(orgID);
  final periods = store.periods(orgID).length;
  final label = org.text('periodLabel');
  return _workList([
    _workRow(
      key: Key('org-templates'),
      icon: 'doc.on.doc',
      tint: GLTheme.mint,
      title: 'Template proker',
      subtitle: 'Kerangka sie dan rencana siap pakai',
      onTap: () => state.open(TemplatesScreen(store: store, orgID: orgID)),
    ),
    if (role.isNotEmpty)
      _workRow(
        key: Key('org-archive'),
        icon: 'archivebox',
        tint: GLTheme.lavender,
        title: 'Arsip & rekap LPJ',
        subtitle: periods == 0
            ? 'Rekap periode berjalan'
            : '$periods periode tersimpan',
        onTap: () => state.open(ArchiveScreen(store: store, orgID: orgID)),
      ),
    if (role == 'ketua')
      _workRow(
        key: Key('org-handover'),
        icon: 'arrow.left.arrow.right',
        tint: GLTheme.butter,
        title: 'Serah terima',
        subtitle: label.isEmpty
            ? 'Tutup periode kepengurusan'
            : 'Tutup periode $label',
        onTap: () async {
          final next = await Navigator.of(state.context).push<String>(
            MaterialPageRoute(
              builder: (_) => HandoverScreen(store: store, orgID: orgID),
            ),
          );
          // "Atur jabatan" in the checklist reuses the org screen's sheet.
          if (next == 'roles' && state is _OrgState && state.mounted) {
            state._manageRoles();
          }
        },
      ),
  ]);
}

// MARK: - Group screen (committee close/reopen, recap)

/// What still keeps a committee open (§1.5), from the viewer's snapshot.
List<String> _committeeBusy(GrouplyStore store, JsonMap group) {
  final groupID = group.text('id');
  final projects = _grProjects(store, groupID);
  final ids = projects.map((p) => p.text('id')).toSet();
  final active = projects.where((p) => p['status'] == 'active').length;
  final open = store.tasks
      .where((t) => ids.contains(t.text('projectID')) && t['status'] != 'done')
      .length;
  final pending = store
      .approvals(group.text('organizationID'))
      .where((a) => a.text('groupID') == groupID && a['status'] == 'pending')
      .length;
  return [
    if (open > 0) '$open tugas belum selesai',
    if (active > 0) '$active sie masih aktif (tandai selesai lalu arsipkan)',
    if (pending > 0) '$pending pengajuan masih menunggu',
  ];
}

List<Widget> _groupPlanSection(_WorkspaceState state, JsonMap group) {
  final store = state.store;
  final orgID = group.text('organizationID');
  if (store.organization(orgID) == null) return [];
  final committee = store.isCommittee(group);
  final closed = store.isClosed(group);
  final ketua = store.orgRole(orgID) == 'ketua';
  final canClose = committee && (ketua || _coordinator(store, group));
  return [
    if (closed)
      Container(
        key: Key('committee-closed'),
        padding: EdgeInsets.all(16),
        decoration: glBox(GLTheme.chip, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: 12,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: 10,
              children: [
                GLIcon('archivebox', size: 20),
                Expanded(
                  child: Text(
                    'Kepanitiaan ini sudah ditutup dan masuk Arsip. Chat tetap bisa dipakai; anggota bisa keluar atau dikeluarkan.',
                    style: gl(14, w500, 0, null, 3),
                  ),
                ),
              ],
            ),
            if (ketua)
              GLOutlineButton(
                key: Key('committee-reopen'),
                title: 'Buka kembali kepanitiaan',
                icon: _activeDivision(store, group)
                    ? 'arrow.counterclockwise'
                    : 'lock',
                onPressed: () => _reopenCommittee(
                  state,
                  group.text('id'),
                  group.text('name'),
                  _activeDivision(store, group),
                ),
              ),
          ],
        ),
      ),
    if (canClose && !closed || _canReport(store, group))
      Row(
        spacing: 8,
        children: [
          if (canClose && !closed)
            Expanded(
              child: GLOutlineButton(
                key: Key('committee-close'),
                title: 'Tutup kepanitiaan',
                icon: 'archivebox',
                onPressed: () => _closeCommittee(state, group),
              ),
            ),
          if (_canReport(store, group))
            Expanded(
              child: GLOutlineButton(
                key: Key('group-report'),
                title: 'Rekap LPJ',
                icon: 'doc.text',
                onPressed: () => state.open(
                  ReportScreen(store: store, groupID: group.text('id')),
                ),
              ),
            ),
        ],
      ),
  ];
}

Future<void> _closeCommittee(_WorkspaceState state, JsonMap group) async {
  final busy = _committeeBusy(state.store, group);
  if (busy.isNotEmpty) {
    await state.confirm(
      'Belum bisa ditutup',
      'Selesaikan dulu: ${busy.join('; ')}.',
      ok: 'Mengerti',
    );
    return;
  }
  if (await state.confirm(
        'Tutup ${group.text('name')}?',
        'Undangan dicabut dan rapat mendatang dibatalkan. Setelah ditutup, hanya chat, keluar, dan serah koordinator yang bisa dilakukan. Kepanitiaan pindah ke Arsip dan tidak dihitung di batas 30.',
        ok: 'Tutup kepanitiaan',
        destructive: true,
      ) &&
      state.mounted) {
    await state.mutate('closeCommittee', {
      'groupID': group.text('id'),
    }, success: 'Kepanitiaan ditutup');
  }
}

Future<void> _reopenCommittee(
  _WorkspaceState state,
  String groupID,
  String name,
  bool planActive,
) async {
  if (!planActive) {
    return state.feedback(
      'Kepanitiaan bisa dibuka kembali saat paket organisasi aktif.',
      kind: GLToastKind.err,
    );
  }
  if (await state.confirm(
        'Buka kembali $name?',
        'Kepanitiaan kembali aktif dan dihitung di batas 30 kepanitiaan.',
        ok: 'Buka kembali',
      ) &&
      state.mounted) {
    await state.mutate('reopenCommittee', {
      'groupID': groupID,
    }, success: 'Kepanitiaan dibuka kembali');
  }
}

// MARK: - Project screen: Rencana + template/recap buttons

List<Widget> _projectPlanSection(
  _WorkspaceState state,
  JsonMap project,
  JsonMap group,
) {
  final store = state.store;
  final orgID = group.text('organizationID');
  if (store.organization(orgID) == null) return [];
  final items = store.planItems(project);
  final manage =
      store.canManageTasks(project) &&
      project['status'] == 'active' &&
      !store.isClosed(group);
  final label = store.isCommittee(group) ? 'sie' : 'proyek';
  // Officers and the coordinator see every project; a koordinator sie only
  // the sie they lead (§3).
  final reportable =
      _orgOfficer(store, orgID) ||
      _coordinator(store, group) ||
      (_member(store, group) && project.text('leadID') == store.currentUserID);
  final periodLabel = project.text('periodLabel');
  final period = periodLabel.isEmpty
      ? null
      : store
            .periods(orgID)
            .where((p) => p.text('label') == periodLabel)
            .firstOrNull;
  return [
    if (items.isNotEmpty)
      Column(
        key: Key('plan-section'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _workHeading(
            'Rencana',
            sub: '${items.length} butir belum menjadi tugas',
          ),
          SizedBox(height: 10),
          Container(
            padding: EdgeInsets.symmetric(vertical: 4, horizontal: 14),
            decoration: glBox(GLTheme.surface, 24),
            child: Column(
              children: [
                for (final item in items)
                  _planItemRow(state, project, group, item, manage),
              ],
            ),
          ),
        ],
      ),
    if (_canSaveTemplate(store, orgID) || reportable)
      Row(
        spacing: 8,
        children: [
          if (_canSaveTemplate(store, orgID))
            Expanded(
              child: GLOutlineButton(
                key: Key('project-save-template'),
                title: 'Simpan template',
                icon: store.organization(orgID)?['planActive'] == true
                    ? 'doc.on.doc'
                    : 'lock',
                onPressed: () {
                  if (store.organization(orgID)?['planActive'] != true) {
                    return state.feedback(
                      'Template bisa disimpan saat paket organisasi aktif.',
                      kind: GLToastKind.err,
                    );
                  }
                  state.open(
                    SaveTemplateScreen(
                      store: store,
                      projectID: project.text('id'),
                    ),
                  );
                },
              ),
            ),
          if (reportable)
            Expanded(
              child: GLOutlineButton(
                key: Key('project-report'),
                title: 'Rekap $label',
                icon: 'doc.text',
                onPressed: () => state.open(
                  ReportScreen(
                    store: store,
                    groupID: group.text('id'),
                    // A labelled project lives in its closed period.
                    periodID: period?.text('id'),
                    periodLabel: period?.text('label'),
                    projectID: project.text('id'),
                  ),
                ),
              ),
            ),
        ],
      ),
  ];
}

Widget _planItemRow(
  _WorkspaceState state,
  JsonMap project,
  JsonMap group,
  JsonMap item,
  bool manage,
) {
  final store = state.store;
  final due = item.date('dueAt')!;
  final late = due.isBefore(store.now);
  final id = item.text('id');
  return MergeSemantics(
    child: Container(
      key: Key('plan-item-$id'),
      constraints: BoxConstraints(minHeight: 64),
      padding: EdgeInsets.symmetric(vertical: 10),
      decoration: _grHairline,
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: 2,
              children: [
                Text(item.text('title'), style: gl(16, w600)),
                if (item.text('description').isNotEmpty)
                  Text(
                    item.text('description'),
                    style: gl(13, w400, 0, GLTheme.text3),
                  ),
                Wrap(
                  spacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      'Deadline ${GLFormat.date(due)}',
                      style: gl(13, w400, 0, GLTheme.secondary),
                    ),
                    if (late) _smallChip(('Lewat', GLTheme.coral)),
                  ],
                ),
              ],
            ),
          ),
          if (manage) ...[
            GLTap(
              key: Key('plan-delete-$id'),
              label: 'Hapus butir ${item.text('title')}',
              onTap: () => _deletePlanItem(state, item),
              child: SizedBox(
                width: 44,
                height: 44,
                child: GLIcon('trash', size: 20, color: GLTheme.danger),
              ),
            ),
            _orgPill(
              'Jadikan tugas',
              'plus',
              () => _showTaskSheet(
                state,
                project,
                group,
                title: item.text('title'),
                description: item.text('description'),
                dueAt: due,
                planItemID: id,
              ),
              key: Key('plan-task-$id'),
            ),
          ],
        ],
      ),
    ),
  );
}

Future<void> _deletePlanItem(_WorkspaceState state, JsonMap item) async {
  if (await state.confirm(
        'Hapus butir rencana?',
        '${item.text('title')} dihapus dari rencana. Tugas yang sudah dibuat tidak terpengaruh.',
        ok: 'Hapus',
        destructive: true,
      ) &&
      state.mounted) {
    await state.mutate('deletePlanItem', {
      'id': item.text('id'),
    }, success: 'Butir rencana dihapus');
  }
}

// MARK: - Templates

class TemplatesScreen extends _WorkspaceScreen {
  const TemplatesScreen({super.key, required super.store, required this.orgID});
  final String orgID;
  @override
  State<TemplatesScreen> createState() => _TemplatesState();
}

class _TemplatesState extends _WorkspaceState<TemplatesScreen>
    with _GroupActions<TemplatesScreen> {
  List<JsonMap>? rows;
  String? failure;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final value = await store.templates(widget.orgID);
      if (mounted) {
        setState(() {
          rows = value;
          failure = null;
        });
      }
    } catch (error) {
      if (mounted) setState(() => failure = '$error');
    }
  }

  @override
  Future<void> reload() async {
    await super.reload();
    await _load();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: store,
    builder: (context, _) {
      if (store.organization(widget.orgID) == null) {
        return GLAccessDenied(text: 'Kamu bukan anggota organisasi ini.');
      }
      final rows = this.rows;
      Widget section(String title, List<JsonMap> list, String empty) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _workHeading(title),
          SizedBox(height: 10),
          if (list.isEmpty)
            Text(empty, style: gl(14, w400, 0, GLTheme.secondary))
          else
            _workList([
              for (final row in list)
                _workRow(
                  key: Key('template-${row.text('id')}'),
                  icon: 'doc.on.doc',
                  tint: row['builtIn'] == true ? GLTheme.mint : GLTheme.sky,
                  title: row.text('name'),
                  subtitle:
                      '${row.number('sectionCount')} sie · ${row.number('itemCount')} butir rencana',
                  chips: [
                    if (row['mine'] == true)
                      _smallChip(('Buatanmu', GLTheme.lavender)),
                  ],
                  onTap: () async {
                    await Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => TemplateScreen(
                          store: store,
                          orgID: widget.orgID,
                          templateID: row.text('id'),
                          mine: row['mine'] == true,
                        ),
                      ),
                    );
                    if (mounted) _load();
                  },
                ),
            ]),
        ],
      );
      return detailPage(
        title: 'Template proker',
        children: [
          Text(
            'Template berisi sie dan rencana kerja, bukan tugas. Setelah dipakai, koordinator mengubah tiap butir rencana menjadi tugas sambil memilih orangnya.',
            style: gl(14, w400, 0, GLTheme.text3, 4),
          ),
          if (failure != null) ...[
            GLFormError(failure!),
            GLOutlineButton(
              title: 'Coba lagi',
              icon: 'arrow.clockwise',
              onPressed: _load,
            ),
          ] else if (rows == null)
            Center(child: CircularProgressIndicator.adaptive())
          else ...[
            section(
              'Organisasi',
              [
                for (final r in rows)
                  if (r['builtIn'] != true) r,
              ],
              'Belum ada template organisasi. Simpan dari layar proyek atau sie.',
            ),
            section('Bawaan Grouply', [
              for (final r in rows)
                if (r['builtIn'] == true) r,
            ], 'Belum ada template bawaan.'),
          ],
        ],
      );
    },
  );
}

class TemplateScreen extends _WorkspaceScreen {
  const TemplateScreen({
    super.key,
    required super.store,
    required this.orgID,
    required this.templateID,
    this.mine = false,
  });
  final String orgID, templateID;
  final bool mine;
  @override
  State<TemplateScreen> createState() => _TemplateState();
}

class _TemplateState extends _WorkspaceState<TemplateScreen>
    with _GroupActions<TemplateScreen> {
  JsonMap? detail;
  String? failure;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final value = await store.template(widget.templateID);
      if (mounted) {
        setState(() {
          detail = value;
          failure = null;
        });
      }
    } catch (error) {
      if (mounted) setState(() => failure = '$error');
    }
  }

  @override
  Future<void> reload() async {
    await super.reload();
    await _load();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: store,
    builder: (context, _) {
      final org = store.organization(widget.orgID);
      if (org == null) {
        return GLAccessDenied(text: 'Kamu bukan anggota organisasi ini.');
      }
      final detail = this.detail;
      final builtIn = detail?['builtIn'] == true;
      final canDelete =
          detail != null &&
          !builtIn &&
          (widget.mine || store.orgRole(widget.orgID) == 'ketua');
      final targets = _coordinatedGroups(store, widget.orgID);
      return detailPage(
        title: 'Template',
        trailing: canDelete
            ? GLCircleButton(
                icon: 'trash',
                label: 'Hapus template',
                onTap: _delete,
              )
            : null,
        children: [
          if (failure != null) ...[
            GLFormError(failure!),
            GLOutlineButton(
              title: 'Coba lagi',
              icon: 'arrow.clockwise',
              onPressed: _load,
            ),
          ] else if (detail == null)
            Center(child: CircularProgressIndicator.adaptive())
          else ...[
            Container(
              padding: EdgeInsets.all(18),
              decoration: glBox(GLTheme.surface, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: 8,
                children: [
                  Text(detail.text('name'), style: gl(23, w700, -0.02)),
                  Wrap(
                    children: [
                      _smallChip(
                        builtIn
                            ? ('Bawaan Grouply', GLTheme.mint)
                            : ('Template organisasi', GLTheme.sky),
                      ),
                    ],
                  ),
                  if (detail.text('description').isNotEmpty)
                    Text(
                      detail.text('description'),
                      style: gl(15, w400, 0, GLTheme.text3, 4),
                    ),
                ],
              ),
            ),
            if (targets.isNotEmpty)
              GLSubmitButton(
                key: Key('template-use'),
                title: 'Pakai template',
                onPressed: () => _use(detail, targets),
              ),
            for (final section
                in (detail['sections'] as List).cast<JsonMap>()) ...[
              _workHeading(
                section.text('title'),
                sub:
                    'Deadline sie ${_offsetLabel(section.number('offsetDays').toInt())}',
              ),
              if ((section['items'] as List).isEmpty)
                Text(
                  'Tanpa butir rencana.',
                  style: gl(14, w400, 0, GLTheme.secondary),
                )
              else
                _workList([
                  for (final item in (section['items'] as List).cast<JsonMap>())
                    Container(
                      constraints: BoxConstraints(minHeight: 52),
                      padding: EdgeInsets.symmetric(vertical: 8),
                      decoration: _grHairline,
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              item.text('title'),
                              style: gl(15, w500),
                            ),
                          ),
                          _smallChip((
                            _offsetLabel(item.number('offsetDays').toInt()),
                            GLTheme.muted,
                          )),
                        ],
                      ),
                    ),
                ]),
            ],
            if (!builtIn && !widget.mine)
              _reportButton(
                this,
                'template',
                widget.templateID,
                'Laporkan template',
              ),
          ],
        ],
      );
    },
  );

  Future<void> _use(JsonMap detail, List<JsonMap> targets) async {
    if (store.organization(widget.orgID)?['planActive'] != true) {
      return feedback(
        'Template bisa dipakai saat paket organisasi aktif.',
        kind: GLToastKind.err,
      );
    }
    final groupID = await showGLSheet<String>(
      context,
      title: 'Pakai ${detail.text('name')}',
      subtitle: 'Sie dan rencananya dibuat di grup yang kamu pilih.',
      builder: (_) => _ApplyTemplateSheet(
        store: store,
        templateID: widget.templateID,
        detail: detail,
        targets: targets,
      ),
    );
    if (groupID != null && mounted) {
      open(GroupScreen(store: store, groupID: groupID));
    }
  }

  Future<void> _delete() async {
    if (await confirm(
          'Hapus template?',
          '${detail?.text('name')} hilang dari daftar organisasi. Sie yang sudah dibuat dari template ini tetap ada.',
          ok: 'Hapus',
          destructive: true,
        ) &&
        mounted) {
      final result = await mutate('deleteTemplate', {
        'id': widget.templateID,
      }, success: 'Template dihapus');
      if (result != null && mounted) Navigator.of(context).maybePop();
    }
  }
}

/// Group + event day; pops with the group ID after `applyTemplate`.
class _ApplyTemplateSheet extends StatefulWidget {
  const _ApplyTemplateSheet({
    required this.store,
    required this.templateID,
    required this.detail,
    required this.targets,
  });
  final GrouplyStore store;
  final String templateID;
  final JsonMap detail;
  final List<JsonMap> targets;
  @override
  State<_ApplyTemplateSheet> createState() => _ApplyTemplateSheetState();
}

class _ApplyTemplateSheetState extends State<_ApplyTemplateSheet> {
  late String groupID = widget.targets.length == 1
      ? widget.targets.single.text('id')
      : '';
  DateTime? event;
  String? error;
  bool busy = false;

  List<JsonMap> get sections =>
      (widget.detail['sections'] as List).cast<JsonMap>();

  Future<void> _save() async {
    if (busy) return;
    final event = this.event;
    if (groupID.isEmpty) return setState(() => error = 'Pilih grup tujuan.');
    if (event == null) return setState(() => error = 'Pilih tanggal acara.');
    final now = widget.store.now;
    // eventAt = 23:59 local on the event day (§4.1).
    final eventAt = DateTime(event.year, event.month, event.day, 23, 59);
    if (sections.any(
      (s) => !eventAt
          .add(Duration(days: s.number('offsetDays').toInt()))
          .isAfter(now),
    )) {
      return setState(
        () => error =
            'Ada sie yang deadline-nya sudah lewat. Pilih tanggal acara yang lebih jauh.',
      );
    }
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await widget.store.mutate('applyTemplate', {
        'templateID': widget.templateID,
        'groupID': groupID,
        'eventAt': eventAt.toUtc().toIso8601String(),
      });
      if (!mounted) return;
      showGLToast(context, '${sections.length} sie dibuat dari template');
      Navigator.of(context).pop(groupID);
    } catch (e) {
      final text = '$e';
      if (mounted) {
        setState(
          () => error = text == GrouplyStore.codeText('invalid_input')
              ? 'Ada sie yang deadline-nya sudah lewat. Pilih tanggal acara yang lebih jauh.'
              : text,
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final event = this.event;
    return PopScope(
      canPop: !busy,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 16,
        children: [
          GLField(
            'Grup tujuan',
            required: true,
            child: _workList([
              for (final group in widget.targets)
                GLTap(
                  key: Key('apply-group-${group.text('id')}'),
                  onTap: () => setState(() => groupID = group.text('id')),
                  child: Semantics(
                    selected: groupID == group.text('id'),
                    child: Container(
                      constraints: BoxConstraints(minHeight: 56),
                      decoration: _grHairline,
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              group.text('name'),
                              style: gl(16, w600),
                            ),
                          ),
                          if (groupID == group.text('id'))
                            GLIcon('checkmark.circle.fill', size: 22),
                        ],
                      ),
                    ),
                  ),
                ),
            ]),
          ),
          GLField(
            'Tanggal acara',
            required: true,
            child: _dayButton(
              key: Key('apply-event'),
              label: 'Pilih tanggal acara',
              value: event,
              onTap: () async {
                final today = _day(widget.store.now);
                final picked = await _pickDay(
                  context,
                  title: 'Tanggal acara',
                  initial: event ?? today.add(Duration(days: 30)),
                  first: today,
                );
                if (picked != null && mounted) {
                  setState(() {
                    this.event = picked;
                    error = null;
                  });
                }
              },
            ),
          ),
          if (event != null)
            Container(
              padding: EdgeInsets.all(14),
              decoration: glBox(GLTheme.surface, 18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: 4,
                children: [
                  for (final s in sections)
                    Text(
                      '${s.text('title')} · ${GLFormat.date(event.add(Duration(days: s.number('offsetDays').toInt())))}',
                      style: gl(14, w400, 0, GLTheme.text3),
                    ),
                  Text(
                    'Butir yang tanggalnya sudah lewat tetap dibuat dan ditandai "Lewat".',
                    style: gl(13, w400, 0, GLTheme.secondary),
                  ),
                ],
              ),
            ),
          if (error != null) GLFormError(error!),
          GLSubmitButton(
            key: Key('apply-save'),
            title: busy ? 'Membuat…' : 'Buat sie dari template',
            busy: busy,
            onPressed: _save,
          ),
        ],
      ),
    );
  }
}

// MARK: - Simpan sebagai template

class SaveTemplateScreen extends _WorkspaceScreen {
  const SaveTemplateScreen({
    super.key,
    required super.store,
    required this.projectID,
  });
  final String projectID;
  @override
  State<SaveTemplateScreen> createState() => _SaveTemplateState();
}

class _DraftItem {
  _DraftItem(String title, this.description, this.offset)
    : title = TextEditingController(text: title);
  final TextEditingController title;
  final String description;
  final int offset;
}

class _DraftSection {
  _DraftSection(String title, this.description, this.offset, this.items)
    : title = TextEditingController(text: title);
  final TextEditingController title;
  final String description;
  final int offset;
  final List<_DraftItem> items;
}

String _clip(String text, int max) =>
    text.length > max ? text.substring(0, max) : text;

class _SaveTemplateState extends _WorkspaceState<SaveTemplateScreen>
    with _GroupActions<SaveTemplateScreen> {
  late final Set<String> picked = {};
  DateTime? event;
  List<_DraftSection>? draft;
  final name = TextEditingController();
  final description = TextEditingController();
  String? error;
  bool saving = false;

  @override
  void initState() {
    super.initState();
    final project = store.project(widget.projectID);
    final group = store.group(project?.text('groupID') ?? '');
    if (project == null || group == null) return;
    picked.add(widget.projectID);
    if (store.isCommittee(group)) {
      for (final p in _grProjects(store, group.text('id'))) {
        if (p['status'] != 'archived') picked.add(p.text('id'));
      }
    }
    name.text = _clip(
      store.isCommittee(group) ? group.text('name') : project.text('title'),
      80,
    );
  }

  @override
  void dispose() {
    name.dispose();
    description.dispose();
    _dropDraft();
    super.dispose();
  }

  void _dropDraft() {
    for (final section in draft ?? <_DraftSection>[]) {
      section.title.dispose();
      for (final item in section.items) {
        item.title.dispose();
      }
    }
    draft = null;
  }

  /// Latest deadline of the chosen projects: a sensible event day.
  DateTime _defaultEvent(List<JsonMap> projects) {
    final dues = [
      for (final p in projects)
        if (picked.contains(p.text('id'))) _day(p.date('dueAt')!),
    ]..sort();
    return dues.isEmpty ? _day(store.now) : dues.last;
  }

  /// Sections from what the viewer can see: each project, its tasks and
  /// remaining plan items, dated relative to [event] (§1.3).
  void _build(List<JsonMap> projects, DateTime event) {
    int offset(DateTime? due) => due == null
        ? 0
        : _day(due).difference(event).inDays.clamp(-365, 365).toInt();
    var total = 0;
    final sections = <_DraftSection>[];
    for (final p in projects.where((p) => picked.contains(p.text('id')))) {
      if (sections.length == 20) break;
      final tasks =
          store.tasks.where((t) => t.text('projectID') == p.text('id')).toList()
            ..sort((a, b) => a.text('dueAt').compareTo(b.text('dueAt')));
      final items = [
        for (final t in tasks)
          _DraftItem(
            _clip(t.text('title'), 120),
            _clip(t.text('description'), 2000),
            offset(t.date('dueAt')),
          ),
        for (final i in store.planItems(p))
          _DraftItem(
            _clip(i.text('title'), 120),
            _clip(i.text('description'), 2000),
            offset(i.date('dueAt')),
          ),
      ].take((200 - total).clamp(0, 40)).toList();
      total += items.length;
      sections.add(
        _DraftSection(
          _clip(p.text('title'), 120),
          _clip(p.text('description'), 2000),
          offset(p.date('dueAt')),
          items,
        ),
      );
    }
    setState(() {
      _dropDraft();
      draft = sections;
      error = null;
    });
  }

  Future<void> _save(String orgID) async {
    final draft = this.draft;
    if (saving || draft == null) return;
    final title = name.text.trim();
    if (title.isEmpty) return setState(() => error = 'Nama template wajib.');
    if (draft.isEmpty) return setState(() => error = 'Sisakan minimal 1 sie.');
    final short = [
      for (final s in draft) s.title,
      for (final s in draft)
        for (final i in s.items) i.title,
    ].any((c) => c.text.trim().length < 3);
    if (short) {
      return setState(() => error = 'Judul sie dan butir minimal 3 karakter.');
    }
    setState(() {
      saving = true;
      error = null;
    });
    try {
      await store.mutate('createTemplate', {
        'organizationID': orgID,
        'name': title,
        'description': description.text.trim(),
        'sections': [
          for (final s in draft)
            {
              'title': s.title.text.trim(),
              'description': s.description,
              'offsetDays': s.offset,
              'items': [
                for (final i in s.items)
                  {
                    'title': i.title.text.trim(),
                    'description': i.description,
                    'offsetDays': i.offset,
                  },
              ],
            },
        ],
      });
      if (!mounted) return;
      feedback('Template disimpan');
      Navigator.of(context).maybePop();
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: store,
    builder: (context, _) {
      final project = store.project(widget.projectID);
      final group = store.group(project?.text('groupID') ?? '');
      final orgID = group?.text('organizationID') ?? '';
      if (project == null ||
          !_member(store, group) ||
          !_canSaveTemplate(store, orgID)) {
        return GLAccessDenied();
      }
      final projects = _grProjects(store, group!.text('id'));
      final draft = this.draft;
      final event = this.event ?? _defaultEvent(projects);
      return detailPage(
        title: 'Simpan template',
        children: [
          Text(
            draft == null
                ? 'Pilih proker yang jadi kerangka. Tugas dan rencananya disalin sebagai butir rencana tanpa nama orang; kamu bisa mengubahnya sebelum disimpan.'
                : 'Periksa dan ubah isinya. Tanggal disimpan relatif terhadap hari acara.',
            style: gl(14, w400, 0, GLTheme.text3, 4),
          ),
          if (draft == null) ...[
            _workHeading(store.isCommittee(group) ? 'Sie' : 'Proyek'),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final p in projects)
                  FilterChip(
                    key: Key('save-pick-${p.text('id')}'),
                    label: Text(p.text('title')),
                    selected: picked.contains(p.text('id')),
                    onSelected: (on) => setState(
                      () => on
                          ? picked.add(p.text('id'))
                          : picked.remove(p.text('id')),
                    ),
                  ),
              ],
            ),
            GLField(
              'Hari acara (patokan tanggal)',
              child: _dayButton(
                key: Key('save-event'),
                label: 'Pilih hari acara',
                value: event,
                onTap: () async {
                  final day = await _pickDay(
                    context,
                    title: 'Hari acara',
                    initial: event,
                    first: DateTime(2020),
                  );
                  if (day != null && mounted) setState(() => this.event = day);
                },
              ),
            ),
            GLSubmitButton(
              key: Key('save-preview'),
              title: 'Susun pratinjau',
              onPressed: () => picked.isEmpty
                  ? setState(() => error = 'Pilih minimal satu proker.')
                  : _build(projects, event),
            ),
            if (error != null) GLFormError(error!),
          ] else ...[
            GLField(
              'Nama template',
              required: true,
              child: GLTextField(
                key: Key('save-name'),
                controller: name,
                maxLength: 80,
                textCapitalization: TextCapitalization.sentences,
              ),
            ),
            GLField(
              'Uraian',
              child: GLTextField(
                key: Key('save-description'),
                controller: description,
                maxLength: 1000,
                minLines: 2,
                maxLines: 4,
                hint: 'Kapan dan untuk acara apa template ini dipakai',
                textCapitalization: TextCapitalization.sentences,
              ),
            ),
            for (final (si, section) in draft.indexed)
              Container(
                key: Key('save-section-$si'),
                padding: EdgeInsets.all(14),
                decoration: glBox(GLTheme.surface, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  spacing: 8,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Sie · deadline ${_offsetLabel(section.offset)}',
                            style: gl(13, w600, 0, GLTheme.secondary),
                          ),
                        ),
                        GLTap(
                          label: 'Buang sie',
                          onTap: () => setState(() {
                            draft.removeAt(si).title.dispose();
                          }),
                          child: SizedBox(
                            width: 44,
                            height: 44,
                            child: GLIcon('xmark', size: 20),
                          ),
                        ),
                      ],
                    ),
                    GLTextField(
                      key: Key('save-section-title-$si'),
                      controller: section.title,
                      maxLength: 120,
                      semanticLabel: 'Judul sie',
                    ),
                    for (final (ii, item) in section.items.indexed)
                      Row(
                        spacing: 6,
                        children: [
                          Expanded(
                            child: GLTextField(
                              key: Key('save-item-$si-$ii'),
                              controller: item.title,
                              maxLength: 120,
                              semanticLabel: 'Judul butir rencana',
                            ),
                          ),
                          _smallChip((
                            _offsetLabel(item.offset),
                            GLTheme.muted,
                          )),
                          GLTap(
                            key: Key('save-item-drop-$si-$ii'),
                            label: 'Buang butir',
                            onTap: () => setState(() {
                              section.items.removeAt(ii).title.dispose();
                            }),
                            child: SizedBox(
                              width: 44,
                              height: 44,
                              child: GLIcon('xmark', size: 18),
                            ),
                          ),
                        ],
                      ),
                    if (section.items.isEmpty)
                      Text(
                        'Tanpa butir rencana.',
                        style: gl(13, w400, 0, GLTheme.secondary),
                      ),
                  ],
                ),
              ),
            if (error != null) GLFormError(error!),
            GLSubmitButton(
              key: Key('save-template'),
              title: saving ? 'Menyimpan…' : 'Simpan template',
              busy: saving,
              onPressed: () => _save(orgID),
            ),
            GLOutlineButton(
              title: 'Ubah pilihan proker',
              onPressed: () => setState(_dropDraft),
            ),
          ],
        ],
      );
    },
  );
}

// MARK: - Serah terima (Ketua)

class HandoverScreen extends _WorkspaceScreen {
  const HandoverScreen({super.key, required super.store, required this.orgID});
  final String orgID;
  @override
  State<HandoverScreen> createState() => _HandoverState();
}

class _HandoverState extends _WorkspaceState<HandoverScreen>
    with _GroupActions<HandoverScreen> {
  final next = TextEditingController();
  List<JsonMap>? groups;
  String? error, failure;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    next.dispose();
    super.dispose();
  }

  /// Every org group with members (`grouply_org_members`): the snapshot
  /// only holds the groups the Ketua is in.
  Future<void> _load() async {
    try {
      final value = await store.orgMembers(widget.orgID);
      if (mounted) {
        setState(() {
          groups = value;
          failure = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => failure = '$e');
    }
  }

  @override
  Future<void> reload() async {
    await super.reload();
    await _load();
  }

  /// Runs [action], then reloads the member list whatever the outcome.
  Future<void> _act(String action, JsonMap payload, String success) async {
    await mutate(action, payload, success: success);
    if (mounted) await _load();
  }

  Widget _check(String title, String sub, List<Widget> body) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    spacing: 10,
    children: [
      _workHeading(title, sub: sub),
      ...body,
    ],
  );

  Widget _line(String text, {String? sub, Widget? action, Key? key}) =>
      Container(
        key: key,
        constraints: BoxConstraints(minHeight: 52),
        padding: EdgeInsets.symmetric(vertical: 6),
        decoration: _grHairline,
        child: Row(
          spacing: 8,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(text, style: gl(15, w500)),
                  if (sub != null)
                    Text(sub, style: gl(13, w400, 0, GLTheme.secondary)),
                ],
              ),
            ),
            ?action,
          ],
        ),
      );

  static List<JsonMap> _members(JsonMap group) =>
      (group['members'] as List).cast<JsonMap>();

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: store,
    builder: (context, _) {
      final org = store.organization(widget.orgID);
      if (org == null || store.orgRole(widget.orgID) != 'ketua') {
        return GLAccessDenied(text: 'Serah terima hanya untuk Ketua.');
      }
      final orgID = widget.orgID;
      final label = org.text('periodLabel');
      final active = org['planActive'] == true;
      final ownGroups = [
        for (final g in store.groups)
          if (g.text('organizationID') == orgID) g,
      ];
      final projects = [
        for (final g in ownGroups) ..._grProjects(store, g.text('id')),
      ];
      final archiving = [
        for (final p in projects)
          if (p['status'] == 'completed' ||
              (p['status'] == 'archived' && p.text('periodLabel').isEmpty))
            p,
      ];
      final carried = [
        for (final p in projects)
          if (p['status'] == 'active') p,
      ];
      final groups = this.groups;
      final officers = _orgRows(org, 'roles');
      return detailPage(
        title: 'Serah terima',
        children: [
          Text(
            label.isEmpty
                ? 'Daftar periksa sebelum menutup periode kepengurusan.'
                : 'Daftar periksa sebelum menutup periode $label.',
            style: gl(14, w400, 0, GLTheme.text3, 4),
          ),
          _check('1. Label periode', 'Sekarang: ${label.isEmpty ? '—' : label}', [
            if (label.isEmpty)
              GLNotice(
                text:
                    'Isi label periode sekarang dulu lewat "Ubah info organisasi" di layar Organisasi.',
              ),
            GLField(
              'Periode baru',
              required: true,
              child: GLTextField(
                key: Key('handover-next'),
                controller: next,
                hint: 'Contoh: 2027/2028',
                maxLength: 40,
              ),
            ),
          ]),
          _check(
            '2. Proker',
            '${archiving.length} masuk arsip · ${carried.length} dibawa ke periode baru',
            [
              _workList([
                for (final p in archiving)
                  _line(p.text('title'), sub: 'Diarsipkan'),
                for (final p in carried)
                  _line(p.text('title'), sub: 'Dibawa (masih berjalan)'),
                if (projects.isEmpty) _line('Belum ada proker.'),
              ]),
              Text(
                'Daftar proker berasal dari divisi dan kepanitiaan yang kamu ikuti; penutupan periode tetap berlaku untuk semua grup.',
                style: gl(13, w400, 0, GLTheme.secondary),
              ),
            ],
          ),
          if (failure != null) ...[
            GLFormError(failure!),
            GLOutlineButton(
              title: 'Coba lagi',
              icon: 'arrow.clockwise',
              onPressed: _load,
            ),
          ] else if (groups == null)
            Center(child: CircularProgressIndicator.adaptive())
          else
            ..._groupChecks(groups, active),
          _check('6. Pengurus', 'Ketua, BPH, dan Pembina periode baru', [
            _workList([
              for (final o in officers)
                _line(o.text('name'), sub: _orgRoleLabel(o.text('role'))),
            ]),
            GLOutlineButton(
              key: Key('handover-roles'),
              title: 'Atur jabatan',
              icon: 'person.badge.shield.checkmark',
              onPressed: () => Navigator.of(context).pop('roles'),
            ),
            Text(
              'Serahkan jabatan Ketua paling akhir, setelah periode ditutup.',
              style: gl(13, w400, 0, GLTheme.secondary),
            ),
          ]),
          if (error != null) GLFormError(error!),
          GLSubmitButton(
            key: Key('handover-close-period'),
            title: busy ? 'Menutup…' : 'Tutup periode',
            busy: busy,
            onPressed: () => _closePeriod(org),
          ),
        ],
      );
    },
  );

  /// Steps 3–5 from `grouply_org_members`.
  List<Widget> _groupChecks(List<JsonMap> groups, bool active) {
    String name(JsonMap group, String id) =>
        _members(group).where((m) => m['id'] == id).firstOrNull?.text('name') ??
        (id.isEmpty ? 'Belum ada' : 'Anggota');
    final open = [
      for (final g in groups)
        if (g['isCommittee'] == true && g['closed'] != true) g,
    ];
    final closed = [
      for (final g in groups)
        if (g['closed'] == true) g,
    ];
    final divisions = [
      for (final g in groups)
        if (g['isCommittee'] != true) g,
    ];
    // Seats held by people left only in a closed committee (§10).
    final seated = {
      for (final g in groups)
        if (g['closed'] != true)
          for (final m in _members(g)) m.text('id'),
    };
    final stranded = [
      for (final g in closed)
        for (final m in _members(g))
          if (!seated.contains(m.text('id'))) (g, m),
    ];
    return [
      _check(
        '3. Kepanitiaan',
        open.isEmpty
            ? 'Tidak ada kepanitiaan aktif'
            : 'Tutup yang pekerjaannya sudah selesai',
        [
          if (open.isNotEmpty || closed.isNotEmpty)
            _workList([
              for (final c in open)
                _line(
                  c.text('name'),
                  sub: 'Aktif',
                  key: Key('handover-committee-${c.text('groupID')}'),
                  action: _orgPill(
                    'Tutup',
                    'archivebox',
                    () => _close(c),
                    key: Key('handover-close-${c.text('groupID')}'),
                  ),
                ),
              for (final c in closed)
                _line(
                  c.text('name'),
                  sub: 'Ditutup',
                  key: Key('handover-committee-${c.text('groupID')}'),
                  action: _orgPill(
                    'Buka',
                    active ? 'arrow.counterclockwise' : 'lock',
                    () async {
                      await _reopenCommittee(
                        this,
                        c.text('groupID'),
                        c.text('name'),
                        active,
                      );
                      if (mounted) await _load();
                    },
                    key: Key('handover-reopen-${c.text('groupID')}'),
                  ),
                ),
            ]),
        ],
      ),
      _check('4. Koordinator divisi', 'Kadiv periode baru', [
        _workList([
          for (final d in divisions)
            _line(
              d.text('name'),
              sub: name(d, d.text('coordinatorID')),
              key: Key('handover-division-${d.text('groupID')}'),
              action: _members(d).length < 2
                  ? null
                  : _orgPill(
                      'Ganti',
                      'person.badge.shield.checkmark',
                      () => _setCoordinator(d),
                      key: Key('handover-coordinator-${d.text('groupID')}'),
                    ),
            ),
        ]),
      ]),
      _check(
        '5. Kursi',
        '${stranded.length} orang hanya tersisa di kepanitiaan tertutup',
        [
          if (stranded.isNotEmpty)
            _workList([
              for (final (g, m) in stranded)
                _line(
                  m.text('name'),
                  sub: m['id'] == g['coordinatorID']
                      ? '${g.text('name')} · koordinator; ganti dulu sebelum dikeluarkan'
                      : g.text('name'),
                  key: Key('handover-seat-${m.text('id')}'),
                  action: m['id'] == g['coordinatorID']
                      ? (_members(g).length < 2
                            ? null
                            : _orgPill(
                                'Ganti',
                                'person.badge.shield.checkmark',
                                () => _setCoordinator(g),
                              ))
                      : _orgPill(
                          'Keluarkan',
                          'person.badge.minus',
                          () => _removeClosed(g, m),
                          key: Key('handover-remove-${m.text('id')}'),
                        ),
                ),
            ]),
          Text(
            'Mereka tetap memakai kursi dan menerima pengumuman sampai dikeluarkan.',
            style: gl(13, w400, 0, GLTheme.secondary),
          ),
        ],
      ),
    ];
  }

  Future<void> _close(JsonMap committee) async {
    if (await confirm(
          'Tutup ${committee.text('name')}?',
          'Bisa ditutup bila semua tugasnya selesai, tidak ada sie aktif, dan tidak ada pengajuan yang menunggu.',
          ok: 'Tutup kepanitiaan',
          destructive: true,
        ) &&
        mounted) {
      await _act('closeCommittee', {
        'groupID': committee.text('groupID'),
      }, 'Kepanitiaan ditutup');
    }
  }

  Future<void> _removeClosed(JsonMap group, JsonMap member) async {
    if (await confirm(
          'Keluarkan ${member.text('name')}?',
          '${member.text('name')} keluar dari ${group.text('name')} yang sudah ditutup, sehingga kursinya bebas. Riwayatnya tetap tersimpan.',
          ok: 'Keluarkan',
          destructive: true,
        ) &&
        mounted) {
      await _act('removeClosedMember', {
        'groupID': group.text('groupID'),
        'userID': member.text('id'),
      }, '${member.text('name')} dikeluarkan');
    }
  }

  Future<void> _setCoordinator(JsonMap group) async {
    final picked = await showGLSheet<JsonMap>(
      context,
      title: 'Koordinator ${group.text('name')}',
      subtitle: 'Pilih anggota grup sebagai koordinator baru.',
      builder: (sheet) => _workList([
        for (final m in _members(group))
          if (m['id'] != group['coordinatorID'])
            GLTap(
              key: Key('coordinator-pick-${m.text('id')}'),
              onTap: () => Navigator.of(sheet).pop(m),
              child: Container(
                constraints: BoxConstraints(minHeight: 60),
                decoration: _grHairline,
                child: Row(
                  children: [
                    GLAvatar(
                      user: store.user(m.text('id')) ?? m,
                      size: 40,
                      fontSize: 13,
                    ),
                    SizedBox(width: 12),
                    Expanded(child: Text(m.text('name'), style: gl(16, w600))),
                  ],
                ),
              ),
            ),
      ]),
    );
    if (picked == null || !mounted) return;
    await _act(
      'setCoordinator',
      {'groupID': group.text('groupID'), 'userID': picked.text('id')},
      '${picked.text('name')} menjadi koordinator ${group.text('name')}',
    );
  }

  Future<void> _closePeriod(JsonMap org) async {
    final current = org.text('periodLabel');
    final label = next.text.trim();
    if (current.isEmpty) {
      return setState(
        () => error = 'Isi label periode sekarang dulu di layar Organisasi.',
      );
    }
    if (label.isEmpty || label == current) {
      return setState(
        () => error = 'Isi label periode baru yang berbeda dari $current.',
      );
    }
    setState(() => error = null);
    if (!await confirm(
          'Tutup periode $current?',
          'Proker yang sudah selesai diarsipkan dan diberi label $current. Proker yang masih berjalan pindah ke $label. Arsip tidak bisa dipulihkan ke daftar aktif.',
          ok: 'Tutup periode',
          destructive: true,
        ) ||
        !mounted ||
        busy ||
        store.loading) {
      return;
    }
    setState(() => busy = true);
    try {
      final result = await store.mutate('closePeriod', {
        'organizationID': widget.orgID,
        'currentLabel': current,
        'nextLabel': label,
      });
      if (!mounted) return;
      feedback(
        'Periode $current ditutup · ${result.number('archived')} proker diarsipkan',
      );
      Navigator.of(context).maybePop();
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }
}

// MARK: - Arsip (pengurus)

class ArchiveScreen extends _WorkspaceScreen {
  const ArchiveScreen({super.key, required super.store, required this.orgID});
  final String orgID;
  @override
  State<ArchiveScreen> createState() => _ArchiveState();
}

class _ArchiveState extends _WorkspaceState<ArchiveScreen>
    with _GroupActions<ArchiveScreen> {
  JsonMap? data;
  String? failure;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final value = await store.orgArchive(widget.orgID);
      if (mounted) {
        setState(() {
          data = value;
          failure = null;
        });
      }
    } catch (error) {
      if (mounted) setState(() => failure = '$error');
    }
  }

  @override
  Future<void> reload() async {
    await super.reload();
    await _load();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: store,
    builder: (context, _) {
      final org = store.organization(widget.orgID);
      if (org == null || !_orgOfficer(store, widget.orgID)) {
        return GLAccessDenied(text: 'Arsip hanya untuk pengurus organisasi.');
      }
      final data = this.data;
      final groups = _orgRows(org, 'divisions');
      return detailPage(
        title: 'Arsip',
        children: [
          _workHeading(
            'Periode berjalan',
            sub: org.text('periodLabel').isEmpty
                ? 'Rekap LPJ per divisi atau kepanitiaan'
                : 'Periode ${org.text('periodLabel')}',
          ),
          _workList([
            for (final d in groups)
              _workRow(
                key: Key('archive-current-${d.text('id')}'),
                icon: 'doc.text',
                tint: d['isCommittee'] == true ? GLTheme.butter : GLTheme.sky,
                title: d.text('name'),
                subtitle: d['closed'] == true
                    ? 'Kepanitiaan ditutup · rekap'
                    : 'Rekap periode berjalan',
                onTap: () =>
                    open(ReportScreen(store: store, groupID: d.text('id'))),
              ),
          ]),
          if (store.orgRole(widget.orgID) == 'ketua' &&
              groups.any((d) => d['closed'] == true))
            _workList([
              for (final d in groups)
                if (d['closed'] == true)
                  Container(
                    constraints: BoxConstraints(minHeight: 56),
                    decoration: _grHairline,
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            '${d.text('name')} · ditutup',
                            style: gl(15, w500),
                          ),
                        ),
                        _orgPill(
                          'Buka kembali',
                          org['planActive'] == true
                              ? 'arrow.counterclockwise'
                              : 'lock',
                          () => _reopenCommittee(
                            this,
                            d.text('id'),
                            d.text('name'),
                            org['planActive'] == true,
                          ),
                          key: Key('archive-reopen-${d.text('id')}'),
                        ),
                      ],
                    ),
                  ),
            ]),
          if (failure != null) ...[
            GLFormError(failure!),
            GLOutlineButton(
              title: 'Coba lagi',
              icon: 'arrow.clockwise',
              onPressed: _load,
            ),
          ] else if (data == null)
            Center(child: CircularProgressIndicator.adaptive())
          else if ((data['periods'] as List).isEmpty)
            Text(
              'Belum ada periode yang ditutup. Periode masuk arsip lewat Serah terima.',
              style: gl(14, w400, 0, GLTheme.secondary),
            )
          else
            for (final period in (data['periods'] as List).cast<JsonMap>())
              _period(period),
        ],
      );
    },
  );

  Widget _period(JsonMap period) {
    final started = period.date('startedAt');
    final closed = period.date('closedAt')!;
    final projects = (period['projects'] as List).cast<JsonMap>();
    final committees = (period['committees'] as List).cast<JsonMap>();
    return Column(
      key: Key('archive-period-${period.text('id')}'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 10,
      children: [
        _workHeading(
          'Periode ${period.text('label')}',
          sub:
              '${started == null ? '' : '${GLFormat.date(started)} – '}${GLFormat.date(closed)}',
        ),
        if (projects.isEmpty)
          Text(
            'Tidak ada proker berlabel periode ini.',
            style: gl(14, w400, 0, GLTheme.secondary),
          )
        else
          _workList([
            for (final p in projects)
              _workRow(
                key: Key('archive-project-${p.text('id')}'),
                icon: 'folder',
                tint: GLTheme.butter,
                title: p.text('title'),
                subtitle:
                    '${p.text('groupName')} · ${p.number('done')}/${p.number('total')} tugas selesai',
                onTap: () => open(
                  ReportScreen(
                    store: store,
                    groupID: p.text('groupID'),
                    periodID: period.text('id'),
                    periodLabel: period.text('label'),
                    projectID: p.text('id'),
                    candidates: [
                      for (final q in projects)
                        if (q.text('groupID') == p.text('groupID')) q,
                    ],
                  ),
                ),
              ),
          ]),
        if (committees.isNotEmpty)
          _workList([
            for (final c in committees)
              _workRow(
                icon: 'archivebox',
                tint: GLTheme.chip,
                title: c.text('name'),
                subtitle:
                    'Kepanitiaan ditutup ${GLFormat.date(c.date('closedAt')!)}',
                onTap: () => open(
                  ReportScreen(
                    store: store,
                    groupID: c.text('id'),
                    periodID: period.text('id'),
                    periodLabel: period.text('label'),
                  ),
                ),
              ),
          ]),
      ],
    );
  }
}

// MARK: - Rekap LPJ

class ReportScreen extends _WorkspaceScreen {
  const ReportScreen({
    super.key,
    required super.store,
    required this.groupID,
    this.periodID,
    this.periodLabel,
    this.projectID,
    this.candidates,
  });
  final String groupID;

  /// Fixed period (from the archive); null = choose, starting at current.
  final String? periodID, periodLabel;

  /// Pre-selected project; [candidates] lists projects known from the
  /// archive when the group is not in the viewer's snapshot.
  final String? projectID;
  final List<JsonMap>? candidates;

  /// Replaced in widget tests; the real one opens the share sheet.
  /// On iOS/Android `XFile.fromData` ignores its `name`, so the file
  /// name travels separately as `fileNameOverrides`.
  @visibleForTesting
  static Future<void> Function(XFile file, String name, Rect? origin) share =
      (file, name, origin) async {
        await SharePlus.instance.share(
          ShareParams(
            files: [file],
            fileNameOverrides: [name],
            sharePositionOrigin: origin,
          ),
        );
      };

  @override
  State<ReportScreen> createState() => _ReportState();
}

class _ReportState extends _WorkspaceState<ReportScreen>
    with _GroupActions<ReportScreen> {
  late String? periodID = widget.periodID;
  Set<String>? selected;
  JsonMap? data;
  String? failure;
  int _requests = 0;
  bool exporting = false;

  @override
  void initState() {
    super.initState();
    if (widget.projectID != null) selected = {widget.projectID!};
    // A koordinator sie without a sie this period starts at one they led.
    final options = _periodOptions();
    if (periodID == null &&
        options.isNotEmpty &&
        !options.any((o) => o.$1 == null)) {
      periodID = options.first.$1;
    }
    _load();
  }

  /// Member who is neither officer nor coordinator: sees own sie only.
  bool _leadOnly(JsonMap group) =>
      !_orgOfficer(store, group.text('organizationID')) &&
      !_coordinator(store, group);

  /// Periods to choose from (null id = current). Officers and the
  /// coordinator get all; a koordinator sie only periods holding a sie of
  /// theirs, since the server refuses the rest (§4.2).
  List<(String?, String)> _periodOptions() {
    final group = store.group(widget.groupID);
    if (widget.periodID != null || !_member(store, group)) return [];
    final periods = store.periods(group!.text('organizationID'));
    final all = <(String?, String)>[
      (null, 'Periode berjalan'),
      for (final p in periods) (p.text('id'), p.text('label')),
    ];
    if (!_leadOnly(group)) return all;
    final labels = {
      for (final p in _grProjects(store, widget.groupID))
        if (p.text('leadID') == store.currentUserID) p.text('periodLabel'),
    };
    return [
      for (final option in all)
        if (labels.contains(option.$1 == null ? '' : option.$2)) option,
    ];
  }

  /// Project choices, latest deadline first: the archive's list, else the
  /// snapshot's projects of this group in the chosen period (a koordinator
  /// sie sees only theirs).
  List<JsonMap>? _choices() {
    final group = store.group(widget.groupID);
    final List<JsonMap> rows;
    if (widget.candidates != null) {
      rows = [...widget.candidates!];
    } else if (!_member(store, group)) {
      return null;
    } else {
      final label = periodID == null
          ? ''
          : store
                    .periods(group!.text('organizationID'))
                    .where((p) => p.text('id') == periodID)
                    .firstOrNull
                    ?.text('label') ??
                widget.periodLabel ??
                '';
      final leadOnly = _leadOnly(group!);
      rows = [
        for (final p in _grProjects(store, widget.groupID))
          if (p.text('periodLabel') == label &&
              (!leadOnly || p.text('leadID') == store.currentUserID))
            p,
      ];
    }
    return rows..sort((a, b) => b.text('dueAt').compareTo(a.text('dueAt')));
  }

  Future<void> _load() async {
    final order = ++_requests;
    final choices = _choices();
    final chosen = selected;
    if (chosen != null && chosen.isEmpty) {
      return setState(() {
        data = null;
        failure = 'Pilih minimal satu proker.';
      });
    }
    setState(() {
      data = null;
      failure = null;
    });
    try {
      final value = await store.report(
        widget.groupID,
        periodID: periodID,
        // A koordinator sie must name their own sie (§4.2).
        projectIDs:
            chosen?.toList() ??
            (choices == null
                ? null
                : [for (final p in choices.take(20)) p.text('id')]),
      );
      if (mounted && order == _requests) setState(() => data = value);
    } catch (error) {
      if (mounted && order == _requests) setState(() => failure = '$error');
    }
  }

  @override
  Future<void> reload() async {
    await super.reload();
    await _load();
  }

  Future<void> _export(BuildContext button, bool pdf) async {
    final data = this.data;
    if (data == null || exporting) return;
    final box = button.findRenderObject() as RenderBox?;
    final origin = box == null
        ? null
        : box.localToGlobal(Offset.zero) & box.size;
    setState(() => exporting = true);
    try {
      final bytes = pdf ? await lpjPdf(data) : lpjCsv(data);
      final name = lpjFileName(data, pdf ? 'pdf' : 'csv');
      await ReportScreen.share(
        XFile.fromData(
          bytes,
          name: name,
          mimeType: pdf ? 'application/pdf' : 'text/csv',
        ),
        name,
        origin,
      );
    } catch (_) {
      feedback(
        'File rekap belum dapat dibuat. Coba lagi.',
        kind: GLToastKind.err,
      );
    } finally {
      if (mounted) setState(() => exporting = false);
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: store,
    builder: (context, _) {
      final options = _periodOptions();
      final choices = _choices();
      final data = this.data;
      return detailPage(
        title: 'Rekap LPJ',
        children: [
          if (options.length > 1)
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final (id, label) in options)
                  ChoiceChip(
                    key: Key('report-period-${id ?? 'current'}'),
                    label: Text(label),
                    selected: periodID == id,
                    onSelected: (_) {
                      setState(() {
                        periodID = id;
                        selected = null;
                      });
                      _load();
                    },
                  ),
              ],
            ),
          if (choices != null && choices.isNotEmpty)
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final p in choices.take(20))
                  FilterChip(
                    key: Key('report-pick-${p.text('id')}'),
                    label: Text(p.text('title')),
                    selected:
                        selected?.contains(p.text('id')) ??
                        choices.take(20).contains(p),
                    onSelected: (on) {
                      final next = {
                        ...(selected ??
                            choices.take(20).map((q) => q.text('id'))),
                      };
                      on ? next.add(p.text('id')) : next.remove(p.text('id'));
                      setState(() => selected = next);
                      _load();
                    },
                  ),
              ],
            ),
          if (failure != null) ...[
            GLFormError(failure!),
            GLOutlineButton(
              title: 'Coba lagi',
              icon: 'arrow.clockwise',
              onPressed: _load,
            ),
          ] else if (data == null)
            Center(child: CircularProgressIndicator.adaptive())
          else ...[
            _preview(data),
            Row(
              spacing: 8,
              children: [
                Expanded(
                  child: Builder(
                    builder: (button) => GLOutlineButton(
                      key: Key('report-pdf'),
                      title: 'Bagikan PDF',
                      icon: 'square.and.arrow.up',
                      onPressed: exporting ? null : () => _export(button, true),
                    ),
                  ),
                ),
                Expanded(
                  child: Builder(
                    builder: (button) => GLOutlineButton(
                      key: Key('report-csv'),
                      title: 'Bagikan CSV',
                      icon: 'square.and.arrow.up',
                      onPressed: exporting
                          ? null
                          : () => _export(button, false),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      );
    },
  );

  Widget _preview(JsonMap data) {
    final group = data['group'] as JsonMap;
    final totals = data['totals'] as JsonMap;
    final projects = (data['projects'] as List).cast<JsonMap>();
    final meetings = (data['meetings'] as List).cast<JsonMap>();
    final approvals = (data['approvals'] as List).cast<JsonMap>();
    return Column(
      key: Key('report-preview'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 12,
      children: [
        Container(
          padding: EdgeInsets.all(18),
          decoration: glBox(GLTheme.surface, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: 4,
            children: [
              Text(group.text('name'), style: gl(21, w700, -0.02)),
              Text(
                data.text('period').isEmpty
                    ? data.text('organization')
                    : '${data.text('organization')} · Periode ${data.text('period')}',
                style: gl(14, w400, 0, GLTheme.secondary),
              ),
              SizedBox(height: 6),
              Text(
                '${totals.number('done')} dari ${totals.number('tasks')} tugas selesai · ${meetings.length} rapat'
                '${approvals.isEmpty ? '' : ' · ${_rupiah(totals.number('approvedAmount'))} disetujui'}',
                style: gl(15, w600),
              ),
            ],
          ),
        ),
        if (projects.isEmpty)
          Text(
            'Tidak ada proker di periode ini.',
            style: gl(14, w400, 0, GLTheme.secondary),
          )
        else
          _workList([
            for (final p in projects)
              () {
                final tasks = (p['tasks'] as List).cast<JsonMap>();
                return Container(
                  constraints: BoxConstraints(minHeight: 56),
                  padding: EdgeInsets.symmetric(vertical: 8),
                  decoration: _grHairline,
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(p.text('title'), style: gl(15, w600)),
                      ),
                      Text(
                        '${tasks.where((t) => t['status'] == 'done').length}/${tasks.length} tugas',
                        style: gl(13, w400, 0, GLTheme.secondary),
                      ),
                    ],
                  ),
                );
              }(),
          ]),
      ],
    );
  }
}
