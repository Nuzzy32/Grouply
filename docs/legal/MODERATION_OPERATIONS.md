# Prosedur Operator Moderasi Grouply

> **DRAF.** Alat yang tersedia saat ini hanya CLI lokal `scripts/moderation_local.py` (localhost). Untuk produksi diperlukan versi yang menunjuk proyek cloud dengan service-role key dari secret manager, bukan dari status Supabase lokal. Belum ada dashboard, notifikasi laporan baru, maupun operator yang bertugas.

## 1. Aturan komunitas (untuk ditampilkan di aplikasi dan store)

Konten berikut dilarang di Grouply:

1. Pelecehan, perundungan, ancaman, atau ujaran kebencian terhadap orang/kelompok.
2. Konten seksual, terutama yang melibatkan anak (selalu dilaporkan ke otoritas).
3. Penyebaran data pribadi orang lain tanpa izin (doxxing).
4. Spam, penipuan, phishing, atau tautan berbahaya.
5. Ajakan kekerasan, menyakiti diri, atau kegiatan ilegal.
6. Peniruan identitas orang lain.

App Store (Guideline 1.2) dan Google Play (kebijakan UGC) mewajibkan aplikasi dengan konten pengguna punya: aturan yang jelas, cara melaporkan konten, cara memblokir pengguna, dan tindak lanjut laporan dalam waktu wajar. Tiga yang pertama sudah ada di aplikasi; poin keempat adalah tujuan prosedur ini.

## 2. Alur laporan (sesuai kode)

- Pengguna melaporkan pesan dari menu pesan, dengan alasan (1–1.000 karakter).
- Server memeriksa keanggotaan, menolak laporan atas pesan sendiri, menyimpan satu laporan per pelapor per pesan, dan membatasi lima laporan baru per menit.
- Laporan berstatus `pending` sampai operator memutuskan `dismissed` atau `removed`.
- `removed` mengganti isi pesan dengan penanda moderasi. Tugas, submission, dan review tidak ikut dihapus.
- Pelapor melihat status laporannya sendiri; catatan operator tidak ditampilkan.
- Keputusan yang sama dapat diulang dengan aman; keputusan berbeda atas laporan yang sudah selesai ditolak.

## 3. Target waktu (usulan)

| Kategori | Contoh | Tinjau dalam |
|---|---|---|
| Darurat | Ancaman nyata, konten seksual anak, menyakiti diri | `[24 jam]`, segera eskalasi |
| Standar | Pelecehan, spam, data pribadi | `[48 jam]` |
| Rendah | Bahasa kasar ringan, salah kategori | `[5 hari kerja]` |

Target ini harus realistis untuk jumlah operator yang ada. Jangan menjanjikan SLA di store bila belum ada yang piket.

## 4. Langkah operator

Lokal (perintah saat ini, lihat `docs/BACKEND_SETUP.md`):

```sh
python3 scripts/moderation_local.py queue
python3 scripts/moderation_local.py review <REPORT_UUID> dismissed --note "Tidak melanggar aturan komunitas"
python3 scripts/moderation_local.py review <REPORT_UUID> removed --note "Pelecehan (aturan 1)"
```

Prosedur per laporan:

1. Ambil antrean (100 laporan `pending` tertua).
2. Baca isi pesan dan alasan. Nilai terhadap aturan di bagian 1. Jangan membuka data lain di luar laporan.
3. Putuskan:
   - **`dismissed`** — tidak melanggar, atau bukti tidak cukup.
   - **`removed`** — melanggar. Catatan wajib menyebut nomor aturan.
4. Bila pelanggaran berat atau berulang dari akun yang sama: catat dan eskalasi ke `[PENANGGUNG JAWAB]`. Penangguhan akun **belum ada** sebagai fitur; sampai ada, gunakan pencabutan sesi + nonaktifkan akun lewat dashboard Supabase, dan dokumentasikan.
5. Konten seksual anak: jangan diunduh/disebarkan, simpan bukti minimal, laporkan ke `[otoritas: mis. Kominfo/Komdigi aduankonten.id, Polri]` dan hubungi `[penasihat hukum]`.

## 5. Kerahasiaan operator

- Output antrean berisi isi pesan dan alasan laporan. Jangan disalin ke chat, tiket publik, atau tangkapan layar yang dibagikan.
- Service-role key hanya diambil dari secret manager saat dibutuhkan, tidak dicetak, tidak disimpan di repo, log, atau dokumen.
- Hanya operator terdaftar (`[DAFTAR NAMA / PERAN]`) yang boleh menjalankan CLI produksi.
- Akses dicatat: siapa, kapan, laporan apa, keputusan apa (`reviewed_at` dan `resolution_note` sudah tersimpan; identitas operator **belum** tercatat, perlu ditambah sebelum produksi).

## 6. Banding

Pengguna yang kontennya dihapus dapat mengajukan banding ke `[EMAIL MODERASI]` dalam `[14]` hari. Banding ditinjau operator berbeda bila memungkinkan. Karena keputusan berbeda atas laporan selesai ditolak server, pemulihan isi pesan saat ini tidak mungkin: isi asli tidak disimpan setelah `removed`.

## 7. Pekerjaan sebelum moderasi produksi siap

- [ ] CLI/endpoint moderasi untuk proyek cloud (secret manager, bukan status lokal).
- [ ] Catat identitas operator pada setiap keputusan.
- [ ] Notifikasi laporan baru ke operator (email/Slack) agar target waktu bisa dipenuhi.
- [ ] Penangguhan/blokir akun di sisi server sebagai tindakan moderasi.
- [ ] Tampilkan aturan komunitas di aplikasi (onboarding atau Profil) dan tautkan dari halaman store.
- [ ] Tetapkan operator piket dan alamat email moderasi.
