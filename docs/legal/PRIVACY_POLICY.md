# Kebijakan Privasi Grouply

> **DRAF — belum berlaku.** Disusun dari perilaku kode per 26 Oktober 2026 (`supabase/migrations`, client Swift dan Flutter). Wajib ditinjau ahli hukum sebelum dipublikasikan. Isian bertanda `[…]` harus dilengkapi. Setelah final, kebijakan ini perlu tersedia di URL publik untuk App Store Connect dan Google Play Console, serta ditautkan dari dalam aplikasi.

Terakhir diperbarui: `[TANGGAL BERLAKU]`

## 1. Siapa kami

Grouply (“kami”) adalah aplikasi koordinasi tugas kelompok. Pengendali data pribadi adalah `[NAMA BADAN USAHA / PERORANGAN]`, `[ALAMAT]`. Hubungi kami di `[EMAIL PRIVASI]` untuk pertanyaan atau permintaan terkait data pribadi.

Kebijakan ini disusun dengan mengacu pada Undang-Undang No. 27 Tahun 2022 tentang Pelindungan Data Pribadi (UU PDP).

## 2. Data yang kami kumpulkan

| Kategori | Isi | Sumber | Tujuan |
|---|---|---|---|
| Akun | Alamat email, kata sandi (disimpan dalam bentuk hash oleh penyedia autentikasi), ID akun | Anda saat mendaftar | Masuk, keamanan akun, atur ulang sandi lewat kode email |
| Akun Apple *(bila fitur tersedia)* | ID pengguna Apple, email (bisa berupa email relay Apple), nama bila Anda izinkan | Apple | Masuk dengan Apple |
| Profil | Nama tampilan (maks. 80 karakter) dan warna avatar | Anda | Ditampilkan kepada anggota grup Anda |
| Keanggotaan | Grup yang Anda ikuti, peran (koordinator/anggota) | Penggunaan aplikasi | Menjalankan grup dan hak akses |
| Konten kerja | Proyek, tugas, catatan submission (maks. 5.000 karakter), tautan HTTPS (maks. 5), review | Anda | Fitur inti aplikasi |
| Pesan | Pesan Group Chat dan diskusi tugas (maks. 2.000 karakter), status baca | Anda | Komunikasi grup dan penanda belum dibaca |
| Riwayat aktivitas | Siapa melakukan aksi apa dan kapan (mis. tugas diserahkan) | Penggunaan aplikasi | Riwayat dan transparansi grup |
| Keamanan & moderasi | Laporan konten (alasan, pesan yang dilaporkan), daftar akun yang Anda blokir | Anda | Keamanan komunitas |
| Undangan | Hash kode undangan, masa berlaku, jumlah pemakaian | Koordinator | Bergabung ke grup |
| Data teknis | Alamat IP, waktu akses, jenis permintaan, log server | Otomatis | Keamanan, pencegahan penyalahgunaan, pembatasan laju |

**Yang tidak kami kumpulkan:** lokasi, kontak telepon, foto/berkas, data kesehatan, data pembayaran, atau pengenal iklan. Aplikasi tidak memuat SDK iklan, analitik pihak ketiga, maupun pelacakan lintas aplikasi.

**Data yang hanya tersimpan di perangkat Anda:** token sesi (di Keychain iOS / penyimpanan aman Android), preferensi tampilan, dan jadwal pengingat lokal. Data ini tidak dikirim ke server kami.

## 3. Dasar pemrosesan

- **Pelaksanaan perjanjian** — menyediakan layanan yang Anda minta saat mendaftar (akun, grup, tugas, pesan).
- **Kepentingan yang sah** — keamanan layanan, pencegahan penyalahgunaan, dan moderasi konten.
- **Kewajiban hukum** — bila diwajibkan peraturan perundang-undangan.
- **Persetujuan** — untuk notifikasi push (bila tersedia), yang dapat Anda cabut kapan saja lewat pengaturan perangkat.

## 4. Siapa yang dapat melihat data Anda

- **Anggota grup yang sama** melihat nama dan warna profil Anda, serta konten, pesan, dan aktivitas Anda di grup tersebut. Pesan dan konten grup **tidak** terenkripsi ujung-ke-ujung; konten tersimpan di server agar dapat diakses anggota.
- **Pengguna lain di luar grup** tidak dapat melihat data Anda. Akses dibatasi di server (row-level security), bukan hanya di aplikasi.
- **Operator moderasi kami** dapat membaca pesan yang dilaporkan beserta alasannya, hanya untuk meninjau laporan.
- **Penyedia layanan (pemroses data)**:
  - Supabase Inc. — basis data, autentikasi, dan realtime. Lokasi server: `[REGION SUPABASE, mis. Singapura]`.
  - `[PENYEDIA SMTP]` — pengiriman email kode verifikasi dan atur ulang sandi.
  - Apple Inc. — Masuk dengan Apple dan notifikasi push iOS *(bila tersedia)*.
  - `[Google/Firebase — bila push Android memakai FCM]`.
- **Otoritas** — bila diwajibkan hukum atau perintah pengadilan yang sah.

Kami tidak menjual data pribadi Anda.

## 5. Transfer data ke luar negeri

Data dapat diproses di server di luar Indonesia (`[NEGARA]`). Kami memastikan penyedia menerapkan pelindungan data yang setara atau lebih tinggi sesuai Pasal 56 UU PDP.

## 6. Penyimpanan dan penghapusan

Lama penyimpanan dijelaskan di [Kebijakan Retensi Data](DATA_RETENTION.md). Ringkasnya:

- Anda dapat **menghapus akun** sendiri dari menu Profil. Email, kata sandi, sesi, profil, keanggotaan grup, status baca, dan daftar blokir dihapus seketika.
- Konten yang Anda kirim ke grup (pesan, submission, review, riwayat aktivitas) **tetap ada** untuk anggota lain agar riwayat kerja kelompok tetap utuh, tetapi tidak lagi terhubung dengan akun Anda dan ditampilkan sebagai “Pengguna terhapus”. Isi yang Anda tulis sendiri (mis. nama di dalam teks pesan) tidak otomatis dihapus; hapus atau minta penghapusan sebelum menghapus akun bila perlu.
- Sebelum akun dapat dihapus, Anda harus mengalihkan tugas yang belum selesai dan peran koordinator (bila grup masih punya anggota lain).

## 7. Keamanan

Komunikasi memakai HTTPS. Kata sandi tidak disimpan dalam bentuk teks biasa. Kode undangan disimpan sebagai hash. Akses data dibatasi per keanggotaan grup di server. Token sesi disimpan di penyimpanan aman perangkat. Tidak ada sistem yang sepenuhnya aman; bila terjadi kegagalan pelindungan data yang berdampak pada Anda, kami akan memberi tahu Anda dan otoritas terkait paling lambat 3 × 24 jam sesuai Pasal 46 UU PDP.

## 8. Hak Anda

Sesuai UU PDP, Anda berhak:

- mendapatkan informasi tentang pemrosesan data Anda (kebijakan ini);
- mengakses dan memperoleh salinan data pribadi Anda;
- memperbaiki data yang tidak akurat (nama profil dapat diubah langsung di aplikasi);
- menghapus data pribadi Anda (hapus akun di aplikasi, atau lewat email);
- menarik persetujuan (mis. notifikasi);
- mengajukan keberatan atas pemrosesan tertentu.

Kirim permintaan ke `[EMAIL PRIVASI]` dari email akun Anda. Kami menanggapi paling lambat `[3 × 24 jam / jangka waktu sesuai peraturan]`.

## 9. Anak

Grouply ditujukan bagi pengguna berusia `[USIA MINIMUM, mis. 13]` tahun ke atas. Pengguna di bawah 18 tahun sebaiknya menggunakan aplikasi dengan sepengetahuan orang tua/wali. Bila kami mengetahui ada akun milik anak di bawah usia minimum tanpa persetujuan orang tua/wali, akun tersebut akan dihapus.

## 10. Konten dan perilaku pengguna

Anda dapat melaporkan pesan yang melanggar aturan dan memblokir pengguna lain dari dalam aplikasi. Blokir hanya menyembunyikan pesan pengguna tersebut dari tampilan Anda. Laporan ditinjau sesuai [Prosedur Moderasi](MODERATION_OPERATIONS.md). Pesan yang melanggar dapat diganti dengan penanda moderasi.

## 11. Tautan eksternal

Tautan yang dibagikan dalam submission dibuka di peramban di luar aplikasi. Kami tidak bertanggung jawab atas praktik privasi situs tersebut.

## 12. Perubahan kebijakan

Perubahan material akan diumumkan di aplikasi sebelum berlaku. Tanggal pembaruan tercantum di bagian atas.

## 13. Kontak

`[NAMA PENGENDALI DATA]` — `[EMAIL PRIVASI]` — `[ALAMAT]`
