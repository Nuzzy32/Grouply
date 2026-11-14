# Handoff Premium tanpa AI

Branch `feat/premium-template-proker`. Tahap 1–5 masih berupa perubahan lokal.

## Tindak Lanjut Rapat

Buka detail rapat organisasi yang sudah selesai. Notulis atau koordinator menambah poin dengan judul, pelaksana, dan tenggat. Pengelola proyek memilih proyek atau sie di grup yang sama dan reviewer yang berbeda dari pelaksana. Tugas yang terbit bisa dibuka dari baris tindak lanjut.

Migration `20261113174441_meeting_follow_ups.sql` menambah penyimpanan dan aksi Supabase. Penerbitan memakai validasi `createTask` dan mengembalikan tugas yang sama saat diulang. Perubahan versi rapat memicu pembaruan detail. Kemampuan baru muncul setelah server mengirim flag dukungan.

## Verifikasi lokal

- 47 tes dari `workspace_test.dart` dan `local_backend_test.dart` lulus dengan `GROUPLY_LOCAL_INTEGRATION=1`. Tes Tindak Lanjut Rapat mencakup tambah ulang dengan ID yang sama, penerbitan bersamaan, tautan tugas, dan pembuatan tugas manual dari rapat.
- Alur layar belum dicoba di simulator atau perangkat fisik. Poin yang belum terbit bisa dihapus koordinator atau notulis lewat `removeMeetingFollowUp`, termasuk setelah paket berakhir, sehingga poin yang tenggatnya lewat atau pelaksananya keluar tidak menahan batas 50 poin per rapat.

## Checklist Review

Template Persiapan Seminar mengisi kriteria hasil di deskripsi setiap draf. Koordinator bisa mengubahnya sebelum terbit. Lembar review menampilkan butir di bawah judul `Kriteria review:` tanpa mengubah aksi setuju atau minta revisi. Tugas tanpa butir tetap memakai tampilan sebelumnya. Centang per butir dan migrasi tugas lama belum dibuat.

Tes widget tampilan kriteria dan alur revisi lulus dalam rangkaian 47 tes di atas.


## Ringkasan Proker

Dashboard Organisasi menampilkan jumlah tugas selesai, terlambat, dan menunggu review per proker aktif. Proker kosong menampilkan **Belum ada tugas**. Anggota divisi dapat membuka daftar per kategori dan masuk ke tugas. Pengurus di luar divisi melihat angka ringkasan sesuai izin dashboard. Perubahan ini memakai RPC dashboard dan snapshot tugas yang sudah ada.

Analyzer bersih. Seluruh 178 tes Flutter lulus dengan integrasi Supabase localhost diaktifkan, termasuk tes akses rincian dashboard. ID fixture tindak lanjut kini unik per rapat agar tes bisa diulang. Alur belum dicoba langsung di simulator atau perangkat fisik.

## Rekap CSV per proker

Buka **Aksi proyek → Ekspor rekap CSV** sebagai koordinator grup atau sie dengan Organization Plan aktif. Ekspor memakai snapshot terbaru yang diizinkan server. CSV memuat nama proker, tugas, pelaksana, status, tenggat, waktu hasil terakhir dikirim, dan tautan hasil terakhir. Tanggal memakai UTC. Data anggota terhapus diberi label anonim, dan teks yang menyerupai formula dinetralkan.

Analyzer bersih dan 176 tes Flutter lulus, termasuk format CSV dan izin menu. Empat tes integrasi localhost dilewati pada run ini. Ekspor diuji di iPhone 17e Simulator (iOS 26.4) dengan Supabase lokal. Share sheet membuka Save to Files dan file tersimpan di On My iPhone. Parser CSV mengonfirmasi satu baris tugas, tujuh kolom, Unicode dan tanda kutip, status, tanggal UTC, dan tautan hasil. Perangkat fisik dan Android belum diuji.


## Draf LPJ

Buka **Aksi proyek → Buat draf LPJ** sebagai koordinator grup atau sie dengan Organization Plan aktif. Draf memakai snapshot tugas proker, tautan hasil terakhir, dan notulen rapat selesai di grup yang sama yang tertaut melalui tugas. Bagian evaluasi dan rekomendasi dapat diisi sebelum berbagi sebagai `draf-lpj.txt`. Perubahan di editor hanya berada di sesi tersebut.

Analyzer bersih dan 46 tes Flutter terfokus lulus, termasuk isi draf, izin menu, dan tampilan editor. iPhone 17e Simulator (iOS 26.4) dengan Supabase lokal berhasil membuka editor, mengubah teks, dan membuka share sheet. File yang dibuat di cache untuk share sheet dibaca ulang dan memuat edit serta tautan hasil. Save to Files belum terverifikasi karena kontrol simulator gagal mengirim klik ke dialog iOS. Tidak ada migrasi baru.

## Perbaikan review 14 November 2026

- Template: permintaan yang belum terkonfirmasi bisa dibuang setelah konfirmasi, dan semua permintaan tersimpan milik akun dihapus saat logout atau hapus akun.
- Tindak lanjut: aksi `removeMeetingFollowUp` untuk poin yang belum terbit. Cast `meetingID` dipindah ke badan fungsi sehingga input salah menjadi `invalid_input`.
- Dashboard: chip bernilai 0 tidak lagi bisa diketuk. Draf LPJ memuat detail rapat secara paralel.
- Uji baru: `supabase/tests/meeting_follow_ups.sql` (15 assertion), skenario `check-locks` batch vs. pengeluaran pengelola proyek (13 skenario lulus), langkah hapus tindak lanjut di tes integrasi Flutter, dan tes widget buang permintaan + logout. Kedua migration Premium diputar ulang di atas skema `main` dalam transaksi yang di-rollback. Riwayat migration lokal `20261113174441` dicatat di `schema_migrations`; `supabase db reset` tidak dijalankan agar data lokal tetap ada.
