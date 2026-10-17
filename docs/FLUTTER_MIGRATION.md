# Migrasi Grouply ke Flutter

## Keputusan dan batas perubahan

Pada 17 Oktober 2026 pengguna secara eksplisit memilih Flutter untuk mendukung Android dan iOS dari satu source aplikasi. Ini memperluas keputusan awal iOS-only di dokumen v1.3; dokumen desain/domain lama tetap menjadi referensi workflow. Web tidak ditambahkan.

Client baru berada di `flutter/`. Source SwiftUI, proyek Xcode native, backend, dan migration yang sudah ada tidak dihapus atau dipindahkan. Perubahan Swift/Supabase lain yang sudah ada di working tree tidak menjadi bagian implementasi port ini. Tidak ada deploy, push Git, commit, rotasi secret, reset database, atau pembuatan akun oleh proses migrasi Flutter.

## Yang tersedia

- Empat tab Beranda, Grup, Chat, Tugas Saya dan profil, menggunakan identitas Soft Future serta app icon Grouply yang sudah ada.
- Demo lokal tersimpan terpisah dengan persona, group/project/task CRUD, assignment, start, submission append-only, review/revisi, archive/restore, invitations, coordinator/membership, diskusi, unread, laporan, block/unblock, dan penghapusan identitas demo.
- Client Supabase Auth email/password untuk akun yang sudah ada; sesi/PKCE melalui secure storage. SharedPreferences menyimpan demo dan penanda signed-out nonrahasia, bukan token. Konfigurasi menolak secret/service-role key dan HTTP remote.
- RPC `grouply_snapshot` / `grouply_mutate` memakai nama action dan payload camelCase dari client Swift. Mode backend menunggu server dan tidak melakukan fallback mutasi demo ketika jaringan gagal.
- Realtime group chat, sinkronisasi read IDs, refresh foreground/reconnect, pembatasan membership, optimistic version check tugas, dan ID pesan stabil untuk retry. Read receipts hanya menandai pesan yang teramati di viewport.
- Deep link lokal `grouply://task/<id>` memeriksa keberadaan tugas dan membership setelah autentikasi; state navigasi dibersihkan ketika akun berganti.
- Target Android/iOS, launcher icon existing, konfigurasi jaringan debug Android khusus localhost, dan Keychain entitlement iOS. Release Android tidak ditandatangani dengan debug key secara diam-diam.

## Verifikasi aktual — 17 Oktober 2026

Lingkungan: Flutter 3.41.4, Dart 3.11.1, macOS; build Android debug dan iOS Simulator.

| Pemeriksaan | Hasil |
| --- | --- |
| `flutter analyze` | Bersih, no issues |
| `flutter test` | 125 tes unit/widget lulus; 1 tes integrasi lokal opt-in dilewati secara default |
| `GROUPLY_LOCAL_INTEGRATION=1 flutter test test/local_backend_test.dart` | 1 tes integrasi nyata localhost lulus |
| `flutter build apk --debug` | APK debug berhasil dibangun |
| `flutter build ios --simulator --no-codesign` | Runner.app simulator berhasil dibangun |
| Smoke UI iPhone 17, iOS 26.4 | Build final terpasang; welcome → demo → Beranda → daftar Chat → percakapan terbuka; deep link `grouply://task/t1` membuka detail tugas setelah dialog iOS disetujui |

Screenshot build final yang diperiksa secara visual: `docs/screenshots/flutter/home-ios.png`, `docs/screenshots/flutter/chat-ios.png`, dan `docs/screenshots/flutter/task-ios.png`. Inset status bar Beranda sudah diperbaiki dan dilindungi widget test. Smoke UI ini memakai demo, bukan sesi backend; tidak membuktikan secure storage pada perangkat atau pengiriman pesan dari UI native.

Tes unit/widget mencakup workflow dan role guard, snapshot/identity isolation, konflik versi, persistence/corrupt demo recovery, session storage/tombstone, RPC HTTP/error handling, formulir/validasi HTTPS, chat retry/read state/moderation, navigasi empat tab, serta layar sempit dengan teks diperbesar.

Tes integrasi memakai **tiga akun lokal yang sudah ada**, pembacaan kredensial privat tanpa mencetak secret, SDK Supabase/RPC/realtime nyata di loopback port 55321. Alur yang lulus: sign-in tiga identitas, grup uji terisolasi, undangan single-use terpisah untuk tiap anggota, proyek/tugas, start, revisi dan approval, penolakan stale version/aksi tanpa izin, pengiriman realtime lintas store, selective read IDs, dan pencabutan membership yang menghilangkan akses. Storage sesi test berupa memori; hasil ini **bukan bukti Keychain/Keystore nyata atau cloud**.

Test opt-in dapat dijalankan ulang dari `flutter/` dengan akun lokal yang sudah disiapkan. Ia sengaja tidak menjalankan setup/reset/deploy dan menolak URL selain loopback port 55321. Fixture grup bertanda `Flutter local smoke <timestamp>` dari percobaan uji tetap tersimpan; tidak ada cleanup destruktif. Tidak ada akun yang dibuat, dihapus, atau diganti kredensialnya. Tes default tidak membaca kredensial ini.

Verifikasi ulang terakhir lulus dengan fixture `Flutter local smoke 1792229566798998`, grup `e316ed79-b1f0-4c63-b2bc-ae47d96215a3`. Pemeriksaan format final tidak mengubah file, analisis bersih, dan kedua artefak dibangun ulang setelah perbaikan inset/deep link.

Artefak lokal (diabaikan Git):

- `flutter/build/app/outputs/flutter-apk/app-debug.apk`
- `flutter/build/ios/iphonesimulator/Runner.app`

## Paritas UI dengan SwiftUI — 17 Oktober 2026

Port awal memakai desain Material buatan sendiri (Beranda "Fokus hari ini", `NavigationBar`, banner demo, seed Adrian/Nadia/Raka) sehingga tampilannya berbeda dari aplikasi Swift. UI Flutter kini diport 1:1 dari SwiftUI:

- `flutter/lib/ui/gl.dart` mencerminkan `Grouply/Core/DesignSystem.swift`: token warna, `gl()` (ukuran/berat/tracking, tinggi baris SF ~1.19, SF Pro Display mulai 19pt plus tabel tracking Apple), ikon SF Symbol → Cupertino Icons, sudut continuous (`RoundedSuperellipseBorder`), kartu, chip, sheet, dialog konfirmasi, toast, header detail.
- Tema: transisi push/swipe-back iOS, scroll bounce, tanpa ripple Material, locale `id_ID`, di Android dan iOS.
- Layar: Welcome + persona demo, sheet login email, tab bar kapsul mengambang, Beranda, Grup (detail/anggota/pengaturan/undangan/gabung), Proyek (Group Pulse, filter, editor), Tugas Saya dan detail tugas (Ringkasan/Hasil kerja/Diskusi, kirim hasil, review, alihkan, editor), Chat (daftar, percakapan, moderasi), Profil (notifikasi, diblokir, tentang/privasi, hapus akun, panel demo). Kontrak action/payload store tidak berubah.
- Seed demo = `Grouply/Core/DemoSeed.swift` (Alex u1 … Laras u7). Key penyimpanan demo naik ke `grouply.demo.v2`, sehingga data demo lama port awal tidak dipakai lagi.
- Perbedaan yang tersisa: beberapa glyph Cupertino tidak identik dengan SF Symbol (mis. database, grid, kunci); Flutter belum punya Sign in with Apple dan date picker iOS (diganti kalender dalam sheet). Android memakai Roboto karena SF tidak boleh dibundel; tata letak dan ukuran tetap sama.

Verifikasi: `flutter analyze` bersih; `flutter test` 126 lulus, 1 integrasi lokal opt-in dilewati (tidak dijalankan ulang pada perubahan UI ini); `flutter build apk --debug` dan `flutter build ios --simulator --debug` berhasil. Perbandingan berdampingan Swift (iPhone 17 Pro) vs Flutter (iPhone 17), iOS 26.4: Welcome, Beranda, Grup, Chat, Tugas Saya, dan detail tugas sudah dicek secara visual; contoh di `docs/screenshots/flutter/compare-welcome.png` dan `compare-home.png`. Belum diuji di emulator atau perangkat Android.

## Belum merupakan pengganti rilis penuh

- Login Apple, pendaftaran, pemulihan kata sandi dan jalur auth produksi Android belum dipasang/disahkan. Flutter saat ini memakai akun email/password yang sudah tersedia.
- Push APNs/FCM, domain universal/app links, moderasi operasional produksi, dan kebijakan retensi masih memerlukan konfigurasi/validasi.
- Belum ada migrasi otomatis snapshot demo/sesi dari sandbox Swift ke Flutter. Bundle ID keduanya `id.grouply.app`: jangan mengganti instalasi pengguna yang berisi data tanpa backup/rencana migrasi. Uji Flutter menggunakan simulator iPhone 17 terpisah dari simulator utama Swift iPhone 17 Pro.
- Draf gagal chat dipertahankan selama layar terbuka, bukan offline write queue atau draft lintas restart. Demo tidak menyinkronkan data ke akun lain.
- APK debug bukan AAB bertanda tangan produksi dan bukan publikasi Play Store. App Store/Play Store, runtime Android/perangkat fisik, login provider, pengiriman push, dan interoperabilitas cloud antarperangkat belum dinyatakan lulus.
- Android SDK tersedia tetapi inventaris device tidak menemukan Android Emulator yang siap dipakai (`avdmanager list avd` gagal). Build APK tidak membuktikan pengujian runtime Android.

Panduan menjalankan dan konfigurasi ada di `flutter/README.md`. Jangan menambahkan service-role key, password test, refresh token, atau file akun privat ke source/artefak dokumentasi.
