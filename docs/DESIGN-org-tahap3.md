# Desain Teknis — Organization Plan Tahap 3 (Alasan berlangganan tiap tahun)

Status: **disetujui 13 November 2026** (kesepuluh rekomendasi di bagian 9), **belum dibangun**. Pembangunan Tahap 3a menunggu pilot berjalan; Tahap 3b (lampiran) ditunda dan butuh persetujuan terpisah. Acuan produk: [PRD-organization-plan.md](PRD-organization-plan.md) (ORG-12 s.d. ORG-15). Dibangun di atas [Tahap 1](DESIGN-org-tahap1.md) dan [Tahap 2](DESIGN-org-tahap2.md). Client: Flutter saja. Backend: Supabase yang sama.

> PRD bagian 9 menjadwalkan Tahap 3 menjelang akhir periode kepengurusan pilot, saat serah terima dan LPJ benar-benar dibutuhkan. Pilot belum berjalan, jadi semua aturan di bawah masih dugaan. Desain ini disiapkan lebih awal supaya keputusan bisa diambil, bukan sebagai tanda untuk langsung membangun.

## 1. Keputusan inti

1. **Tahap 3 dipecah dua.** **3a**: template proker (ORG-12), arsip periode dan serah terima (ORG-13), rekap LPJ (ORG-14). **3b**: lampiran file (ORG-15). Bagian 3a hampir seluruhnya memakai data yang sudah ada. Bagian 3b butuh layanan baru (Storage), biaya penyimpanan, moderasi file, dan mengubah larangan "attachment" di scope v1.3, jadi dibangun terpisah setelah 3a dipakai pilot.
2. **Template berisi rencana, bukan tugas.** Setiap tugas wajib punya pelaksana dan reviewer yang berbeda (constraint `tasks_active_owners` dan `tasks_check`), sedangkan template tidak tahu siapa orangnya. Memakai template membuat proyek/sie beserta **daftar rencana**: butir judul, uraian, dan deadline. Coordinator atau koordinator sie mengubah tiap butir menjadi tugas lewat sheet tugas yang sudah ada, sambil memilih orangnya.
3. **Template adalah konten yang ditulis pembuatnya.** Client menyusun isi template dari proker yang bisa dilihat pembuatnya, menampilkannya sebagai pratinjau yang bisa diedit, lalu mengirim isinya. Server hanya memvalidasi bentuknya. Dengan begitu tidak ada isi tugas grup lain yang tersalin diam-diam. Template bisa dilaporkan seperti konten organisasi lain.
4. **Template bawaan adalah konten produk**, bukan data demo: empat kerangka generik (seminar, lomba, makrab, oprec) tanpa nama orang, disimpan di migration, berlaku untuk semua organisasi.
5. **Kepanitiaan ditutup secara eksplisit**, tidak otomatis. Syaratnya: tidak ada tugas yang belum selesai di proyek mana pun (termasuk yang diarsipkan), tidak ada proyek aktif yang belum diarsipkan, dan tidak ada pengajuan `pending`. Kepanitiaan tertutup hanya mengizinkan chat, keluar, mengeluarkan anggota, serah coordinator, dan melapor. Ia tidak dihitung di batas 30 dan pindah ke Arsip. Ini menutup batas yang dicatat di Tahap 2.
6. **Tutup periode hanya mengarsipkan dan memberi label.** Proker yang sudah selesai diarsipkan; semua proker yang sudah diarsipkan diberi label periode itu. Proker yang masih berjalan pindah ke periode baru. Kepanitiaan tidak ditutup otomatis; daftar periksa serah terima menautkan ke "Tutup kepanitiaan".
7. **Serah terima butuh hak Ketua atas coordinator.** Kadiv lama yang sudah lulus atau tidak merespons bisa menahan divisinya selamanya, karena `transferCoordinator` hanya bisa dilakukan coordinator. Tahap 3 menambah aksi Ketua `setCoordinator` khusus grup organisasi.
8. **Rekap LPJ dirakit server, dibentuk client.** RPC mengembalikan data terstruktur untuk satu periode; Flutter membuat CSV dan PDF lalu membagikannya. Tidak ada file yang disimpan di server.
9. **Arsip bisa dibaca pengurus baru.** Pengurus melihat ringkasan dan rekap proker semua grup organisasi, termasuk yang tidak pernah mereka ikuti. Tanpa ini, masalah utama di PRD ("data hilang saat ganti pengurus") tidak terselesaikan.
10. **Paket berakhir tidak mengunci data organisasi sendiri.** Membaca arsip, rekap, dan ekspornya, menutup kepanitiaan, dan menutup periode tetap bisa, karena paket justru sering berakhir tepat saat serah terima. Yang terkunci hanya membuat yang baru: memakai dan menyimpan template, membuka kembali kepanitiaan.

## 2. Model data (Tahap 3a, satu migration)

```sql
create table public.proker_templates (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid references public.organizations(id),   -- null = bawaan
  created_by uuid references public.profiles(id) on delete set null,
  name text not null check (length(name) between 1 and 80),
  description text not null default '' check (length(description) <= 1000),
  -- [{title, description, offsetDays, items: [{title, description, offsetDays}]}]
  -- offsetDays relatif terhadap hari acara; 1–20 sie, 0–40 butir per sie, maks 200 butir
  sections jsonb not null,
  created_at timestamptz not null default now()
);
create index proker_templates_org on public.proker_templates(organization_id);
create index proker_templates_creator on public.proker_templates(created_by);

create table public.project_plan_items (
  id uuid primary key default gen_random_uuid(),
  project_id uuid not null references public.projects(id),
  position smallint not null check (position between 1 and 40),
  title text not null check (length(title) between 3 and 120),
  description text not null default '' check (length(description) <= 2000),
  due_at timestamptz not null,
  task_id uuid references public.tasks(id) on delete set null,   -- terisi setelah dijadikan tugas
  unique (project_id, position)
);
create index project_plan_items_task on public.project_plan_items(task_id) where task_id is not null;

create table public.organization_periods (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id),
  label text not null check (length(label) between 1 and 40),
  started_at timestamptz,                 -- penutupan periode sebelumnya; null untuk periode pertama
  closed_at timestamptz not null default now(),
  closed_by uuid references public.profiles(id) on delete set null,
  unique (organization_id, label)
);

alter table public.projects add column period_id uuid references public.organization_periods(id);
create index projects_period on public.projects(period_id) where period_id is not null;
alter table public.groups add column closed_at timestamptz,
  add constraint groups_closed_committee check (closed_at is null or is_committee);
```

- Tiga tabel baru: RLS aktif, tanpa policy, `revoke all` dari `PUBLIC, anon, authenticated`, di luar publikasi Realtime. Sama dengan tabel Tahap 2.
- Judul butir rencana minimal 3 karakter, sama dengan batas sheet tugas di client, supaya setiap butir bisa langsung dijadikan tugas.
- Hapus akun: kolom pembuat menjadi null; tidak ada FK baru yang menghalangi `deleteAccount`. Proyek, tugas, dan organisasi tidak pernah dihapus, jadi FK tanpa `on delete` aman.

## 3. Hak akses

| Aksi | Siapa | Syarat |
|---|---|---|
| Melihat daftar template bawaan dan organisasi | Anggota organisasi | – |
| Memakai template | Coordinator grup tujuan | Paket aktif; grup organisasi yang belum ditutup |
| Membuat template | Ketua, BPH, coordinator grup organisasi mana pun | Paket aktif; maks 50 template per organisasi |
| Menghapus template organisasi | Pembuatnya, Ketua | – |
| Mengubah butir rencana menjadi tugas | Coordinator grup, koordinator sie proyek itu | Aturan `createTask` yang ada |
| Menghapus butir rencana | Coordinator grup, koordinator sie | Butir belum menjadi tugas |
| Menutup kepanitiaan | Coordinator kepanitiaan, Ketua | Syarat di keputusan inti 5 |
| Membuka kembali kepanitiaan | Ketua | Paket aktif; batas 30 kepanitiaan |
| Mengganti coordinator grup organisasi (`setCoordinator`) | Ketua | Target anggota grup itu |
| Menutup periode | Ketua | – |
| Melihat arsip periode | Pengurus | – |
| Membaca dan mengekspor rekap | Pengurus (semua grup); coordinator (grupnya); koordinator sie (sienya saja, tanpa pengajuan) | – |

## 4. Kontrak RPC

### 4.1 Aksi baru di `grouply_mutate` (fungsi baru `private.mutate_orgplan`)

| Aksi | Payload | Hasil | Aturan / error |
|---|---|---|---|
| `applyTemplate` | `templateID`, `groupID`, `eventAt` (ISO, dihitung client sebagai akhir hari acara waktu lokal) | `{projectIDs}` | Coordinator; paket aktif; grup tertutup → `group_closed`. Satu proyek per sie dengan `due_at = eventAt + offsetDays`; sie yang deadline-nya sudah lewat → `invalid_input`. Butir yang deadline-nya sudah lewat tetap dibuat dan ditandai "lewat" di client. Maks 5 pemakaian per jam per grup → `rate_limited` |
| `createTemplate` | `organizationID`, `name`, `description?`, `sections` | `{id}` | Lihat hak akses; bentuk `sections` divalidasi penuh → `invalid_input`; template ke-51 → `rate_limited` |
| `deleteTemplate` | `id` | `{}` | Pembuat atau Ketua; template bawaan → `forbidden` |
| `deletePlanItem` | `id` | `{}` | Coordinator/koordinator sie; butir yang sudah menjadi tugas → `plan_item_used` |
| `closeCommittee` | `groupID` | `{}` | Belum memenuhi syarat → `committee_busy`. Sekaligus mencabut undangan yang masih berlaku dan membatalkan rapat terjadwal di masa depan |
| `reopenCommittee` | `groupID` | `{}` | Ketua; paket aktif; 30 kepanitiaan aktif → `invalid_input` |
| `setCoordinator` | `groupID`, `userID` | `{}` | Ketua organisasi grup itu; target anggota grup → `invalid_input` |
| `closePeriod` | `organizationID`, `currentLabel`, `nextLabel` | `{periodID, archived}` | Ketua. `currentLabel` harus sama dengan label sekarang (beda → `stale_version`, jadi retry tidak menutup periode dua kali) dan tidak kosong. `nextLabel` 1–40 karakter, beda dari `currentLabel`, belum pernah ditutup → `period_exists`. Mengarsipkan proyek `completed`, memberi `period_id` ke semua proyek yang sudah diarsipkan dan belum berlabel, lalu mengganti label |

Perubahan pada aksi yang sudah ada:

- `createTask` menerima `planItemID` opsional: butir harus di proyek yang sama dan belum dipakai (diperiksa ulang setelah kunci grup) → `plan_item_used`; `task_id` diisi dalam transaksi yang sama.
- `restoreProject` pada proyek yang sudah berlabel periode → `project_read_only`. Arsip periode tetap jujur.
- `updateOrganization` menolak label periode yang sudah pernah ditutup → `period_exists`.
- `createDivision` menghitung batas 30 kepanitiaan hanya dari yang belum ditutup.
- `reportContent` menerima `kind: 'template'` (template organisasi, bukan bawaan; pelapor anggota organisasi, bukan pembuatnya).

**Grup tertutup — daftar izin**, diperiksa sekali setelah kunci grup di `mutate_workflow` (termasuk jalur `joinGroup`), `mutate_orgwork`, dan `mutate_orgplan`. Yang diizinkan: `sendMessage`, `retryMessage`, `markChatRead`, `reportMessage`, `reportContent`, `leaveGroup`, `removeMember`, `transferCoordinator`, `setCoordinator`, `markAnnouncementRead`, `deleteAnnouncement`, `reopenCommittee`. Semua aksi lain pada grup itu → `group_closed`.

### 4.2 RPC baca (tanpa syarat paket aktif)

- **`grouply_templates(org_id)`**: anggota organisasi. Daftar template bawaan + milik organisasi: nama, uraian, jumlah sie dan butir, tanggal dibuat. Tanpa nama pembuat. Isi `sections` lengkap untuk satu template lewat `grouply_template(template_id)`.
- **`grouply_org_archive(org_id)`**: pengurus saja. Periode yang sudah ditutup; per periode: proker berlabel periode itu (grup, judul, deadline, jumlah tugas/selesai) dan kepanitiaan yang ditutup selama periode itu, termasuk yang sudah tidak beranggota.
- **`grouply_report(group_id, period_id, project_ids)`**: data rekap untuk satu grup dan satu periode (`period_id` null = periode berjalan).

```json
{ "generatedAt": "…", "organization": "BEM FST", "period": "2026/2027",
  "group": { "name": "Panitia Seminar", "isCommittee": true, "coordinator": "…" },
  "projects": [{ "title": "Sie Publikasi", "dueAt": "…", "status": "completed", "lead": "…",
    "tasks": [{ "title": "Poster", "assignee": "…", "reviewer": "…", "status": "done",
      "dueAt": "…", "doneAt": "…", "revisions": 2, "links": ["https://…"] }] }],
  "meetings": [{ "title": "Rapat perdana", "startsAt": "…", "present": 12, "excused": 2,
    "minutes": "…", "minutesTruncated": false }],
  "approvals": [{ "title": "Dana publikasi", "amount": 500000, "status": "approved", "closedAt": "…",
    "chain": ["Raka (disetujui)", "Ayu (disetujui)"] }],
  "totals": { "tasks": 18, "done": 18, "approvedAmount": 2750000 } }
```

- Proyek: yang berlabel periode itu, atau untuk periode berjalan yang belum berlabel. `project_ids` maks 20 dan harus termasuk di sana.
- Rapat dan pengajuan: milik grup itu dalam jendela periode (`started_at`..`closed_at`, atau sampai sekarang). Maks 100 rapat; notulen dipotong 4.000 karakter per rapat dengan penanda `minutesTruncated`.
- Koordinator sie hanya menerima proyeknya sendiri, rapat grup (sudah ia lihat sebagai anggota), dan **tanpa** pengajuan.
- `doneAt` = waktu review yang menyetujui; `links` = tautan submission terakhir. Nama mengikuti `private.org_name` (akun terhapus → "Anggota terhapus", diblokir pelihat → "Anggota").

### 4.3 Snapshot

Aditif:
- `projects[]` + `periodLabel` (`''` untuk periode berjalan) dan `planItems[]` (hanya untuk proyek aktif yang belum diarsipkan, hanya butir yang belum menjadi tugas: id, position, title, description, dueAt).
- `groups[]` + `closed` (bool).
- `organizations[]` + `divisions[].closed`. Kepanitiaan tertutup tidak muncul di Dashboard (`grouply_org_overview`).

### 4.4 Urutan kunci

Tetap: **profil → grup (urut `id`) → organisasi (urut `id`, `FOR NO KEY UPDATE`) → `user_sync_state`**.

- `applyTemplate`, `deletePlanItem`, `closeCommittee`, `reopenCommittee`, `setCoordinator`: profil → grup → organisasi → sync.
- `createTemplate`, `deleteTemplate`: profil → organisasi.
- `closePeriod`: pemeriksaan Ketua tanpa kunci dulu (supaya anggota biasa tidak bisa memicu penguncian semua grup), lalu profil → **semua grup organisasi urut `id`** → organisasi → periksa ulang Ketua dan label → sync (`org_touch`). Proyek di grup yang dibuat setelah daftar grup dikunci tidak diubah; grup baru belum punya proyek selesai.

## 5. Flutter

| Layar | Isi |
|---|---|
| **Template** (dari layar Organisasi) | Daftar bawaan + milik organisasi; detail sie dan butir; "Pakai" → pilih grup tujuan dan tanggal acara; laporkan template organisasi |
| **Simpan sebagai template** (dari proyek/sie) | Pratinjau sie dan butir dari proker yang bisa dilihat pengguna, dengan tanggal acara sebagai patokan; bisa diedit sebelum disimpan |
| **Proyek/Sie** | Bagian **Rencana**: butir yang belum menjadi tugas, dengan penanda "lewat"; "Jadikan tugas" membuka sheet tugas terisi judul, uraian, dan deadline; hapus butir |
| **Kepanitiaan** | "Tutup kepanitiaan" dengan alasan jika belum bisa; penanda "Ditutup"; tombol pembuatan disembunyikan; pindah ke bagian Arsip di layar Organisasi |
| **Serah terima** (Ketua) | Daftar periksa: isi label periode baru; proker yang akan diarsipkan vs yang dibawa; kepanitiaan yang bisa ditutup; ganti Ketua/BPH/Pembina; ganti coordinator per divisi lewat `setCoordinator`; jumlah kursi yang dipakai orang yang hanya ada di kepanitiaan tertutup, dengan tautan mengeluarkan mereka; lalu "Tutup periode" dengan konfirmasi |
| **Arsip** (pengurus) | Per periode: proker berlabel dan kepanitiaan tertutup; tiap proker bisa dibuka sebagai ringkasan dan diekspor |
| **Rekap LPJ** | Pilih periode dan proker/sie, pratinjau ringkas, lalu "Bagikan PDF" atau "Bagikan CSV" |

- PDF dibuat di perangkat dengan paket `pdf` (dependency baru, murni Dart) di `compute()`, memakai font Noto Sans (regular dan bold, lisensi OFL) yang dibundel sebagai aset, karena font bawaan paket tidak mendukung karakter di luar Latin-1. Karakter yang tetap tidak didukung diganti.
- CSV: UTF-8 dengan BOM supaya Excel membaca huruf dengan benar; sel yang diawali `= + - @` diberi awalan `'` supaya tidak dijalankan sebagai rumus.
- Berbagi lewat `share_plus` (sudah ada) dengan `XFile.fromData` dan `sharePositionOrigin` untuk iPad.
- `_showTaskSheet` mendapat parameter awal judul, uraian, deadline, dan `planItemID`.
- `serverMessage`: `group_closed`, `committee_busy`, `plan_item_used`, `period_exists`, dan `rate_limited` khusus template.
- `DemoBackend`: koleksi template, butir rencana, dan periode masuk daftar backup/restore di `mutate()`.

## 6. Pengujian

**SQL** (`supabase/tests/organization_plan.sql`, rollback):

1. Template: bawaan terbaca semua anggota; validasi bentuk `sections`; batas 50; hapus oleh pembuat/Ketua; bawaan tidak bisa dihapus; laporan template.
2. `applyTemplate`: deadline sie dan butir benar dari `eventAt`; sie lewat ditolak, butir lewat tetap dibuat; batas 5 per jam; grup tertutup ditolak.
3. Butir rencana: hanya bisa dipakai sekali dan di proyeknya; hapus butir terpakai → `plan_item_used`; snapshot hanya memuat butir yang belum dipakai di proyek aktif.
4. Kepanitiaan: tutup ditolak bila ada tugas belum selesai di proyek arsip, proyek aktif, atau pengajuan `pending`; setelah ditutup, setiap aksi di luar daftar izin → `group_closed`, termasuk `joinGroup`, `reopenProject`, `restoreProject`, `setProjectLead`, `recordMeeting`; undangan tercabut dan rapat mendatang batal; batas 30 tidak menghitung yang tertutup; buka kembali memeriksa batas.
5. `setCoordinator`: hanya Ketua, hanya grup organisasi, target harus anggota.
6. `closePeriod`: label kosong ditolak; retry dengan `currentLabel` lama → `stale_version`; `nextLabel` yang sudah ditutup → `period_exists`; proyek selesai diarsipkan dan berlabel; proyek yang diarsipkan manual ikut berlabel; proyek berjalan tetap aktif; `restoreProject` proyek berlabel ditolak; `updateOrganization` ke label tertutup ditolak; berjalan tanpa paket aktif.
7. Rekap dan arsip: hanya pengurus/coordinator/koordinator sie sesuai cakupan; koordinator sie tidak menerima pengajuan; rapat dan pengajuan dibatasi jendela periode; batas jumlah dan potongan notulen; nama mengikuti aturan blokir/terhapus.
8. Akses langsung ke tabel dan fungsi baru ditolak; regresi suite lama tetap lulus.

**Konkurensi** (dua sesi):

- `closePeriod` serentak dengan `createTask`, `deleteAccount` anggota, `createDivision`, `joinGroup`, dan `transferKetua` → tanpa deadlock, invarian label dan arsip terjaga.
- Dua `createTask` dari butir yang sama → tepat satu berhasil.
- `closeCommittee` serentak dengan `createTask` di proyek kepanitiaan itu → salah satu ditolak, tidak ada tugas terbuka di kepanitiaan tertutup.

**Flutter**: widget test tiap layar; pembuatan CSV (BOM, awalan rumus) dan PDF dari data rekap palsu, termasuk karakter non-Latin; satu alur integrasi localhost: pakai template → jadikan tugas → selesaikan → rekap → tutup kepanitiaan → tutup periode → arsip.

## 7. Tahap 3b — Lampiran file (ringkas, untuk diputuskan nanti)

- Bucket privat Supabase Storage, jalur `org/<org_id>/<uuid>`; policy `storage.objects` memakai helper keanggotaan, tidak pernah publik.
- Unggah dua langkah: RPC mencatat slot (jenis, ukuran yang dinyatakan, konten induk), client mengunggah dengan JWT pengguna, lalu RPC konfirmasi memeriksa ukuran asli dari metadata Storage dan memotong kuota di bawah kunci organisasi.
- Dipakai di pengajuan (proposal, RAB), rapat (foto, daftar hadir), dan pengumuman. Submission tugas tetap tautan saja, supaya alur grup gratis tidak berubah.
- Batas awal: JPG/PNG/PDF, maks 10 MB per file, kuota per organisasi diatur operator.
- Butuh keputusan tersendiri: kuota dan harga, apakah file ikut terhapus saat konten ditarik atau akun dihapus, pemindaian file, dan jalur lapor untuk file. Stack lokal harus menjalankan `storage-api`, yang sekarang dikecualikan dari `supabase start`.

## 8. Urutan kerja (3a)

1. **Backend**: migration + template bawaan + daftar izin grup tertutup + suite SQL + uji kunci.
2. **Flutter**: store/backend/`DemoBackend`, lalu layar per fitur dengan urutan template dan rencana → tutup kepanitiaan → rekap dan ekspor → serah terima dan arsip.

   Keduanya bisa paralel setelah kontrak bagian 4 disepakati.
3. **Integrasi**: tes localhost, lalu catat perubahan scope di `docs/PRD.md` dan `CLAUDE.md`.

Bagian paling berisiko: daftar izin grup tertutup (menyentuh tiga fungsi mutasi), `closePeriod` yang mengunci semua grup organisasi, definisi ulang `mutate_workflow`, dan pembuatan PDF di perangkat.

Desain ini sudah ditinjau secara independen terhadap kode migration dan Flutter. Temuan soal anggota yang terjebak di kepanitiaan tertutup, daftar tolak yang tidak lengkap, penutupan otomatis yang bisa balapan, retry `closePeriod`, label periode, kebocoran pengajuan ke koordinator sie, rekap lintas periode, syarat paket yang tidak bisa ditegakkan, salinan isi tugas grup lain ke template, Kadiv yang tidak merespons, font PDF, dan injeksi rumus CSV sudah dimasukkan di atas.

## 9. Keputusan (disetujui 13 November 2026, semua sesuai rekomendasi)

1. Tahap 3 dipecah: 3a (template, arsip/serah terima, rekap LPJ) dibangun dulu; 3b (lampiran file) ditunda sampai 3a dipakai pilot (rekomendasi). Alternatif: semuanya sekaligus.
2. Template berisi rencana yang diubah menjadi tugas satu per satu oleh coordinator/koordinator sie (rekomendasi). Alternatif membuat tugas langsung tidak mungkin tanpa memilih dua orang per tugas.
3. Empat template bawaan generik (seminar, lomba, makrab, oprec) disertakan sebagai konten produk (rekomendasi), atau organisasi mulai tanpa template bawaan.
4. Template dibuat dari pratinjau yang bisa diedit oleh Ketua, BPH, atau coordinator mana pun (rekomendasi), atau hanya Ketua/BPH.
5. Kepanitiaan ditutup manual dengan syarat semua pekerjaannya selesai; tutup periode tidak menutup kepanitiaan otomatis (rekomendasi).
6. Tutup periode hanya mengarsipkan proker yang sudah selesai; yang berjalan dibawa ke periode baru (rekomendasi). Alternatif: semua proker diarsipkan dan tugas yang belum selesai dibatalkan.
7. Ketua boleh mengganti coordinator grup organisasi mana pun (`setCoordinator`) untuk serah terima (rekomendasi). Tanpa ini, Kadiv yang tidak merespons menahan divisinya.
8. Pengurus periode baru boleh membaca arsip dan rekap semua grup organisasi, termasuk nama pelaksana, tautan hasil kerja, dan notulen (rekomendasi). Ini pengungkapan baru: di Tahap 1–2 pengurus tidak melihat isi tugas grup yang tidak mereka ikuti.
9. Membaca, mengekspor rekap, dan menutup periode tidak butuh paket aktif (rekomendasi), karena paket sering berakhir tepat saat serah terima.
10. Rekap dibagikan sebagai PDF dan CSV yang dibuat di perangkat, dengan dependency baru `pdf` dan font Noto Sans dibundel (rekomendasi, menambah sekitar 1 MB ke aplikasi). Alternatif: CSV saja tanpa dependency baru.

## 10. Batas yang diketahui

- Rekap LPJ hanya merangkum yang tercatat di aplikasi. Keuangan di luar pengajuan (kas, bukti transfer) tetap di luar scope; PRD melarang pembukuan kas.
- Rapat dan pengajuan tidak terkait ke sie tertentu; rekap per sie tetap menampilkan rapat seluruh grup dalam periode itu.
- Menutup kepanitiaan tidak membebaskan kursi: anggota yang hanya tersisa di kepanitiaan tertutup tetap dihitung dan tetap menerima pengumuman organisasi sampai dikeluarkan. Layar serah terima menunjukkan jumlahnya.
- Template bawaan berbahasa Indonesia dan generik; isinya perlu dicek pengurus pilot.
- Proyek dan tugas belum punya tanggal dibuat (`created_at`), jadi rekap memakai deadline dan tanggal selesai tugas, bukan tanggal mulai.
