# Backend Grouply: setup dan batas verifikasi

Backend ini berjalan lokal pada Docker dan memakai Supabase Auth, PostgreSQL, RLS, dan RPC sungguhan. Mode demo sudah dihapus dari kedua client, jadi semua data aplikasi berasal dari backend ini; belum dideploy ke proyek Supabase cloud.

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

Email atur ulang kata sandi memakai kode 6 digit dari `supabase/templates/recovery.html`. Setelah mengubah template atau `config.toml`, jalankan `supabase stop` lalu perintah start di atas untuk proyek ini; email lokal terbaca di Mailpit port 55324. Template cloud diatur terpisah di dashboard.

Skrip `setup` hanya mengizinkan localhost port 55321. Ia membuat tiga akun pengujian pada Supabase Auth lokal, menghasilkan kata sandi acak, dan menulis:

- `Config/Local.xcconfig`: URL dan **publishable key publik**, diabaikan Git.
- `~/Library/Application Support/GrouplyDevelopment/accounts.json`: kredensial lokal dengan izin file `0600`, di luar repo. Jangan commit atau membagikan file ini.

Untuk mencoba server di aplikasi, pilih **Masuk dengan Akun**. Pada build Debug gunakan email/password akun pengujian dari file privat tersebut. Akun pengujian email/password tidak ditawarkan pada build Release.

Di simulator, gunakan signing ad hoc agar Keychain memiliki identitas aplikasi. Build unsigned (`CODE_SIGNING_ALLOWED=NO`) tidak dapat membuktikan Keychain bekerja.

### Email pendaftaran dan pemulihan

Template email pemulihan lokal berada di `supabase/templates/recovery.html` dan didaftarkan di `supabase/config.toml`. Terapkan template yang sama ke konfigurasi Auth proyek cloud sebelum menguji reset password di cloud; `{{ .Token }}` harus ditampilkan sebagai kode OTP enam digit. Client meminta email reset, memverifikasi kode OTP, lalu langsung memasukkan pengguna setelah kata sandi baru tersimpan. Respons pengiriman selalu netral: `Jika email terdaftar, kode telah dikirim`.

```sh
xcodebuild -project Grouply.xcodeproj -scheme Grouply \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -derivedDataPath build test \
  CODE_SIGN_IDENTITY=- CODE_SIGNING_ALLOWED=YES CODE_SIGNING_REQUIRED=YES
```

Tes integrasi native membaca path akun lokal melalui scheme environment `GROUPLY_LOCAL_ACCOUNTS_PATH`. Tanpa setup lokal, tes integrasi menandai dirinya skipped; tes store dan client mock tetap berjalan. Tidak ada kata sandi yang tertanam pada source atau diketik melalui log XCTest UI.

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

UI menunggu respons server sebelum menganggap perubahan berhasil. State tidak ditulis ke file. Token sesi hanya masuk Keychain; logout menghapus state cloud. Refresh dilakukan saat foreground atau pull to refresh.

### Group Chat Realtime lokal

Migration `20261017040000_realtime_group_chat.sql` mengaktifkan publikasi INSERT/UPDATE untuk `chat_messages`, `chat_reads`, dan `user_sync_state` saja. Client memakai WebSocket URLSession dan protokol Phoenix 1.0.0, tanpa dependency tambahan. Payload message dibatasi SELECT RLS membership. Read markers dan revision difilter ke akun sendiri; jangan menerbitkan DELETE membership karena event DELETE tidak memiliki jaminan RLS yang sama.

Event menginvalidasi snapshot terotorisasi, bukan langsung menambahkan payload ke UI. Event beruntun digabung dan ditunda saat mutasi berlangsung. Fetch gagal dicoba kembali dengan backoff. Heartbeat 20 detik, pembaruan JWT, retry 1–30 detik, snapshot setelah subscription siap/reconnect, serta penghentian socket saat background/logout menangani lifecycle. Daftar dan ruang chat menampilkan status ketika koneksi belum siap. Unread/read disinkronkan lintas sesi akun yang sama. Penanda baca mengirim `messageIDs` yang benar-benar diamati, sehingga pesan baru yang berlomba dengan request tidak ikut terbaca.

Membership berubah → revision pribadi tanpa payload grup → snapshot baru, termasuk bagi akun yang dicabut. Snapshot menghapus akses dan pesan grup dari state aktif. Ini tidak dapat menarik kembali data yang pernah diterima perangkat; perangkat offline baru mengetahui pencabutan setelah terhubung kembali.

Tes `testRealtimeMessagesUnreadReconnectAndMembershipRevocation` membuktikan pengiriman antar-akun, unread/read lintas sesi, recovery pesan ketika socket dihentikan lalu diaktifkan, deduplikasi ID, serta penghapusan cache setelah membership dicabut. Ini memakai beberapa client native dalam **satu simulator** dan Supabase localhost, bukan dua iPhone fisik atau layanan cloud.

`shortcut:` snapshot memuat seluruh data terotorisasi untuk slice awal; ganti dengan query berhalaman sebelum riwayat grup membesar. Ini belum merupakan uji beban atau readiness beta publik.

## Milestone E lokal: laporan, blokir, dan hapus akun

Migration `20261017050000_milestone_e_safety.sql` menambahkan status laporan privat (`pending`, `dismissed`, `removed`), peninjauan operator, dan penghapusan akun transactional. Migration additive `20261017060000_milestone_e_lock_order.sql` memperbaiki urutan lock, dan `20261017070000_milestone_e_snapshot_identity.sql` memastikan reviewer historis terhapus diserialisasi sebagai identitas kosong. Ketiganya wajib diterapkan. Pengujian dan CLI berikut hanya untuk Supabase lokal Grouply, bukan production.

```sh
python3 scripts/moderation_local.py queue
python3 scripts/moderation_local.py review <REPORT_UUID> dismissed --note "Tidak melanggar aturan grup"
python3 scripts/moderation_local.py review <REPORT_UUID> removed --note "Konten melanggar aturan grup"
python3 scripts/milestone_e_local.py --run
python3 scripts/moderation_local.py check-locks
```

CLI operator mengambil service-role key dari status Supabase lokal tanpa mencetak/menyimpannya. Output antrean berisi alasan dan isi pesan yang dilaporkan; jangan membagikan output tersebut. Endpoint `grouply_moderation(action,payload)` hanya dapat dipanggil service role, bukan akun aplikasi atau claim metadata buatan pengguna. `removed` mengganti isi pesan dengan penanda moderasi, bukan menghapus tugas, versi submission, atau histori review. Keputusan akhir identik dapat diulang; keputusan berbeda terhadap laporan yang selesai ditolak. Tidak ada operator yang otomatis bertugas, SLA, email notifikasi, atau dashboard moderation production.

`check-locks` membuat dua akun disposable acak, memakai dua sesi PostgreSQL untuk mengamati blocking aktual, lalu membersihkan fixture miliknya sendiri. Lima interleaving menguji assignment saat mutasi anggota menunggu, serta deletion melawan dismiss/remove untuk pelapor aktif/mantan anggota. Perubahan race di-rollback; jangan arahkan skrip ke database lain. Tidak ada reset atau penghapusan akun lama.

`reportMessage` memvalidasi membership, menolak laporan pesan sendiri, menyimpan satu laporan per pelapor/pesan, dan membatasi laporan baru lima per menit. Pelapor hanya melihat alasan/status laporannya sendiri; catatan operator tidak ditampilkan. Block/unblock tetap berupa penyembunyian pesan untuk akun sendiri (bukan mengeluarkan anggota, mencegah semua pengiriman, atau menghapus konten). Revision pribadi memperbarui sesi lain akun yang sama.

`deleteAccount` menghapus Auth, profil, membership, read markers, dan blokir pribadi serta mengosongkan FK identitas pada histori bersama. RPC/RLS tidak memberi akses kepada JWT lama; refresh/login akun tersebut tidak dapat digunakan lagi. App hanya menganggap penghapusan sukses setelah menerima `deleted: true`, kemudian membersihkan Keychain dan state tanpa mengambil snapshot akun yang sudah dihapus. Kegagalan jaringan tanpa konfirmasi bukan bukti penghapusan berhasil; muat ulang/masuk kembali untuk memastikan status sebelum mencoba lagi.

Prasyarat penghapusan: transfer koordinator bila ada anggota lain, lalu alihkan semua tugas non-`done` sebagai pelaksana/reviewer, termasuk proyek arsip. Tidak ada reassignment otomatis. Bila hanya tersisa satu anggota, grup dan riwayat dipertahankan tanpa coordinator/membership; undangan dicabut. Riwayat tidak otomatis dialihkan ke pengguna lain. Pesan/hasil kerja/review tetap ada dengan identitas kosong yang ditampilkan sebagai “Pengguna terhapus”; isi kontribusi bisa masih mengandung informasi pribadi yang ditulis pengguna. Ini bukan penghapusan konten menyeluruh dan kebijakan retensi belum disahkan untuk rilis publik.

Alur Apple belum teruji; pencabutan token Sign in with Apple belum diimplementasikan. Jangan menganggap deletion lokal akun password sebagai bukti kesiapan penghapusan akun Apple/App Review. Tugas selesai dengan peserta yang telah dihapus tidak dapat dibuka kembali; buat tugas pengganti dengan peserta aktif.

## Menghubungkan proyek cloud nanti

Salin `Config/Local.xcconfig.example` dan isi URL HTTPS serta publishable key proyek sendiri. Jangan masukkan service-role key, APNs key, refresh token atau password ke bundle. Jangan jalankan migration pada cloud sebelum target proyek dan perubahan disetujui.

Sign in with Apple sudah memiliki tombol native, nonce aman, pertukaran id_token, dan entitlement. Pemakaiannya masih membutuhkan signing team/capability Apple yang valid dan konfigurasi provider Apple di Supabase. Alur Apple belum diuji dengan akun/perangkat nyata. Lihat [panduan Apple Supabase](https://supabase.com/docs/guides/auth/social-login/auth-apple).

Belum tersedia/teruji: deployment cloud, Realtime pada jaringan nyata/dua perangkat fisik, APNs/local reminders, domain/AASA Universal Links, pencabutan token Apple, operator moderasi production dan kebijakan retention yang disahkan. Aksi yang belum didukung server menampilkan error; tidak jatuh kembali ke mutasi demo.
