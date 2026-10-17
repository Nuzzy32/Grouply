# Migrasi Grouply ke Flutter

## Keputusan dan batas perubahan

Pada 17 Oktober 2026 pengguna secara eksplisit memilih Flutter untuk mendukung Android dan iOS dari satu source aplikasi. Ini memperluas keputusan awal iOS-only di dokumen v1.3; dokumen desain/domain lama tetap menjadi referensi workflow. Web tidak ditambahkan.

Client baru berada di `flutter/`. Source SwiftUI, proyek Xcode native, backend, dan migration yang sudah ada tidak dihapus atau dipindahkan. Perubahan Swift/Supabase lain yang sudah ada di working tree tidak menjadi bagian implementasi port ini. Tidak ada deploy, push Git, commit, rotasi secret, reset database, atau pembuatan akun oleh proses migrasi Flutter.

## Yang tersedia

- Empat tab Beranda, Grup, Chat, Tugas Saya dan profil, menggunakan identitas Soft Future serta app icon Grouply yang sudah ada.
- (Historis, demo dihapus 17 Oktober 2026) Demo lokal tersimpan terpisah dengan persona, group/project/task CRUD, assignment, start, submission append-only, review/revisi, archive/restore, invitations, coordinator/membership, diskusi, unread, laporan, block/unblock, dan penghapusan identitas demo.
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
- Perbedaan yang tersisa: beberapa glyph Cupertino tidak identik dengan SF Symbol (mis. database, grid, kunci); Flutter belum punya Sign in with Apple, share sheet (diganti salin ke clipboard), dan date picker iOS (diganti kalender dalam sheet). Android memakai Roboto karena SF tidak boleh dibundel; tata letak dan ukuran tetap sama.

Verifikasi: `flutter analyze` bersih; `flutter test` 126 lulus, 1 integrasi lokal opt-in dilewati (tidak dijalankan ulang pada perubahan UI ini); `flutter build apk --debug` dan `flutter build ios --simulator --debug` berhasil. Perbandingan berdampingan Swift (iPhone 17 Pro) vs Flutter (iPhone 17), iOS 26.4: Welcome, Beranda, Grup, Chat, Tugas Saya, dan detail tugas sudah dicek secara visual; contoh di `docs/screenshots/flutter/compare-welcome.png` dan `compare-home.png`. Belum diuji di emulator atau perangkat Android.

## Daftar akun dan atur ulang kata sandi — 17 Oktober 2026

- Sheet akun memakai komponen Soft Future yang sama dengan sheet lain (`showGLSheet`, `GLField`, `glInputDecoration`, `GLSubmitButton`, `GLFormError`, `GLNotice`): toggle Masuk/Daftar bergaya pill, tombol tampil/sembunyikan sandi, indikator minimal 8 karakter, dan Atur Ulang Sandi dua langkah. Daftar meminta nama ≤80, email, kata sandi ≥8. Screenshot: `docs/screenshots/flutter/auth-signup-ios.png`, `auth-reset-code-ios.png`. Nama dikirim sebagai metadata dan dipakai trigger profil yang sudah ada; tidak ada migration baru.
- Pemulihan memakai kode 6 digit di email (`verifyOTP` tipe recovery lalu `updateUser`), bukan tautan, sehingga tidak butuh deep link/Universal Link. Template lokal: `supabase/templates/recovery.html` lewat `[auth.email.template.recovery]` di `supabase/config.toml`. Jika `updateUser` gagal setelah kode diterima, sesi ditutup dan pengguna diminta kode baru.
- Respons pendaftaran tanpa sesi (konfirmasi email aktif) tidak login otomatis; sheet kembali ke Masuk dengan pesan untuk membuka email konfirmasi. Lokal `enable_confirmations = false`.
- Kode error Auth (`user_already_exists`, `weak_password`, `otp_expired`, rate limit, dll.) dipetakan ke pesan Indonesia. Pesan kirim kode tidak membocorkan apakah email terdaftar.
- **Cloud:** template recovery di dashboard Supabase harus diganti agar memuat `{{ .Token }}`, SMTP produksi harus dipasang, dan keputusan konfirmasi email/panjang sandi minimum perlu ditetapkan. Belum dilakukan.

Verifikasi: `flutter analyze` bersih; `flutter test` 131 lulus (5 tes baru: store dan widget sheet), 2 integrasi lokal opt-in dilewati secara default. `GROUPLY_LOCAL_INTEGRATION=1 flutter test test/local_backend_test.dart` lulus 2/2, termasuk tes baru: daftar → nama sampai ke profil → duplikat ditolak → kirim kode → kode dibaca dari Mailpit lokal → kode salah ditolak → kode benar → sandi lama ditolak, sandi baru diterima → akun dihapus lewat `deleteAccount`. Smoke UI iPhone 17 (iOS 26.4, simulator terpisah dari Swift): daftar akun dari sheet sampai Beranda menampilkan nama; akun tes kemudian dihapus. Header sheet diperbaiki (tombol Batal sebelumnya menumpuk di judul). APK debug dan iOS simulator dibangun ulang. Belum diuji di Android runtime atau cloud.

## Penghapusan mode demo — 17 Oktober 2026

- Aplikasi Flutter tidak lagi berisi demo: `lib/core/demo.dart`, persona di Welcome, panel demo/ganti persona di Profil, kode undangan contoh, banner offline, teks simulasi hapus akun/laporan, dan penyimpanan `grouply.demo.*` dihapus dari `lib/`. `GrouplyStore` hanya memanggil backend; tanpa konfigurasi, sheet akun menampilkan pemberitahuan server belum dikonfigurasi.
- Welcome kini berisi **Masuk dengan Akun** dan **Belum punya akun? Daftar**. Kode undangan dikirim apa adanya (dipangkas), karena token server peka huruf besar/kecil.
- Seed lama dipindah ke `test/demo_backend.dart` (fake `GrouplyBackend` khusus tes) agar tes widget tetap punya data. Tes yang hanya memeriksa aturan workflow versi demo dan persistence demo dihapus; aturan tersebut ditegakkan server.
- Catatan: perangkat yang pernah menjalankan versi lama masih menyimpan key `grouply.demo.v2` di SharedPreferences; tidak dibaca lagi.

Verifikasi: `flutter analyze` bersih; `flutter test` 125 lulus, 2 integrasi opt-in dilewati; `GROUPLY_LOCAL_INTEGRATION=1 flutter test test/local_backend_test.dart` 2/2 lulus; APK debug dan iOS simulator dibangun ulang; Welcome tanpa persona dicek di simulator iPhone 17.

## Belum merupakan pengganti rilis penuh

- Login Apple dan jalur auth produksi Android belum dipasang/disahkan. Daftar akun dan atur ulang kata sandi email sudah ada (lihat bagian di atas), tetapi baru teruji di localhost.
- Push APNs/FCM, domain universal/app links, moderasi operasional produksi, dan kebijakan retensi masih memerlukan konfigurasi/validasi.
- Belum ada migrasi otomatis sesi dari sandbox Swift ke Flutter. Bundle ID keduanya `id.grouply.app`: jangan mengganti instalasi pengguna yang berisi data tanpa backup/rencana migrasi. Uji Flutter menggunakan simulator iPhone 17 terpisah dari simulator utama Swift iPhone 17 Pro.
- Draf gagal chat dipertahankan selama layar terbuka, bukan offline write queue atau draft lintas restart.
- APK debug bukan AAB bertanda tangan produksi dan bukan publikasi Play Store. App Store/Play Store, runtime Android/perangkat fisik, login provider, pengiriman push, dan interoperabilitas cloud antarperangkat belum dinyatakan lulus.
- Android SDK tersedia tetapi inventaris device tidak menemukan Android Emulator yang siap dipakai (`avdmanager list avd` gagal). Build APK tidak membuktikan pengujian runtime Android.

Panduan menjalankan dan konfigurasi ada di `flutter/README.md`. Jangan menambahkan service-role key, password test, refresh token, atau file akun privat ke source/artefak dokumentasi.
