# Kebijakan Retensi Data Grouply

> **DRAF.** Kolom “Perilaku saat ini” dibaca dari `supabase/migrations` per 26 Oktober 2026. Kolom “Usulan” adalah keputusan yang belum disahkan dan **belum diimplementasikan**. Pemilik produk dan penasihat hukum harus menyetujui angka usulan sebelum rilis publik. Setiap usulan yang disetujui perlu job pembersihan terjadwal (mis. `pg_cron`) beserta tesnya.

## Prinsip

1. Simpan data selama dibutuhkan untuk fitur yang dipakai pengguna, tidak lebih.
2. Riwayat kerja kelompok adalah milik bersama grup. Penghapusan akun memutus identitas, tetapi tidak menghapus kontribusi yang diandalkan anggota lain.
3. Data keamanan (laporan, log) disimpan cukup lama untuk menangani penyalahgunaan berulang, lalu dihapus.

## Jadwal retensi

| Data | Tabel | Perilaku saat ini | Usulan |
|---|---|---|---|
| Akun auth (email, hash sandi) | `auth.users` | Disimpan sampai akun dihapus; dihapus seketika oleh `deleteAccount` | Sama. Akun yang tidak pernah masuk setelah `[24]` bulan diberi peringatan email, lalu dihapus `[30]` hari kemudian |
| Refresh token / sesi | `auth.refresh_tokens`, Keychain | Dihapus saat hapus akun; Keychain dibersihkan saat logout | Sama; ikuti masa berlaku bawaan Supabase |
| Profil (nama, warna) | `profiles` | Dihapus seketika saat hapus akun | Sama |
| Keanggotaan grup | `group_members` | Dihapus saat keluar grup / hapus akun | Sama |
| Status baca chat | `chat_reads` | Dihapus saat hapus akun | Sama |
| Daftar blokir | `user_blocks` | Dihapus saat unblock atau saat salah satu akun dihapus | Sama |
| Pesan chat & diskusi tugas | `chat_messages` | Disimpan tanpa batas; pengirim dikosongkan (`sender_id = NULL`) saat akun dihapus | Disimpan selama grup ada. Lihat “Grup tanpa anggota” |
| Proyek, tugas, submission, review | `projects`, `tasks`, `submissions`, `reviews` | Disimpan tanpa batas; submission append-only; identitas dikosongkan saat hapus akun | Disimpan selama grup ada |
| Riwayat aktivitas | `activity_events` | Disimpan tanpa batas; `actor_id` dikosongkan saat hapus akun | Hapus event lebih tua dari `[24]` bulan |
| Undangan | `private.invitations` | Kedaluwarsa setelah 7 hari (bawaan) atau dicabut; baris tetap disimpan | Hapus baris `[30]` hari setelah kedaluwarsa/dicabut/habis kuota |
| Laporan konten | `private.content_reports` | Disimpan tanpa batas. Saat pelapor menghapus akun, `reason` diganti `[Pelapor terhapus]` dan `reporter_id` dikosongkan | Laporan `pending` disimpan sampai ditinjau. Laporan selesai dihapus `[12]` bulan setelah `reviewed_at` |
| Pesan yang dimoderasi | `chat_messages` | Isi diganti penanda moderasi (keputusan `removed`); isi asli tidak disimpan di tabel | Sama |
| Grup tanpa anggota | `groups` + turunannya | Bila anggota terakhir menghapus akun, grup dan riwayat tetap ada tanpa koordinator/anggota; undangan dicabut | Hapus permanen grup tanpa anggota setelah `[90]` hari beserta seluruh kontennya |
| Log server / API | Supabase | Mengikuti retensi log paket Supabase `[sebutkan paket]` | Tidak lebih dari `[90]` hari |
| Backup basis data | Supabase | Mengikuti paket (PITR/backup harian) | Data terhapus ikut hilang dari backup paling lambat `[7–30]` hari setelah siklus backup berputar; sebutkan di kebijakan privasi |
| Preferensi & pengingat lokal | Perangkat | Tetap di perangkat sampai aplikasi dihapus | Sama |

## Penghapusan akun (ringkas, sesuai kode)

Prasyarat: transfer peran koordinator bila grup masih punya anggota lain, dan alihkan semua tugas non-`done` (termasuk di proyek arsip) sebagai pelaksana maupun reviewer. Setelah itu, dalam satu transaksi:

1. Undangan grup yang dikoordinasi dicabut; koordinator grup dikosongkan.
2. Keanggotaan, status baca, dan blokir (dua arah) dihapus.
3. Alasan laporan yang dibuat pengguna diganti `[Pelapor terhapus]`.
4. `client_id` pesan dan referensi target aktivitas dikosongkan.
5. Profil, refresh token, dan akun auth dihapus. Kolom identitas di pesan, aktivitas, tugas, submission, review, dan laporan menjadi `NULL` (`ON DELETE SET NULL`).

Batasan yang harus disebutkan ke pengguna: isi teks kontribusi yang dibuat sendiri tidak dihapus dan bisa memuat informasi pribadi.

## Permintaan hapus konten tertentu

Belum ada fitur hapus/sunting pesan di aplikasi. Sampai fitur itu ada, permintaan lewat `[EMAIL PRIVASI]` ditangani operator dengan keputusan moderasi `removed` atau SQL service role yang dicatat. Tanggapi dalam `[jangka waktu UU PDP]`.

## Keputusan yang masih harus diambil

- [ ] Setujui angka usulan di tabel (atau ganti).
- [ ] Pilih paket Supabase dan catat retensi log/backup aktualnya.
- [ ] Putuskan apakah perlu fitur hapus pesan sendiri sebelum rilis.
- [ ] Implementasikan job pembersihan terjadwal dan tes SQL untuk tiap aturan yang disetujui.
- [ ] Sinkronkan angka final ke bagian 6 [Kebijakan Privasi](PRIVACY_POLICY.md).
