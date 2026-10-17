# Status implementasi Grouply

Per 17 Oktober 2026, native SwiftUI iPhone iOS 17+ tersedia dalam mode demo dan **mode server Supabase lokal**. Backend sungguhan sudah terhubung ke UI; deployment cloud dan seluruh gate beta publik belum selesai.

## Slice backend yang tersedia

- Supabase Auth untuk tiga akun pengujian terpisah, sesi Keychain, refresh token, logout dan pemulihan sesi.
- Migration PostgreSQL, SELECT dengan RLS, serta RPC transactional untuk grup, anggota/undangan, proyek, tugas, submission/review dan pesan.
- Validasi membership/role, lock proyek selesai/arsip, optimistic version, hash token undangan, idempotensi komentar dan batas frekuensi server.
- UI menunggu respons server, refresh saat foreground/pull to refresh, serta error yang dapat dibaca. Tidak ada fallback mutasi demo pada akun server.
- Integrasi native Apple sign-in dengan nonce dan entitlement tersedia sebagai source; provider Apple/perangkat nyata belum diverifikasi.

Setup dan perintah pengujian ada di [Backend Setup](BACKEND_SETUP.md). Cloud state tidak ditulis ke snapshot demo; laporan cloud dibersihkan saat logout. Respons 401 dari request sesi lama tidak boleh menghapus kredensial sesi baru.

## Tersedia di demo

- Beranda, Grup, Chat dan Tugas Saya dengan navigasi detail/sheet.
- Buat/gabung/edit grup, undangan tujuh hari dengan expiry/revoke/usage/capacity, anggota, transfer koordinator, keluar/remove dengan pemeriksaan tanggung jawab aktif.
- Buat/edit proyek, progress, selesai, buka kembali eksplisit, arsip dan pulihkan status sebelumnya.
- Buat/edit/alihkan/mulai tugas, kirim hasil dan tautan HTTPS, riwayat revisi, approve/minta revisi. Completed/archived readonly; edit/reassign terkunci pada in_review/done; membership dan versi diperiksa store.
- Group Chat dan diskusi tugas lokal, aktivitas menuju tugas, unread per persona, simulasi pesan gagal/retry, contoh report/block.
- Profil/persona, simulasi offline/waktu, anonimisasi akun demo dan reset; snapshot JSON atomik dengan cadangan file tidak terbaca.
- Share Sheet dan rute lokal `grouply://task/<id>` dengan validasi akses.

State persona dan JSON lokal bukan autentikasi server. Mode Supabase memakai Auth dan otorisasi server terpisah. Switch notifikasi tetap preferensi contoh, laporan belum dikirim kepada moderator, dan tautan lokal bukan Universal Link publik.

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

## Target cloud dan rilis yang belum tersedia

Belum tersedia/terverifikasi: deployment cloud, provider Apple nyata, Realtime Group Chat lintas perangkat, APNs/pengingat lokal, domain/AASA/Universal Links, moderasi operasional, retention dan penghapusan akun server. Source migration aktual ada di `supabase/migrations`; DDL dokumen produk mencakup target yang lebih luas. Tidak ada proyek cloud atau database production yang diubah. Gate cloud/TestFlight tetap belum dicentang.
