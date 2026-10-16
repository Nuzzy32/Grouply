# Status implementasi Grouply

Per 16 Oktober 2026, implementasi native SwiftUI iPhone iOS 17+ **tersedia sebagai demo lokal** dari prototype v3.1. Cakupan lengkap produk tetap mengikuti enam spesifikasi v1.3; status ini membedakan implementasi lokal dengan target cloud.

## Tersedia di demo

- Beranda, Grup, Chat dan Tugas Saya dengan navigasi detail/sheet.
- Buat/gabung/edit grup, undangan tujuh hari dengan expiry/revoke/usage/capacity, anggota, transfer koordinator, keluar/remove dengan pemeriksaan tanggung jawab aktif.
- Buat/edit proyek, progress, selesai, buka kembali eksplisit, arsip dan pulihkan status sebelumnya.
- Buat/edit/alihkan/mulai tugas, kirim hasil dan tautan HTTPS, riwayat revisi, approve/minta revisi. Completed/archived readonly; edit/reassign terkunci pada in_review/done; membership dan versi diperiksa store.
- Group Chat dan diskusi tugas lokal, aktivitas menuju tugas, unread per persona, simulasi pesan gagal/retry, contoh report/block.
- Profil/persona, simulasi offline/waktu, anonimisasi akun demo dan reset; snapshot JSON atomik dengan cadangan file tidak terbaca.
- Share Sheet dan rute lokal `grouply://task/<id>` dengan validasi akses.

State persona dan JSON lokal bukan autentikasi atau isolasi keamanan server. Switch notifikasi adalah preferensi contoh, laporan tidak dikirim kepada moderator, dan tautan lokal bukan Universal Link publik.

## Verifikasi

| Pemeriksaan | Hasil saat catatan dibuat |
|---|---|
| Simulator build pertama | Lulus |
| Regresi akhir setelah perbaikan | **13 core + 5 UI lulus; 0 kegagalan** |
| Layar kecil | 4 UI smoke tests lulus pada iPhone SE generasi 3 (375 × 667 pt) |
| Lingkungan | iPhone 17 Pro dan iPhone SE generasi 3 Simulator, iOS 26.4 |
| UI | Navigasi empat tab, buat grup → buat proyek → detail otomatis, review approval, submission pelaksana, kirim chat, large Dynamic Type |
| Aksesibilitas | Basic labels diimplementasikan; audit VoiceOver fisik belum dilakukan |

Perintah build/test dan peta proyek ada di [README](../README.md) dan [CLAUDE](../CLAUDE.md). UI test memakai seed in-memory, bukan snapshot tersimpan pengguna. Belum ada pengujian iPhone fisik, jaringan/perangkat ganda, semua ukuran layar, atau minimum OS iOS 17.

Hasil XCTest lokal: `artifacts/Grouply-Delivery.xcresult` (13 + 5), `artifacts/Grouply-Small.xcresult` (4 UI). Screenshot final ada di [screenshots](screenshots/). Build logs dan result bundles diabaikan Git; screenshot pilihan disimpan bersama dokumentasi.

Review tambahan menutup pesan gagal yang terlihat lintas persona, koordinator demo yang tidak terjangkau, dan cursor unread yang terpengaruh perubahan waktu simulasi. Layout tab dan status chip diperbaiki setelah pemeriksaan screenshot pada Dynamic Type terbesar. Perubahan akhir pada header Grup/Chat mengikuti layout sumber v3.1.

## Target cloud dan rilis yang belum tersedia

Supabase Auth/Sign in with Apple, database/migrations/RLS/RPC, Realtime Group Chat lintas perangkat, APNs/pengingat lokal, domain/AASA/Universal Links, moderasi operasional, retention, dan penghapusan akun server belum diimplementasikan atau diverifikasi. DDL dan kontrak di dokumentasi adalah blueprint; tidak ada deployment atau perubahan database live dari pekerjaan ini. Milestone B dan gate cloud tetap belum dicentang.
