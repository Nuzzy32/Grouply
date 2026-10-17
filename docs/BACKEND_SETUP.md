# Backend Grouply: setup dan batas verifikasi

Backend ini berjalan lokal pada Docker dan memakai Supabase Auth, PostgreSQL, RLS, dan RPC sungguhan. Ia terpisah dari persona demo; belum dideploy ke proyek Supabase cloud.

## Menjalankan lokal

Dari root repo, dengan Docker aktif:

```sh
supabase start -x storage-api,imgproxy,postgres-meta,studio,edge-runtime,logflare,vector,supavisor
python3 scripts/backend_local.py setup
python3 scripts/backend_local.py smoke
xcodegen generate
open Grouply.xcodeproj
```

Port Grouply: API **55321**, PostgreSQL **55322**, email lokal **55324**, shadow database **55320**. Port berbeda mencegah bentrok dengan proyek Supabase lain. Jangan menjalankan `supabase stop` terhadap proyek lain.

Skrip `setup` hanya mengizinkan localhost port 55321. Ia membuat tiga akun pengujian pada Supabase Auth lokal, menghasilkan kata sandi acak, dan menulis:

- `Config/Local.xcconfig`: URL dan **publishable key publik**, diabaikan Git.
- `~/Library/Application Support/GrouplyDevelopment/accounts.json`: kredensial lokal dengan izin file `0600`, di luar repo. Jangan commit atau membagikan file ini.

Untuk mencoba server di aplikasi, pilih **Masuk dengan Akun**. Pada build Debug gunakan email/password akun pengujian dari file privat tersebut. Persona di bagian demo tetap merupakan data lokal terpisah. Akun pengujian email/password tidak ditawarkan pada build Release.

Di simulator, gunakan signing ad hoc agar Keychain memiliki identitas aplikasi. Build unsigned (`CODE_SIGNING_ALLOWED=NO`) tidak dapat membuktikan Keychain bekerja.

```sh
xcodebuild -project Grouply.xcodeproj -scheme Grouply \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -derivedDataPath build test \
  CODE_SIGN_IDENTITY=- CODE_SIGNING_ALLOWED=YES CODE_SIGNING_REQUIRED=YES
```

Tes integrasi native membaca path akun lokal melalui scheme environment `GROUPLY_LOCAL_ACCOUNTS_PATH`. Tanpa setup lokal, tes integrasi menandai dirinya skipped; tes demo dan client mock tetap berjalan. Tidak ada kata sandi yang tertanam pada source atau diketik melalui log XCTest UI.

## Migration dan pengujian keamanan

Migration canonical ada di `supabase/migrations/`. Jangan menyalin contoh DDL dari dokumen produk sebagai migration kedua.

```sh
docker exec -i supabase_db_Grouply psql -U postgres -d postgres \
  -v ON_ERROR_STOP=1 < supabase/tests/workflow.sql
supabase db advisors --local --type all --level warn --fail-on warn
supabase db lint --local
```

Suite SQL memakai transaksi rollback untuk fixture. `supabase db reset --local --no-seed` hanya untuk database lokal Grouply yang datanya boleh dihapus; reset akan menghapus akun dan grup pengujian lokal. Setelah reset jalankan `setup` lagi.

`smoke` menguji Auth tiga akun, buat/gabung grup, proyek, tugas, submit dan approve melalui HTTP. Dua request review berlomba pada versi yang sama: tepat satu berhasil dan satu menerima `stale_version`. Ia juga menguji penolakan query/mutasi lintas grup, DML langsung, dan snapshot tanpa login. Hasil tanpa kredensial ditulis ke `artifacts/backend-http-verification.json`.

## Kontrak yang dipakai aplikasi

- `grouply_snapshot()`: hanya data yang boleh dilihat akun aktif; email pengguna lain tidak disertakan, hash/kode undangan tidak diekspos.
- `grouply_mutate(action, payload)`: mutasi server transactional, membership/role/status/version diperiksa ulang. Payload memakai nama parameter camelCase pada store Swift.
- Operasi terpercaya berada di schema `private` dengan `search_path` eksplisit. Wrapper publik hanya dapat dieksekusi `authenticated`; tabel client hanya mendapat SELECT dengan RLS.
- Undangan memakai token acak dan hash privat, expiry tujuh hari, kuota dan kapasitas delapan anggota. Kode hanya dikembalikan pada pembuatan undangan.
- Batas server: 30 pesan teks per pengirim/grup/menit dan 10 undangan per grup/menit. Retry pesan dengan ID yang sama diperiksa sebelum batas frekuensi.

UI menunggu respons server sebelum menganggap perubahan berhasil. Cloud state tidak ditulis ke JSON demo. Token sesi hanya masuk Keychain; logout menghapus state cloud. Refresh dilakukan saat foreground atau pull to refresh.

### Group Chat Realtime lokal

Migration `20261017040000_realtime_group_chat.sql` mengaktifkan publikasi INSERT/UPDATE untuk `chat_messages`, `chat_reads`, dan `user_sync_state` saja. Client memakai WebSocket URLSession dan protokol Phoenix 1.0.0, tanpa dependency tambahan. Payload message dibatasi SELECT RLS membership. Read markers dan revision difilter ke akun sendiri; jangan menerbitkan DELETE membership karena event DELETE tidak memiliki jaminan RLS yang sama.

Event menginvalidasi snapshot terotorisasi, bukan langsung menambahkan payload ke UI. Event beruntun digabung dan ditunda saat mutasi berlangsung. Fetch gagal dicoba kembali dengan backoff. Heartbeat 20 detik, pembaruan JWT, retry 1–30 detik, snapshot setelah subscription siap/reconnect, serta penghentian socket saat background/logout menangani lifecycle. Daftar dan ruang chat menampilkan status ketika koneksi belum siap. Unread/read disinkronkan lintas sesi akun yang sama. Penanda baca mengirim `messageIDs` yang benar-benar diamati, sehingga pesan baru yang berlomba dengan request tidak ikut terbaca.

Membership berubah → revision pribadi tanpa payload grup → snapshot baru, termasuk bagi akun yang dicabut. Snapshot menghapus akses dan pesan grup dari state aktif. Ini tidak dapat menarik kembali data yang pernah diterima perangkat; perangkat offline baru mengetahui pencabutan setelah terhubung kembali.

Tes `testRealtimeMessagesUnreadReconnectAndMembershipRevocation` membuktikan pengiriman antar-akun, unread/read lintas sesi, recovery pesan ketika socket dihentikan lalu diaktifkan, deduplikasi ID, serta penghapusan cache setelah membership dicabut. Ini memakai beberapa client native dalam **satu simulator** dan Supabase localhost, bukan dua iPhone fisik atau layanan cloud.

`shortcut:` snapshot memuat seluruh data terotorisasi untuk slice awal; ganti dengan query berhalaman sebelum riwayat grup membesar. Ini belum merupakan uji beban atau readiness beta publik.

## Menghubungkan proyek cloud nanti

Salin `Config/Local.xcconfig.example` dan isi URL HTTPS serta publishable key proyek sendiri. Jangan masukkan service-role key, APNs key, refresh token atau password ke bundle. Jangan jalankan migration pada cloud sebelum target proyek dan perubahan disetujui.

Sign in with Apple sudah memiliki tombol native, nonce aman, pertukaran id_token, dan entitlement. Pemakaiannya masih membutuhkan signing team/capability Apple yang valid dan konfigurasi provider Apple di Supabase. Alur Apple belum diuji dengan akun/perangkat nyata. Lihat [panduan Apple Supabase](https://supabase.com/docs/guides/auth/social-login/auth-apple).

Belum tersedia/teruji: deployment cloud, Realtime pada jaringan nyata/dua perangkat fisik, APNs/local reminders, domain/AASA Universal Links, penghapusan akun server, pengiriman laporan ke moderator, serta kebijakan retention yang disahkan. Aksi yang belum didukung server menampilkan error; tidak jatuh kembali ke mutasi demo.
