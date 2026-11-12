# Desain Teknis — Organization Plan Tahap 2 (Kerja harian organisasi)

Status: **disetujui 12 November 2026** (kesembilan rekomendasi di bagian 8). Backend diimplementasikan di `supabase/migrations/20261112133033_org_work.sql` dan teruji di localhost (`supabase/tests/organization_work.sql`, `scripts/billing_local.py check-locks`). Acuan produk: [PRD-organization-plan.md](PRD-organization-plan.md) (ORG-07 s.d. ORG-11). Dibangun di atas [Tahap 1](DESIGN-org-tahap1.md). Client: Flutter saja. Backend: Supabase lokal yang sama.

> PRD bagian 8 meminta wawancara 5–8 pengurus sebelum Tahap 2 dibangun, dan itu belum dilakukan. Semua aturan di bawah masih dugaan terbaik, jadi dibuat sesederhana mungkin supaya murah diubah setelah pilot.

## 1. Keputusan inti

1. **Kepanitiaan = grup di dalam organisasi dengan penanda `is_committee`.** Anggotanya boleh dari divisi mana pun. Ketua pelaksana = coordinator grup. Proyek di dalam kepanitiaan ditampilkan sebagai **Sie**. Chat, tugas, review, undangan multi-pakai, dan Dashboard langsung berfungsi.
2. **Koordinator sie = `projects.lead_id`.** Coordinator grup boleh menunjuk satu anggota sebagai penanggung jawab proyek. Ia boleh membuat, mengubah, mengalihkan, dan membuka kembali tugas **di proyek itu saja**. Berlaku untuk divisi maupun kepanitiaan. Tanpa ini, ketua pelaksana harus membuat sendiri semua tugas 40 panitia.
3. **Persetujuan berjenjang:** pengaju menyusun sendiri urutan 1–5 penyetuju saat mengajukan. Calon penyetuju hanya coordinator grup asal dan pengurus, yaitu orang yang namanya memang sudah terlihat oleh pengaju. Tidak ada rantai baku per organisasi.
4. **Hak memutuskan diperiksa saat memutuskan, bukan hanya saat diajukan.** Penyetuju yang jabatannya dicabut atau tidak lagi menjadi coordinator grup asal tidak bisa memutuskan dan tidak lagi melihat pengajuan itu. Pengajuannya tetap `pending` dengan tanda "penyetuju tidak lagi menjabat"; pengaju membatalkan lalu mengajukan ulang.
5. **Pengajuan tidak bisa diedit.** Ditolak di satu jenjang = pengajuan ditutup; revisi diajukan sebagai pengajuan baru. Polanya sama dengan submission yang append-only.
6. **Rapat hanya per grup** (divisi atau kepanitiaan). Rapat BPH diadakan di divisi "BPH Inti". Rapat pleno seluruh organisasi tidak dibuat.
7. **Daftar hadir adalah catatan per rapat, bukan rekap per orang.** Tidak ada persentase kehadiran anggota, karena itu sudah masuk "rapor staf" yang dilarang PRD.
8. **Pengumuman:** seluruh organisasi oleh Ketua/BPH, per grup oleh coordinatornya. Jumlah "sudah baca" terlihat oleh penulis dan pengurus; **nama** yang belum baca hanya untuk orang yang satu grup dengan yang melihat. Jadi setiap Kadiv bisa menagih stafnya sendiri, dan aturan privasi Tahap 1 tidak berubah.
9. **ORG-11 (push dari server) ditunda.** Butuh project Firebase dan kunci APNs yang belum ada. Penggantinya di tahap ini: notifikasi lokal untuk rapat (H-1 dan 1 jam sebelumnya) dan badge di aplikasi. Pengganti ini lebih lemah dari push; batasnya ada di bagian 9.
10. **Paket berakhir:** semua yang sudah ada tetap bisa dibaca dan diselesaikan (memutuskan pengajuan, mengisi notulen, menandai baca). Yang terkunci hanya membuat yang baru. Sama dengan keputusan 7 Tahap 1.
11. **Snapshot tetap terbatas.** Notulen, agenda, dan daftar hadir tidak ikut snapshot; diambil lewat RPC detail saat rapat dibuka. Pengajuan dan pengumuman ikut snapshot, tetapi jumlah dan panjang teksnya dibatasi (bagian 4.5).

## 2. Model data (satu migration baru)

```sql
alter table public.groups
  add column is_committee boolean not null default false,
  add constraint groups_committee_in_org check (not is_committee or organization_id is not null);

alter table public.projects
  add column lead_id uuid references public.profiles(id) on delete set null;
create index projects_lead on public.projects(lead_id) where lead_id is not null;

create table public.meetings (
  id uuid primary key default gen_random_uuid(),
  group_id uuid not null references public.groups(id),
  created_by uuid references public.profiles(id) on delete set null,
  note_taker_id uuid references public.profiles(id) on delete set null,   -- notulis
  title text not null check (length(title) between 1 and 120),
  starts_at timestamptz not null,
  place text not null default '' check (length(place) <= 200),            -- ruangan atau tautan
  agenda text not null default '' check (length(agenda) <= 5000),
  minutes text not null default '' check (length(minutes) <= 20000),      -- notulen
  status text not null default 'scheduled' check (status in ('scheduled','done','cancelled')),
  version integer not null default 1 check (version > 0),
  created_at timestamptz not null default now()
);
create index meetings_group on public.meetings(group_id, starts_at);
create index meetings_created_by on public.meetings(created_by);
create index meetings_note_taker on public.meetings(note_taker_id);

create table public.meeting_attendance (
  meeting_id uuid not null references public.meetings(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  status text not null check (status in ('hadir','izin')),               -- tidak tercatat = tanpa keterangan
  primary key (meeting_id, user_id)
);
create index meeting_attendance_user on public.meeting_attendance(user_id);

alter table public.tasks
  add column meeting_id uuid references public.meetings(id) on delete set null;
create index tasks_meeting on public.tasks(meeting_id) where meeting_id is not null;

create table public.approvals (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id),
  group_id uuid not null references public.groups(id),                    -- grup asal
  requester_id uuid references public.profiles(id) on delete set null,
  title text not null check (length(title) between 1 and 120),
  note text not null check (length(note) between 1 and 2000),
  amount bigint check (amount between 0 and 999999999999),                -- rupiah, opsional
  links jsonb not null default '[]' check (private.valid_links(links)),
  status text not null default 'pending'
    check (status in ('pending','approved','rejected','cancelled','lapsed')),
  created_at timestamptz not null default now(),
  closed_at timestamptz,
  check ((status = 'pending') = (closed_at is null))
);
create index approvals_org on public.approvals(organization_id, status, created_at desc);
create index approvals_group on public.approvals(group_id);
create index approvals_requester on public.approvals(requester_id);

create table public.approval_steps (
  approval_id uuid not null references public.approvals(id) on delete cascade,
  position smallint not null check (position between 1 and 5),
  approver_id uuid references public.profiles(id) on delete set null,
  decision text check (decision in ('approved','rejected')),
  note text not null default '' check (length(note) <= 1000),
  decided_at timestamptz,
  primary key (approval_id, position),
  unique (approval_id, approver_id),
  check ((decision is null) = (decided_at is null)),
  check (decision is distinct from 'rejected' or length(note) > 0)
);
create index approval_steps_approver on public.approval_steps(approver_id);

create table public.announcements (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id),
  group_id uuid references public.groups(id),                             -- null = seluruh organisasi
  author_id uuid references public.profiles(id) on delete set null,
  title text not null check (length(title) between 1 and 120),
  body text not null check (length(body) between 1 and 2000),
  created_at timestamptz not null default now()
);
create index announcements_org on public.announcements(organization_id, created_at desc);
create index announcements_group on public.announcements(group_id) where group_id is not null;
create index announcements_author on public.announcements(author_id);

create table public.announcement_reads (
  announcement_id uuid not null references public.announcements(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  read_at timestamptz not null default now(),
  primary key (announcement_id, user_id)
);
create index announcement_reads_user on public.announcement_reads(user_id);
```

- Enam tabel baru: RLS aktif, `revoke all` dari `PUBLIC, anon, authenticated`, **tanpa policy**, tidak masuk publikasi Realtime. Sama dengan `organizations`.
- `status = 'lapsed'`: pengajuan dibatalkan sistem karena pengaju, atau penyetuju yang belum memutuskan, keluar dari organisasi (bagian 4.4).
- Tidak ada lampiran. Pengajuan memakai tautan HTTPS (maks 5) dengan `private.valid_links`, sama seperti submission.
- Hapus akun: kolom pelaku di-`SET NULL`; baris kehadiran dan tanda baca milik akun itu ikut terhapus. Tidak ada FK baru yang menghalangi `deleteAccount`.
- Grup yang kosong setelah hapus akun tetap menyimpan rapat dan pengumumannya. Tidak ada yang bisa melihatnya; tidak dibersihkan.
- Aksi rapat dan `setProjectLead` menulis `activity_events` (dipakai juga untuk batas 30 tulisan rapat per jam per grup). Aksi persetujuan dan pengumuman tidak.
- Nama di daftar tingkat organisasi (`requesterName`, `steps[].name`, `authorName`): id kosong dan nama "Anggota terhapus" untuk akun yang dihapus; "Anggota" untuk orang yang diblokir pelihat.

## 3. Hak akses

| Aksi | Siapa | Syarat |
|---|---|---|
| Membuat kepanitiaan | Ketua, BPH | Paket aktif |
| Menunjuk koordinator sie | Coordinator grup | Grup milik organisasi; paket aktif; proyek aktif |
| Mencabut koordinator sie | Coordinator grup | – |
| Membuat/mengubah/mengalihkan/membuka kembali tugas | Coordinator grup, **atau koordinator sie di proyeknya** | Aturan tugas yang ada |
| Menjadwalkan, mengubah, membatalkan rapat | Coordinator grup | Menjadwalkan butuh paket aktif |
| Mengisi notulen dan daftar hadir | Coordinator grup atau notulis rapat itu | Rapat tidak dibatalkan dan waktunya sudah lewat |
| Melihat rapat, notulen, daftar hadir | Anggota grup | – |
| Mengajukan persetujuan | Anggota grup milik organisasi | Paket aktif; maks 5 pengajuan terbuka per orang |
| Memutuskan satu jenjang | Penyetuju pada jenjang yang berjalan, **dan saat itu masih** pemegang jabatan atau coordinator grup asal | Pengajuan `pending` |
| Membatalkan pengajuan | Pengaju | Pengajuan `pending` |
| Melihat pengajuan | Pengaju; pemegang jabatan; coordinator grup asal | – |
| Pengumuman seluruh organisasi | Ketua, BPH | Paket aktif |
| Pengumuman grup | Coordinator grup | Paket aktif |
| Menarik pengumuman | Penulisnya; Ketua untuk pengumuman seluruh organisasi | – |
| Menandai "Sudah baca" | Penerima pengumuman | – |

- Penyetuju selalu pemegang jabatan atau coordinator grup asal, jadi daftar "yang boleh melihat" sudah mencakup mereka selama masih berhak.
- **Pengungkapan baru yang disengaja:** pengurus (Ketua/BPH/Pembina) melihat semua pengajuan di organisasinya, termasuk nama pengaju, juga saat paket sudah berakhir. Di Tahap 1 nama staf hanya sampai ke pengurus lewat Dashboard.
- BPH tetap tidak punya hak tulis di divisi orang lain. Semua pemeriksaan di RPC.

## 4. Kontrak RPC

### 4.1 Aksi baru di `grouply_mutate`

Ditangani fungsi baru `private.mutate_orgwork`. `private.mutate` didefinisikan ulang (disalin persis dari `20261112071535`) untuk dua hal: menambah daftar aksi yang diteruskan, dan menyamakan penanganan kesalahan format dengan `grouply_billing` (tanggal, angka, dan rentang yang tidak valid → `invalid_input`, bukan error mentah Postgres).

| Aksi | Payload | Hasil | Aturan / error |
|---|---|---|---|
| `createDivision` *(diperluas, di `mutate_org`)* | + `committee` (bool, default false) | `{id}` | Batas dihitung terpisah: 30 divisi berpenghuni **dan** 30 kepanitiaan berpenghuni. Pembuat menjadi coordinator; ketua pelaksana masuk lewat undangan lalu menerima `transferCoordinator`, sama seperti Kadiv |
| `setProjectLead` | `projectID`, `userID` (null = cabut) | `{}` | Coordinator. Menunjuk: grup milik organisasi, paket aktif (`plan_inactive`), proyek aktif (`project_read_only`), target anggota grup (`invalid_input`). Mencabut selalu boleh |
| `createMeeting` | `groupID`, `title`, `startsAt`, `place?`, `agenda?`, `noteTakerID?` | `{id}` | Coordinator; grup milik organisasi; paket aktif; notulis harus anggota grup. `startsAt` boleh lampau (untuk mencatat rapat yang sudah terjadi) |
| `updateMeeting` | `id`, `expectedVersion`, `title`, `startsAt`, `place`, `agenda`, `noteTakerID` | `{}` | Coordinator; status `scheduled`, selain itu `meeting_closed`; versi berbeda → `stale_version` |
| `cancelMeeting` | `id`, `expectedVersion` | `{}` | Coordinator; status `scheduled`, selain itu `meeting_closed` |
| `recordMeeting` | `id`, `expectedVersion`, `minutes`, `attendance: [{userID, status}]` | `{}` | Coordinator atau notulis; status bukan `cancelled` (`meeting_closed`); `starts_at <= now()` (`invalid_input`); versi berbeda → `stale_version`. Status menjadi `done`. Daftar hadir diganti **hanya untuk anggota grup saat ini**; catatan orang yang sudah keluar grup dibiarkan. `userID` baru harus anggota grup; `status` ∈ `hadir`/`izin` |
| `requestApproval` | `groupID`, `title`, `note`, `amount?`, `links?`, `approverIDs` (1–5) | `{id}` | Anggota grup; grup milik organisasi; paket aktif. Penyetuju tidak boleh ganda, bukan pengaju, dan masing-masing coordinator grup itu atau pemegang jabatan → `invalid_input`. Maks 5 pengajuan `pending` per pengaju → `rate_limited` |
| `decideApproval` | `id`, `approve` (bool), `note` (wajib jika menolak) | `{}` | Status bukan `pending` → `approval_closed`. Pelaku harus penyetuju pada jenjang pertama yang belum diputuskan **dan** masih berhak (keputusan inti 4) → `forbidden`. Menolak → `rejected`; menyetujui jenjang terakhir → `approved` |
| `cancelApproval` | `id` | `{}` | Hanya pengaju; status `pending`, selain itu `approval_closed` |
| `postAnnouncement` | `organizationID`, `groupID?`, `title`, `body` | `{id}` | Paket aktif. Tanpa `groupID`: Ketua/BPH, maks 5 per jam per organisasi. Dengan `groupID`: coordinator grup itu, maks 10 per jam per grup. Lewat batas → `rate_limited` |
| `deleteAnnouncement` | `id` | `{}` | Lihat tabel hak akses |
| `markAnnouncementRead` | `id` | `{}` | Penerima; idempoten |

- Semua aksi tulis rapat dibatasi 30 per jam per grup → `rate_limited`.
- Kode error baru: `approval_closed`, `meeting_closed`.

### 4.2 Perubahan pada `private.mutate_workflow`

Disalin persis dari `20261112071535`, dengan dua blok berubah:

- **Pemeriksaan coordinator** untuk `createTask`, `updateTask`, `reassignTask`, `reopenTask`: lolos juga jika `actor = p.lead_id`. Baris proyek sudah dikunci dan keanggotaan pelaku sudah diperiksa sebelum titik ini, jadi koordinator sie yang baru dikeluarkan mendapat `forbidden`.
- **`createTask`** menerima `meetingID` opsional. Rapatnya harus berada di grup yang sama dan tidak dibatalkan → `invalid_input`.

### 4.3 Sinyal perubahan ke client

Client memuat ulang snapshot setiap ada `INSERT` di `chat_messages` atau perubahan baris `user_sync_state` miliknya. Maka:

| Perubahan | Sinyal |
|---|---|
| Rapat dijadwalkan, dibatalkan, waktu/tempatnya diubah, atau notulennya diisi pertama kali; koordinator sie ditunjuk | Pesan aktivitas di chat grup, misalnya "Menjadwalkan rapat · Rapat mingguan" |
| Perubahan rapat lainnya (agenda, notulis, revisi notulen) | Tidak ada. Terlihat saat rapat dibuka atau snapshot berikutnya |
| Pengajuan dibuat/diputuskan/dibatalkan | `user_sync_state` pengaju, semua penyetuju, pemegang jabatan, dan coordinator grup asal, dalam satu batch urut `user_id` |
| Pengumuman dibuat/ditarik | Seluruh organisasi: `org_touch`. Per grup: anggota grup, satu batch urut `user_id` |
| `markAnnouncementRead` | Hanya pelakunya. Jumlah baca di layar penulis segar saat snapshot berikutnya |
| Kepanitiaan dibuat | `org_touch` (sudah ada di `createDivision`) |

Pesan aktivitas ikut dihitung sebagai pesan belum dibaca di tab Chat, sama seperti pesan aktivitas tugas yang sudah ada. Karena itu hanya perubahan rapat yang penting bagi anggota yang menulis pesan.

### 4.4 Trigger `group_members_org_guard` (diperluas)

Tetap `AFTER DELETE` pada `group_members`, tetap berjalan sebelum `membership_sync`. Tambahan untuk grup milik organisasi:

1. Sebelum memeriksa organisasi: kosongkan `projects.lead_id` dan `meetings.note_taker_id` milik orang itu **di grup yang ditinggalkan**.
2. Setelah kunci organisasi diambil dan orang itu terbukti tidak lagi anggota organisasi: semua pengajuan `pending` di organisasi itu yang ia ajukan, atau yang ia masih harus putuskan, menjadi `lapsed`.

- `lapsed` tidak menaikkan `user_sync_state` dari dalam trigger. Pihak lain melihat statusnya saat snapshot berikutnya; client juga memuat ulang saat menerima `approval_closed` (bagian 5.1).
- Pengaju yang keluar dari grup asal tetapi masih anggota organisasi: pengajuannya tetap berjalan dan ia tetap bisa melihat dan membatalkannya.
- Aturan jabatan Tahap 1 (`ketua_transfer_required`, `org_role_holder`) tidak berubah. Keanggotaan kepanitiaan dihitung sebagai keanggotaan organisasi, jadi pemegang jabatan boleh hanya menjadi anggota kepanitiaan. Kalimat di `CLAUDE.md` diubah menjadi "divisi atau kepanitiaan"; penutupan kepanitiaan di ORG-13 harus memperhitungkan ini.

### 4.5 Snapshot (`grouply_snapshot`)

`private.snapshot` didefinisikan ulang; semua perubahan aditif dan client lama mengabaikannya.

- `groups[]` + `isCommittee`; `projects[]` + `leadID` (`''` jika kosong); `organizations[].divisions[]` + `isCommittee`.
- Key baru `meetings[]`, untuk grup tempat pengguna menjadi anggota: semua rapat dengan `starts_at` dalam 30 hari terakhir atau di masa depan, ditambah 100 rapat lebih lama yang terbaru.

```json
{ "id": "…", "groupID": "…", "title": "Rapat mingguan", "startsAt": "…", "place": "Sekre",
  "status": "scheduled", "version": 1, "createdBy": "…", "noteTakerID": "…",
  "hasMinutes": false, "present": 0, "excused": 0, "myStatus": "", "taskIDs": [] }
```

- `organizations[]` mendapat dua key:

```json
"approvals": [{ "id": "…", "groupID": "…", "groupName": "Humas", "title": "Dana publikasi",
  "note": "…", "amount": 750000, "links": [], "status": "pending", "createdAt": "…", "closedAt": null,
  "requesterID": "…", "requesterName": "…",
  "steps": [{ "position": 1, "approverID": "…", "name": "…", "eligible": true,
              "decision": null, "note": "", "decidedAt": null }] }],
"announcements": [{ "id": "…", "groupID": "", "title": "…", "body": "…", "createdAt": "…",
  "authorID": "…", "authorName": "…", "read": false,
  "readCount": 41, "audienceCount": 87, "unreadIDs": ["…"] }]
```

- `approvals`: hanya yang boleh dilihat pengguna (bagian 3). Maks 100 yang `pending` (terlama dulu) ditambah 30 yang terakhir ditutup. `steps[].eligible` = penyetuju itu masih berhak memutuskan.
- `announcements`: 30 terakhir yang ditujukan ke pengguna (seluruh organisasi, atau grup tempat ia anggota).
  - `readCount` dan `audienceCount` dihitung dari penerima **saat ini**, dan hanya diisi untuk penulis dan pengurus; selain itu 0.
  - `unreadIDs` diisi untuk penulis, pengurus, dan coordinator grup mana pun, dan selalu dibatasi ke orang yang satu grup dengan pengguna.
- Nama (`requesterName`, `steps[].name`, `authorName`) dikirim langsung seperti `roles[].name` di Tahap 1, karena `users` hanya berisi orang yang satu grup. Orang yang diblokir pengguna tampil sebagai "Anggota"; isi pengumuman dan pengajuannya tetap tampil, karena itu konten resmi organisasi.
- Riwayat di luar batas 30/100 belum bisa dibuka. RPC riwayat berhalaman dibuat saat organisasi pilot benar-benar mencapai batas itu.

### 4.6 Detail rapat: `public.grouply_meeting(meeting_id uuid)`

Hanya anggota grup rapat itu → selain itu `forbidden`. Tanpa syarat paket aktif.

```json
{ "id": "…", "version": 3, "agenda": "…", "minutes": "…",
  "attendance": [{ "userID": "…", "status": "hadir" }] }
```

### 4.7 Dashboard

`grouply_org_overview`: `divisions[]` mendapat `isCommittee`. Selain itu tidak berubah. Pengajuan yang tertahan dihitung client dari `organizations[].approvals`, karena pengurus sudah menerima pengajuan `pending`.

### 4.8 Urutan kunci

Tetap satu urutan: **profil → grup (urut `id`) → organisasi (urut `id`, `FOR NO KEY UPDATE`) → `user_sync_state` (urut `user_id`)**.

| Jalur | Urutan |
|---|---|
| Rapat, `setProjectLead`, pengumuman grup | profil → grup (`FOR UPDATE`) → [pengumuman: sync] |
| Pengumuman organisasi | profil → organisasi → sync |
| `requestApproval`, `decideApproval`, `cancelApproval` | profil → grup asal → organisasi → sync |
| Keluar/dikeluarkan/hapus akun | tidak berubah; `lapsed` terjadi di bawah kunci organisasi yang sudah diambil trigger |

- Semua aksi persetujuan dalam satu organisasi berurutan di kunci organisasi, jadi baris `approvals` tidak dikunci sendiri. (Penyederhanaan: kunci per pengajuan baru diperlukan kalau throughput jadi masalah.)
- `decideApproval` mengunci grup asal supaya pemeriksaan "masih coordinator" tidak balapan dengan `transferCoordinator`, yang hanya mengunci grup.
- Aksi baru masing-masing mengambil satu batch kunci sync. Jalur lama (`createDivision`, `deleteAccount`) sudah mengambil lebih dari satu batch, jadi deadlock lintas organisasi pada baris sync tetap mungkin secara teori seperti sekarang; Postgres membatalkan salah satu transaksi dan pengguna mengulang.

## 5. Flutter

### 5.1 Inti

- **`backend.dart`**: tambah `meetingDetail(String id)` (`rpc('grouply_meeting')`), termasuk di `DemoBackend` dan `FakeBackend`.
- **`store.dart`**:
  - List `meetings`; decode `approvals`/`announcements` di dalam organisasi. Key yang tidak ada dianggap kosong, supaya build baru tetap jalan di database lama.
  - Helper: `isCommittee(group)`, `canManageTasks(project)` (coordinator atau `leadID`), `pendingForMe(orgID)`, `unreadAnnouncements(orgID)`, `meetingDetail(id)` (tanpa cache, pola `orgOverview`).
  - `canManageTasks` menggantikan pemeriksaan coordinator di enam tempat pada `task_screens.dart` dan `project_screens.dart`.
  - `serverMessage`: `approval_closed`, `meeting_closed`.
  - Setelah mutasi gagal dengan `approval_closed`, `meeting_closed`, atau `stale_version`, store menjadwalkan muat ulang, supaya kartu yang sudah basi hilang.
- **`reminders.dart`**: rapat `scheduled` di grup sendiri masuk rencana notifikasi ("Rapat besok", "Rapat 1 jam lagi"). Field `taskID` pada `Reminder` diganti id umum. Batas 60 notifikasi terdekat tetap.
- **`DemoBackend`**: aturan server (lapse, pencabutan koordinator sie, penyaringan per pelihat) harus ditiru di Dart, dan list baru harus masuk daftar backup/restore di `mutate()`.

### 5.2 Layar (file baru `features/org_work_screens.dart`, `part of workspace_screens.dart`)

| Layar | Isi |
|---|---|
| **Organisasi** | Daftar dipisah: Divisi dan Kepanitiaan. Tombol "Tambah kepanitiaan" (Ketua/BPH). Baris baru **Persetujuan** (badge = menunggu keputusanmu) dan **Pengumuman** (badge = belum dibaca). Kartu organisasi di tab Grup menampilkan badge gabungan |
| **Grup (divisi/kepanitiaan)** | Bagian baru **Rapat** (berikutnya + "Lihat semua") dan tombol "Ajukan persetujuan". Di kepanitiaan, judul bagian Proyek menjadi "Sie" |
| **Proyek/Sie** | Baris "Koordinator sie" dengan tombol tunjuk/cabut (coordinator). Tombol "Buat tugas" juga aktif untuk koordinator sie |
| **Daftar rapat** | Akan datang dan selesai, per grup |
| **Rapat** | Waktu, tempat, agenda; notulen; daftar hadir (jumlah + nama anggota grup); "Tugas dari rapat ini" dengan statusnya; tombol "Jadikan tugas" |
| **Jadwalkan rapat** (sheet) | Judul, tanggal dan jam, tempat/tautan, agenda, notulis |
| **Isi notulen** | Teks notulen + pilihan hadir/izin per anggota |
| **Daftar persetujuan** | Tab: Menunggu saya, Pengajuan saya, Semua (pengurus). Tiap kartu menunjukkan "Tertahan di \<nama\> · N hari", atau "Penyetuju tidak lagi menjabat" |
| **Pengajuan** | Uraian, nominal, tautan, garis jenjang dengan keputusan dan catatan; tombol Setujui/Tolak untuk penyetuju aktif; Batalkan untuk pengaju |
| **Ajukan persetujuan** (sheet) | Judul, uraian, nominal (opsional), tautan, susunan penyetuju berurutan |
| **Pengumuman** | Daftar; detail dengan tombol "Sudah baca"; penulis dan pengurus melihat "41 dari 87 sudah baca"; nama yang belum baca (yang segrup) |

- "Jadikan tugas" hanya tampil untuk orang yang coordinator atau koordinator sie di minimal satu proyek aktif grup itu. Ia memilih proyek/sie tujuan, lalu sheet tugas yang ada terbuka. `_showTaskSheet` mendapat dua parameter opsional: judul awal dan `meetingID`. Notulis yang bukan keduanya tidak melihat tombol ini.
- Layar rapat memuat ulang detailnya saat `version` di snapshot berubah.
- Pola gating mengikuti Tahap 1: tombol khusus jabatan disembunyikan; tombol yang terkunci paket tetap tampil dengan ikon gembok dan toast.
- Tab Beranda, Chat, dan Tugas Saya tidak berubah.

## 6. Pengujian

**SQL** (`supabase/tests/organization_work.sql`, pola yang sama, rollback):

1. Kepanitiaan: dibuat Ketua/BPH; batas dihitung terpisah dari divisi; anggota lintas divisi tidak memakai kursi baru.
2. Koordinator sie: boleh empat aksi tugas di proyeknya; ditolak di proyek lain, untuk aksi proyek, dan setelah dicabut atau keluar grup.
3. Rapat: hanya coordinator yang menjadwalkan; notulis boleh mengisi; rapat yang belum mulai tidak bisa dinotulenkan; versi basi → `stale_version`; kehadiran orang yang sudah keluar grup tetap ada setelah notulen direvisi; non-anggota ditolak membuka detail; `createTask` dengan `meetingID` dari grup lain ditolak.
4. Persetujuan: rantai berjalan berurutan; penyetuju jenjang 2 ditolak sebelum gilirannya; tolak tanpa catatan ditolak; keputusan pada pengajuan tertutup → `approval_closed`; staf lain tidak melihatnya di snapshot; penyetuju tidak sah atau ganda → `invalid_input`; pengajuan terbuka ke-6 → `rate_limited`.
5. Hak yang hilang: BPH yang jabatannya dicabut, dan Kadiv yang sudah menyerahkan coordinator, tidak bisa memutuskan dan tidak lagi menerima pengajuan itu di snapshot.
6. `lapsed`: penyetuju keluar dari grup terakhirnya; pengaju menghapus akun; penyetuju yang hanya pindah divisi tidak memicu.
7. Pengumuman: hak tulis dan hak tarik per lingkup; hitungan baca hanya dari penerima saat ini; `unreadIDs` tidak memuat orang di luar grup pelihat; Kadiv mendapat `unreadIDs` stafnya untuk pengumuman seluruh organisasi.
8. Paket tidak aktif: semua aksi "membuat" → `plan_inactive`; memutuskan, mengisi notulen, dan menandai baca tetap bisa.
9. Format tidak valid (tanggal, nominal di luar rentang) → `invalid_input`.
10. Akses langsung ke enam tabel baru dan `mutate_orgwork` oleh `authenticated`, serta `grouply_meeting` oleh `anon`, ditolak.
11. Regresi: `workflow` 40, `milestone_e` 54, `organization` 66 tetap lulus tanpa diubah.

**Konkurensi** (ditambahkan ke `billing_local.py check-locks`; fixture baru dihapus sebelum grup dan organisasinya):

- Kadiv mengeluarkan pengaju dari grup terakhirnya serentak dengan penyetuju memutuskan → tepat satu urutan yang konsisten: diputuskan lalu `lapsed` tidak terjadi, atau `lapsed` lalu `approval_closed`.
- `deleteAccount` pengaju serentak dengan `decideApproval` → tanpa deadlock.
- `transferCoordinator` serentak dengan `decideApproval` oleh coordinator lama → setelah serah terima, `forbidden`.
- Koordinator sie `createTask` serentak dengan dirinya dikeluarkan → setelah dikeluarkan, `forbidden`.

**Flutter**: decode dan toleransi key hilang; peta error; widget test untuk tiap layar dengan `DemoBackend`; satu alur integrasi localhost (kepanitiaan → sie + koordinator → rapat → tugas dari rapat → pengajuan dua jenjang → pengumuman dibaca).

## 7. Urutan kerja

1. **Backend**: migration + suite SQL + uji kunci.
2. **Flutter**: store/backend/`DemoBackend`, lalu layar per fitur dengan urutan ORG-07 → ORG-09 → ORG-08 → ORG-10.

   Keduanya bisa paralel setelah kontrak bagian 4 disepakati.
3. **Integrasi**: tes localhost, lalu catat perubahan scope di `docs/PRD.md` dan `CLAUDE.md`, dan bukti di `docs/IMPLEMENTATION_STATUS.md`.

Bagian paling berisiko: definisi ulang `private.mutate`, `mutate_workflow`, dan `snapshot`, serta perluasan trigger. Bagian Flutter kali ini lebih besar dari backend, termasuk meniru aturan server di `DemoBackend`.

Desain ini sudah ditinjau secara independen terhadap kode migration dan Flutter. Temuan soal hak penyetuju yang hilang, daftar hadir orang yang keluar, aturan pengumuman yang saling bertentangan, ukuran snapshot, pengajuan `lapsed` yang basi di layar, dan pesan aktivitas rapat sudah dimasukkan di atas.

## 8. Keputusan (disetujui 12 November 2026, semua sesuai rekomendasi)

1. Push dari server (ORG-11) ditunda sampai ada Firebase/APNs; diganti notifikasi lokal rapat dan badge (rekomendasi). Alternatif: kamu siapkan project Firebase dulu.
2. Koordinator sie boleh mengelola tugas di proyeknya (rekomendasi), atau tetap hanya ketua pelaksana/Kadiv.
3. Susunan penyetuju dipilih pengaju tiap kali mengajukan (rekomendasi), atau rantai baku yang diatur Ketua per organisasi.
4. Siapa pun anggota boleh mengajukan (rekomendasi), atau hanya Kadiv/ketua pelaksana.
5. Pembina boleh menjadi penyetuju (rekomendasi, karena proposal biasanya butuh persetujuan pembina), atau tetap hanya melihat seperti tertulis di PRD.
6. Pengurus melihat semua pengajuan di organisasi beserta nama pengajunya (rekomendasi), atau hanya pengajuan yang rantainya memuat dirinya.
7. Penyetuju atau pengaju keluar organisasi → pengajuan otomatis batal dengan keterangan (rekomendasi), atau orang itu tidak boleh keluar/hapus akun sebelum pengajuannya selesai.
8. Rapat hanya per divisi/kepanitiaan, tanpa rapat pleno dan tanpa rekap kehadiran per orang (rekomendasi).
9. Nama yang belum baca pengumuman hanya terlihat untuk orang segrup; pengurus melihat jumlah seluruh organisasi (rekomendasi), atau pengurus melihat semua nama.

## 9. Batas yang diketahui dan di luar Tahap 2

- **Belum ada tombol "Laporkan"** untuk pengumuman, notulen, dan pengajuan. Pelaporan yang ada hanya untuk pesan chat. Sebelum rilis ke store, konten buatan pengguna ini perlu jalur lapor. Untuk pilot, penulisnya terbatas pada pengurus dan coordinator.
- **Notifikasi lokal bukan pengganti push.** Jadwalnya hanya diperbarui saat aplikasi dibuka di perangkat itu. Rapat yang dibatalkan atau dipindah saat aplikasi tertutup tetap berbunyi pada jam lama, dan rapat baru tidak memberi tahu sampai aplikasi dibuka. Pengajuan dan pengumuman baru sama sekali tidak memberi tahu saat aplikasi tertutup.
- Kepanitiaan yang sudah selesai belum bisa ditutup; ia tetap tampil dan dihitung di batas 30. Penutupan masuk bersama arsip periode (ORG-13).
- Anggota kepanitiaan masuk lewat kode undangan. "Tambah langsung dari daftar anggota organisasi" tidak dibuat, karena nama anggota divisi lain memang disembunyikan.
- Pengajuan yang penyetujunya kehilangan jabatan tidak pindah otomatis ke penggantinya; pengaju harus mengajukan ulang.
- Di luar tahap ini: push server, rapat pleno, RSVP mandiri, rantai persetujuan baku, lampiran file, riwayat berhalaman, template, arsip periode, rekap LPJ.
