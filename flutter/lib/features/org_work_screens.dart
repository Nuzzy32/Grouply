part of 'workspace_screens.dart';

// Organization Plan Tahap 2 (docs/DESIGN-org-tahap2.md §5.2): kepanitiaan,
// koordinator sie, rapat, persetujuan berjenjang, pengumuman. Role-only
// buttons are hidden; plan-locked buttons stay visible with a lock and a
// toast. The server enforces every rule (§3).

String _rupiah(num value) {
  final digits = value.toInt().toString();
  final out = StringBuffer('Rp ');
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) out.write('.');
    out.write(digits[i]);
  }
  return out.toString();
}

String _when(DateTime value) =>
    '${GLFormat.longDate(value)} · ${GLFormat.time(value)}';

(String, Color) _meetingStatus(String status) => switch (status) {
  'scheduled' => ('Terjadwal', GLTheme.sky),
  'done' => ('Selesai', GLTheme.mint),
  _ => ('Dibatalkan', GLTheme.chip),
};

(String, Color) _approvalStatus(String status) => switch (status) {
  'pending' => ('Menunggu', GLTheme.butter),
  'approved' => ('Disetujui', GLTheme.mint),
  'rejected' => ('Ditolak', GLTheme.coral),
  'cancelled' => ('Dibatalkan', GLTheme.chip),
  _ => ('Gugur', GLTheme.chip),
};

Widget _smallChip((String, Color) status) =>
    GLChip(label: status.$1, background: status.$2, height: 24, fontSize: 12);

String _personName(GrouplyStore store, String id) => id.isEmpty
    ? 'Akun dihapus'
    : id == store.currentUserID
    ? 'Kamu'
    : store.user(id)?.text('name') ?? 'Anggota';

/// White rounded list holding [_workRow]s.
Widget _workList(List<Widget> rows) => Container(
  padding: EdgeInsets.symmetric(vertical: 4, horizontal: 14),
  decoration: glBox(GLTheme.surface, 24),
  child: Column(children: rows),
);

Widget _workHeading(String title, {String? sub, Widget? action}) => Row(
  children: [
    Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: gl(21, w700, -0.02)),
          if (sub != null) Text(sub, style: gl(13, w400, 0, GLTheme.secondary)),
        ],
      ),
    ),
    if (action != null) ...[SizedBox(width: 8), action],
  ],
);

Widget _workRow({
  Key? key,
  required String icon,
  required Color tint,
  required String title,
  required String subtitle,
  required VoidCallback onTap,
  int badge = 0,
  List<Widget> chips = const [],
}) => GLTap(
  key: key,
  onTap: onTap,
  child: MergeSemantics(
    child: Container(
      constraints: BoxConstraints(minHeight: 64),
      padding: EdgeInsets.symmetric(vertical: 10),
      decoration: _grHairline,
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: glBox(tint, 14),
            child: GLIcon(icon, size: 20),
          ),
          SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: gl(16, w600)),
                SizedBox(height: 2),
                Text(subtitle, style: gl(13, w400, 0, GLTheme.secondary)),
                if (chips.isNotEmpty) ...[
                  SizedBox(height: 6),
                  Wrap(spacing: 6, runSpacing: 6, children: chips),
                ],
              ],
            ),
          ),
          if (badge > 0) ...[
            SizedBox(width: 8),
            GLCountBadge(count: badge, size: 24),
          ],
          SizedBox(width: 4),
          GLIcon('chevron.right', size: 22, color: GLTheme.secondary),
        ],
      ),
    ),
  ),
);

/// Pending decisions plus unread announcements, for the organization card.
int _orgWorkBadge(GrouplyStore store, String orgID) =>
    store.pendingForMe(orgID).length + store.unreadAnnouncements(orgID).length;

// MARK: - Organization screen rows

Widget _orgWorkLinks(_WorkspaceState state, String orgID) {
  final store = state.store;
  final pending = store.pendingForMe(orgID).length;
  final unread = store.unreadAnnouncements(orgID).length;
  return _workList([
    _workRow(
      key: Key('org-approvals'),
      icon: 'checkmark.seal',
      tint: GLTheme.butter,
      title: 'Persetujuan',
      subtitle: pending > 0
          ? '$pending menunggu keputusanmu'
          : 'Proposal dan dana berjenjang',
      badge: pending,
      onTap: () => state.open(ApprovalsScreen(store: store, orgID: orgID)),
    ),
    _workRow(
      key: Key('org-announcements'),
      icon: 'megaphone',
      tint: GLTheme.sky,
      title: 'Pengumuman',
      subtitle: unread > 0 ? '$unread belum dibaca' : 'Kabar dari pengurus',
      badge: unread,
      onTap: () => state.open(AnnouncementsScreen(store: store, orgID: orgID)),
    ),
  ]);
}

// MARK: - Group screen section

/// "Rapat" and "Ajukan persetujuan" for groups of a known organization.
List<Widget> _groupWorkSection(_WorkspaceState state, JsonMap group) {
  final store = state.store;
  if (store.organization(group.text('organizationID')) == null) return [];
  final groupID = group.text('id');
  final coord = _coordinator(store, group);
  final active = _activeDivision(store, group);
  final scheduled =
      store.meetings
          .where(
            (m) => m.text('groupID') == groupID && m['status'] == 'scheduled',
          )
          .toList()
        ..sort((a, b) => a.text('startsAt').compareTo(b.text('startsAt')));
  bool past(JsonMap m) => m.date('startsAt')!.isBefore(store.now);
  final next = scheduled.where((m) => !past(m)).toList();
  // Meetings already held but not yet recorded, newest first.
  final unrecorded = scheduled.where(past).toList().reversed.take(3).toList();
  return [
    Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _workHeading(
          'Rapat',
          action: GLTap(
            key: Key('group-meetings'),
            onTap: () =>
                state.open(MeetingsScreen(store: store, groupID: groupID)),
            child: Container(
              height: 44,
              padding: EdgeInsets.only(left: 12, right: 4),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('Lihat semua', style: gl(15, w600)),
                  SizedBox(width: 2),
                  GLIcon('chevron.right', size: 20),
                ],
              ),
            ),
          ),
        ),
        SizedBox(height: 10),
        if (next.isEmpty)
          Container(
            padding: EdgeInsets.symmetric(vertical: 14, horizontal: 16),
            decoration: glBox(GLTheme.surface, 20),
            child: Text(
              'Belum ada rapat terjadwal.',
              style: gl(14, w400, 0, GLTheme.text3),
            ),
          )
        else
          _workList([_meetingRow(state, next.first)]),
        if (unrecorded.isNotEmpty) ...[
          SizedBox(height: 10),
          _workList([for (final m in unrecorded) _meetingRow(state, m)]),
        ],
        SizedBox(height: 10),
        Row(
          children: [
            if (coord) ...[
              Expanded(
                child: GLOutlineButton(
                  key: Key('meeting-schedule'),
                  title: 'Jadwalkan rapat',
                  icon: active ? 'calendar.badge.plus' : 'lock',
                  onPressed: () => _scheduleMeeting(state, group),
                ),
              ),
              SizedBox(width: 8),
            ],
            Expanded(
              child: GLOutlineButton(
                key: Key('approval-request'),
                title: 'Ajukan persetujuan',
                icon: active ? 'checkmark.seal' : 'lock',
                onPressed: () => _requestApproval(state, group),
              ),
            ),
          ],
        ),
      ],
    ),
  ];
}

// MARK: - Koordinator sie (project screen)

Widget? _projectLeadRow(_WorkspaceState state, JsonMap project, JsonMap group) {
  final store = state.store;
  if (store.organization(group.text('organizationID')) == null) return null;
  final lead = project.text('leadID');
  final coord = _coordinator(store, group);
  final label = store.isCommittee(group)
      ? 'Koordinator sie'
      : 'Penanggung jawab';
  return Container(
    key: Key('project-lead'),
    padding: EdgeInsets.symmetric(vertical: 12, horizontal: 16),
    decoration: glBox(GLTheme.surface, 24),
    child: Row(
      children: [
        lead.isEmpty
            ? Container(
                width: 40,
                height: 40,
                decoration: glBox(GLTheme.muted, 14),
                child: GLIcon('person.crop.circle.badge.checkmark', size: 20),
              )
            : GLAvatar(user: store.user(lead), size: 40, fontSize: 13),
        SizedBox(width: 12),
        Expanded(
          child: MergeSemantics(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: gl(13, w400, 0, GLTheme.secondary)),
                Text(
                  lead.isEmpty ? 'Belum ditunjuk' : _personName(store, lead),
                  style: gl(16, w600),
                ),
              ],
            ),
          ),
        ),
        if (coord) ...[
          if (lead.isNotEmpty)
            GLTap(
              key: Key('project-lead-clear'),
              label: 'Cabut $label',
              onTap: () => _clearLead(state, project, label),
              child: Container(
                height: 44,
                padding: EdgeInsets.symmetric(horizontal: 10),
                alignment: Alignment.center,
                child: Text('Cabut', style: gl(14, w600, 0, GLTheme.danger)),
              ),
            ),
          _orgPill(
            lead.isEmpty ? 'Tunjuk' : 'Ganti',
            _activeDivision(store, group) ? 'person.badge.plus' : 'lock',
            () => _pickLead(state, project, group, label),
            key: Key('project-lead-set'),
          ),
        ],
      ],
    ),
  );
}

Future<void> _pickLead(
  _WorkspaceState state,
  JsonMap project,
  JsonMap group,
  String label,
) async {
  final store = state.store;
  if (!_activeDivision(store, group)) {
    return state.feedback(
      '$label bisa ditunjuk saat paket organisasi aktif.',
      kind: GLToastKind.err,
    );
  }
  if (project.text('status') != 'active') {
    return state.feedback(
      'Proyek selesai atau diarsipkan hanya dapat dibaca.',
      kind: GLToastKind.err,
    );
  }
  final picked = await showGLSheet<String>(
    state.context,
    title: 'Tunjuk ${label.toLowerCase()}',
    subtitle:
        'Ia boleh membuat, mengubah, mengalihkan, dan membuka kembali tugas di ${project.text('title')} saja.',
    builder: (sheet) => _workList([
      for (final id in group.ids('memberIDs'))
        if (id != project.text('leadID'))
          GLTap(
            onTap: () => Navigator.of(sheet).pop(id),
            child: Container(
              constraints: BoxConstraints(minHeight: 60),
              decoration: _grHairline,
              child: Row(
                children: [
                  GLAvatar(user: store.user(id), size: 40, fontSize: 13),
                  SizedBox(width: 12),
                  Expanded(
                    child: Text(_personName(store, id), style: gl(16, w600)),
                  ),
                ],
              ),
            ),
          ),
    ]),
  );
  if (picked == null || !state.mounted) return;
  await state.mutate(
    'setProjectLead',
    {'projectID': project.text('id'), 'userID': picked},
    success: '${_personName(store, picked)} menjadi ${label.toLowerCase()}',
  );
}

Future<void> _clearLead(
  _WorkspaceState state,
  JsonMap project,
  String label,
) async {
  if (await state.confirm(
        'Cabut ${label.toLowerCase()}?',
        'Tugas yang sudah dibuat tetap ada. Setelah dicabut, hanya koordinator yang bisa mengelola tugas proyek ini.',
        ok: 'Cabut',
        destructive: true,
      ) &&
      state.mounted) {
    await state.mutate('setProjectLead', {
      'projectID': project.text('id'),
      'userID': null,
    }, success: '${label[0]}${label.substring(1)} dicabut');
  }
}

// MARK: - Meetings

Widget _meetingRow(_WorkspaceState state, JsonMap meeting) {
  final store = state.store;
  final start = meeting.date('startsAt')!;
  final status = meeting.text('status');
  final place = meeting.text('place');
  return _workRow(
    icon: status == 'done' ? 'doc.text' : 'calendar',
    tint: _meetingStatus(status).$2,
    title: meeting.text('title'),
    subtitle: '${_when(start)}${place.isEmpty ? '' : ' · $place'}',
    chips: [
      if (status == 'scheduled' && start.isBefore(store.now))
        _smallChip(('Belum dinotulenkan', GLTheme.butter))
      else
        _smallChip(_meetingStatus(status)),
      if (status == 'done')
        GLChip(
          label:
              '${meeting.number('present')} hadir · ${meeting.number('excused')} izin',
          background: GLTheme.muted,
          height: 24,
          fontSize: 12,
        ),
    ],
    onTap: () =>
        state.open(MeetingScreen(store: store, meetingID: meeting.text('id'))),
  );
}

Future<void> _scheduleMeeting(
  _WorkspaceState state,
  JsonMap group, {
  JsonMap? meeting,
  JsonMap? detail,
}) async {
  final store = state.store;
  if (meeting == null && !_activeDivision(store, group)) {
    return state.feedback(
      'Rapat baru bisa dijadwalkan saat paket organisasi aktif.',
      kind: GLToastKind.err,
    );
  }
  final result = await showGLSheet<JsonMap>(
    state.context,
    title: meeting == null ? 'Jadwalkan rapat' : 'Ubah rapat',
    builder: (_) => _MeetingSheet(
      store: store,
      group: group,
      meeting: meeting,
      detail: detail,
    ),
  );
  if (meeting == null && result != null && state.mounted) {
    final id = result.text('id');
    if (id.isNotEmpty) state.open(MeetingScreen(store: store, meetingID: id));
  }
}

class MeetingsScreen extends _WorkspaceScreen {
  const MeetingsScreen({
    super.key,
    required super.store,
    required this.groupID,
  });
  final String groupID;
  @override
  State<MeetingsScreen> createState() => _MeetingsState();
}

class _MeetingsState extends _WorkspaceState<MeetingsScreen>
    with _GroupActions<MeetingsScreen> {
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: store,
    builder: (context, _) {
      final group = store.group(widget.groupID);
      if (!_member(store, group)) return GLAccessDenied();
      final all = store.meetings
          .where((m) => m.text('groupID') == widget.groupID)
          .toList();
      List<JsonMap> having(String status, {bool newestFirst = true}) =>
          all.where((m) => m['status'] == status).toList()..sort(
            (a, b) => newestFirst
                ? b.text('startsAt').compareTo(a.text('startsAt'))
                : a.text('startsAt').compareTo(b.text('startsAt')),
          );
      final sections = [
        ('Terjadwal', having('scheduled', newestFirst: false)),
        ('Selesai', having('done')),
        ('Dibatalkan', having('cancelled')),
      ];
      final coord = _coordinator(store, group);
      return detailPage(
        title: 'Rapat',
        trailing: coord
            ? GLCircleButton(
                icon: _activeDivision(store, group) ? 'plus' : 'lock',
                label: 'Jadwalkan rapat',
                onTap: () => _scheduleMeeting(this, group!),
              )
            : null,
        children: [
          Text(group!.text('name'), style: gl(23, w700, -0.02)),
          if (all.isEmpty)
            GLEmptyState(
              title: 'Belum ada rapat',
              message: coord
                  ? 'Jadwalkan rapat pertama. Anggota grup mendapat pengingat sehari dan satu jam sebelumnya.'
                  : 'Koordinator belum menjadwalkan rapat.',
              icon: 'calendar',
              tint: GLTheme.sky,
            ),
          for (final (label, rows) in sections)
            if (rows.isNotEmpty)
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _workHeading(label, sub: '${rows.length} rapat'),
                  SizedBox(height: 10),
                  _workList([for (final m in rows) _meetingRow(this, m)]),
                ],
              ),
        ],
      );
    },
  );
}

class MeetingScreen extends _WorkspaceScreen {
  const MeetingScreen({
    super.key,
    required super.store,
    required this.meetingID,
  });
  final String meetingID;
  @override
  State<MeetingScreen> createState() => _MeetingState();
}

class _MeetingState extends _WorkspaceState<MeetingScreen>
    with _GroupActions<MeetingScreen> {
  JsonMap? detail;
  String? failure;
  int _requests = 0;
  int? _requestedVersion;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final order = ++_requests;
    _requestedVersion = store
        .meeting(widget.meetingID)
        ?.number('version')
        .toInt();
    try {
      final value = await store.meetingDetail(widget.meetingID);
      if (mounted && order == _requests) {
        setState(() {
          detail = value;
          failure = null;
        });
      }
    } catch (error) {
      if (mounted && order == _requests) {
        setState(() => failure = error.toString());
      }
    }
  }

  @override
  Future<void> reload() async {
    await super.reload();
    await _load();
  }

  bool _current() =>
      detail != null &&
      detail!['version'] == store.meeting(widget.meetingID)?['version'];

  /// Detail whose version matches the snapshot, so a sheet never mixes
  /// stale agenda/minutes with a newer title or version. Reloads once.
  Future<JsonMap?> _freshDetail() async {
    if (!_current()) await reload();
    if (mounted && _current()) return detail;
    feedback(
      'Detail rapat belum termuat. Coba lagi sebentar.',
      kind: GLToastKind.err,
    );
    return null;
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: store,
    builder: (context, _) {
      final meeting = store.meeting(widget.meetingID);
      final group = store.group(meeting?.text('groupID') ?? '');
      if (meeting == null || !_member(store, group)) {
        return GLAccessDenied(
          text: 'Rapat tidak ditemukan, atau kamu bukan anggota grupnya.',
        );
      }
      // Reload agenda/minutes/attendance when the snapshot version moves.
      final version = meeting.number('version').toInt();
      if (version != _requestedVersion) {
        _requestedVersion = version;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _load();
        });
      }
      return _content(meeting, group!);
    },
  );

  bool _canRecord(JsonMap meeting, JsonMap group) =>
      meeting['status'] != 'cancelled' &&
      (_coordinator(store, group) ||
          meeting.text('noteTakerID') == store.currentUserID);

  List<JsonMap> _taskProjects(JsonMap group) => [
    for (final p in _grProjects(store, group.text('id')))
      if (p['status'] == 'active' && store.canManageTasks(p)) p,
  ];

  Widget _content(JsonMap meeting, JsonMap group) {
    final status = meeting.text('status');
    final start = meeting.date('startsAt')!;
    final noteTaker = meeting.text('noteTakerID');
    final detail = this.detail;
    final coord = _coordinator(store, group);
    final tasks = [for (final id in meeting.ids('taskIDs')) ?store.task(id)];
    final canTask = status != 'cancelled' && _taskProjects(group).isNotEmpty;
    Widget info(String icon, String text) => Padding(
      padding: EdgeInsets.only(top: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GLIcon(icon, size: 18, color: GLTheme.text3),
          SizedBox(width: 8),
          Expanded(child: Text(text, style: gl(14, w400, 0, GLTheme.text3))),
        ],
      ),
    );
    Widget card(List<Widget> children) => Container(
      padding: EdgeInsets.all(18),
      decoration: glBox(GLTheme.surface, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: children,
      ),
    );
    return detailPage(
      title: 'Rapat',
      trailing: coord && status == 'scheduled'
          ? GLCircleButton(
              icon: 'ellipsis',
              label: 'Aksi rapat',
              onTap: () => _actions(meeting, group),
            )
          : null,
      children: [
        card([
          Text(meeting.text('title'), style: gl(23, w700, -0.02)),
          SizedBox(height: 8),
          Wrap(children: [_smallChip(_meetingStatus(status))]),
          info('calendar', _when(start)),
          if (meeting.text('place').isNotEmpty)
            info('mappin', meeting.text('place')),
          info(
            'person.2',
            '${group.text('name')} · Notulis: ${noteTaker.isEmpty ? 'belum ditunjuk' : _personName(store, noteTaker)}',
          ),
        ]),
        if (detail == null && failure == null)
          Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Center(child: CircularProgressIndicator.adaptive()),
          ),
        if (failure != null) ...[
          GLFormError(failure!),
          GLOutlineButton(
            title: 'Coba lagi',
            icon: 'arrow.clockwise',
            onPressed: _load,
          ),
        ],
        if (detail != null) ...[
          _workHeading('Agenda'),
          card([
            Text(
              detail.text('agenda').isEmpty
                  ? 'Belum ada agenda.'
                  : detail.text('agenda'),
              style: gl(15, w400, 0, GLTheme.text3, 4),
            ),
          ]),
          _workHeading(
            'Notulen',
            action: _canRecord(meeting, group)
                ? _orgPill(
                    detail.text('minutes').isEmpty ? 'Isi notulen' : 'Ubah',
                    start.isAfter(store.now) ? 'lock' : 'square.and.pencil',
                    () => _record(meeting, group),
                    key: Key('meeting-record'),
                  )
                : null,
          ),
          card([
            Text(
              detail.text('minutes').isEmpty
                  ? 'Belum ada notulen.'
                  : detail.text('minutes'),
              style: gl(15, w400, 0, GLTheme.text3, 4),
            ),
          ]),
          ..._attendance(meeting, group, detail),
        ],
        _workHeading(
          'Tugas dari rapat ini',
          action: canTask
              ? _orgPill(
                  'Jadikan tugas',
                  'plus',
                  () => _makeTask(meeting, group),
                  key: Key('meeting-task'),
                )
              : null,
        ),
        if (tasks.isEmpty)
          Text(
            'Belum ada tugas dari rapat ini.',
            style: gl(14, w400, 0, GLTheme.secondary),
          )
        else
          _workList([
            for (final task in tasks)
              _workRow(
                icon: GLStatus.icon(task.text('status')),
                tint: GLStatus.tint(task.text('status')),
                title: task.text('title'),
                subtitle:
                    '${_personName(store, task.text('assigneeID'))} · ${GLStatus.label(task.text('status'))}',
                onTap: () =>
                    open(TaskScreen(store: store, taskID: task.text('id'))),
              ),
          ]),
      ],
    );
  }

  /// Per-meeting record only; no per-person attendance rate (§1.7).
  List<Widget> _attendance(JsonMap meeting, JsonMap group, JsonMap detail) {
    final marks = {
      for (final row in (detail['attendance'] as List).cast<JsonMap>())
        row.text('userID'): row.text('status'),
    };
    final members = group.ids('memberIDs');
    final present = members.where((id) => marks[id] == 'hadir').length;
    final excused = members.where((id) => marks[id] == 'izin').length;
    return [
      _workHeading(
        'Daftar hadir',
        sub: meeting['status'] == 'done'
            ? '$present hadir · $excused izin · ${members.length - present - excused} tanpa keterangan'
            : 'Diisi bersama notulen',
      ),
      if (meeting['status'] == 'done')
        Container(
          padding: EdgeInsets.symmetric(vertical: 4, horizontal: 14),
          decoration: glBox(GLTheme.surface, 24),
          child: Column(
            children: [
              for (final id in members)
                MergeSemantics(
                  child: Container(
                    constraints: BoxConstraints(minHeight: 56),
                    decoration: _grHairline,
                    child: Row(
                      children: [
                        GLAvatar(user: store.user(id), size: 36, fontSize: 12),
                        SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            _personName(store, id),
                            style: gl(15, w600),
                          ),
                        ),
                        GLChip(
                          label: switch (marks[id]) {
                            'hadir' => 'Hadir',
                            'izin' => 'Izin',
                            _ => 'Tanpa keterangan',
                          },
                          background: switch (marks[id]) {
                            'hadir' => GLTheme.mint,
                            'izin' => GLTheme.butter,
                            _ => GLTheme.chip,
                          },
                          height: 24,
                          fontSize: 12,
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
    ];
  }

  Future<void> _record(JsonMap meeting, JsonMap group) async {
    if (meeting.date('startsAt')!.isAfter(store.now)) {
      return feedback(
        'Notulen bisa diisi setelah rapat dimulai.',
        kind: GLToastKind.err,
      );
    }
    final detail = await _freshDetail();
    if (detail == null || !mounted) return;
    meeting = store.meeting(widget.meetingID) ?? meeting;
    await showGLSheet<JsonMap>(
      context,
      title: 'Notulen',
      subtitle: meeting.text('title'),
      builder: (_) => _MinutesSheet(
        store: store,
        meeting: meeting,
        group: group,
        detail: detail,
      ),
    );
  }

  Future<void> _makeTask(JsonMap meeting, JsonMap group) async {
    final options = _taskProjects(group);
    var project = options.length == 1 ? options.single : null;
    project ??= await showGLSheet<JsonMap>(
      context,
      title: store.isCommittee(group) ? 'Pilih sie' : 'Pilih proyek',
      builder: (sheet) => _workList([
        for (final p in options)
          _workRow(
            icon: 'folder',
            tint: GLTheme.butter,
            title: p.text('title'),
            subtitle: 'Tugas baru masuk ke sini',
            onTap: () => Navigator.of(sheet).pop(p),
          ),
      ]),
    );
    if (project == null || !mounted) return;
    final title = 'Tindak lanjut ${meeting.text('title')}';
    await _showTaskSheet(
      this,
      project,
      group,
      title: title.length > 120 ? title.substring(0, 120) : title,
      meetingID: meeting.text('id'),
    );
  }

  Future<void> _actions(JsonMap meeting, JsonMap group) async {
    final pick = await showGLSheet<String>(
      context,
      title: 'Aksi rapat',
      builder: (sheet) => _workList([
        _workRow(
          key: Key('meeting-edit'),
          icon: 'pencil',
          tint: GLTheme.muted,
          title: 'Ubah rapat',
          subtitle: 'Judul, waktu, tempat, agenda, notulis',
          onTap: () => Navigator.of(sheet).pop('edit'),
        ),
        _workRow(
          key: Key('meeting-cancel'),
          icon: 'xmark.circle',
          tint: GLTheme.coral,
          title: 'Batalkan rapat',
          subtitle: 'Anggota melihat rapat ini sebagai dibatalkan',
          onTap: () => Navigator.of(sheet).pop('cancel'),
        ),
      ]),
    );
    if (!mounted || pick == null) return;
    final fresh = store.meeting(widget.meetingID) ?? meeting;
    if (pick == 'edit') {
      final detail = await _freshDetail();
      if (detail == null || !mounted) return;
      await _scheduleMeeting(
        this,
        group,
        meeting: store.meeting(widget.meetingID) ?? fresh,
        detail: detail,
      );
    } else if (await confirm(
          'Batalkan rapat?',
          '${fresh.text('title')} tidak bisa dijadwalkan ulang. Buat rapat baru bila perlu.',
          ok: 'Batalkan rapat',
          destructive: true,
        ) &&
        mounted) {
      await mutate('cancelMeeting', {
        'id': widget.meetingID,
        'expectedVersion': fresh.number('version').toInt(),
      }, success: 'Rapat dibatalkan');
    }
  }
}

/// Error text for a meeting sheet. After `stale_version` the sheet adopts
/// the newest version (typed text stays) and says what happened, so a
/// second save is a deliberate overwrite.
Future<String> _staleText(
  GrouplyStore store,
  String meetingID,
  Object failure,
  void Function(int version) adopt,
) async {
  if ('$failure' != GrouplyStore.codeText('stale_version')) return '$failure';
  try {
    adopt((await store.meetingDetail(meetingID)).number('version').toInt());
  } catch (_) {
    return '$failure';
  }
  return 'Rapat ini baru diubah orang lain. Isianmu masih di sini: buka layar rapat untuk melihat versi terbarunya, atau simpan lagi untuk menimpanya.';
}

/// Create/edit sheet (§4.1 `createMeeting` / `updateMeeting`).
class _MeetingSheet extends StatefulWidget {
  const _MeetingSheet({
    required this.store,
    required this.group,
    this.meeting,
    this.detail,
  });
  final GrouplyStore store;
  final JsonMap group;
  final JsonMap? meeting, detail;
  @override
  State<_MeetingSheet> createState() => _MeetingSheetState();
}

class _MeetingSheetState extends State<_MeetingSheet> {
  late final title = TextEditingController(text: widget.meeting?.text('title'));
  late final place = TextEditingController(text: widget.meeting?.text('place'));
  late final agenda = TextEditingController(
    text: widget.detail?.text('agenda'),
  );
  late DateTime startsAt =
      widget.meeting?.date('startsAt')?.toLocal() ??
      () {
        final n = DateTime.now();
        return DateTime(n.year, n.month, n.day + 1, 16);
      }();
  late String noteTaker = widget.meeting?.text('noteTakerID') ?? '';
  // Captured on open so a concurrent edit surfaces as stale_version.
  // From `grouply_meeting`, the same read as the agenda shown here.
  late int version = widget.detail?.number('version').toInt() ?? 0;
  String? error;
  bool saving = false;

  @override
  void dispose() {
    title.dispose();
    place.dispose();
    agenda.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showGLSheet<DateTime>(
      context,
      title: 'Tanggal rapat',
      builder: (sheet) => Container(
        decoration: glBox(GLTheme.surface, 24),
        child: CalendarDatePicker(
          initialDate: startsAt,
          firstDate: DateTime(2020),
          lastDate: DateTime(2030, 12, 31),
          onDateChanged: (d) => Navigator.of(sheet).pop(d),
        ),
      ),
    );
    if (picked != null && mounted) {
      setState(
        () => startsAt = DateTime(
          picked.year,
          picked.month,
          picked.day,
          startsAt.hour,
          startsAt.minute,
        ),
      );
    }
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(startsAt),
    );
    if (picked != null && mounted) {
      setState(
        () => startsAt = DateTime(
          startsAt.year,
          startsAt.month,
          startsAt.day,
          picked.hour,
          picked.minute,
        ),
      );
    }
  }

  Future<void> _save() async {
    if (saving) return;
    final name = title.text.trim();
    if (name.isEmpty) return setState(() => error = 'Judul rapat wajib diisi.');
    final meeting = widget.meeting;
    final taker = noteTaker.isEmpty ? null : noteTaker;
    final payload = <String, dynamic>{
      if (meeting == null)
        'groupID': widget.group.text('id')
      else ...{
        'id': meeting.text('id'),
        'expectedVersion': version,
      },
      'title': name,
      'startsAt': startsAt.toUtc().toIso8601String(),
      'place': place.text.trim(),
      'agenda': agenda.text.trim(),
      if (meeting != null) 'noteTakerID': taker else 'noteTakerID': ?taker,
    };
    setState(() {
      saving = true;
      error = null;
    });
    try {
      final result = await widget.store.mutate(
        meeting == null ? 'createMeeting' : 'updateMeeting',
        payload,
      );
      if (!mounted) return;
      showGLToast(
        context,
        meeting == null ? 'Rapat dijadwalkan' : 'Rapat diperbarui',
      );
      Navigator.of(context).pop(result);
    } catch (e) {
      final text = meeting == null
          ? '$e'
          : await _staleText(widget.store, meeting.text('id'), e, (v) {
              version = v;
            });
      if (mounted) setState(() => error = text);
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  Widget _pickerButton(
    String label,
    String icon,
    String value,
    VoidCallback onTap,
  ) => GLTap(
    label: '$label, $value',
    onTap: onTap,
    child: Container(
      height: 50,
      padding: EdgeInsets.symmetric(horizontal: 14),
      decoration: glBox(GLTheme.surface, 16, border: GLTheme.border),
      child: Row(
        children: [
          GLIcon(icon, size: 20),
          SizedBox(width: 8),
          Expanded(
            child: Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: gl(15, w600),
            ),
          ),
        ],
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final store = widget.store;
    return PopScope(
      canPop: !saving,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 16,
        children: [
          GLField(
            'Judul rapat',
            required: true,
            child: GLTextField(
              key: Key('meeting-title'),
              controller: title,
              hint: 'Contoh: Rapat mingguan',
              maxLength: 120,
              textCapitalization: TextCapitalization.sentences,
            ),
          ),
          GLField(
            'Waktu',
            required: true,
            child: Row(
              spacing: 8,
              children: [
                Expanded(
                  flex: 3,
                  child: _pickerButton(
                    'Tanggal rapat',
                    'calendar',
                    GLFormat.longDate(startsAt),
                    _pickDate,
                  ),
                ),
                Expanded(
                  flex: 2,
                  child: _pickerButton(
                    'Jam rapat',
                    'clock',
                    GLFormat.time(startsAt),
                    _pickTime,
                  ),
                ),
              ],
            ),
          ),
          GLField(
            'Tempat atau tautan',
            child: GLTextField(
              key: Key('meeting-place'),
              controller: place,
              hint: 'Contoh: Sekre BEM atau tautan Meet',
              maxLength: 200,
            ),
          ),
          GLField(
            'Agenda',
            child: GLTextField(
              key: Key('meeting-agenda'),
              controller: agenda,
              hint: 'Poin yang dibahas',
              maxLength: 5000,
              minLines: 3,
              maxLines: 6,
              textCapitalization: TextCapitalization.sentences,
            ),
          ),
          GLField(
            'Notulis',
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final (id, label) in [
                  ('', 'Belum ditunjuk'),
                  for (final id in widget.group.ids('memberIDs'))
                    (id, _personName(store, id)),
                ])
                  GLTap(
                    key: Key('meeting-notetaker-${id.isEmpty ? 'none' : id}'),
                    label: 'Notulis $label',
                    onTap: () => setState(() => noteTaker = id),
                    child: GLChip(
                      label: label,
                      icon: noteTaker == id ? 'checkmark' : null,
                      background: noteTaker == id ? GLTheme.lavender : null,
                      outlined: noteTaker != id,
                      height: 36,
                    ),
                  ),
              ],
            ),
          ),
          if (error != null) GLFormError(error!),
          GLSubmitButton(
            key: Key('meeting-save'),
            title: saving
                ? 'Menyimpan…'
                : widget.meeting == null
                ? 'Jadwalkan'
                : 'Simpan',
            busy: saving,
            onPressed: _save,
          ),
        ],
      ),
    );
  }
}

/// Minutes + hadir/izin per current member (§4.1 `recordMeeting`).
class _MinutesSheet extends StatefulWidget {
  const _MinutesSheet({
    required this.store,
    required this.meeting,
    required this.group,
    required this.detail,
  });
  final GrouplyStore store;
  final JsonMap meeting, group, detail;
  @override
  State<_MinutesSheet> createState() => _MinutesSheetState();
}

class _MinutesSheetState extends State<_MinutesSheet> {
  late final minutes = TextEditingController(
    text: widget.detail.text('minutes'),
  );
  late final Map<String, String> marks = {
    for (final row in (widget.detail['attendance'] as List).cast<JsonMap>())
      if (widget.group.ids('memberIDs').contains(row.text('userID')))
        row.text('userID'): row.text('status'),
  };
  late int version = widget.detail.number('version').toInt();
  String? error;
  bool saving = false;

  @override
  void dispose() {
    minutes.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (saving) return;
    setState(() {
      saving = true;
      error = null;
    });
    try {
      await widget.store.mutate('recordMeeting', {
        'id': widget.meeting.text('id'),
        'expectedVersion': version,
        'minutes': minutes.text.trim(),
        'attendance': [
          for (final MapEntry(key: userID, value: status) in marks.entries)
            {'userID': userID, 'status': status},
        ],
      });
      if (!mounted) return;
      showGLToast(context, 'Notulen disimpan');
      Navigator.of(context).pop();
    } catch (e) {
      final text = await _staleText(
        widget.store,
        widget.meeting.text('id'),
        e,
        (v) => version = v,
      );
      if (mounted) setState(() => error = text);
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !saving,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 16,
      children: [
        GLField(
          'Notulen',
          child: GLTextField(
            key: Key('meeting-minutes'),
            controller: minutes,
            hint: 'Keputusan dan tindak lanjut rapat',
            maxLength: 20000,
            minLines: 5,
            maxLines: 10,
            textCapitalization: TextCapitalization.sentences,
          ),
        ),
        GLField(
          'Daftar hadir',
          child: Container(
            padding: EdgeInsets.symmetric(vertical: 4, horizontal: 14),
            decoration: glBox(GLTheme.surface, 24),
            child: Column(
              children: [
                for (final id in widget.group.ids('memberIDs'))
                  Container(
                    constraints: BoxConstraints(minHeight: 60),
                    decoration: _grHairline,
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            _personName(widget.store, id),
                            style: gl(15, w600),
                          ),
                        ),
                        for (final (status, label) in [
                          ('hadir', 'Hadir'),
                          ('izin', 'Izin'),
                        ]) ...[
                          SizedBox(width: 6),
                          GLTap(
                            key: Key('attendance-$id-$status'),
                            label: '${_personName(widget.store, id)} $label',
                            onTap: () => setState(
                              () => marks[id] == status
                                  ? marks.remove(id)
                                  : marks[id] = status,
                            ),
                            child: GLChip(
                              label: label,
                              background: marks[id] == status
                                  ? (status == 'hadir'
                                        ? GLTheme.mint
                                        : GLTheme.butter)
                                  : null,
                              outlined: marks[id] != status,
                              height: 36,
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
        Text(
          'Yang tidak ditandai tercatat tanpa keterangan.',
          style: gl(13, w400, 0, GLTheme.text3),
        ),
        if (error != null) GLFormError(error!),
        GLSubmitButton(
          key: Key('meeting-record-save'),
          title: saving ? 'Menyimpan…' : 'Simpan notulen',
          busy: saving,
          onPressed: _save,
        ),
      ],
    ),
  );
}

// MARK: - Approvals

/// "Tertahan di `nama` · N hari", or the stale-approver warning.
String _approvalWait(GrouplyStore store, JsonMap approval) {
  final step = GrouplyStore.currentStep(approval);
  if (step == null) return '';
  if (step['eligible'] != true) return 'Penyetuju tidak lagi menjabat';
  DateTime since = approval.date('createdAt')!;
  for (final s in (approval['steps'] as List).cast<JsonMap>()) {
    final at = s.date('decidedAt');
    if (at != null && at.isAfter(since)) since = at;
  }
  final days = store.now.difference(since).inDays;
  final name = step.text('approverID') == store.currentUserID
      ? 'kamu'
      : step.text('name');
  return 'Tertahan di $name · ${days == 0 ? 'hari ini' : '$days hari'}';
}

Future<void> _requestApproval(_WorkspaceState state, JsonMap group) async {
  final store = state.store;
  if (!_activeDivision(store, group)) {
    return state.feedback(
      'Pengajuan baru bisa dibuat saat paket organisasi aktif.',
      kind: GLToastKind.err,
    );
  }
  final result = await showGLSheet<JsonMap>(
    state.context,
    title: 'Ajukan persetujuan',
    subtitle:
        'Susun urutan penyetuju. Pengajuan tidak bisa diubah; revisi diajukan ulang.',
    builder: (_) => _ApprovalSheet(store: store, group: group),
  );
  if (result != null && state.mounted && result.text('id').isNotEmpty) {
    state.open(
      ApprovalScreen(
        store: store,
        orgID: group.text('organizationID'),
        approvalID: result.text('id'),
      ),
    );
  }
}

class _ApprovalSheet extends StatefulWidget {
  const _ApprovalSheet({required this.store, required this.group});
  final GrouplyStore store;
  final JsonMap group;
  @override
  State<_ApprovalSheet> createState() => _ApprovalSheetState();
}

class _ApprovalSheetState extends State<_ApprovalSheet> {
  final title = TextEditingController();
  final note = TextEditingController();
  final amount = TextEditingController();
  final links = TextEditingController();
  final order = <String>[];
  String? error;
  bool saving = false;

  GrouplyStore get store => widget.store;

  /// Origin coordinator and org officers: names the requester already sees.
  List<(String, String)> get candidates {
    final org = store.organization(widget.group.text('organizationID'));
    final coordinator = widget.group.text('coordinatorID');
    final seen = <String>{store.currentUserID};
    return [
      if (coordinator.isNotEmpty && seen.add(coordinator))
        (coordinator, '${_personName(store, coordinator)} · Koordinator'),
      for (final role in _orgRows(org ?? {}, 'roles'))
        if (seen.add(role.text('userID')))
          (
            role.text('userID'),
            '${role.text('name')} · ${_orgRoleLabel(role.text('role'))}',
          ),
    ];
  }

  @override
  void dispose() {
    for (final c in [title, note, amount, links]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (saving) return;
    void fail(String text) => setState(() => error = text);
    final name = title.text.trim();
    final body = note.text.trim();
    final typed = amount.text.trim();
    final rawAmount = typed.replaceAll('.', '');
    final urls = [
      for (final line in links.text.split('\n'))
        if (line.trim().isNotEmpty) line.trim(),
    ];
    if (name.isEmpty) return fail('Judul pengajuan wajib diisi.');
    if (body.isEmpty) return fail('Uraian wajib diisi.');
    if (typed.isNotEmpty &&
        !RegExp(r'^(\d+|\d{1,3}(\.\d{3})+)$').hasMatch(typed)) {
      return fail(
        'Nominal hanya angka, dengan titik sebagai pemisah ribuan (contoh 1.500.000).',
      );
    }
    if (rawAmount.length > 12) return fail('Nominal terlalu besar.');
    if (urls.length > 5 ||
        urls.any((u) => !u.toLowerCase().startsWith('https://'))) {
      return fail('Gunakan maksimal 5 tautan HTTPS, satu per baris.');
    }
    if (order.isEmpty) return fail('Pilih minimal satu penyetuju.');
    setState(() {
      saving = true;
      error = null;
    });
    try {
      final result = await store.mutate('requestApproval', {
        'groupID': widget.group.text('id'),
        'title': name,
        'note': body,
        if (rawAmount.isNotEmpty) 'amount': int.parse(rawAmount),
        if (urls.isNotEmpty) 'links': urls,
        'approverIDs': List.of(order),
      });
      if (!mounted) return;
      showGLToast(context, 'Pengajuan dikirim');
      Navigator.of(context).pop(result);
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !saving,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 16,
      children: [
        GLField(
          'Judul',
          required: true,
          child: GLTextField(
            key: Key('approval-title'),
            controller: title,
            hint: 'Contoh: Dana cetak poster',
            maxLength: 120,
            textCapitalization: TextCapitalization.sentences,
          ),
        ),
        GLField(
          'Uraian',
          required: true,
          child: GLTextField(
            key: Key('approval-note'),
            controller: note,
            hint: 'Untuk apa, kapan, dan rinciannya',
            maxLength: 2000,
            minLines: 3,
            maxLines: 6,
            textCapitalization: TextCapitalization.sentences,
          ),
        ),
        GLField(
          'Nominal (opsional)',
          child: GLTextField(
            key: Key('approval-amount'),
            controller: amount,
            hint: 'Rupiah, contoh 750000',
            keyboardType: TextInputType.number,
            maxLength: 15,
          ),
        ),
        GLField(
          'Tautan (opsional)',
          child: GLTextField(
            key: Key('approval-links'),
            controller: links,
            hint: 'https://… satu per baris, maks 5',
            keyboardType: TextInputType.url,
            minLines: 2,
            maxLines: 5,
          ),
        ),
        GLField(
          'Urutan penyetuju',
          required: true,
          trailing: '${order.length}/5',
          child: candidates.isEmpty
              ? GLNotice(
                  text:
                      'Belum ada koordinator atau pengurus lain yang bisa menyetujui.',
                )
              : Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final (id, label) in candidates)
                      GLTap(
                        key: Key('approver-$id'),
                        label: order.contains(id)
                            ? 'Penyetuju ${order.indexOf(id) + 1}: $label'
                            : 'Tambah penyetuju $label',
                        onTap: () => setState(() {
                          if (!order.remove(id) && order.length < 5) {
                            order.add(id);
                          }
                        }),
                        child: GLChip(
                          label: order.contains(id)
                              ? '${order.indexOf(id) + 1}. $label'
                              : label,
                          background: order.contains(id)
                              ? GLTheme.lavender
                              : null,
                          outlined: !order.contains(id),
                          height: 36,
                        ),
                      ),
                  ],
                ),
        ),
        if (error != null) GLFormError(error!),
        GLSubmitButton(
          key: Key('approval-save'),
          title: saving ? 'Mengirim…' : 'Kirim pengajuan',
          busy: saving,
          onPressed: _save,
        ),
      ],
    ),
  );
}

class ApprovalsScreen extends _WorkspaceScreen {
  const ApprovalsScreen({super.key, required super.store, required this.orgID});
  final String orgID;
  @override
  State<ApprovalsScreen> createState() => _ApprovalsState();
}

class _ApprovalsState extends _WorkspaceState<ApprovalsScreen>
    with _GroupActions<ApprovalsScreen> {
  String tab = 'mine';

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: store,
    builder: (context, _) {
      final org = store.organization(widget.orgID);
      if (org == null) {
        return GLAccessDenied(text: 'Kamu bukan anggota organisasi ini.');
      }
      // Officers see every approval; a coordinator gets those of the groups
      // they lead (the server already filters what it sends).
      final officer =
          store.orgRole(widget.orgID).isNotEmpty ||
          store.groups.any(
            (g) =>
                g.text('organizationID') == widget.orgID &&
                _coordinator(store, g),
          );
      final all = store.approvals(widget.orgID);
      final tabs = [
        ('mine', 'Menunggu saya', store.pendingForMe(widget.orgID)),
        (
          'sent',
          'Pengajuan saya',
          [
            for (final a in all)
              if (a.text('requesterID') == store.currentUserID) a,
          ],
        ),
        if (officer) ('all', 'Semua', all),
      ];
      final current = tabs.firstWhere(
        (t) => t.$1 == tab,
        orElse: () => tabs.first,
      );
      return detailPage(
        title: 'Persetujuan',
        children: [
          Text(org.text('name'), style: gl(23, w700, -0.02)),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            clipBehavior: Clip.none,
            child: Row(
              spacing: 6,
              children: [
                for (final (key, label, rows) in tabs)
                  _grButton(
                    key: Key('approvals-tab-$key'),
                    label: '$label · ${rows.length}',
                    selected: key == current.$1,
                    onTap: () => setState(() => tab = key),
                    child: Container(
                      height: 44,
                      padding: EdgeInsets.symmetric(horizontal: 16),
                      alignment: Alignment.center,
                      decoration: ShapeDecoration(
                        color: key == current.$1
                            ? GLTheme.ink
                            : GLTheme.surface,
                        shape: StadiumBorder(
                          side: BorderSide(color: GLTheme.ink, width: 1.5),
                        ),
                      ),
                      child: Text(
                        '$label · ${rows.length}',
                        style: gl(
                          14,
                          w600,
                          0,
                          key == current.$1 ? GLTheme.onInk : GLTheme.ink,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          if (current.$3.isEmpty)
            GLEmptyState(
              title: switch (current.$1) {
                'mine' => 'Tidak ada yang menunggu',
                'sent' => 'Belum ada pengajuan',
                _ => 'Belum ada pengajuan',
              },
              message: current.$1 == 'sent'
                  ? 'Ajukan proposal atau dana dari layar divisi atau kepanitiaanmu.'
                  : 'Pengajuan yang menunggu keputusanmu muncul di sini.',
              icon: 'checkmark.seal',
              tint: GLTheme.butter,
            )
          else
            _workList([for (final a in current.$3) _approvalRow(a)]),
        ],
      );
    },
  );

  Widget _approvalRow(JsonMap approval) {
    final status = approval.text('status');
    final wait = status == 'pending' ? _approvalWait(store, approval) : '';
    final amount = approval['amount'];
    return _workRow(
      icon: 'checkmark.seal',
      tint: _approvalStatus(status).$2,
      title: approval.text('title'),
      subtitle:
          '${approval.text('groupName')} · ${approval.text('requesterID') == store.currentUserID ? 'Kamu' : approval.text('requesterName')}${amount is int ? ' · ${_rupiah(amount)}' : ''}',
      chips: [
        _smallChip(_approvalStatus(status)),
        if (wait.isNotEmpty)
          GLChip(
            label: wait,
            background: wait.startsWith('Penyetuju')
                ? GLTheme.coral
                : GLTheme.muted,
            height: 24,
            fontSize: 12,
          ),
      ],
      onTap: () => open(
        ApprovalScreen(
          store: store,
          orgID: widget.orgID,
          approvalID: approval.text('id'),
        ),
      ),
    );
  }
}

class ApprovalScreen extends _WorkspaceScreen {
  const ApprovalScreen({
    super.key,
    required super.store,
    required this.orgID,
    required this.approvalID,
  });
  final String orgID, approvalID;
  @override
  State<ApprovalScreen> createState() => _ApprovalState();
}

class _ApprovalState extends _WorkspaceState<ApprovalScreen>
    with _GroupActions<ApprovalScreen> {
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: store,
    builder: (context, _) {
      final approval = store
          .approvals(widget.orgID)
          .where((a) => a.text('id') == widget.approvalID)
          .firstOrNull;
      if (approval == null) {
        return GLAccessDenied(
          text:
              'Pengajuan tidak ditemukan, atau kamu tidak lagi berhak melihatnya.',
        );
      }
      return _content(approval);
    },
  );

  Widget _content(JsonMap approval) {
    final status = approval.text('status');
    final pending = status == 'pending';
    final mine = approval.text('requesterID') == store.currentUserID;
    final step = GrouplyStore.currentStep(approval);
    final myTurn = store
        .pendingForMe(widget.orgID)
        .any((a) => a.text('id') == widget.approvalID);
    final amount = approval['amount'];
    final created = approval.date('createdAt')!;
    final steps = (approval['steps'] as List).cast<JsonMap>();
    return detailPage(
      title: 'Pengajuan',
      children: [
        Container(
          padding: EdgeInsets.all(18),
          decoration: glBox(GLTheme.surface, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(approval.text('title'), style: gl(23, w700, -0.02)),
              SizedBox(height: 8),
              Wrap(children: [_smallChip(_approvalStatus(status))]),
              SizedBox(height: 10),
              Text(
                '${approval.text('groupName')} · ${mine ? 'Kamu' : approval.text('requesterName')} · ${GLFormat.longDate(created)}',
                style: gl(14, w400, 0, GLTheme.text3),
              ),
              if (amount is int) ...[
                SizedBox(height: 12),
                Text(_rupiah(amount), style: gl(22, w800, -0.02)),
              ],
              SizedBox(height: 12),
              Text(
                approval.text('note'),
                style: gl(15, w400, 0, GLTheme.text3, 4),
              ),
              for (final link in approval.ids('links')) ...[
                SizedBox(height: 8),
                _TaskLinkRow(url: link, external: true),
              ],
            ],
          ),
        ),
        if (status == 'lapsed')
          GLNotice(
            text:
                'Pengajuan gugur karena pengaju atau penyetuju keluar dari organisasi.',
            color: GLTheme.chip,
          ),
        if (pending && step != null && step['eligible'] != true)
          GLNotice(
            key: Key('approval-stale'),
            text: mine
                ? 'Penyetuju tidak lagi menjabat. Batalkan pengajuan ini lalu ajukan ulang dengan penyetuju yang baru.'
                : 'Penyetuju tidak lagi menjabat. Pengaju perlu membatalkan dan mengajukan ulang.',
            color: GLTheme.coral,
            icon: 'exclamationmark.triangle',
          ),
        _workHeading('Jenjang persetujuan'),
        Container(
          padding: EdgeInsets.symmetric(vertical: 4, horizontal: 14),
          decoration: glBox(GLTheme.surface, 24),
          child: Column(
            children: [for (final s in steps) _stepRow(s, step, pending)],
          ),
        ),
        if (myTurn)
          Row(
            spacing: 8,
            children: [
              Expanded(
                child: GLOutlineButton(
                  key: Key('approval-reject'),
                  title: 'Tolak',
                  icon: 'xmark',
                  onPressed: () => _reject(approval),
                ),
              ),
              Expanded(
                child: GLSubmitButton(
                  key: Key('approval-approve'),
                  title: 'Setujui',
                  busy: busy,
                  onPressed: () => _approve(approval),
                ),
              ),
            ],
          ),
        if (mine && pending)
          GLOutlineButton(
            key: Key('approval-cancel'),
            title: 'Batalkan pengajuan',
            icon: 'xmark.circle',
            onPressed: () => _cancel(approval),
          ),
      ],
    );
  }

  Widget _stepRow(JsonMap step, JsonMap? current, bool pending) {
    final decision = step['decision'];
    final at = step.date('decidedAt');
    final isCurrent = pending && identical(step, current);
    final (label, tint) = switch (decision) {
      'approved' => ('Disetujui', GLTheme.mint),
      'rejected' => ('Ditolak', GLTheme.coral),
      _ when !pending => ('Tidak diputuskan', GLTheme.chip),
      _ when step['eligible'] != true => ('Tidak lagi menjabat', GLTheme.coral),
      _ when isCurrent => ('Menunggu keputusan', GLTheme.butter),
      _ => ('Belum giliran', GLTheme.chip),
    };
    final id = step.text('approverID');
    return MergeSemantics(
      child: Container(
        padding: EdgeInsets.symmetric(vertical: 12),
        decoration: _grHairline,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 32,
              height: 32,
              alignment: Alignment.center,
              decoration: ShapeDecoration(
                color: isCurrent ? GLTheme.ink : GLTheme.muted,
                shape: CircleBorder(),
              ),
              child: Text(
                '${step.number('position')}',
                style: gl(14, w700, 0, isCurrent ? GLTheme.onInk : GLTheme.ink),
              ),
            ),
            SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    id == store.currentUserID ? 'Kamu' : step.text('name'),
                    style: gl(16, w600),
                  ),
                  SizedBox(height: 4),
                  Wrap(spacing: 6, children: [_smallChip((label, tint))]),
                  if (step.text('note').isNotEmpty) ...[
                    SizedBox(height: 6),
                    Text(
                      step.text('note'),
                      style: gl(14, w400, 0, GLTheme.text3, 3),
                    ),
                  ],
                  if (at != null) ...[
                    SizedBox(height: 4),
                    Text(_when(at), style: gl(12, w400, 0, GLTheme.secondary)),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _approve(JsonMap approval) async {
    final last =
        (approval['steps'] as List)
            .cast<JsonMap>()
            .where((s) => s['decision'] == null)
            .length ==
        1;
    if (await confirm(
          'Setujui pengajuan?',
          last
              ? 'Kamu penyetuju terakhir. Pengajuan akan berstatus Disetujui.'
              : 'Pengajuan lanjut ke penyetuju berikutnya.',
          ok: 'Setujui',
        ) &&
        mounted) {
      await mutate('decideApproval', {
        'id': widget.approvalID,
        'approve': true,
        'note': '',
      }, success: 'Pengajuan disetujui');
    }
  }

  Future<void> _reject(JsonMap approval) => showGLSheet<JsonMap>(
    context,
    title: 'Tolak pengajuan',
    subtitle: 'Pengajuan langsung ditutup. Pengaju bisa mengajukan versi baru.',
    builder: (_) => _OrgFormSheet(
      store: store,
      action: 'decideApproval',
      inputs: [
        (
          key: 'approval-reason',
          label: 'Alasan',
          hint: 'Wajib diisi',
          initial: '',
          min: 1,
          max: 1000,
          lines: 3,
        ),
      ],
      payload: (v) => {'id': widget.approvalID, 'approve': false, 'note': v[0]},
      submit: 'Tolak',
      success: 'Pengajuan ditolak',
    ),
  );

  Future<void> _cancel(JsonMap approval) async {
    if (await confirm(
          'Batalkan pengajuan?',
          'Pengajuan ditutup dan tidak bisa dibuka lagi.',
          ok: 'Batalkan pengajuan',
          destructive: true,
        ) &&
        mounted) {
      await mutate('cancelApproval', {
        'id': widget.approvalID,
      }, success: 'Pengajuan dibatalkan');
    }
  }
}

// MARK: - Announcements

/// Targets the viewer may post to: the whole org (Ketua/BPH) and groups of
/// this org they coordinate.
List<(String, String)> _announceTargets(GrouplyStore store, String orgID) => [
  if (['ketua', 'bph'].contains(store.orgRole(orgID)))
    ('', 'Seluruh organisasi'),
  for (final g in store.groups)
    if (g.text('organizationID') == orgID && _coordinator(store, g))
      (g.text('id'), g.text('name')),
];

class AnnouncementsScreen extends _WorkspaceScreen {
  const AnnouncementsScreen({
    super.key,
    required super.store,
    required this.orgID,
  });
  final String orgID;
  @override
  State<AnnouncementsScreen> createState() => _AnnouncementsState();
}

class _AnnouncementsState extends _WorkspaceState<AnnouncementsScreen>
    with _GroupActions<AnnouncementsScreen> {
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: store,
    builder: (context, _) {
      final org = store.organization(widget.orgID);
      if (org == null) {
        return GLAccessDenied(text: 'Kamu bukan anggota organisasi ini.');
      }
      final rows = store.announcements(widget.orgID);
      final targets = _announceTargets(store, widget.orgID);
      final active = org['planActive'] == true;
      return detailPage(
        title: 'Pengumuman',
        trailing: targets.isEmpty
            ? null
            : GLCircleButton(
                key: Key('announcement-new'),
                icon: active ? 'plus' : 'lock',
                label: 'Buat pengumuman',
                onTap: () => _post(targets, active),
              ),
        children: [
          Text(org.text('name'), style: gl(23, w700, -0.02)),
          if (rows.isEmpty)
            GLEmptyState(
              title: 'Belum ada pengumuman',
              message:
                  'Pengumuman dari pengurus dan koordinator muncul di sini.',
              icon: 'megaphone',
              tint: GLTheme.sky,
            )
          else
            _workList([
              for (final row in rows)
                _workRow(
                  icon: 'megaphone',
                  tint: row['read'] == true ? GLTheme.muted : GLTheme.sky,
                  title: row.text('title'),
                  subtitle:
                      '${_announceScope(row)} · ${row.text('authorName')} · ${GLFormat.date(row.date('createdAt')!)}',
                  chips: [
                    if (row['read'] != true)
                      _smallChip(('Belum dibaca', GLTheme.butter)),
                  ],
                  onTap: () => open(
                    AnnouncementScreen(
                      store: store,
                      orgID: widget.orgID,
                      announcementID: row.text('id'),
                    ),
                  ),
                ),
            ]),
        ],
      );
    },
  );

  String _announceScope(JsonMap row) => row.text('groupID').isEmpty
      ? 'Seluruh organisasi'
      : store.group(row.text('groupID'))?.text('name') ?? 'Grup';

  Future<void> _post(List<(String, String)> targets, bool active) async {
    if (!active) {
      return feedback(
        'Pengumuman baru bisa dibuat saat paket organisasi aktif.',
        kind: GLToastKind.err,
      );
    }
    final target = targets.length == 1
        ? targets.single
        : await showGLSheet<(String, String)>(
            context,
            title: 'Kirim ke',
            builder: (sheet) => _workList([
              for (final t in targets)
                _workRow(
                  key: Key('announce-target-${t.$1.isEmpty ? 'org' : t.$1}'),
                  icon: t.$1.isEmpty ? 'building.2' : 'person.3',
                  tint: t.$1.isEmpty ? GLTheme.lavender : GLTheme.mint,
                  title: t.$2,
                  subtitle: t.$1.isEmpty
                      ? 'Semua anggota organisasi'
                      : 'Anggota grup ini saja',
                  onTap: () => Navigator.of(sheet).pop(t),
                ),
            ]),
          );
    if (target == null || !mounted) return;
    await showGLSheet<JsonMap>(
      context,
      title: 'Buat pengumuman',
      subtitle: 'Untuk: ${target.$2}',
      builder: (_) => _OrgFormSheet(
        store: store,
        action: 'postAnnouncement',
        inputs: [
          (
            key: 'announcement-title',
            label: 'Judul',
            hint: 'Contoh: Rapat pleno ditiadakan',
            initial: '',
            min: 3,
            max: 120,
            lines: 1,
          ),
          (
            key: 'announcement-body',
            label: 'Isi',
            hint: 'Tulis pengumuman',
            initial: '',
            min: 1,
            max: 2000,
            lines: 5,
          ),
        ],
        payload: (v) => {
          'organizationID': widget.orgID,
          if (target.$1.isNotEmpty) 'groupID': target.$1,
          'title': v[0],
          'body': v[1],
        },
        submit: 'Kirim',
        success: 'Pengumuman dikirim',
      ),
    );
  }
}

class AnnouncementScreen extends _WorkspaceScreen {
  const AnnouncementScreen({
    super.key,
    required super.store,
    required this.orgID,
    required this.announcementID,
  });
  final String orgID, announcementID;
  @override
  State<AnnouncementScreen> createState() => _AnnouncementState();
}

class _AnnouncementState extends _WorkspaceState<AnnouncementScreen>
    with _GroupActions<AnnouncementScreen> {
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: store,
    builder: (context, _) {
      final row = store
          .announcements(widget.orgID)
          .where((a) => a.text('id') == widget.announcementID)
          .firstOrNull;
      if (row == null) {
        return GLAccessDenied(
          text: 'Pengumuman ini sudah ditarik atau tidak ditujukan kepadamu.',
        );
      }
      return _content(row);
    },
  );

  Widget _content(JsonMap row) {
    final author = row.text('authorID');
    final mine = author == store.currentUserID;
    final orgWide = row.text('groupID').isEmpty;
    final canDelete =
        mine || (orgWide && store.orgRole(widget.orgID) == 'ketua');
    final audience = row.number('audienceCount').toInt();
    final unread = row.ids('unreadIDs');
    final created = row.date('createdAt')!;
    return detailPage(
      title: 'Pengumuman',
      trailing: canDelete
          ? GLCircleButton(
              key: Key('announcement-delete'),
              icon: 'trash',
              label: 'Tarik pengumuman',
              onTap: _delete,
            )
          : null,
      children: [
        Container(
          padding: EdgeInsets.all(18),
          decoration: glBox(GLTheme.surface, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(row.text('title'), style: gl(23, w700, -0.02)),
              SizedBox(height: 6),
              Text(
                '${orgWide ? 'Seluruh organisasi' : store.group(row.text('groupID'))?.text('name') ?? 'Grup'} · ${mine ? 'Kamu' : row.text('authorName')} · ${_when(created)}',
                style: gl(13, w400, 0, GLTheme.secondary),
              ),
              SizedBox(height: 14),
              Text(row.text('body'), style: gl(16, w400, 0, null, 5)),
            ],
          ),
        ),
        if (row['read'] == true)
          GLNotice(
            text: 'Sudah kamu baca.',
            color: GLTheme.mint,
            icon: 'checkmark.circle',
          )
        else if (!mine)
          GLSubmitButton(
            key: Key('announcement-read'),
            title: 'Sudah baca',
            busy: busy,
            onPressed: () => mutate('markAnnouncementRead', {
              'id': widget.announcementID,
            }, success: 'Ditandai sudah dibaca'),
          ),
        if (audience > 0)
          MergeSemantics(
            child: Container(
              key: Key('announcement-reads'),
              padding: EdgeInsets.all(16),
              decoration: glBox(GLTheme.surface, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    '${row.number('readCount')} dari $audience sudah baca',
                    style: gl(17, w700),
                  ),
                  SizedBox(height: 8),
                  GLProgressBar(value: row.number('readCount') / audience),
                ],
              ),
            ),
          ),
        if (unread.isNotEmpty) ...[
          _workHeading(
            'Belum baca',
            sub: 'Hanya orang yang satu grup denganmu',
          ),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final id in unread)
                GLChip(
                  label: _personName(store, id),
                  icon: 'person.2',
                  background: GLTheme.muted,
                ),
            ],
          ),
        ],
      ],
    );
  }

  Future<void> _delete() async {
    if (await confirm(
          'Tarik pengumuman?',
          'Pengumuman hilang dari semua penerima.',
          ok: 'Tarik',
          destructive: true,
        ) &&
        mounted) {
      final result = await mutate('deleteAnnouncement', {
        'id': widget.announcementID,
      }, success: 'Pengumuman ditarik');
      if (result != null && mounted) Navigator.of(context).maybePop();
    }
  }
}
