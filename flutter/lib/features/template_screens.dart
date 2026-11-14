part of 'workspace_screens.dart';

class _SeminarTemplateScreen extends StatefulWidget {
  const _SeminarTemplateScreen({required this.store, required this.projectID});
  final GrouplyStore store;
  final String projectID;
  @override
  State<_SeminarTemplateScreen> createState() => _SeminarTemplateState();
}

class _TemplateDraft {
  _TemplateDraft(String title, String description, this.dueAt, this.assignee)
    : title = TextEditingController(text: title),
      description = TextEditingController(text: description);
  final TextEditingController title, description;
  DateTime dueAt;
  String? assignee, reviewer;
  bool selected = true;
  void dispose() {
    title.dispose();
    description.dispose();
  }
}

class _SeminarTemplateState extends State<_SeminarTemplateScreen> {
  static const roles = ['Acara', 'Keuangan', 'Publikasi'];
  final mapping = <String, Set<String>>{for (final role in roles) role: {}};
  final drafts = <_TemplateDraft>[];
  DateTime? seminar;
  JsonMap? pending;
  String? error;
  bool loading = true, busy = false, pendingLoadFailed = false;
  GrouplyStore get store => widget.store;

  @override
  void initState() {
    super.initState();
    _loadPending();
  }

  Future<void> _loadPending() async {
    try {
      final value = await store.pendingTaskBatch(widget.projectID);
      if (mounted) {
        setState(() {
          pending = value;
          pendingLoadFailed = false;
          error = null;
          loading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          error = 'Permintaan tersimpan tidak dapat dibaca. Coba buka kembali.';
          pendingLoadFailed = true;
          loading = false;
        });
      }
    }
  }

  @override
  void dispose() {
    for (final draft in drafts) {
      draft.dispose();
    }
    super.dispose();
  }

  Future<DateTime?> _date(DateTime initial) => showDatePicker(
    context: context,
    initialDate: initial.isBefore(DateTime(2000)) ? DateTime(2000) : initial,
    firstDate: DateTime(2000),
    lastDate: DateTime(2100),
  );

  void _makeDrafts(JsonMap group) {
    final date = seminar;
    if (date == null) {
      setState(() => error = 'Pilih tanggal seminar terlebih dahulu.');
      return;
    }
    final counts = <String, int>{
      for (final id in group.ids('memberIDs')) id: 0,
    };
    for (final task in store.tasks) {
      final project = store.project(task.text('projectID'));
      if (project?.text('groupID') == group.text('id') &&
          project?.text('status') == 'active' &&
          task.text('status') != 'done') {
        final id = task.text('assigneeID');
        if (counts.containsKey(id)) counts[id] = counts[id]! + 1;
      }
    }
    String? suggest(String role) {
      final candidates = mapping[role]!.where(counts.containsKey).toList()
        ..sort((a, b) {
          final count = counts[a]!.compareTo(counts[b]!);
          if (count != 0) return count;
          final name = _taskName(
            store,
            a,
          ).toLowerCase().compareTo(_taskName(store, b).toLowerCase());
          return name != 0 ? name : a.compareTo(b);
        });
      if (candidates.isEmpty) return null;
      final id = candidates.first;
      counts[id] = counts[id]! + 1;
      return id;
    }

    for (final draft in drafts) {
      draft.dispose();
    }
    drafts.clear();
    for (final (title, description, role, offset) in [
      (
        'Susun rundown acara',
        'Rundown seminar siap ditinjau.\n\n$_reviewCriteriaHeading\n- Urutan sesi dan durasinya jelas.\n- Penanggung jawab tiap sesi tercantum.',
        'Acara',
        7,
      ),
      (
        'Susun RAB seminar',
        'Rencana anggaran seminar siap ditinjau.\n\n$_reviewCriteriaHeading\n- Volume dan harga satuan tiap pos tercantum.\n- Total sesuai rincian biaya.',
        'Keuangan',
        14,
      ),
      (
        'Buat poster seminar',
        'Poster seminar siap ditinjau.\n\n$_reviewCriteriaHeading\n- Tanggal, waktu, dan lokasi tercantum.\n- Informasi pendaftaran bisa dibaca.',
        'Publikasi',
        7,
      ),
    ]) {
      drafts.add(
        _TemplateDraft(
          title,
          description,
          _taskEndOfDay(date.subtract(Duration(days: offset))),
          suggest(role),
        ),
      );
    }
    setState(() {
      error = null;
    });
  }

  Future<void> _publish(JsonMap project, JsonMap group) async {
    if (busy) return;
    JsonMap payload;
    if (pending != null) {
      payload = pending!;
    } else {
      final selected = drafts.where((d) => d.selected).toList();
      if (selected.isEmpty) {
        setState(() => error = 'Pilih setidaknya satu tugas.');
        return;
      }
      final current = store.project(widget.projectID);
      if (current == null ||
          current.text('status') != 'active' ||
          !store.canManageTasks(current) ||
          !_activeDivision(store, group)) {
        setState(
          () => error =
              'Proyek, akses, atau paket telah berubah. Muat ulang proyek.',
        );
        return;
      }
      for (var i = 0; i < drafts.length; i++) {
        final d = drafts[i];
        if (!d.selected) continue;
        final title = d.title.text.trim().split(RegExp(r'\s+')).join(' ');
        if (title.length < 3 ||
            title.length > 120 ||
            d.description.text.trim().length > 2000 ||
            !group.ids('memberIDs').contains(d.assignee) ||
            !group.ids('memberIDs').contains(d.reviewer) ||
            d.assignee == d.reviewer ||
            !d.dueAt.isAfter(store.now)) {
          setState(
            () => error =
                'Periksa tugas ${i + 1}: judul, pelaksana, reviewer berbeda, dan tenggat mendatang wajib diisi.',
          );
          return;
        }
      }
      payload = {
        'projectID': widget.projectID,
        'requestID': _clientID(),
        'tasks': [
          for (final d in selected)
            {
              'title': d.title.text.trim().split(RegExp(r'\s+')).join(' '),
              'description': d.description.text.trim(),
              'assigneeID': d.assignee,
              'reviewerID': d.reviewer,
              'dueAt': d.dueAt.toUtc().toIso8601String(),
            },
        ],
      };
    }
    FocusScope.of(context).unfocus();
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final result = await store.publishTaskBatch(payload);
      if (!mounted) return;
      final ids = result['ids'] as List;
      showGLToast(context, '${ids.length} tugas berhasil dibuat.');
      Navigator.of(context).pop();
    } catch (e) {
      JsonMap? saved;
      try {
        saved = await store.pendingTaskBatch(widget.projectID);
      } catch (_) {
        saved = payload;
      }
      if (mounted) {
        setState(() {
          pending = saved;
          error = '$e';
        });
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _discard() async {
    if (!await showGLConfirm(
          context,
          title: 'Buang permintaan?',
          text:
              'Tugas dari permintaan ini mungkin sudah dibuat. Periksa daftar tugas proyek sebelum menerbitkan ulang.',
          ok: 'Buang',
        ) ||
        !mounted) {
      return;
    }
    setState(() => busy = true);
    try {
      await store.discardTaskBatch(widget.projectID);
      if (mounted) setState(() => pending = null);
    } catch (_) {
      if (mounted) {
        setState(() => error = 'Permintaan belum dapat dibuang. Coba lagi.');
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: store,
    builder: (context, _) {
      final project = store.project(widget.projectID);
      final group = store.group(project?.text('groupID') ?? '');
      if (project == null || group == null || !store.canManageTasks(project)) {
        return GLAccessDenied();
      }
      final members = group.ids('memberIDs');
      final enabled =
          !loading &&
          !busy &&
          pending == null &&
          _activeDivision(store, group) &&
          project.text('status') == 'active' &&
          store.taskBatchAvailable;
      Widget picker(
        String label,
        String? value,
        ValueChanged<String?> change,
        Key key,
      ) => DropdownButtonFormField<String>(
        key: key,
        initialValue: members.contains(value) ? value : null,
        decoration: glInputDecoration(hint: label),
        items: [
          for (final id in members)
            DropdownMenuItem(value: id, child: Text(_taskName(store, id))),
        ],
        onChanged: enabled ? (v) => setState(() => change(v)) : null,
      );
      return PopScope(
        canPop: !busy,
        child: GLDetailScaffold(
          title: 'Template Proker',
          children: [
            Text('Persiapan Seminar', style: gl(22, w700)),
            if (loading)
              Center(child: CircularProgressIndicator.adaptive())
            else if (pendingLoadFailed) ...[
              GLFormError(error!),
              GLOutlineButton(
                title: 'Coba lagi',
                icon: 'arrow.clockwise',
                onPressed: () {
                  setState(() => loading = true);
                  _loadPending();
                },
              ),
            ] else if (pending != null) ...[
              Text(
                'Penerbitan sebelumnya belum terkonfirmasi. Coba lagi dengan permintaan yang sama.',
                style: gl(15, w400),
              ),
              if (error != null) GLFormError(error!),
              GLSubmitButton(
                key: Key('template-retry'),
                title: 'Coba lagi',
                busy: busy,
                onPressed: store.taskBatchAvailable
                    ? () => _publish(project, group)
                    : null,
              ),
              if (!store.taskBatchAvailable)
                GLFormError('Server belum dapat mengonfirmasi penerbitan ini.'),
              GLOutlineButton(
                key: Key('template-discard'),
                title: 'Buang permintaan',
                icon: 'trash',
                onPressed: busy ? null : _discard,
              ),
            ] else if (!store.taskBatchAvailable)
              GLFormError(
                'Server belum mendukung template. Tugas tetap dapat dibuat secara manual.',
              )
            else if (!_activeDivision(store, group))
              GLFormError(
                'Paket organisasi belum aktif. Tugas tetap dapat dibuat secara manual.',
              )
            else if (project.text('status') != 'active')
              GLFormError('Proyek harus aktif untuk menggunakan template.')
            else ...[
              Text(
                'Pilih tanggal seminar dan anggota untuk tiap peran. Pemetaan ini tidak mengubah jabatan organisasi.',
                style: gl(15, w400),
              ),
              GLOutlineButton(
                key: Key('template-date'),
                title: seminar == null
                    ? 'Pilih tanggal seminar'
                    : 'Seminar: ${GLFormat.date(seminar!)}',
                icon: 'calendar',
                onPressed: enabled && drafts.isEmpty
                    ? () async {
                        final date = await _date(
                          seminar ?? store.now.add(Duration(days: 30)),
                        );
                        if (date != null && mounted) {
                          setState(() => seminar = date);
                        }
                      }
                    : null,
              ),
              for (final role in roles) ...[
                Text(role, style: gl(16, w600)),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    for (final id in members)
                      FilterChip(
                        key: Key('template-role-$role-$id'),
                        label: Text(_taskName(store, id)),
                        selected: mapping[role]!.contains(id),
                        onSelected: enabled && drafts.isEmpty
                            ? (v) => setState(() {
                                if (v) {
                                  mapping[role]!.add(id);
                                } else {
                                  mapping[role]!.remove(id);
                                }
                              })
                            : null,
                      ),
                  ],
                ),
              ],
              if (drafts.isEmpty)
                GLSubmitButton(
                  key: Key('template-draft'),
                  title: 'Siapkan draf',
                  onPressed: enabled ? () => _makeDrafts(group) : null,
                )
              else ...[
                Text('Periksa pembagian tugas', style: gl(19, w700)),
                GLOutlineButton(
                  title: 'Ubah pemetaan dan buat ulang draf',
                  icon: 'arrow.clockwise',
                  onPressed: enabled
                      ? () async {
                          if (await showGLConfirm(
                                context,
                                title: 'Buat ulang draf?',
                                text: 'Perubahan pada draf ini akan hilang.',
                                ok: 'Buat ulang',
                              ) &&
                              mounted) {
                            setState(() {
                              for (final d in drafts) {
                                d.dispose();
                              }
                              drafts.clear();
                            });
                          }
                        }
                      : null,
                ),
                for (var i = 0; i < drafts.length; i++) ...[
                  Builder(
                    builder: (context) {
                      final d = drafts[i];
                      final late =
                          project.date('dueAt') != null &&
                          DateUtils.dateOnly(d.dueAt).isAfter(
                            DateUtils.dateOnly(
                              project.date('dueAt')!.toLocal(),
                            ),
                          );
                      return Container(
                        padding: EdgeInsets.all(16),
                        decoration: glBox(GLTheme.surface, 20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          spacing: 10,
                          children: [
                            CheckboxListTile(
                              key: Key('template-select-$i'),
                              contentPadding: EdgeInsets.zero,
                              title: Text(
                                'Tugas ${i + 1}',
                                style: gl(16, w600),
                              ),
                              value: d.selected,
                              onChanged: enabled
                                  ? (v) =>
                                        setState(() => d.selected = v ?? false)
                                  : null,
                            ),
                            Text('Judul tugas', style: gl(14, w600)),
                            IgnorePointer(
                              ignoring: !enabled,
                              child: GLTextField(
                                key: Key('template-title-$i'),
                                controller: d.title,
                                maxLength: 120,
                                semanticLabel: 'Judul tugas ${i + 1}',
                                onChanged: (_) => setState(() {}),
                              ),
                            ),
                            Text('Hasil yang diharapkan', style: gl(14, w600)),
                            IgnorePointer(
                              ignoring: !enabled,
                              child: GLTextField(
                                key: Key('template-description-$i'),
                                controller: d.description,
                                maxLength: 2000,
                                maxLines: 3,
                                semanticLabel: 'Hasil yang diharapkan ${i + 1}',
                              ),
                            ),
                            picker(
                              'Pilih pelaksana',
                              d.assignee,
                              (v) => d.assignee = v,
                              Key('template-assignee-$i'),
                            ),
                            picker(
                              'Pilih reviewer',
                              d.reviewer,
                              (v) => d.reviewer = v,
                              Key('template-reviewer-$i'),
                            ),
                            GLOutlineButton(
                              key: Key('template-due-$i'),
                              title: 'Deadline ${GLFormat.date(d.dueAt)}',
                              icon: 'calendar',
                              onPressed: enabled
                                  ? () async {
                                      final picked = await _date(d.dueAt);
                                      if (picked != null && mounted) {
                                        setState(
                                          () => d.dueAt = _taskEndOfDay(picked),
                                        );
                                      }
                                    }
                                  : null,
                            ),
                            if (!d.dueAt.isAfter(store.now))
                              Text(
                                'Deadline sudah lewat. Pilih tanggal mendatang.',
                                style: gl(13, w500, 0, GLTheme.secondary),
                              ),
                            if (late)
                              Text(
                                'Deadline melewati deadline proyek. Pastikan ini disengaja.',
                                style: gl(13, w500, 0, GLTheme.secondary),
                              ),
                            if (d.assignee == null ||
                                d.reviewer == null ||
                                d.assignee == d.reviewer)
                              Text(
                                'Pilih pelaksana dan reviewer yang berbeda.',
                                style: gl(13, w500, 0, GLTheme.secondary),
                              ),
                            if (d.title.text.trim().length < 3)
                              Text(
                                'Judul minimal 3 karakter.',
                                style: gl(13, w500, 0, GLTheme.secondary),
                              ),
                          ],
                        ),
                      );
                    },
                  ),
                ],
                if (error != null) GLFormError(error!),
                GLSubmitButton(
                  key: Key('template-publish'),
                  title: 'Terbitkan tugas',
                  busy: busy,
                  onPressed: enabled ? () => _publish(project, group) : null,
                ),
              ],
              if (error != null && drafts.isEmpty) GLFormError(error!),
              GLOutlineButton(
                title: 'Batal',
                onPressed: busy ? null : () => Navigator.of(context).pop(),
              ),
            ],
          ],
        ),
      );
    },
  );
}
