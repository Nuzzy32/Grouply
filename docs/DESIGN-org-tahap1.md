# Desain Teknis — Organization Plan Tahap 1 (Fondasi)

Status: **disetujui 12 November 2026.** Backend (`supabase/migrations/20261112071535_organizations.sql`) dan client Flutter sudah diimplementasikan dan teruji di localhost, termasuk integrasi keduanya. Bukti ada di `docs/IMPLEMENTATION_STATUS.md`. Acuan produk: [PRD-organization-plan.md](PRD-organization-plan.md) (ORG-01 s.d. ORG-06). Client: Flutter saja. Backend: Supabase lokal yang sama (`supabase/migrations`).

## 1. Keputusan inti

1. **Divisi = grup yang sudah ada.** Tabel `groups` mendapat kolom `organization_id`. Proyek, tugas, review, chat, unread, undangan, dan Group Pulse langsung berfungsi untuk divisi tanpa perubahan.
2. **Kadiv = coordinator grup.** Tidak ada tabel jabatan baru untuk Kadiv dan Staf. Jabatan tingkat organisasi hanya tiga: `ketua`, `bph`, `pembina`.
3. **Pemegang jabatan wajib anggota minimal satu divisi.** Karena itu, membuat organisasi otomatis membuat divisi pertama ("BPH Inti"). Dengan aturan ini tidak perlu undangan tingkat organisasi. Aturan ini dijaga trigger di database (bagian 4.3), bukan hanya oleh RPC.
4. **BPH tidak mendapat hak tulis di divisi orang lain pada Tahap 1.** BPH memantau lewat Dashboard. Untuk mengubah sesuatu, BPH lewat Kadiv atau ikut menjadi anggota divisi tersebut. Ini membuat aturan keamanan yang sudah teruji tetap utuh.
5. **Dashboard dari RPC ringkasan terpisah**, bukan dari snapshot. Snapshot tetap hanya berisi divisi tempat pengguna menjadi anggota, jadi ukurannya tidak membengkak untuk organisasi 150 orang.
6. **Kursi dihitung per orang unik di seluruh organisasi.** Orang yang ikut dua divisi tetap memakai satu kursi.
7. **Paket berakhir = kembali ke batas gratis, bukan read-only.** Data dan pekerjaan yang sedang berjalan tetap bisa dipakai. Yang terkunci: Dashboard, divisi baru, undangan multi-pakai, dan anggota baru di atas 8 per divisi. *(Ini mengubah kalimat ORG-06 di PRD. Alasannya: membekukan tugas di tengah proker merugikan anggota yang tidak memutuskan soal pembayaran.)*
8. **Aktivasi paket manual oleh operator** lewat RPC khusus `service_role` dan skrip lokal. Tidak ada payment gateway.

## 2. Model data (migration baru)

```sql
create table public.organizations (
  id uuid primary key default gen_random_uuid(),
  name text not null check (length(name) between 1 and 80),
  description text not null default '' check (length(description) <= 1000),
  period_label text not null default '' check (length(period_label) <= 40),  -- mis. "2026/2027"
  seat_limit integer not null default 0 check (seat_limit between 0 and 500),
  plan_expires_at timestamptz,            -- null = belum pernah aktif
  created_at timestamptz not null default now()
);

create table public.organization_roles (
  organization_id uuid not null references public.organizations(id),
  user_id uuid not null references public.profiles(id) on delete cascade,
  role text not null check (role in ('ketua','bph','pembina')),
  primary key (organization_id, user_id)
);
create unique index organization_one_ketua on public.organization_roles(organization_id) where role = 'ketua';
create index organization_roles_user on public.organization_roles(user_id);

alter table public.groups add column organization_id uuid references public.organizations(id);
create index groups_organization on public.groups(organization_id) where organization_id is not null;

-- Undangan multi-pakai untuk oprec. Batas per jenis grup diperiksa di RPC.
alter table private.invitations drop constraint invitations_max_uses_check,
  add constraint invitations_max_uses_check check (max_uses between 1 and 200);
```

- Kedua tabel baru: RLS aktif, `revoke all` dari `anon` dan `authenticated`, **tanpa policy**. Akses hanya lewat fungsi `security definer`, sama seperti `private.invitations`. Tidak masuk publikasi Realtime.
- Semua fungsi baru di `private` (helper, `mutate_org`, fungsi trigger): `security definer`, `search_path = ''`, dan `revoke execute … from PUBLIC, anon, authenticated, service_role`. Fungsi `public` baru juga di-`revoke` dari `PUBLIC, anon` secara eksplisit, karena Supabase memberi `EXECUTE` ke `anon` secara default. Polanya sama dengan `grouply_mutate` di `20261016130113`.
- Penguncian baris organisasi selalu `FOR NO KEY UPDATE`, supaya pengecekan FK (`KEY SHARE`) dari tabel lain tidak ikut tertahan.
- Nama parameter fungsi tidak boleh sama dengan nama kolom (misalnya `organization_id`), karena di plpgsql akan menjadi referensi ambigu. Gunakan `org_id`.
- Helper:
  - `org_role(oid)`: jabatan `auth.uid()` di organisasi ini, atau null.
  - `org_member(oid)`: apakah `auth.uid()` anggota salah satu divisinya.
  - `org_active(oid)`: `plan_expires_at > now()`.
  - `org_seats(oid)`: jumlah orang unik di semua divisinya.
- **Divisi kosong.** `deleteAccount` milik anggota tunggal sebuah divisi meninggalkan divisi dengan 0 anggota, `coordinator_id` NULL, dan undangan yang sudah dicabut. Divisi seperti ini tidak dihitung dalam batas 30 divisi dan tidak ditampilkan di daftar maupun Dashboard.

## 3. Hak akses

| Aksi | Ketua | BPH | Pembina | Kadiv | Staf |
|---|---|---|---|---|---|
| Melihat organisasi: nama, periode, daftar divisi + jumlah anggota, status paket, pengurus | ✓ | ✓ | ✓ | ✓ | ✓ |
| Dashboard (paket aktif) | ✓ | ✓ | ✓ | – | – |
| Mengubah info organisasi | ✓ | – | – | – | – |
| Membuat divisi (paket aktif) | ✓ | ✓ | – | – | – |
| Mengatur jabatan BPH/Pembina | ✓ | – | – | – | – |
| Menyerahkan jabatan Ketua | ✓ | – | – | – | – |
| Mengelola isi divisi (undangan, anggota, proyek, tugas) | aturan coordinator yang sudah ada, hanya di divisi yang ia pimpin |
| Undangan multi-pakai (paket aktif) | coordinator divisi organisasi |

Semua pemeriksaan dilakukan di RPC. Validasi di Flutter hanya untuk menyembunyikan tombol.

## 4. Kontrak RPC

### 4.1 Aksi baru di `grouply_mutate`

Ditangani di fungsi baru `private.mutate_org`. Untuk memanggilnya, **`private.mutate` (pembungkus luar) juga harus didefinisikan ulang**, disalin dari versi terbaru di `20261017060000` (yang mengunci baris profil dengan `FOR NO KEY UPDATE`), bukan dari `050000`. Payload camelCase seperti aksi yang sudah ada.

Setiap aksi di bawah mengunci organisasi **terlebih dahulu**, lalu memeriksa keanggotaan dan jabatan di statement terpisah sesudahnya. Dengan begitu, hasil pemeriksaan tidak bisa basi karena ada orang yang keluar divisi di saat bersamaan.

| Aksi | Payload | Hasil | Aturan / error |
|---|---|---|---|
| `createOrganization` | `name`, `description?`, `periodLabel?`, `divisionName?` (default "BPH Inti") | `{id, groupID}` | Pembuat menjadi `ketua` + coordinator divisi pertama. Maks 3 organisasi tempat ia menjadi ketua (aktif atau belum) → `rate_limited` |
| `updateOrganization` | `id`, `name`, `description`, `periodLabel` | `{}` | Hanya ketua → `forbidden` |
| `createDivision` | `organizationID`, `name`, `description?` | `{id}` | Ketua/BPH, paket aktif → `plan_inactive`; maks 30 divisi berpenghuni → `invalid_input`. Pembuat menjadi coordinator + anggota, lalu bisa `transferCoordinator` ke Kadiv |
| `setOrgRole` | `organizationID`, `userID`, `role` (`bph`/`pembina`/null) | `{}` | Hanya ketua. `role = 'ketua'` ditolak. Target harus anggota organisasi dan bukan diri sendiri → `invalid_input` |
| `transferKetua` | `organizationID`, `userID` | `{}` | Hanya ketua; target anggota organisasi, bukan diri sendiri, dan belum menjadi ketua di 3 organisasi → `invalid_input`/`rate_limited`. Turunkan ketua lama ke `bph` **dulu**, baru angkat target, karena indeks unik satu-ketua tidak bisa ditunda |

### 4.2 Perubahan pada aksi yang sudah ada

Perubahan ini membutuhkan **definisi ulang `private.mutate_workflow`**. Isinya disalin dari migration `20261017040000`, dengan dua blok yang berubah:

- **`joinGroup`**: setelah mengunci grup, kunci organisasinya (`FOR NO KEY UPDATE`), lalu hitung ulang. Batas `>= 8` diganti dengan:
  - Grup biasa, atau divisi dari organisasi yang paketnya tidak aktif: tetap maks 8 → `group_full`. Undangan multi-pakai yang dibuat saat paket masih aktif diperlakukan sebagai sekali pakai (`used_count >= 1` → `invite_full`).
  - Divisi dari organisasi aktif: jika pengguna belum anggota organisasi dan `org_seats >= seat_limit` → `org_full`. Batas teknis 200 orang per divisi → `group_full`.
- **`generateInvite`**: menerima `maxUses` opsional.
  - Grup biasa: hanya boleh 1 atau tidak diisi (perilaku sekarang).
  - Divisi organisasi aktif: 1–200.
  - Selain itu → `invalid_input`.

### 4.3 Trigger keanggotaan

Trigger `AFTER DELETE` pada `group_members`, bernama **`group_members_org_guard`**. Nama ini sengaja dipilih supaya berurutan sebelum `membership_sync`, karena trigger sejenis dijalankan Postgres berdasarkan urutan alfabet nama. Akibatnya kunci organisasi diambil sebelum baris `user_sync_state` (lihat 4.8).

Langkahnya, jika grup yang ditinggalkan adalah divisi sebuah organisasi:

1. Kunci organisasi (`FOR NO KEY UPDATE`).
2. Hitung ulang apakah orang ini masih anggota divisi lain di organisasi yang sama. Jika masih → selesai.
3. Jika ini divisi terakhirnya dan ia memegang jabatan:

| Jabatan | Keluar sendiri / hapus akun | Dikeluarkan orang lain (`removeMember`) |
|---|---|---|
| **Ketua**, dan masih ada anggota lain di organisasi | `ketua_transfer_required` | `ketua_transfer_required` |
| **Ketua**, dan ia satu-satunya anggota organisasi | Jabatan dihapus; organisasi menjadi tidak berpenghuni. Akun tetap bisa dihapus (sesuai aturan hapus akun App Store) | Tidak mungkin terjadi |
| **BPH / Pembina** | Jabatan dihapus | `org_role_holder` (Ketua harus mencabut jabatannya dulu) |

"Keluar sendiri" dikenali dari `OLD.user_id = auth.uid()`. Ini mencakup `leaveGroup` dan `deleteAccount`.

Karena trigger mengunci organisasi sebelum menghitung, dua kasus balapan berikut tertutup:
- Dua Kadiv mengeluarkan orang yang sama dari dua divisi berbeda di saat bersamaan.
- `setOrgRole` berjalan bersamaan dengan target yang sedang keluar dari divisi terakhirnya.

### 4.4 Snapshot (`grouply_snapshot`)

Perubahan bersifat aditif. Client Swift lama tetap aman karena Codable mengabaikan field tambahan.

- `groups[]` mendapat field `organizationID` (string, `''` jika bukan divisi).
- Key baru `organizations[]` untuk organisasi tempat pengguna menjadi anggota:

```json
{ "id": "…", "name": "BEM FST", "description": "", "periodLabel": "2026/2027",
  "planActive": true, "planExpiresAt": "2027-08-31T…Z", "seatLimit": 120, "seatsUsed": 87,
  "myRole": "bph",
  "roles": [{"userID": "…", "name": "…", "role": "ketua"}],
  "divisions": [{"id": "…", "name": "Humas", "memberCount": 14, "isMember": false}] }
```

- **`roles[].name`** adalah pengungkapan yang disengaja dan terbatas: anggota organisasi boleh tahu siapa pengurusnya. Tanpa field ini, staf tidak bisa melihat nama BPH, karena `users` di snapshot hanya berisi orang yang satu grup dengan viewer. Jika viewer memblokir pengurus itu, namanya dikirim sebagai "Anggota".
- Nama Kadiv atau anggota divisi lain **tidak** ikut dikirim, dan `profile_visible` tidak diubah.
- Divisi tanpa anggota tidak dimasukkan ke `divisions`.

### 4.5 Dashboard: `public.grouply_org_overview(org_id uuid)`

- Hanya untuk ketua/BPH/pembina → selain itu `forbidden`. Paket harus aktif → `plan_inactive`.
- `coordinatorID` dikirim sebagai `''` jika kosong, sama seperti snapshot.
- Hanya proyek aktif (`status = 'active'` dan belum diarsipkan).
- Definisi penanda sama dengan Flutter:
  - **Terlambat**: `due_at < now()` dan belum `done`.
  - **Review tertahan**: `in_review` dan submission terakhir lebih dari 48 jam.
  - **Tanpa kabar**: `todo`/`in_progress`/`needs_revision` dan aktivitas terakhir (submission atau pesan di thread tugas) lebih dari 48 jam.

```json
{ "generatedAt": "…",
  "divisions": [{ "id": "…", "name": "Humas", "coordinatorID": "…", "memberCount": 14,
    "projects": [{ "id": "…", "title": "Seminar Nasional", "dueAt": "…",
      "total": 18, "done": 7, "inReview": 2, "overdue": 1, "idle": 3, "reviewPending": 1 }] }],
  "attention": [{ "taskID": "…", "title": "…", "divisionID": "…", "projectID": "…",
    "assigneeID": "…", "status": "in_progress", "dueAt": "…",
    "reason": "overdue|review_pending|idle", "hours": 52 }],
  "users": [{ "id": "…", "name": "…", "tint": "…" }] }
```

- `attention` diurutkan: terlambat (deadline terdekat) → review tertahan → tanpa kabar. Maks 50 baris.
- `users` hanya berisi orang yang dirujuk: Kadiv dan pelaksana di `attention`. Nama orang yang diblokir viewer ditampilkan sebagai "Anggota".
- Indeks yang dipakai sudah ada: `projects_group`, `tasks_project`, `messages_task`, `submissions(task_id, revision)`. Ditambah `groups_organization` yang baru.

### 4.6 Operator: `public.grouply_billing(action, payload)`

- Hanya untuk `service_role`, mengikuti pola `grouply_moderation`.
- Aksi: `activatePlan {organizationID, seatLimit, expiresAt}` dan `deactivatePlan {organizationID}`.
- Skrip lokal `scripts/billing_local.py` mengikuti pola `moderation_local.py`, tanpa mencetak kredensial.

### 4.7 Sinkronisasi

- `setOrgRole`, `transferKetua`, `createDivision`, `updateOrganization`, dan aktivasi paket menaikkan `user_sync_state` untuk semua anggota organisasi (`ORDER BY user_id`), agar snapshot mereka segar.
- Trigger `membership_sync` yang ada hanya menaikkan anggota grup yang berubah. Jadi `seatsUsed` dan `memberCount` di divisi lain bisa basi sampai snapshot berikutnya (aplikasi dibuka kembali atau ditarik ke bawah). Ini diterima, karena hanya angka tampilan; pemeriksaan kursi selalu dihitung ulang di server.
- Dashboard tidak realtime: dimuat ulang saat dibuka, ditarik ke bawah, atau aplikasi kembali ke depan.

### 4.8 Urutan kunci (mencegah deadlock)

Satu urutan untuk semua jalur:

**profil → grup (urut `id`) → organisasi (urut `id`, `FOR NO KEY UPDATE`) → baris `user_sync_state` (urut `user_id`)**

| Jalur | Urutan yang diambil |
|---|---|
| `joinGroup` | profil → grup → organisasi → sync (trigger `membership_sync` saat insert) |
| `leaveGroup` / `removeMember` | profil → grup → organisasi (`group_members_org_guard`) → sync (`membership_sync`) |
| `deleteAccount` | profil → semua grupnya (urut `id`, sudah ada) → **semua organisasinya (urut `id`, ditambahkan di `private.mutate`)** → sync |
| `setOrgRole`, `transferKetua`, `createDivision`, `updateOrganization`, `activatePlan` | profil → organisasi → sync |

- Dua orang yang masuk ke divisi berbeda saat kursi tinggal satu akan berurutan di kunci organisasi, jadi tidak bisa sama-sama lolos.
- Pada `deleteAccount`, kunci organisasi harus diambil secara eksplisit dan berurutan **sebelum** menghapus `group_members`. Kalau tidak, trigger akan mengunci organisasi dalam urutan pemindaian grup, yang bisa saling silang dengan transaksi lain.

## 5. Flutter

### 5.1 Inti (`flutter/lib/core/`)

- **`backend.dart`**:
  - Tambah `orgOverview(String id)` di `GrouplyBackend` dan implementasi Supabase (`rpc('grouply_org_overview')`).
  - `DemoBackend` di `test/demo_backend.dart` ikut ditambah untuk tes.
- **`store.dart`**:
  - Tambah list `organizations` dengan validasi seperti key lain. Jika key tidak ada, dianggap `[]`, supaya build baru tetap jalan di database yang belum dimigrasi.
  - Helper baru: `organization(id)`, `orgRole(orgID)`, `isDivision(group)`.
- **Peta kode error server → pesan Indonesia.** Saat ini semua error mutasi tampil sebagai "Perubahan belum terkonfirmasi…" (`store.dart`, blok `catch` di `mutate`). Tambah peta untuk:
  - kode baru: `org_full`, `plan_inactive`, `ketua_transfer_required`, `org_role_holder`;
  - kode lama yang sudah ada: `group_full`, `invite_full`, `invite_expired`, `active_assignment`, `coordinator_transfer_required`, `stale_version`, `project_read_only`, `already_reviewed`, `rate_limited`, `forbidden`, `invalid_input`, `unauthorized`.

  Peta hanya dipakai untuk error yang dilempar server (`PostgrestException` dengan kode `P0001`). Kegagalan jaringan tetap memakai pesan "belum terkonfirmasi", karena perubahannya mungkin sudah tersimpan.

### 5.2 Layar (file baru `features/org_screens.dart`, `part of workspace_screens.dart`)

| Layar | Isi |
|---|---|
| **Tab Grup** | Bagian "Organisasi" berisi kartu organisasi, di atas daftar grup. Divisi tidak diulang di daftar grup biasa. Menu "+" ditambah "Buat organisasi" |
| **Buat organisasi** (sheet) | Nama, periode, nama divisi pertama (default "BPH Inti") |
| **Organisasi** | Nama, periode, chip status paket, kursi terpakai/batas; tombol Dashboard (ketua/BPH/pembina); daftar divisi (yang diikuti bisa dibuka ke layar grup, yang lain hanya info); daftar pengurus; menu aksi sesuai jabatan |
| **Dashboard Organisasi** | Ringkasan (Proker aktif, Terlambat, Tanpa kabar, Review >48 jam); baris per divisi dengan progres; daftar "Perlu perhatian". Ketuk tugas → buka tugas jika viewer anggota divisinya, jika tidak tampil ringkasan saja |
| **Atur jabatan** (sheet) | Pilih anggota → BPH / Pembina / Hapus jabatan; serahkan Ketua dengan konfirmasi |
| **Banner paket tidak aktif** | "Paket belum aktif. Hubungi tim Grouply dengan kode organisasi ini." + tombol salin ID |
| **Layar grup (divisi)** | Chip nama organisasi yang menuju layar Organisasi. Sheet undangan untuk divisi organisasi aktif mendapat pilihan pemakaian: 1 / 10 / 30 / 100. **Penjaga 8 anggota di client** (`_maxMembers` di `groups_screens.dart`, yang menolak membuat undangan saat grup berisi 8 orang) dilewati untuk divisi organisasi aktif; server tetap yang menentukan batas |

Tab Chat dan Tugas Saya tidak berubah: divisi otomatis muncul sebagai room chat, dan tugas dari divisi masuk ke Tugas Saya.

## 6. Pengujian

**SQL** (`supabase/tests/organization.sql`, pola `pg_temp.check`/`denied` dengan rollback):

1. `createOrganization` membuat ketua dan divisi pertama.
2. Staf/Kadiv tidak bisa `setOrgRole`, `updateOrganization`, `createDivision`, atau membuka overview.
3. Paket tidak aktif: `createDivision` dan overview → `plan_inactive`; anggota ke-9 sebuah divisi → `group_full`; `maxUses > 1` → `invalid_input`.
4. Paket aktif: kursi penuh → `org_full`; masuk divisi kedua tidak memakai kursi baru; divisi bisa lebih dari 8 orang.
5. Trigger jabatan:
   - Ketua keluar dari divisi terakhir saat masih ada anggota lain → `ketua_transfer_required`, dan `deleteAccount` miliknya juga ditolak.
   - Ketua yang menjadi satu-satunya anggota organisasi **bisa** menghapus akun.
   - BPH keluar sendiri → jabatannya terhapus.
   - Kadiv mengeluarkan BPH dari divisi terakhirnya → `org_role_holder`.
   - `setOrgRole` dengan `role='ketua'` dan `transferKetua` ke diri sendiri → `invalid_input`.
6. Akses langsung ditolak:
   - `select`/`insert` ke tabel baru oleh `authenticated`.
   - `private.mutate_org` dan helper dipanggil langsung oleh `authenticated` → `permission denied`, seperti tes `mutate_workflow` di `milestone_e.sql`.
   - `grouply_org_overview` dan `grouply_billing` oleh `anon`; `grouply_billing` juga oleh `authenticated`.
7. Hitungan overview (terlambat/review/tanpa kabar) cocok dengan fixture.
8. Grup biasa tanpa organisasi berperilaku persis seperti sebelumnya (regresi `workflow.sql` dan `milestone_e.sql` tetap lulus).

**Konkurensi** (pola dua sesi di `moderation_local.py`):

- Dua `joinGroup` serentak ke divisi berbeda saat kursi tinggal satu → tepat satu berhasil.
- Dua Kadiv serentak mengeluarkan ketua dari dua divisi terakhirnya → tepat satu berhasil, yang lain `ketua_transfer_required`.
- `setOrgRole` serentak dengan target yang keluar dari divisi terakhirnya → tidak ada jabatan tanpa keanggotaan di akhir.
- `deleteAccount` serentak dengan `removeMember` dan `setOrgRole` di organisasi yang sama → tidak ada deadlock (lima kali ulang, seperti uji `060000`).

**Flutter**:

- Tes store: decode `organizations`, toleran saat key tidak ada.
- Tes peta error.
- Widget test dengan `DemoBackend`:
  - Buat organisasi mengirim payload yang benar.
  - Tombol aksi muncul sesuai jabatan.
  - Dashboard tampil dari data overview palsu.
  - Banner paket tidak aktif tampil.
  - Pilihan `maxUses` hanya muncul di divisi organisasi aktif.
- `local_backend_test.dart`: satu alur integrasi localhost (buat organisasi → aktivasi lewat skrip → buat divisi → undang → dashboard).

## 7. Urutan kerja

1. **Backend**: migration (tabel, helper, `mutate_org`, definisi ulang `private.mutate` dan `mutate_workflow`, trigger, snapshot, overview, billing) + tes SQL + tes konkurensi + `billing_local.py`.
2. **Flutter**: store/backend/peta error/`DemoBackend` + layar + tes widget.

   Langkah 1 dan 2 **bisa dikerjakan paralel** setelah kontrak di bagian 4 disepakati, karena Flutter dibangun dulu terhadap `DemoBackend`.
3. **Integrasi**: tes localhost tiga akun, lalu update `docs/PRD.md` (perubahan scope v1.3), `CLAUDE.md`, `docs/IMPLEMENTATION_STATUS.md`, dan `docs/BACKEND_SETUP.md`.

Perkiraan relatif: backend dan Flutter kira-kira sama besar. Bagian backend paling berisiko ada di definisi ulang `private.mutate` + `mutate_workflow`, trigger jabatan, dan urutan kunci.

Desain ini sudah ditinjau ulang secara independen terhadap kode migration. Temuan soal balapan trigger, urutan kunci, hapus akun ketua tunggal, divisi kosong, dan penjaga 8 anggota di client sudah dimasukkan di atas.

## 8. Keputusan yang perlu disetujui

1. Paket berakhir = kembali ke batas gratis (rekomendasi) atau read-only seperti tertulis di PRD.
2. BPH tanpa hak tulis di divisi lain pada Tahap 1 (rekomendasi) atau BPH bisa bertindak sebagai coordinator semua divisi.
3. Kursi dihitung per orang unik (rekomendasi) atau per keanggotaan divisi.
4. Seat limit dan masa aktif untuk pilot, misalnya 150 kursi sampai akhir periode, gratis.
5. Anggota hanya melihat nama dan jumlah anggota divisi lain, bukan isi divisinya (rekomendasi).
6. Nama pengurus (ketua/BPH/pembina) terlihat oleh semua anggota organisasi (rekomendasi), atau tetap tersembunyi kecuali satu grup.
7. Kadiv tidak boleh mengeluarkan pemegang jabatan dari divisi terakhirnya; Ketua harus mencabut jabatannya dulu (rekomendasi), atau jabatannya ikut terhapus diam-diam.

## 9. Di luar Tahap 1

Kepanitiaan lintas divisi, persetujuan berjenjang, rapat, pengumuman, push server, template, arsip periode, rekap LPJ, lampiran, memindahkan grup lama ke dalam organisasi, undangan tingkat organisasi, hak tulis BPH, versi web, pembayaran otomatis.
