# Status implementasi Grouply

Per 17 Oktober 2026, native SwiftUI iPhone iOS 17+ hanya memakai **mode server Supabase lokal**. Deployment cloud dan seluruh gate beta publik belum selesai.

## Penghapusan mode demo — 17 Oktober 2026

Atas permintaan pengguna, mode demo dihapus dari SwiftUI dan Flutter: persona/seed (`DemoSeed.swift`, `flutter/lib/core/demo.dart`), snapshot JSON lokal, panel demo, simulasi offline/waktu/gagal kirim, dan salinan lokal aturan workflow. Semua aksi kini hanya lewat RPC server; tanpa akun aksi ditolak. Nama tipe `DemoStore`/`DemoError` dipertahankan (historis). Data uji di Supabase lokal (grup/proyek/tugas/pesan/undangan/laporan sisa tes) juga dikosongkan; tiga akun lokal dipertahankan untuk tes integrasi.

Tes yang hanya menguji aturan versi demo dihapus karena aturan itu kini hanya ditegakkan server (suite SQL dan tes integrasi). SwiftUI: tes UI berbasis persona dihapus; `WorkflowTests` ditulis ulang untuk store tanpa server. Flutter: seed lama dipindah menjadi fake backend khusus tes `flutter/test/demo_backend.dart` untuk tes widget.

Verifikasi SwiftUI setelah penghapusan (iPhone 17 Pro Simulator, iOS 26.4): build berhasil; **25 tes unit/integrasi + 1 tes UI lulus**, 0 gagal, termasuk 4 tes integrasi ke Supabase lokal. Satu tes integrasi sempat flaky (sign-out bertabrakan dengan refresh Realtime) dan diperbaiki dengan menunggu store tidak sibuk; 5/5 percobaan ulang lulus. Ini satu simulator + localhost, bukan perangkat fisik atau cloud.

Bagian di bawah ini adalah catatan historis sebelum penghapusan demo.

## Slice backend yang tersedia

- Supabase Auth untuk tiga akun pengujian terpisah, sesi Keychain, refresh token, logout dan pemulihan sesi.
- Migration PostgreSQL, SELECT dengan RLS, serta RPC transactional untuk grup, anggota/undangan, proyek, tugas, submission/review dan pesan.
- Validasi membership/role, lock proyek selesai/arsip, optimistic version, hash token undangan, idempotensi komentar dan batas frekuensi server.
- UI menunggu respons server, refresh saat foreground/pull to refresh, serta error yang dapat dibaca. Tidak ada fallback mutasi demo pada akun server.
- Integrasi native Apple sign-in dengan nonce dan entitlement tersedia sebagai source; provider Apple/perangkat nyata belum diverifikasi.

Setup dan perintah pengujian ada di [Backend Setup](BACKEND_SETUP.md). Cloud state tidak ditulis ke snapshot demo; laporan cloud dibersihkan saat logout. Respons 401 dari request sesi lama tidak boleh menghapus kredensial sesi baru.

## Fitur (catatan historis; demo sudah dihapus)

- Beranda, Grup, Chat dan Tugas Saya dengan navigasi detail/sheet.
- Buat/gabung/edit grup, undangan tujuh hari dengan expiry/revoke/usage/capacity, anggota, transfer koordinator, keluar/remove dengan pemeriksaan tanggung jawab aktif.
- Buat/edit proyek, progress, selesai, buka kembali eksplisit, arsip dan pulihkan status sebelumnya.
- Buat/edit/alihkan/mulai tugas, kirim hasil dan tautan HTTPS, riwayat revisi, approve/minta revisi. Completed/archived readonly; edit/reassign terkunci pada in_review/done; membership dan versi diperiksa store.
- Group Chat dan diskusi tugas lokal, aktivitas menuju tugas, unread per persona, simulasi pesan gagal/retry, contoh report/block.
- Profil/persona, simulasi offline/waktu, anonimisasi akun demo dan reset; snapshot JSON atomik dengan cadangan file tidak terbaca.
- Share Sheet dan rute lokal `grouply://task/<id>` dengan validasi akses.

State persona dan JSON lokal bukan autentikasi server. Mode Supabase memakai Auth dan otorisasi server terpisah. Switch notifikasi tetap preferensi contoh, laporan privat tersedia bagi operator lewat CLI lokal (tanpa pengiriman email/SLA), dan tautan lokal bukan Universal Link publik.

## Verifikasi

| Pemeriksaan | Hasil saat catatan dibuat |
|---|---|
| Simulator build pertama | Lulus |
| Regresi tahap UI (16 Oktober) | **13 core + 5 UI lulus; 0 kegagalan** |
| Layar kecil | 4 UI smoke tests lulus pada iPhone SE generasi 3 (375 × 667 pt) |
| Lingkungan | iPhone 17 Pro dan iPhone SE generasi 3 Simulator, iOS 26.4 |
| UI | Navigasi empat tab, buat grup → buat proyek → detail otomatis, review approval, submission pelaksana, kirim chat, large Dynamic Type |
| Aksesibilitas | Basic labels diimplementasikan; audit VoiceOver fisik belum dilakukan |
| Database backend | 36 assertion SQL + percobaan DML langsung ditolak; advisors warn/error bersih |
| HTTP backend | Auth 3 akun → grup → tugas → submit → approve lulus; race 2 review menghasilkan tepat 1 sukses dan 1 stale_version; RLS lintas grup dan anonymous ditolak |
| Native backend | **23 tes native lulus**, termasuk client HTTP nyata, store lintas instance, Keychain signed simulator, refresh/logout, serta respons sesi lama; tidak ada tes integrasi yang skipped |
| UI backend | **6 tes UI lulus**, termasuk form login dan regresi workflow demo |

Perintah build/test dan peta proyek ada di [README](../README.md) dan [CLAUDE](../CLAUDE.md). UI test memakai seed in-memory, bukan snapshot tersimpan pengguna. Belum ada pengujian iPhone fisik, jaringan/perangkat ganda, semua ukuran layar, atau minimum OS iOS 17.

Hasil XCTest lokal: `artifacts/Grouply-Delivery.xcresult` (13 + 5), `artifacts/Grouply-Small.xcresult` (4 UI). Screenshot final ada di [screenshots](screenshots/). Build logs dan result bundles diabaikan Git; screenshot pilihan disimpan bersama dokumentasi.

Bukti slice backend: `artifacts/Grouply-Backend-Final.xcresult` (6 UI), `artifacts/Grouply-Backend-UI-Check.xcresult` (pemeriksaan ulang login/navigasi), `artifacts/Grouply-Backend-Verified.xcresult` (23 tes native termasuk undangan dan Keychain), serta `artifacts/backend-http-verification.json`. Suite SQL memakai transaksi rollback. Advisors dan database lint bersih pada tingkat warn/error. Keychain diverifikasi pada simulator yang signed, belum pada iPhone fisik.

Review tambahan menutup pesan gagal yang terlihat lintas persona, koordinator demo yang tidak terjangkau, dan cursor unread yang terpengaruh perubahan waktu simulasi. Layout tab dan status chip diperbaiki setelah pemeriksaan screenshot pada Dynamic Type terbesar. Perubahan akhir pada header Grup/Chat mengikuti layout sumber v3.1.

## Realtime lokal — 17 Oktober 2026

- WebSocket native tanpa dependency baru; heartbeat, refresh JWT, backoff, snapshot setelah subscription siap/reconnect dan stop saat background/logout.
- INSERT pesan terotorisasi RLS, read markers akun sendiri serta revision pribadi untuk perubahan membership. DELETE/TRUNCATE tidak dipublikasikan.
- Tes native lintas akun/sesi pada satu iPhone 17 Simulator iOS 26.4 + Supabase lokal membuktikan pesan/unread, read lintas sesi, gap recovery tanpa duplikasi, dan purge akses/pesan setelah membership dicabut. Ini bukan bukti dua perangkat fisik atau cloud.
- Suite SQL rollback: **40 PASS notices + 23 RPC denial yang diharapkan**, termasuk observed-only read race, input malformed, own-marker RLS, revoke/leave/rejoin, dan publication scope. Migration diterapkan incremental pada DB lokal Grouply, tanpa reset.
- Regresi native terbaru: **29 tes lulus, tanpa skipped**, termasuk parser/subscription, integrasi Realtime lokal, stale snapshot setelah expiry/cancellation, dan retry catchup tanpa event baru. Database lint lokal tidak menemukan schema errors.
- Regresi akhir **6 tes UI lulus** (login, workflow, kirim chat, Dynamic Type). Bukti lokal: `build/Logs/Test/Test-Grouply-2026.10.17_10-55-20-+0700.xcresult`; log native/UI `/tmp/grouply-realtime-final.log`, SQL `/tmp/grouply-realtime-sql.log`, lint `/tmp/grouply-realtime-lint.log`. Log dan result bundle tidak masuk Git.
- Snapshot penuh masih menjadi batas skalabilitas; belum diuji beban, kehilangan koneksi jaringan nyata berkepanjangan, atau APNs.

## Milestone E lokal — 17 Oktober 2026

- Laporan privat memiliki status pending/dismissed/removed; hanya service role dapat meninjau lewat RPC/CLI lokal. Tidak ada email/SLA/operator production otomatis. Report sendiri ditolak; dedup dan limit lima laporan baru/menit berlaku di server.
- Block/unblock memperbarui revision pribadi lintas sesi; placeholder yang pernah dibuka kembali disembunyikan saat status blokir berubah.
- Hapus akun password menghapus Auth/sesi/profil dan data pribadi, mempertahankan histori bersama tanpa referensi identitas akun. Konten historis masih bisa memuat informasi pribadi; kebijakan retensi belum disahkan. Tugas non-done termasuk arsip dan peran koordinator menjadi prasyarat, tanpa reassignment otomatis. Grup satu anggota dipertahankan tanpa akses anggota dan undangannya dicabut.
- Client mensyaratkan respons `deleted: true`, membersihkan sesi/state tanpa snapshot berikutnya, dan melaporkan kegagalan pembersihan Keychain secara eksplisit. Tugas selesai dengan peserta terhapus tidak dapat dibuka kembali; buat tugas pengganti.
- Regresi native **34 tes lulus**, termasuk empat integrasi localhost, report/block lintas sesi dan delete client; **7 tes UI lulus**, termasuk prasyarat hapus akun demo. Tes ulang final: `build/Logs/Test/Test-Grouply-2026.10.17_14-29-57-+0700.xcresult`, log `/tmp/grouply-e-verified-final.log`. Ini satu simulator iOS 26.4 + localhost, bukan perangkat fisik/cloud atau uji UI penghapusan akun live.
- Self-check script HTTP lulus: menolak target nonlokal, memvalidasi fixture miliknya sendiri, membersihkan profil via RPC, menolak fallback admin saat status tidak pasti, dan memulihkan login fixture yang gagal. Bukti live HTTP dan concurrency dicatat terpisah setelah dijalankan.
- Migration `050000` dan koreksi additive `060000` diterapkan incremental lokal, tanpa reset. SQL Milestone E **54 PASS** dan regresi workflow **40 PASS notices + denial checks**, keduanya rollback; lint lokal tingkat warning tidak menemukan schema errors.
- Lima interleaving dua worker direproduksi sebagai deadlock pada `050000`, lalu **5/5 lulus** pada `060000`: assignment/member mutation dan deletion/moderation dismissed/removed bagi pelapor aktif/mantan anggota. Actor memakai `FOR NO KEY UPDATE`; deletion mengunci konten sebelum sync/trigger membership/blokir. Ini regresi kasus terarah, bukan uji beban atau bukti bebas seluruh deadlock. Fresh database replay tidak dijalankan.
- Tes HTTP lokal **5 skenario lulus** setelah memperbaiki serialization `reviews.reviewer_id` nullable menjadi string kosong pada migration additive `070000`; semua fixture terhapus (`cleanup_failures: 0`). Offline self-check script juga lulus. `070000` diterapkan incrementally setelah suite SQL 54 checks, workflow 40 notices, dan race 5/5 dijalankan; lint tidak menemukan schema errors.

## Reminder bertahap dan penanda tugas mandek — 12 November 2026

- Flutter saja (client SwiftUI tetap H-1 dan tidak diubah): local notification H-3 dan H-1 untuk tugas milik sendiri, plus nudge "Belum ada kabar 2 hari" 48 jam setelah aktivitas terakhir task (submission atau pesan di thread task). Chip **Tanpa kabar N hari** di kartu/detail task dan hitungan di Group Pulse coordinator. Tanpa perubahan schema atau migration.
- Verifikasi: `flutter analyze` bersih dan **131 tes Flutter lulus**. Notifikasi di perangkat/emulator nyata belum diuji. Nudge hanya sampai ke perangkat assignee sendiri karena push server belum ada.

## Organization Plan Tahap 1 — backend lokal, 12 November 2026

- Migration `20261112071535_organizations.sql`: tabel `organizations`/`organization_roles` (tanpa akses langsung), `groups.organization_id`, aksi `createOrganization`/`updateOrganization`/`createDivision`/`setOrgRole`/`transferKetua`, kursi per orang unik pada `joinGroup`, undangan multi-pakai (`maxUses` 1–200) hanya untuk divisi organisasi aktif, trigger `group_members_org_guard`, snapshot `organizations[]` + `groups[].organizationID`, RPC `grouply_org_overview`, dan RPC operator `grouply_billing` (service_role saja). `private.mutate` dan `mutate_workflow` didefinisikan ulang dari salinan persis versi sebelumnya; hanya blok yang dicatat di header migration yang berubah.
- Verifikasi lokal:
  - Suite SQL: `workflow` **40 PASS**, `milestone_e` **54 PASS** (sama dengan sebelum migration), dan `organization` **66 PASS**, semuanya rollback.
  - Uji kunci: `moderation_local.py check-locks` 5/5 dan `billing_local.py check-locks` 6/6. Keenamnya mencakup kursi terakhir, dua Kadiv mengeluarkan ketua, `setOrgRole` vs keluar divisi, dan tiga interleaving `deleteAccount`.
  - Uji mutasi: menghapus kunci organisasi di trigger membuat 2 dari 6 uji kunci gagal; setelah dipulihkan, semuanya lulus lagi.
  - `backend_local.py smoke` HTTP tiga akun lulus. Advisors (warn) dan lint bersih.
- Client Flutter (branch `claude/happy-moser-cf5b16`, commit `f97c0c7`):
  - Bagian Organisasi di tab Grup, layar Organisasi, Dashboard, atur jabatan, dan banner paket tidak aktif.
  - Pilihan undangan 1/10/30/100 untuk divisi aktif.
  - Peta kode error server (P0001) ke pesan Indonesia.
- Verifikasi Flutter: `flutter analyze` bersih; `flutter test` **141 lulus** dengan 3 tes opt-in localhost dilewati. Dengan `GROUPLY_LOCAL_INTEGRATION=1`, ketiganya lulus terhadap backend lokal yang sudah dimigrasi, dua kali berturut-turut. Tes organisasi baru mencakup:
  - pendiri baru per run;
  - batas paket tidak aktif;
  - aktivasi lewat RPC operator;
  - divisi, undangan multi-pakai, dan hitungan kursi;
  - jabatan dan penolakan non-ketua;
  - Dashboard dan penolakan staf;
  - tugas selesai;
  - jabatan hilang saat keluar sendiri;
  - hapus akun pendiri tunggal.
- Batas yang diketahui: picker "Atur jabatan" hanya menampilkan orang yang satu divisi dengan Ketua, karena `users` di snapshot dibatasi `profile_visible`. Client SwiftUI tidak mengenal organisasi.
- Belum ada bukti cloud, perangkat nyata, atau uji beban. Fresh database replay tidak dijalankan; migration diterapkan incremental pada database lokal yang ada.

## Organization Plan Tahap 2 — backend lokal, 12 November 2026

- Migration `20261112133033_org_work.sql`:
  - `groups.is_committee`, `projects.lead_id`, `tasks.meeting_id`, dan enam tabel tertutup (`meetings`, `meeting_attendance`, `approvals`, `approval_steps`, `announcements`, `announcement_reads`).
  - Aksi baru di `private.mutate_orgwork`: `setProjectLead`, `createMeeting`/`updateMeeting`/`cancelMeeting`/`recordMeeting`, `requestApproval`/`decideApproval`/`cancelApproval`, `postAnnouncement`/`deleteAnnouncement`/`markAnnouncementRead`; `createDivision` menerima `committee`.
  - RPC `grouply_meeting`; snapshot mendapat `meetings[]`, `isCommittee`, `leadID`, `organizations[].approvals` dan `announcements`; Dashboard mendapat `isCommittee`.
  - Trigger `group_members_org_guard` diperluas: mengosongkan koordinator sie dan notulis di grup yang ditinggalkan, dan membuat pengajuan `lapsed` saat pengaju atau penyetuju keluar organisasi.
  - `private.mutate`, `mutate_workflow`, `mutate_org`, `org_overview`, dan `snapshot` didefinisikan ulang dari salinan persis versi Tahap 1; hanya blok yang dicatat di komentar tiap fungsi yang berubah.
- Verifikasi lokal:
  - Suite SQL: `workflow` **40**, `milestone_e` **54**, `organization` **66** (sama seperti sebelum migration), `organization_work` **120 PASS**, semuanya rollback.
  - Uji kunci: `moderation_local.py check-locks` 5/5, `billing_local.py check-locks` **10/10**.
  - Uji mutasi: melonggarkan pemeriksaan hak penyetuju membuat suite SQL dan satu uji kunci gagal; setelah dipulihkan, semuanya lulus lagi.
  - `backend_local.py smoke` lulus; advisors (warn) dan lint bersih; tiga tes integrasi Flutter localhost yang sudah ada tetap lulus terhadap backend baru.
- Client Flutter Tahap 2 (file baru `features/org_work_screens.dart`): Divisi/Kepanitiaan, koordinator sie, rapat (daftar, detail, jadwal, notulen + hadir/izin, "Jadikan tugas"), persetujuan (Menunggu saya / Pengajuan saya / Semua, Setujui/Tolak/Batalkan), pengumuman dengan hitungan baca, badge di kartu organisasi, pengingat lokal rapat (H-1 dan 1 jam), dan penanda kepanitiaan serta pengajuan tertahan di Dashboard.
- Review atas client menemukan dua bug sebelum digabung (sheet rapat memakai versi dari daftar sehingga bisa menimpa agenda/notulen; Kadiv bukan pengurus tidak bisa membuka pengajuan divisinya) dan tujuh perbaikan kecil; semuanya diperbaiki dengan tes.
- Tes integrasi localhost sempat gagal acak (sekitar 3 dari 5 run): `refresh()` yang dipanggil langsung bisa disalip muat ulang otomatis dari realtime dan selesai tanpa menerapkan data terbaru. Sekarang refresh yang tersalip menunggu snapshot terbaru diterapkan; ada tes unit yang gagal tanpa perbaikan itu.
- Verifikasi Flutter di hasil gabungan: `flutter analyze` bersih; `flutter test` **167 lulus** dengan 4 tes opt-in localhost dilewati. Dengan `GROUPLY_LOCAL_INTEGRATION=1`, keempat tes localhost lulus 3/3 run di hasil gabungan (8/8 di branch sebelum digabung). Tes Tahap 2 mencakup kepanitiaan, koordinator sie membuat tugas, notulen + daftar hadir + tugas dari rapat, persetujuan dua jenjang + pesan "sudah diputuskan", dan hitungan baca pengumuman.
- Push server (ORG-11) tidak dibuat. Belum ada bukti cloud, perangkat nyata, uji beban, atau audit VoiceOver.

## Laporkan konten organisasi — 13 November 2026

- Migration `20261113111326_report_org_content.sql`: `private.content_reports` mendapat `target_kind`/`target_id`/`excerpt`; aksi `reportContent` (pengumuman, rapat, pengajuan; ditolak untuk penulisnya sendiri, satu laporan per pelapor per konten, lima per menit); antrean dan `review` operator mencakup konten organisasi, dengan kunci grup → organisasi sebelum baris laporan; snapshot `reports[]` mendapat `kind` dan `targetID`.
- Flutter: tombol **Laporkan** di layar rapat, pengajuan, dan pengumuman memakai lembar laporan yang sama dengan chat; berubah menjadi "Sudah kamu laporkan" setelah terkirim.
- Verifikasi lokal: `organization_work` **142 PASS** (22 baru), `workflow` 40, `milestone_e` 54, `organization` 66; uji kunci `billing_local.py` **12/12**, `moderation_local.py` 5/5; smoke, advisors, dan lint bersih; `flutter analyze` bersih, `flutter test` **168 lulus**; keempat tes localhost lulus 3/3 run, termasuk laporan pengumuman dan peninjauan operator lewat HTTP.

## Organization Plan Tahap 3a — backend lokal, 13 November 2026

- Migration `20261113115440_org_plan.sql`:
  - Tabel tertutup `proker_templates` (empat template bawaan generik), `project_plan_items`, `organization_periods`; `projects.period_id`, `groups.closed_at`.
  - Aksi di `private.mutate_orgplan`: `applyTemplate`, `createTemplate`, `deleteTemplate`, `deletePlanItem`, `closeCommittee`, `reopenCommittee`, `setCoordinator`, `closePeriod`. `createTask` menerima `planItemID`.
  - Kepanitiaan tertutup hanya mengizinkan chat, keluar, mengeluarkan anggota, serah coordinator, dan melapor (`group_closed` untuk sisanya), di `mutate_workflow`, `mutate_orgwork`, dan `mutate_orgplan`.
  - RPC baca `grouply_templates`, `grouply_template`, `grouply_org_archive`, `grouply_report`; snapshot mendapat `closed`, `periodLabel`, `planItems`, `organizations[].periods`; template bisa dilaporkan (`removed` = template dihapus).
  - `private.mutate`, `mutate_workflow`, `mutate_orgwork`, `mutate_org`, `org_overview`, `snapshot`, `report_content`, dan `grouply_moderation` didefinisikan ulang dari salinan persis versi sebelumnya; perubahan dicatat di komentar tiap fungsi.
- Verifikasi lokal:
  - Suite SQL: `organization_plan` **107 PASS** (baru); `workflow` 40, `milestone_e` 54, `organization` 66, `organization_work` 142 tetap lulus.
  - Uji kunci: `billing_local.py check-locks` **16/16** (empat baru), `moderation_local.py` 5/5. Uji mutasi: menghapus penjaga butir rencana yang sudah dipakai membuat uji kunci dan suite SQL gagal; setelah dipulihkan, lulus lagi.
  - Smoke HTTP, advisors (warn), dan lint bersih; keempat tes integrasi Flutter yang sudah ada tetap lulus terhadap backend baru.
- Review client menemukan bahwa serah terima tidak menjangkau divisi yang tidak diikuti Ketua. Backend menambah RPC `grouply_org_members` (Ketua saja) dan aksi `removeClosedMember`; kolom "Revisi" di rekap kini menghitung pengiriman setelah yang pertama.
- Client Flutter Tahap 3a (file baru `features/org_plan_screens.dart`, `core/lpj_export.dart`): template (daftar, detail, pakai, simpan dari pratinjau, laporkan), bagian Rencana di proyek/sie, tutup/buka kepanitiaan, Serah terima (ganti coordinator per divisi, kursi di kepanitiaan tertutup, tutup periode), Arsip, dan Rekap LPJ dengan PDF/CSV (paket `pdf` 3.12, font Noto Sans dibundel ±1,2 MB, CSV ber-BOM dengan pengaman rumus). Review sebelum digabung juga memperbaiki PDF yang gagal untuk notulen panjang, tombol Rekap yang ditolak untuk proker periode lama, dan tombol yang pasti ditolak server di grup tertutup.
- Verifikasi Flutter di hasil gabungan: `flutter analyze` bersih; `flutter test` **195 lulus** dengan 5 tes opt-in localhost dilewati. Dengan `GROUPLY_LOCAL_INTEGRATION=1`, kelima tes localhost lulus 3/3 run; tes Tahap 3a mencakup template bawaan dan buatan sendiri, butir rencana yang hanya bisa dipakai sekali, tutup kepanitiaan, rekap, tutup periode termasuk penolakan retry, arsip, daftar anggota serah terima, dan mengeluarkan anggota kepanitiaan tertutup.
- Belum diuji: build APK/iOS, lembar Bagikan di perangkat nyata, tampilan PDF di pembaca PDF, cloud. Fresh database replay belum dijalankan; migration diterapkan incremental.

## Premium tanpa AI — Template Proker

- Flutter menampilkan **Gunakan Template** untuk koordinator grup atau sie di proyek organisasi. Template **Persiapan Seminar** menghasilkan tiga draf. Saran pelaksana memakai pemetaan peran dan jumlah tugas aktif. Koordinator dapat mengubah atau melepas pilihan sebelum menerbitkan tugas.
- Migration `20261113173427_premium_task_batch.sql` menambah `publishTaskBatch` untuk satu proyek, maksimal 20 tugas. Aksi memakai validasi dan efek `createTask`, dengan pemeriksaan paket aktif untuk penerbitan baru. Hasil disimpan bersama tugas dalam satu transaksi. Flutter menyimpan permintaan yang belum terkonfirmasi di secure storage agar percobaan ulang memakai ID yang sama.
- Verifikasi lokal: `flutter analyze` bersih, **178 tes Flutter lulus** termasuk 4 integrasi Supabase localhost, empat suite SQL lama **302 pemeriksaan lulus**, dan suite batch **12 pemeriksaan lulus**. Uji kunci organisasi **12/12**, advisors dan lint bersih. Integrasi menguji dua permintaan batch bersamaan lewat HTTP dan memeriksa tugas terlihat oleh pelaksana.
- Build iOS Simulator berhasil. Build Android belum terverifikasi karena resolusi dependensi Gradle belum berhasil. Alur UI diuji melalui widget test dan belum dijalankan di simulator, perangkat fisik, atau cloud. Tahap berikutnya dan pilot ada di [rencana Premium](PLAN-premium-tanpa-ai.md).
- Setelah digabung dengan Tahap 3a (14 November 2026): `flutter analyze` bersih, **210 tes Flutter lulus** dengan `GROUPLY_LOCAL_INTEGRATION=1`, tujuh suite SQL lulus (termasuk `organization_plan` 107 dan `meeting_follow_ups` 15), dan `check-locks` **17/17**. Kelas layar template Premium diganti nama menjadi `_SeminarTemplateScreen` agar tidak bentrok dengan `TemplateScreen` Tahap 3a. Dua jalur template (Premium per proyek dan template organisasi Tahap 3a) serta dua draf LPJ masih berdampingan dan perlu diputuskan.

## Target cloud dan rilis yang belum tersedia

Belum tersedia/terverifikasi: deployment cloud, provider Apple nyata dan pencabutan token Apple, Realtime Group Chat lintas perangkat fisik, APNs/pengingat lokal, domain/AASA/Universal Links, operator moderasi production dan kebijakan retention. Penghapusan akun password server dan CLI moderasi tersedia lokal, bukan bukti readiness Apple/App Review. Source migration aktual ada di `supabase/migrations`; DDL dokumen produk mencakup target yang lebih luas. Tidak ada proyek cloud atau database production yang diubah. Gate cloud/TestFlight tetap belum dicentang.

Draf kebijakan untuk rilis publik (belum disahkan, butuh tinjauan hukum): [Kebijakan Privasi](legal/PRIVACY_POLICY.md), [Retensi Data](legal/DATA_RETENTION.md), [Prosedur Moderasi](legal/MODERATION_OPERATIONS.md).
