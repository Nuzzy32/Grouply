# PRD — Organization Plan (fitur berbayar)

Status: **draf rencana, belum disetujui, belum ada kode.** Client: Flutter saja. Backend: Supabase yang sama.

## 1. Ringkasan

Organization Plan adalah paket berbayar Grouply untuk organisasi mahasiswa (BEM, HIMA, UKM, kepanitiaan). Paket gratis tetap untuk kelompok tugas kuliah sampai 8 orang. Paket berbayar menambah **struktur**: organisasi, divisi, jabatan, proker, rapat, persetujuan, dan arsip per periode.

## 2. Latar belakang

- BMC sudah memasukkan "Organization & Team Plans" sebagai sumber pendapatan, tetapi aplikasi belum punya fiturnya.
- Aplikasi sekarang dibatasi 8 anggota per grup dengan satu coordinator. Organisasi 30–150 orang tidak muat.
- Bagian inti sudah ada dan bisa dipakai ulang: grup, proyek, tugas, kirim hasil, review, chat, Group Pulse, pengingat, penanda "Tanpa kabar".

## 3. Tujuan

Organisasi bisa menjalankan proker dari pembagian tugas sampai laporan di satu aplikasi, dan bersedia membayar untuk itu.

Target uji awal (eksploratif, bukan janji):

| Ukuran | Target |
|---|---|
| Pilot | 3 organisasi memakai selama satu proker penuh |
| Kemauan bayar | Minimal 2 dari 3 menyatakan mau bayar dari kas |
| Pemakaian | Minimal 60% anggota membuka aplikasi tiap minggu |
| Pemantauan | BPH membuka Dashboard Organisasi minimal 1 kali seminggu |

## 4. Segmen

1. **Pengurus inti organisasi tetap** (Ketua, Sekretaris, Bendahara BEM/HIMA/UKM). Mereka harus tahu kondisi semua divisi tanpa menagih satu per satu. Merekalah yang memutuskan membeli.
2. **Ketua pelaksana kepanitiaan** (seminar, lomba, makrab; 1–3 bulan). Tim dibentuk cepat, lintas divisi, dengan tenggat keras.

Kadiv dan staf adalah pemakai harian, bukan pembeli.

Batasan: uang berasal dari kas organisasi, kepengurusan berganti tiap tahun, hampir semua anggota memakai HP.

## 5. Nilai yang ditawarkan

| | Pengurus inti | Ketua pelaksana |
|---|---|---|
| **Yang ingin dicapai** | Semua proker jalan dan LPJ beres di akhir periode | Acara terlaksana tepat waktu |
| **Cara sekarang** | Banyak grup WA, Google Sheets, menagih Kadiv satu per satu | Grup WA per sie, daftar tugas di pesan tersemat |
| **Sakitnya** | Tidak tahu divisi mana yang macet sampai terlambat; data hilang saat ganti pengurus | Tugas tumpang tindih, persetujuan dana tertahan tanpa ada yang tahu |
| **Cara kita** | Dashboard semua divisi, persetujuan berjenjang, arsip periode | Kepanitiaan lintas divisi, template acara, rapat jadi tugas |
| **Hasilnya** | Masalah terlihat lebih awal; pengurus baru tidak mulai dari nol | Semua sie tahu tugas dan tenggatnya |
| **Alternatif** | WA + Sheets, Notion, Trello | Sama |

Kenapa memilih kita: dibuat untuk cara kerja organisasi kampus (divisi, proker, LPJ), berbahasa Indonesia, nyaman di HP, dan sudah punya alur kirim hasil + review.

**Pernyataan nilai:** Grouply membantu pengurus organisasi mahasiswa melihat dan menuntaskan semua proker di satu tempat, tanpa menagih lewat WhatsApp dan tanpa kehilangan data saat ganti kepengurusan.

## 6. Fitur

### Tahap 1 — Fondasi (wajib ada supaya bisa dijual)

| ID | Fitur | Yang didapat pengguna |
|---|---|---|
| ORG-01 | **Workspace Organisasi** | Satu organisasi berisi banyak divisi. Divisi memakai "grup" yang sudah ada, jadi proyek, tugas, dan chat langsung berfungsi |
| ORG-02 | **Kapasitas besar** | Anggota organisasi dan anggota per divisi boleh lebih dari 8 (angka pasti menunggu validasi) |
| ORG-03 | **Jabatan dan hak akses** | Ketua, BPH, Kadiv, Staf, dan Pembina (hanya melihat). Kadiv mengatur divisinya; BPH melihat semua |
| ORG-04 | **Undangan per divisi** | Satu tautan per divisi untuk memasukkan banyak anggota sekaligus, misalnya hasil oprec |
| ORG-05 | **Dashboard Organisasi** | Satu layar untuk BPH: progres tiap proker, yang terlambat, yang "Tanpa kabar", dan review yang tertahan |
| ORG-06 | **Status langganan** | Aktif atau berakhir. Saat berakhir, organisasi kembali ke batas gratis: data dan pekerjaan berjalan tetap bisa dipakai, tetapi Dashboard, divisi baru, dan anggota di atas 8 per divisi terkunci (keputusan 12 November 2026) |

### Tahap 2 — Kerja harian organisasi

| ID | Fitur | Yang didapat pengguna |
|---|---|---|
| ORG-07 | **Kepanitiaan lintas divisi** | Proker dengan anggota dari beberapa divisi, dibagi per sie |
| ORG-08 | **Persetujuan berjenjang** | Proposal atau anggaran lewat urutan penyetuju (misalnya Kadiv → Bendahara → Ketua). Terlihat sedang tertahan di siapa |
| ORG-09 | **Rapat** | Jadwal, agenda, notulen, daftar hadir. Keputusan rapat langsung dijadikan tugas |
| ORG-10 | **Pengumuman** | Pengumuman ke organisasi atau divisi dengan tombol "Sudah baca" dan daftar yang belum |
| ORG-11 | **Pengingat dari server** | Notifikasi push untuk tugas, rapat, dan persetujuan yang menunggu, walau aplikasi tertutup |

### Tahap 3 — Alasan berlangganan tiap tahun

| ID | Fitur | Yang didapat pengguna |
|---|---|---|
| ORG-12 | **Template proker** | Kerangka siap pakai (seminar, lomba, makrab, oprec). Proker sendiri bisa disimpan jadi template |
| ORG-13 | **Arsip periode dan serah terima** | Tutup periode, ganti pengurus, proker lama jadi arsip hanya-baca |
| ORG-14 | **Rekap untuk LPJ** | Ekspor PDF/CSV per proker: tugas, pelaksana, status, tautan hasil, tanggal |
| ORG-15 | **Lampiran file** | Unggah foto/PDF dengan kuota penyimpanan |

### Gratis vs berbayar

| | Gratis | Organization Plan |
|---|---|---|
| Grup | Maks 8 anggota, berdiri sendiri | Divisi di dalam organisasi, kapasitas besar |
| Peran | Coordinator dan anggota | Ketua, BPH, Kadiv, Staf, Pembina |
| Pantauan | Group Pulse per proyek | Dashboard semua divisi |
| Lainnya | Tugas, review, chat, pengingat | Persetujuan, rapat, pengumuman, arsip, rekap |

### Tidak dikerjakan

Rapor atau penilaian staf, AI, pesan pribadi (DM), pembukuan kas, pembuat surat, versi web, dan pembayaran otomatis di dalam aplikasi untuk versi pertama.

## 7. Catatan teknis

- Tambahan utama: tabel organisasi, keanggotaan organisasi dengan jabatan, dan kolom organisasi pada grup. Divisi tetap grup biasa.
- Batas 8 anggota sekarang ditulis langsung di RPC (`group_full`). Perlu diganti jadi batas menurut paket.
- Hak akses jabatan harus diperiksa di RLS/RPC, bukan hanya di aplikasi.
- `grouply_snapshot` sekarang mengirim semua data sekaligus. Untuk organisasi besar perlu dibatasi ke divisi sendiri, dan dashboard memakai RPC ringkasan terpisah.
- Versi pertama: langganan diaktifkan manual oleh operator setelah transfer. Tanpa payment gateway.
- ORG-11 butuh FCM/APNs, yang belum tersambung.

## 8. Asumsi dan pertanyaan terbuka

- **Belum ada wawancara dengan pengurus organisasi.** Semua "sakit" di bagian 5 adalah dugaan. Validasi ke 5–8 pengurus (ketua dan bendahara) sebelum membangun Tahap 2.
- Harga dan bentuknya (per periode? per jumlah anggota?) belum ditentukan.
- Berapa kapasitas yang wajar per organisasi dan per divisi?
- Aturan App Store/Play Store soal menjual fitur digital di luar pembelian dalam aplikasi perlu dicek sebelum rilis.
- Apakah BPH butuh versi web? Sekarang web di luar scope.
- PRD v1.3 melarang pricing dan attachment. Paket ini adalah **perubahan scope** yang harus dicatat di `docs/PRD.md` dan `CLAUDE.md` setelah disetujui.

## 9. Urutan rilis

1. **Tahap 1** dulu, dipakai pilot oleh 1–2 organisasi secara gratis. Ini bagian terbesar karena menyentuh hak akses dan cara data dimuat.
2. **Tahap 2** dipilih berdasarkan hasil pilot. ORG-08 dan ORG-09 adalah kandidat terkuat.
3. **Tahap 3** menjelang akhir periode kepengurusan pilot, saat serah terima dan LPJ benar-benar dibutuhkan.
