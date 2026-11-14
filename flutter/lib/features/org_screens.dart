part of 'workspace_screens.dart';

// Organization Plan Tahap 1 (docs/DESIGN-org-tahap1.md §5.2). Buttons are
// hidden by org role only; the server enforces every rule (§3).

String _orgRoleLabel(String role) => switch (role) {
  'ketua' => 'Ketua',
  'bph' => 'BPH',
  'pembina' => 'Pembina',
  _ => 'Anggota',
};

const _orgRoleOrder = ['ketua', 'bph', 'pembina'];

List<JsonMap> _orgRows(JsonMap row, String key) =>
    (row[key] as List? ?? []).whereType<JsonMap>().toList();

/// Division of an organization whose plan is active: no 8-member client cap
/// and multi-use invites. The server still checks seats and its own caps.
bool _activeDivision(GrouplyStore store, JsonMap? group) =>
    store.organization(group?.text('organizationID') ?? '')?['planActive'] ==
    true;

/// Divisions of a known organization are listed under it, not as groups.
bool _plainGroup(GrouplyStore store, JsonMap group) =>
    store.organization(group.text('organizationID')) == null;

Widget _orgPlanChip(JsonMap org) => org['planActive'] == true
    ? GLChip(
        label: 'Paket aktif',
        icon: 'checkmark.shield',
        background: GLTheme.mint,
        fontSize: 12,
      )
    : GLChip(
        label: org['planExpiresAt'] == null
            ? 'Paket belum aktif'
            : 'Paket berakhir',
        icon: 'exclamationmark.circle',
        background: GLTheme.coral,
        fontSize: 12,
      );

Widget _orgRoleChip(String role) => GLChip(
  label: _orgRoleLabel(role),
  icon: role.isEmpty ? null : 'rosette',
  background: role.isEmpty ? GLTheme.muted : GLTheme.lavender,
  fontSize: 12,
);

/// Outlined 44pt pill, like "Undang" on the group screen.
Widget _orgPill(String label, String icon, VoidCallback onTap, {Key? key}) =>
    _grButton(
      key: key,
      label: label,
      onTap: onTap,
      child: Container(
        height: 44,
        padding: EdgeInsets.only(left: 10, right: 14),
        decoration: ShapeDecoration(
          shape: StadiumBorder(
            side: BorderSide(color: GLTheme.ink, width: 1.5),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            GLIcon(icon, size: 19),
            SizedBox(width: 4),
            Text(label, style: gl(14, w600)),
          ],
        ),
      ),
    );

// MARK: - Grup tab

/// "Organisasi" block above the plain group list.
List<Widget> _orgSection(_WorkspaceState state, {required bool groupsFollow}) {
  final store = state.store;
  if (store.organizations.isEmpty) return [];
  return [
    SizedBox(height: 16),
    GLSectionHeading(title: 'Organisasi'),
    for (final org in store.organizations) ...[
      SizedBox(height: 16),
      GLTap.card(
        onTap: () =>
            state.open(OrganizationScreen(store: store, orgID: org.text('id'))),
        child: MergeSemantics(child: _OrgCard(store, org)),
      ),
    ],
    if (groupsFollow) ...[
      SizedBox(height: 16),
      GLSectionHeading(title: 'Grup kelompok'),
    ],
  ];
}

Future<void> _createOrganization(_WorkspaceState state) async {
  final store = state.store;
  final result = await showGLSheet<JsonMap>(
    state.context,
    title: 'Buat organisasi',
    subtitle:
        'Untuk BEM, HIMA, atau UKM. Setiap divisi adalah grup tersendiri.',
    builder: (_) => _OrgFormSheet(
      store: store,
      action: 'createOrganization',
      inputs: [
        (
          key: 'org-name',
          label: 'Nama organisasi',
          hint: 'Contoh: BEM FST',
          initial: '',
          min: 3,
          max: 80,
          lines: 1,
        ),
        (
          key: 'org-period',
          label: 'Periode',
          hint: 'Contoh: 2026/2027',
          initial: '',
          min: 0,
          max: 40,
          lines: 1,
        ),
        (
          key: 'org-division',
          label: 'Nama divisi pertama',
          hint: 'Contoh: BPH Inti',
          initial: 'BPH Inti',
          min: 3,
          max: 40,
          lines: 1,
        ),
      ],
      payload: (v) => {'name': v[0], 'periodLabel': v[1], 'divisionName': v[2]},
      note:
          'Kamu jadi Ketua dan koordinator divisi pertama. Divisi lain, Dashboard, dan undangan multi-pakai tersedia setelah paket aktif.',
      submit: 'Buat organisasi',
      success: 'Organisasi dibuat',
    ),
  );
  if (result != null && state.mounted) {
    state.open(OrganizationScreen(store: store, orgID: result.text('id')));
  }
}

class _OrgCard extends StatelessWidget {
  const _OrgCard(this.store, this.org);
  final GrouplyStore store;
  final JsonMap org;
  @override
  Widget build(BuildContext context) {
    final divisions = _orgRows(org, 'divisions');
    final committees = divisions.where((d) => d['isCommittee'] == true).length;
    final mine = divisions
        .where((d) => d['isMember'] == true)
        .map((d) => d.text('name'))
        .join(', ');
    final period = org.text('periodLabel');
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(18),
      decoration: glBox(GLTheme.surface, 28, shadow: true),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: glBox(GLTheme.lavender, 20),
                child: GLIcon('building.2', size: 26),
              ),
              SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(org.text('name'), style: gl(18, w700, -0.015)),
                    SizedBox(height: 2),
                    Text(
                      period.isEmpty ? 'Organisasi' : 'Periode $period',
                      style: gl(14, w400, 0, GLTheme.secondary),
                    ),
                  ],
                ),
              ),
              if (_orgWorkBadge(store, org.text('id')) case final n when n > 0)
                Padding(
                  padding: EdgeInsets.only(right: 6),
                  child: GLCountBadge(count: n, size: 24),
                ),
              GLIcon('chevron.right', size: 22, color: GLTheme.secondary),
            ],
          ),
          SizedBox(height: 14),
          Text(
            '${divisions.length - committees} divisi${committees > 0 ? ' · $committees kepanitiaan' : ''} · ${org.number('seatsUsed')} anggota${mine.isEmpty ? '' : ' · Divisimu: $mine'}',
            style: gl(14, w400, 0, GLTheme.text3),
          ),
          SizedBox(height: 14),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              _orgRoleChip(store.orgRole(org.text('id'))),
              _orgPlanChip(org),
            ],
          ),
        ],
      ),
    );
  }
}

// MARK: - Forms

typedef _OrgInput = ({
  String key,
  String label,
  String hint,
  String initial,
  int min,
  int max,
  int lines,
});

/// Create/edit sheet for organizations and divisions; pops with the result.
class _OrgFormSheet extends StatefulWidget {
  const _OrgFormSheet({
    required this.store,
    required this.action,
    required this.inputs,
    required this.payload,
    required this.submit,
    required this.success,
    this.note,
    this.failureText,
  });
  final GrouplyStore store;
  final String action, submit, success;
  final String? note;

  /// Rewrites the store's error text for this form, e.g. to name a limit.
  final String Function(String message)? failureText;
  final List<_OrgInput> inputs;
  final JsonMap Function(List<String> values) payload;
  @override
  State<_OrgFormSheet> createState() => _OrgFormSheetState();
}

class _OrgFormSheetState extends State<_OrgFormSheet> {
  late final fields = [
    for (final input in widget.inputs)
      TextEditingController(text: input.initial),
  ];
  String? error;
  bool saving = false;

  @override
  void dispose() {
    for (final field in fields) {
      field.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (saving || widget.store.loading) return;
    final values = [for (final field in fields) field.text.trim()];
    for (final (i, input) in widget.inputs.indexed) {
      if (values[i].length < input.min) {
        return setState(
          () => error = '${input.label} minimal ${input.min} karakter.',
        );
      }
    }
    setState(() {
      saving = true;
      error = null;
    });
    try {
      final result = await widget.store.mutate(
        widget.action,
        widget.payload(values),
      );
      if (!mounted) return;
      showGLToast(context, widget.success);
      Navigator.of(context).pop(result);
    } catch (e) {
      final text = e.toString();
      if (mounted) {
        setState(() => error = widget.failureText?.call(text) ?? text);
      }
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !saving,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final (i, input) in widget.inputs.indexed) ...[
          if (i > 0) SizedBox(height: 16),
          GLField(
            input.label,
            required: input.min > 0,
            trailing: input.lines > 1
                ? '${fields[i].text.length}/${input.max}'
                : null,
            child: GLTextField(
              key: Key(input.key),
              controller: fields[i],
              hint: input.hint,
              maxLength: input.max,
              minLines: input.lines,
              maxLines: input.lines,
              textCapitalization: TextCapitalization.sentences,
              onChanged: input.lines > 1 ? (_) => setState(() {}) : null,
            ),
          ),
        ],
        if (widget.note != null) ...[
          SizedBox(height: 16),
          Text(widget.note!, style: gl(14, w400, 0, GLTheme.secondary, 4)),
        ],
        if (error != null) ...[SizedBox(height: 16), GLFormError(error!)],
        SizedBox(height: 16),
        GLSubmitButton(
          key: Key('org-save'),
          title: saving ? 'Menyimpan…' : widget.submit,
          busy: saving,
          onPressed: _save,
        ),
      ],
    ),
  );
}

/// Invite sheet step for divisions of an active org (design §4.2).
Widget _orgInviteUses(BuildContext sheet) => Container(
  padding: EdgeInsets.symmetric(vertical: 4, horizontal: 16),
  decoration: glBox(GLTheme.surface, 24),
  child: Column(
    children: [
      for (final (uses, note) in [
        (1, 'Sekali pakai'),
        (10, 'Untuk beberapa anggota baru'),
        (30, 'Untuk satu angkatan'),
        (100, 'Untuk open recruitment'),
      ])
        GLTap(
          key: Key('invite-uses-$uses'),
          onTap: () => Navigator.of(sheet).pop(uses),
          child: MergeSemantics(
            child: Container(
              constraints: BoxConstraints(minHeight: 60),
              padding: EdgeInsets.symmetric(vertical: 8),
              decoration: uses == 100 ? null : _grHairline,
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('$uses orang', style: gl(16, w600)),
                        SizedBox(height: 2),
                        Text(note, style: gl(13, w400, 0, GLTheme.secondary)),
                      ],
                    ),
                  ),
                  GLIcon('chevron.right', size: 22, color: GLTheme.secondary),
                ],
              ),
            ),
          ),
        ),
    ],
  ),
);

// MARK: - Organization screen

class OrganizationScreen extends _WorkspaceScreen {
  const OrganizationScreen({
    super.key,
    required super.store,
    required this.orgID,
  });
  final String orgID;
  @override
  State<OrganizationScreen> createState() => _OrgState();
}

class _OrgState extends _WorkspaceState<OrganizationScreen>
    with _GroupActions<OrganizationScreen> {
  String get orgID => widget.orgID;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: store,
    builder: (context, _) {
      final org = store.organization(orgID);
      if (org == null) {
        return GLAccessDenied(
          text:
              'Kamu bukan anggota organisasi ini, atau organisasinya tidak ditemukan.',
        );
      }
      return _content(org);
    },
  );

  Widget _content(JsonMap org) {
    final role = store.orgRole(orgID);
    final active = org['planActive'] == true;
    final used = org.number('seatsUsed').toInt();
    final limit = org.number('seatLimit').toInt();
    final description = org.text('description');
    final period = org.text('periodLabel');
    final all = _orgRows(org, 'divisions');
    final divisions = [
      for (final d in all)
        if (d['isCommittee'] != true) d,
    ];
    final committees = [
      for (final d in all)
        if (d['isCommittee'] == true) d,
    ];
    final officers = _orgRows(org, 'roles')
      ..sort(
        (a, b) => _orgRoleOrder
            .indexOf(a.text('role'))
            .compareTo(_orgRoleOrder.indexOf(b.text('role'))),
      );
    return detailPage(
      title: 'Organisasi',
      trailing: role == 'ketua'
          ? GLCircleButton(
              icon: 'square.and.pencil',
              label: 'Ubah info organisasi',
              onTap: () => _edit(org),
            )
          : null,
      children: [
        Container(
          padding: EdgeInsets.all(20),
          decoration: glBox(GLTheme.surface, 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 58,
                    height: 58,
                    decoration: glBox(GLTheme.lavender, 22),
                    child: GLIcon('building.2', size: 28),
                  ),
                  SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(org.text('name'), style: gl(23, w700, -0.02)),
                        SizedBox(height: 2),
                        Text(
                          period.isEmpty ? 'Organisasi' : 'Periode $period',
                          style: gl(14, w400, 0, GLTheme.secondary),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              if (description.isNotEmpty) ...[
                SizedBox(height: 14),
                Text(description, style: gl(15, w400, 0, GLTheme.text3, 4)),
              ],
              SizedBox(height: 14),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [_orgPlanChip(org), _orgRoleChip(role)],
              ),
              SizedBox(height: 14),
              Row(
                children: [
                  GLIcon('person.3', size: 18, color: GLTheme.text3),
                  SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      active
                          ? '$used dari $limit kursi terpakai'
                          : '$used anggota · batas gratis 8 orang per divisi',
                      style: gl(14, w400, 0, GLTheme.text3),
                    ),
                  ),
                ],
              ),
              if (active && limit > 0) ...[
                SizedBox(height: 10),
                GLProgressBar(value: used / limit),
              ],
              if (role.isNotEmpty) ...[
                SizedBox(height: 16),
                _grButton(
                  key: Key('org-dashboard'),
                  label: active
                      ? 'Dashboard'
                      : 'Dashboard, tersedia saat paket aktif',
                  onTap: () => active
                      ? open(OrgDashboardScreen(store: store, orgID: orgID))
                      : feedback(
                          'Dashboard tersedia saat paket aktif.',
                          kind: GLToastKind.err,
                        ),
                  child: Container(
                    height: 48,
                    decoration: glBox(GLTheme.ink, 16),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        GLIcon(
                          active ? 'speedometer' : 'lock',
                          size: 19,
                          color: GLTheme.onInk,
                        ),
                        SizedBox(width: 6),
                        Text(
                          'Dashboard',
                          style: gl(15, w600, 0, GLTheme.onInk),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
        if (!active)
          _OrgPlanBanner(
            org: org,
            onCopy: () => _copy(orgID, 'Kode organisasi disalin'),
          ),

        _orgWorkLinks(this, orgID),

        _divisionBlock(
          'Divisi',
          divisions,
          role == 'ketua' || role == 'bph',
          active,
          committee: false,
        ),
        if (committees.isNotEmpty || role == 'ketua' || role == 'bph')
          _divisionBlock(
            'Kepanitiaan',
            committees,
            role == 'ketua' || role == 'bph',
            active,
            committee: true,
          ),

        // Officers
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(child: Text('Pengurus', style: gl(21, w700, -0.02))),
                if (role == 'ketua') ...[
                  SizedBox(width: 8),
                  _orgPill(
                    'Atur jabatan',
                    'person.badge.shield.checkmark',
                    _manageRoles,
                    key: Key('org-roles'),
                  ),
                ],
              ],
            ),
            SizedBox(height: 10),
            Container(
              padding: EdgeInsets.symmetric(vertical: 4, horizontal: 14),
              decoration: glBox(GLTheme.surface, 24),
              child: Column(
                children: [
                  for (final officer in officers)
                    MergeSemantics(
                      child: _personRow(
                        officer.text('userID'),
                        officer.text('name'),
                        officer.text('role'),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _divisionBlock(
    String title,
    List<JsonMap> rows,
    bool canAdd,
    bool active, {
    required bool committee,
  }) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      _workHeading(
        title,
        sub: '${rows.length} ${committee ? 'kepanitiaan' : 'divisi'}',
        action: canAdd
            ? _orgPill(
                committee ? 'Tambah kepanitiaan' : 'Tambah divisi',
                active ? 'plus' : 'lock',
                () => _addDivision(active, committee: committee),
                key: Key(committee ? 'org-add-committee' : 'org-add-division'),
              )
            : null,
      ),
      SizedBox(height: 10),
      if (rows.isEmpty)
        Text(
          committee
              ? 'Belum ada kepanitiaan. Anggotanya boleh dari divisi mana pun.'
              : 'Belum ada divisi.',
          style: gl(14, w400, 0, GLTheme.secondary),
        )
      else
        Container(
          padding: EdgeInsets.symmetric(vertical: 4, horizontal: 14),
          decoration: glBox(GLTheme.surface, 24),
          child: Column(
            children: [for (final division in rows) _divisionRow(division)],
          ),
        ),
    ],
  );

  Widget _divisionRow(JsonMap division) {
    final id = division.text('id');
    final group = store.group(id);
    final member = division['isMember'] == true && _member(store, group);
    final row = Container(
      constraints: BoxConstraints(minHeight: 64),
      padding: EdgeInsets.symmetric(vertical: 10),
      decoration: _grHairline,
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: glBox(glTint(group?.text('tint'), GLTheme.muted), 14),
            child: GLIcon(group?.text('icon') ?? 'person.3', size: 20),
          ),
          SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(division.text('name'), style: gl(16, w600)),
                SizedBox(height: 2),
                Text(
                  '${division.number('memberCount')} anggota${member ? ' · kamu anggota' : ''}',
                  style: gl(13, w400, 0, GLTheme.secondary),
                ),
              ],
            ),
          ),
          if (member)
            GLIcon('chevron.right', size: 22, color: GLTheme.secondary),
        ],
      ),
    );
    return member
        ? GLTap(
            onTap: () => open(GroupScreen(store: store, groupID: id)),
            child: MergeSemantics(child: row),
          )
        : MergeSemantics(child: row);
  }

  Widget _personRow(String id, String name, String role) => Container(
    constraints: BoxConstraints(minHeight: 64),
    padding: EdgeInsets.symmetric(vertical: 10),
    decoration: _grHairline,
    child: Row(
      children: [
        GLAvatar(
          user: store.user(id) ?? <String, dynamic>{'name': name},
          size: 44,
          fontSize: 14,
        ),
        SizedBox(width: 12),
        Expanded(
          child: Text(
            '$name${id == store.currentUserID ? ' (kamu)' : ''}',
            style: gl(16, w600),
          ),
        ),
        SizedBox(width: 12),
        _GroupsSmallChip(
          label: _orgRoleLabel(role),
          icon: role.isEmpty ? 'person.2' : 'rosette',
          background: role == 'ketua'
              ? GLTheme.mint
              : role.isEmpty
              ? GLTheme.muted
              : GLTheme.lavender,
        ),
      ],
    ),
  );

  Future<void> _edit(JsonMap org) => showGLSheet<JsonMap>(
    context,
    title: 'Ubah organisasi',
    builder: (_) => _OrgFormSheet(
      store: store,
      action: 'updateOrganization',
      inputs: [
        (
          key: 'org-name',
          label: 'Nama organisasi',
          hint: 'Contoh: BEM FST',
          initial: org.text('name'),
          min: 3,
          max: 80,
          lines: 1,
        ),
        (
          key: 'org-period',
          label: 'Periode',
          hint: 'Contoh: 2026/2027',
          initial: org.text('periodLabel'),
          min: 0,
          max: 40,
          lines: 1,
        ),
        (
          key: 'org-description',
          label: 'Deskripsi',
          hint: 'Visi, misi, atau catatan singkat',
          initial: org.text('description'),
          min: 0,
          max: 1000,
          lines: 3,
        ),
      ],
      payload: (v) => {
        'id': orgID,
        'name': v[0],
        'periodLabel': v[1],
        'description': v[2],
      },
      submit: 'Simpan',
      success: 'Info organisasi disimpan',
    ),
  );

  Future<void> _addDivision(bool active, {bool committee = false}) async {
    final kind = committee ? 'Kepanitiaan' : 'Divisi';
    if (!active) {
      return feedback(
        '$kind baru bisa dibuat saat paket aktif.',
        kind: GLToastKind.err,
      );
    }
    final result = await showGLSheet<JsonMap>(
      context,
      title: committee ? 'Tambah kepanitiaan' : 'Tambah divisi',
      builder: (_) => _OrgFormSheet(
        store: store,
        action: 'createDivision',
        inputs: [
          (
            key: 'division-name',
            label: 'Nama ${kind.toLowerCase()}',
            hint: committee ? 'Contoh: Panitia Dies Natalis' : 'Contoh: Humas',
            initial: '',
            min: 3,
            max: 40,
            lines: 1,
          ),
        ],
        payload: (v) => {
          'organizationID': orgID,
          'name': v[0],
          if (committee) 'committee': true,
        },
        note: committee
            ? 'Kamu jadi koordinator kepanitiaan ini. Undang panitia dari divisi mana pun, lalu serahkan peran koordinator ke ketua pelaksana. Proyek di kepanitiaan tampil sebagai Sie.'
            : 'Kamu jadi koordinator divisi ini. Undang anggotanya, lalu serahkan peran koordinator ke Kadiv lewat menu anggota.',
        failureText: committee
            ? (text) => text == GrouplyStore.codeText('invalid_input')
                  ? 'Kepanitiaan belum dapat dibuat. Nama 3–40 karakter, dan satu organisasi maksimal punya 30 kepanitiaan.'
                  : text
            : null,
        submit: committee ? 'Buat kepanitiaan' : 'Buat divisi',
        success: '$kind dibuat',
      ),
    );
    if (result != null && mounted && result.text('id').isNotEmpty) {
      open(GroupScreen(store: store, groupID: result.text('id')));
    }
  }

  /// Ketua only: people the viewer can see in this org's divisions.
  void _manageRoles() => showGLSheet<void>(
    context,
    title: 'Atur jabatan',
    subtitle:
        'Pilih anggota untuk dijadikan BPH atau Pembina, atau serahkan jabatan Ketua.',
    builder: (sheet) => ListenableBuilder(
      listenable: store,
      builder: (sheet, _) {
        final org = store.organization(orgID);
        if (org == null) return SizedBox.shrink();
        final officers = {
          for (final row in _orgRows(org, 'roles')) row.text('userID'): row,
        };
        final ids = {
          for (final group in store.groups)
            if (group.text('organizationID') == orgID)
              ...group.ids('memberIDs'),
          ...officers.keys,
        }..remove(store.currentUserID);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (ids.isEmpty)
              GLNotice(
                text: 'Belum ada anggota lain di divisi yang kamu ikuti.',
              )
            else
              Container(
                padding: EdgeInsets.symmetric(vertical: 4, horizontal: 14),
                decoration: glBox(GLTheme.surface, 24),
                child: Column(
                  children: [
                    for (final id in ids)
                      () {
                        final name =
                            officers[id]?.text('name') ??
                            store.user(id)?.text('name') ??
                            'Anggota';
                        final role = officers[id]?.text('role') ?? '';
                        return GLTap(
                          onTap: () {
                            Navigator.of(sheet).pop();
                            _roleActions(id, name, role);
                          },
                          child: MergeSemantics(
                            child: _personRow(id, name, role),
                          ),
                        );
                      }(),
                  ],
                ),
              ),
            SizedBox(height: 16),
            Text(
              'Hanya anggota dari divisi yang kamu ikuti yang tampil di sini.',
              style: gl(13, w400, 0, GLTheme.text3),
            ),
          ],
        );
      },
    ),
  );

  void _roleActions(String userID, String name, String role) {
    final rows = <(String, String, Color, Future<void> Function())>[
      if (role != 'bph')
        (
          'Jadikan BPH',
          'rosette',
          GLTheme.ink,
          () => _setRole(userID, name, 'bph'),
        ),
      if (role != 'pembina')
        (
          'Jadikan Pembina',
          'rosette',
          GLTheme.ink,
          () => _setRole(userID, name, 'pembina'),
        ),
      if (role.isNotEmpty)
        (
          'Cabut jabatan',
          'person.badge.minus',
          GLTheme.danger,
          () => _setRole(userID, name, null),
        ),
      (
        'Serahkan jabatan Ketua',
        'arrow.left.arrow.right',
        GLTheme.danger,
        () => _transferKetua(userID, name),
      ),
    ];
    showGLSheet<void>(
      context,
      title: name,
      subtitle: 'Jabatan saat ini: ${_orgRoleLabel(role)}',
      builder: (sheet) => Container(
        padding: EdgeInsets.symmetric(vertical: 4, horizontal: 16),
        decoration: glBox(GLTheme.surface, 24),
        child: Column(
          children: [
            for (final (label, icon, color, go) in rows)
              GLTap(
                onTap: () {
                  Navigator.of(sheet).pop();
                  go();
                },
                child: Container(
                  constraints: BoxConstraints(minHeight: 56),
                  decoration: _grHairline,
                  child: Row(
                    children: [
                      GLIcon(icon, size: 22, color: color),
                      SizedBox(width: 12),
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
    );
  }

  Future<void> _setRole(String userID, String name, String? role) async {
    await run(
      'setOrgRole',
      {'organizationID': orgID, 'userID': userID, 'role': role},
      role == null
          ? 'Jabatan $name dicabut'
          : '$name sekarang ${_orgRoleLabel(role)}',
    );
  }

  Future<void> _transferKetua(String userID, String name) async {
    if (await confirm(
      'Serahkan jabatan Ketua?',
      '$name akan menjadi Ketua. Kamu menjadi BPH dan tidak bisa lagi mengubah info organisasi atau mengatur jabatan.',
      ok: 'Serahkan',
      destructive: true,
    )) {
      await run('transferKetua', {
        'organizationID': orgID,
        'userID': userID,
      }, '$name sekarang Ketua');
    }
  }
}

/// Shown while the plan is not active (never activated or expired).
class _OrgPlanBanner extends StatelessWidget {
  const _OrgPlanBanner({required this.org, required this.onCopy});
  final JsonMap org;
  final VoidCallback onCopy;
  @override
  Widget build(BuildContext context) {
    final ended = org.date('planExpiresAt')?.toLocal();
    final text = ended == null
        ? 'Paket belum aktif. Hubungi tim Grouply dengan kode organisasi ini.'
        : 'Paket berakhir ${GLFormat.date(ended)} ${ended.year}. Organisasi kembali ke batas gratis: 8 anggota per divisi, tanpa Dashboard, divisi baru, dan undangan multi-pakai. Hubungi tim Grouply dengan kode organisasi ini.';
    return Container(
      key: Key('org-plan-banner'),
      padding: EdgeInsets.all(16),
      decoration: glBox(GLTheme.butter, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              GLIcon('exclamationmark.triangle', size: 20),
              SizedBox(width: 10),
              Expanded(child: Text(text, style: gl(14, w500, 0, null, 3))),
            ],
          ),
          SizedBox(height: 12),
          Container(
            padding: EdgeInsets.symmetric(vertical: 10, horizontal: 14),
            decoration: glBox(GLTheme.surface, 14),
            child: SelectableText(
              org.text('id'),
              style: gl(13, w600, 0, GLTheme.text3),
            ),
          ),
          SizedBox(height: 10),
          GLOutlineButton(
            title: 'Salin kode organisasi',
            icon: 'doc.on.doc',
            height: 44,
            onPressed: onCopy,
          ),
        ],
      ),
    );
  }
}

// MARK: - Dashboard

class OrgDashboardScreen extends _WorkspaceScreen {
  const OrgDashboardScreen({
    super.key,
    required super.store,
    required this.orgID,
  });
  final String orgID;
  @override
  State<OrgDashboardScreen> createState() => _OrgDashboardState();
}

class _OrgDashboardState extends _WorkspaceState<OrgDashboardScreen>
    with _GroupActions<OrgDashboardScreen>, WidgetsBindingObserver {
  JsonMap? data;
  String? failure;
  int _requests = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    reload();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) reload();
  }

  /// Not realtime (design §4.7): fetched on open, pull to refresh and resume.
  @override
  Future<void> reload() async {
    final order = ++_requests;
    try {
      final value = await store.orgOverview(widget.orgID);
      if (mounted && order == _requests) {
        setState(() {
          data = value;
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
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: store,
    builder: (context, _) {
      final org = store.organization(widget.orgID);
      if (org == null || store.orgRole(widget.orgID).isEmpty) {
        return GLAccessDenied(
          text: 'Dashboard hanya untuk Ketua, BPH, dan Pembina organisasi ini.',
        );
      }
      if (org['planActive'] != true) {
        return GLAccessDenied(text: 'Paket organisasi belum aktif.');
      }
      final data = this.data;
      final stamp = data?.date('generatedAt');
      return detailPage(
        title: 'Dashboard',
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(org.text('name'), style: gl(23, w700, -0.02)),
              SizedBox(height: 2),
              Text(
                stamp == null
                    ? 'Memuat ringkasan…'
                    : 'Diperbarui ${GLFormat.time(stamp)} · tarik ke bawah untuk memuat ulang',
                style: gl(13, w400, 0, GLTheme.secondary),
              ),
            ],
          ),
          if (failure != null && data == null) ...[
            GLEmptyState(
              title: 'Dashboard belum tersedia',
              message: failure!,
              icon: 'speedometer',
              tint: GLTheme.coral,
            ),
            GLOutlineButton(
              title: 'Coba lagi',
              icon: 'arrow.clockwise',
              onPressed: reload,
            ),
          ] else if (failure != null)
            GLFormError(failure!),
          if (data == null && failure == null)
            Padding(
              padding: EdgeInsets.symmetric(vertical: 40),
              child: Center(child: CircularProgressIndicator.adaptive()),
            ),
          if (data != null) ..._overview(data),
        ],
      );
    },
  );

  String _person(JsonMap data, String id) {
    for (final user in _orgRows(data, 'users')) {
      if (user.text('id') == id) return user.text('name');
    }
    return store.user(id)?.text('name') ?? 'Anggota';
  }

  List<Widget> _overview(JsonMap data) {
    final divisions = _orgRows(data, 'divisions');
    final projects = [for (final d in divisions) ..._orgRows(d, 'projects')];
    int sum(String key) =>
        projects.fold(0, (total, p) => total + p.number(key).toInt());
    final attention = _orgRows(data, 'attention');
    final names = {for (final d in divisions) d.text('id'): d.text('name')};
    Widget tile(String label, int value, String icon, Color tint) => Expanded(
      child: MergeSemantics(
        child: Container(
          padding: EdgeInsets.all(16),
          decoration: glBox(tint, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              GLIcon(icon, size: 22),
              SizedBox(height: 10),
              Text('$value', style: gl(28, w800, -0.02)),
              SizedBox(height: 2),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: gl(13, w600, 0, GLTheme.text3),
              ),
            ],
          ),
        ),
      ),
    );
    return [
      Column(
        children: [
          Row(
            children: [
              tile('Proker aktif', projects.length, 'folder', GLTheme.sky),
              SizedBox(width: 10),
              tile(
                'Terlambat',
                sum('overdue'),
                'clock.badge.xmark',
                GLTheme.coral,
              ),
            ],
          ),
          SizedBox(height: 10),
          Row(
            children: [
              tile('Tanpa kabar', sum('idle'), 'hourglass', GLTheme.butter),
              SizedBox(width: 10),
              tile(
                'Review >48 jam',
                sum('reviewPending'),
                'eye',
                GLTheme.lavender,
              ),
            ],
          ),
        ],
      ),
      ..._dashboardApprovals(),
      for (final (title, committee) in [
        ('Divisi', false),
        ('Kepanitiaan', true),
      ])
        if (divisions.any((d) => (d['isCommittee'] == true) == committee)) ...[
          GLSectionHeading(title: title),
          for (final division in divisions)
            if ((division['isCommittee'] == true) == committee)
              _divisionCard(division, data),
        ],
      GLSectionHeading(title: 'Perlu perhatian'),
      if (attention.isEmpty)
        GLNotice(
          text: 'Tidak ada tugas yang terlambat, tertahan, atau tanpa kabar.',
          color: GLTheme.mint,
          icon: 'checkmark.circle',
        )
      else
        Container(
          padding: EdgeInsets.symmetric(vertical: 4, horizontal: 14),
          decoration: glBox(GLTheme.surface, 24),
          child: Column(
            children: [
              for (final item in attention) _attentionRow(item, data, names),
            ],
          ),
        ),
    ];
  }

  /// Pending approvals come from the snapshot, not the overview (§4.7).
  List<Widget> _dashboardApprovals() {
    final pending = [
      for (final a in store.approvals(widget.orgID))
        if (a['status'] == 'pending') a,
    ];
    if (pending.isEmpty) return [];
    final oldest = pending
        .map((a) => a.date('createdAt')!)
        .reduce((a, b) => a.isBefore(b) ? a : b);
    final days = store.now.difference(oldest).inDays;
    return [
      _workList([
        _workRow(
          key: Key('dashboard-approvals'),
          icon: 'checkmark.seal',
          tint: GLTheme.butter,
          title: '${pending.length} pengajuan tertahan',
          subtitle: days > 0
              ? 'Terlama menunggu $days hari'
              : 'Semua diajukan hari ini',
          onTap: () => open(ApprovalsScreen(store: store, orgID: widget.orgID)),
        ),
      ]),
    ];
  }

  Widget _divisionCard(JsonMap division, JsonMap data) {
    final projects = _orgRows(division, 'projects');
    final kadiv = division.text('coordinatorID');
    return Container(
      padding: EdgeInsets.all(16),
      decoration: glBox(GLTheme.surface, 24, shadow: true),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text(division.text('name'), style: gl(17, w700))),
              SizedBox(width: 8),
              Text(
                '${division.number('memberCount')} anggota',
                style: gl(13, w400, 0, GLTheme.secondary),
              ),
            ],
          ),
          SizedBox(height: 2),
          Text(
            '${division['isCommittee'] == true ? 'Ketua pelaksana' : 'Kadiv'}: ${kadiv.isEmpty ? 'belum ada' : _person(data, kadiv)}',
            style: gl(13, w400, 0, GLTheme.text3),
          ),
          if (projects.isEmpty) ...[
            SizedBox(height: 12),
            Text(
              'Belum ada proker aktif.',
              style: gl(14, w400, 0, GLTheme.secondary),
            ),
          ],
          for (final project in projects) ...[
            SizedBox(height: 14),
            _projectProgress(
              project,
              division.text('id'),
              data.date('generatedAt'),
            ),
          ],
        ],
      ),
    );
  }

  void _openProjectTasks(
    JsonMap project,
    String divisionID,
    String filter,
    String label,
    DateTime? generatedAt,
  ) {
    final projectID = project.text('id');
    final cutoff = generatedAt ?? store.now;
    showGLSheet<void>(
      context,
      title: label,
      subtitle: project.text('title'),
      builder: (sheetContext) => ListenableBuilder(
        listenable: store,
        builder: (_, _) {
          if (store.orgRole(widget.orgID).isEmpty ||
              store.organization(widget.orgID)?['planActive'] != true ||
              !_member(store, store.group(divisionID))) {
            return GLFormError('Akses ke rincian proker tidak tersedia.');
          }
          final tasks = store.tasks.where((task) {
            if (task.text('projectID') != projectID) return false;
            final status = task.text('status');
            return switch (filter) {
              'done' => status == 'done',
              'overdue' =>
                status != 'done' &&
                    task.date('dueAt')?.isBefore(cutoff) == true,
              'inReview' => status == 'in_review',
              _ => false,
            };
          }).toList();
          if (tasks.isEmpty) {
            return Text('Tidak ada tugas dalam kategori ini.');
          }
          return _workList([
            for (final task in tasks)
              _workRow(
                icon: 'checkmark.circle',
                tint: GLStatus.tint(task.text('status')),
                title: task.text('title'),
                subtitle: GLStatus.label(task.text('status')),
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  open(TaskScreen(store: store, taskID: task.text('id')));
                },
              ),
          ]);
        },
      ),
    );
  }

  Widget _projectProgress(
    JsonMap project,
    String divisionID,
    DateTime? generatedAt,
  ) {
    final total = project.number('total').toInt();
    final done = project.number('done').toInt();
    final due = project.date('dueAt');
    final canOpen = _member(store, store.group(divisionID));
    final flags = [
      for (final (key, label, tint) in [
        ('done', 'selesai', GLTheme.mint),
        ('overdue', 'terlambat', GLTheme.coral),
        ('inReview', 'menunggu review', GLTheme.chip),
        ('idle', 'tanpa kabar', GLTheme.butter),
        ('reviewPending', 'review tertahan', GLTheme.lavender),
      ])
        if (total > 0 &&
            (project.number(key) > 0 ||
                const {'done', 'overdue', 'inReview'}.contains(key)))
          if (canOpen &&
              project.number(key) > 0 &&
              const {'done', 'overdue', 'inReview'}.contains(key))
            GLTap(
              key: Key('project-summary-${project.text('id')}-$key'),
              label: '${project.number(key)} $label, lihat tugas',
              onTap: () => _openProjectTasks(
                project,
                divisionID,
                key,
                label,
                generatedAt,
              ),
              child: SizedBox(
                height: 44,
                child: Center(
                  widthFactor: 1,
                  child: GLChip(
                    label: '${project.number(key)} $label ›',
                    background: tint,
                    height: 28,
                    fontSize: 12,
                  ),
                ),
              ),
            )
          else
            GLChip(
              label: '${project.number(key)} $label',
              background: tint,
              height: 24,
              fontSize: 12,
            ),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(child: Text(project.text('title'), style: gl(15, w600))),
            SizedBox(width: 8),
            Text(
              total == 0 ? 'Belum ada tugas' : '$done/$total selesai',
              style: gl(13, w400, 0, GLTheme.text3),
            ),
          ],
        ),
        if (due != null) ...[
          SizedBox(height: 2),
          Text(
            'Deadline ${GLFormat.date(due)}',
            style: gl(12, w400, 0, GLTheme.secondary),
          ),
        ],
        SizedBox(height: 8),
        if (total > 0) GLProgressBar(value: done / total),
        if (flags.isNotEmpty) ...[
          SizedBox(height: 8),
          Wrap(spacing: 6, runSpacing: 6, children: flags),
        ],
      ],
    );
  }

  (String, Color) _reason(JsonMap item) {
    final hours = item.number('hours').toInt();
    final span = hours >= 48 ? '${hours ~/ 24} hari' : '$hours jam';
    return switch (item.text('reason')) {
      'overdue' => ('Terlambat $span', GLTheme.coral),
      'review_pending' => ('Review tertahan $span', GLTheme.lavender),
      _ => ('Tanpa kabar $span', GLTheme.butter),
    };
  }

  Widget _attentionRow(JsonMap item, JsonMap data, Map<String, String> names) {
    final (reason, tint) = _reason(item);
    final status = item.text('status');
    return GLTap(
      onTap: () => _openTask(item, data, names),
      child: MergeSemantics(
        child: Container(
          constraints: BoxConstraints(minHeight: 64),
          padding: EdgeInsets.symmetric(vertical: 12),
          decoration: _grHairline,
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(item.text('title'), style: gl(16, w600)),
                    SizedBox(height: 2),
                    Text(
                      '${names[item.text('divisionID')] ?? 'Divisi'} · ${_person(data, item.text('assigneeID'))}',
                      style: gl(13, w400, 0, GLTheme.secondary),
                    ),
                    SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        GLChip(
                          label: reason,
                          background: tint,
                          height: 24,
                          fontSize: 12,
                        ),
                        GLChip(
                          label: GLStatus.label(status),
                          background: GLStatus.tint(status),
                          height: 24,
                          fontSize: 12,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              SizedBox(width: 8),
              GLIcon('chevron.right', size: 22, color: GLTheme.secondary),
            ],
          ),
        ),
      ),
    );
  }

  /// Members open the task; others only get a read-only summary (design §3).
  void _openTask(JsonMap item, JsonMap data, Map<String, String> names) {
    final id = item.text('taskID');
    if (_member(store, store.group(item.text('divisionID'))) &&
        store.task(id) != null) {
      return open(TaskScreen(store: store, taskID: id));
    }
    final due = item.date('dueAt');
    final rows = [
      ('Divisi', names[item.text('divisionID')] ?? '-'),
      ('Pelaksana', _person(data, item.text('assigneeID'))),
      ('Status', GLStatus.label(item.text('status'))),
      (
        'Deadline',
        due == null ? '-' : '${GLFormat.longDate(due)}, ${GLFormat.time(due)}',
      ),
      ('Penanda', _reason(item).$1),
    ];
    showGLSheet<void>(
      context,
      title: 'Ringkasan tugas',
      builder: (_) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: EdgeInsets.all(18),
            decoration: glBox(GLTheme.surface, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(item.text('title'), style: gl(18, w700)),
                SizedBox(height: 12),
                for (final (label, value) in rows)
                  Padding(
                    padding: EdgeInsets.symmetric(vertical: 4),
                    child: MergeSemantics(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SizedBox(
                            width: 92,
                            child: Text(
                              label,
                              style: gl(14, w400, 0, GLTheme.secondary),
                            ),
                          ),
                          Expanded(child: Text(value, style: gl(14, w600))),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
          SizedBox(height: 16),
          GLNotice(
            text:
                'Kamu bukan anggota divisi ini, jadi detail tugas tidak bisa dibuka. Hubungi Kadiv-nya untuk tindak lanjut.',
            color: GLTheme.sky,
          ),
        ],
      ),
    );
  }
}
