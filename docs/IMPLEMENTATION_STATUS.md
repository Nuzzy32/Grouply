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

## Target cloud dan rilis yang belum tersedia

Belum tersedia/terverifikasi: deployment cloud, provider Apple nyata dan pencabutan token Apple, Realtime Group Chat lintas perangkat fisik, APNs/pengingat lokal, domain/AASA/Universal Links, operator moderasi production dan kebijakan retention. Penghapusan akun password server dan CLI moderasi tersedia lokal, bukan bukti readiness Apple/App Review. Source migration aktual ada di `supabase/migrations`; DDL dokumen produk mencakup target yang lebih luas. Tidak ada proyek cloud atau database production yang diubah. Gate cloud/TestFlight tetap belum dicentang.
