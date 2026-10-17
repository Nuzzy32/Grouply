# Grouply Flutter

Port Android + iOS dari aplikasi SwiftUI Grouply. Source Swift tetap dipertahankan sebagai referensi dan fallback selama migrasi; backend dan migration Supabase tetap dipakai bersama, tidak digandakan.

## Jalankan

```sh
cd flutter
flutter pub get
flutter run
```

Tanpa konfigurasi, aplikasi menawarkan **demo lokal**. Demo tidak terhubung ke akun atau data server, dan snapshot demo Swift tidak diimpor otomatis.

Untuk akun email yang sudah terdaftar pada backend:

```sh
flutter run \
  --dart-define=SUPABASE_URL=https://PROJECT.supabase.co \
  --dart-define=SUPABASE_ANON_KEY=PUBLIC_PUBLISHABLE_KEY
```

Gunakan hanya publishable/anon key yang memang boleh dibundel dalam aplikasi. Jangan gunakan service-role key. Kredensial sesi disimpan melalui secure storage, bukan snapshot demo. Backend harus menerapkan migration repository dan RLS. App tidak menambahkan akun atau melakukan deploy otomatis.

Untuk Supabase lokal yang sudah disiapkan dengan `scripts/backend_local.py`, URL Android Emulator adalah `http://10.0.2.2:55321`; iOS Simulator menggunakan `http://localhost:55321`. Android debug hanya mengizinkan HTTP lokal ke `localhost`, `127.0.0.1`, dan `10.0.2.2`. Release memerlukan HTTPS. Perangkat fisik tidak dapat memakai localhost komputer; gunakan backend HTTPS yang dipilih dan diuji secara eksplisit.

## Validasi dan artefak

```sh
flutter analyze
flutter test
flutter build apk --debug
flutter build ios --simulator --no-codesign
```

APK debug: `build/app/outputs/flutter-apk/app-debug.apk`. Ini artefak pengujian, bukan rilis Play Store. Signing produksi Android sengaja tidak menggunakan debug key. Untuk distribusi, siapkan signing resmi, build AAB, dan uji perangkat nyata. iOS juga memerlukan signing/provisioning milik pemilik aplikasi untuk perangkat atau App Store.

## Batas migrasi

- Login Flutter memakai email/password akun yang sudah tersedia; Apple sign-in, pendaftaran, dan pemulihan akun belum diport. Ini bukan pengganti penuh jalur login produksi Swift.
- Push notification/APNs/FCM belum disambungkan. Jangan menganggap preferensi atau layar sebagai bukti pengiriman notifikasi.
- Deep link lokal `grouply://task/<id>` memeriksa akses setelah login. Domain universal/app links belum dikonfigurasi.
- Bundle/application ID Flutter adalah `id.grouply.app`. Memasang versi iOS Flutter dapat menggantikan aplikasi Swift dengan ID yang sama; data demo/sesi tidak dimigrasikan otomatis. Gunakan simulator terpisah atau backup sebelum mengganti instalasi.
- Keberhasilan build dan unit/widget test bukan bukti cloud, login provider, realtime antarperangkat, atau kesiapan beta. Lihat catatan verifikasi aktual di `../docs/FLUTTER_MIGRATION.md`.
