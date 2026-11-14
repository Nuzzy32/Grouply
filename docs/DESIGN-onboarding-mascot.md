# Onboarding dengan maskot — rencana animasi

Status: disetujui pengguna 14 November 2026; render dan kode Flutter dibuat 14 November 2026 (lihat bagian 9).

## 1. Ruang lingkup

- Hanya client Flutter. Muncul **sekali sebelum layar Welcome** (login/daftar) pada peluncuran pertama. Flag `grouply.onboardingSeen` disimpan di `shared_preferences` (sudah jadi dependency).
- Empat slide yang bisa digeser dan dilewati. Slide terakhir menuju `_Welcome` yang sudah ada di `lib/app.dart`.
- Maskot: dino ungu bergaya clay 3D. Nama: **Gupy**.

## 2. Alur slide

| # | Pesan | Maskot | Animasi Flutter di sekitarnya |
|---|-------|--------|-------------------------------|
| 1 | "Halo, aku Gupy!" + tagline Grouply | `wave_once` sekali, lalu `idle_loop` | Judul dan teks masuk berurutan |
| 2 | "Bagi tugas, semua jelas siapa ngapain" | `clipboard` diam + melayang pelan | 3 kartu tugas muncul, centangnya tercentang satu per satu |
| 3 | "Kirim hasil, review, dan ngobrol bareng" | `phone` diam + melayang pelan | Gelembung chat muncul satu per satu |
| 4 | "Siap mulai?" + tombol **Mulai** | `point` menunjuk tombol | Tap Mulai → `celebrate_once` + konfeti, lalu masuk Welcome |

Pose `idle_blink`, ekspresi berpikir, dan ekspresi skeptis disimpan untuk empty state atau error nanti, tidak dipakai di onboarding.

## 3. Animasi pra-render (EffectCraft)

Format umum:
- 24 fps, alpha (RGBA), sisi 768 px.
- Diekspor ke animated WebP di `flutter/assets/mascot/anim/`.
- Target ≤ 400 KB per file.
- Tanpa bayangan lantai.

Sumber proyek: `flutter/assets/mascot/_src/mascot.ecproj`.

### `idle_loop` — 3 detik (72 frame), loop mulus, dari layer

| Layer | Gerak | Anchor |
|-------|-------|--------|
| `badan` | Skala Y 100 → 101,5% → 100 (napas), ease sinus | Telapak kaki |
| `kepala` + mata + mulut | Ikut naik ±4 px, rotasi ±1,5° sedikit tertunda dari napas | Leher |
| `ekor` | Rotasi −4° ↔ +4°, ease sinus, fase berbeda dari napas | Pangkal ekor |
| `tangan_kiri` / `tangan_kanan` | Rotasi ±2°, saling berlawanan | Bahu |
| Mata | `mata_ramah`, lalu kedip di frame 40–44 (`mata_tutup`), kembali ke `mata_ramah` | — |
| Mulut | `mulut_senyum` sepanjang loop | — |

Frame 0 harus sama persis dengan frame 72.

### `wave_once` — 1,6 detik (38 frame), tidak loop, dari layer

1. **Frame 0–8:** `tangan_kanan` naik (rotasi sekitar −110° dari bahu) dengan sedikit lewat lalu balik (overshoot). Kepala miring 4° ke arah tangan.
2. **Frame 8–28:** dua kali lambaian ±15°. Mulut berganti ke `mulut_tertawa` pada frame 6–30.
3. **Frame 28–38:** tangan turun, dan semua layer kembali **persis ke frame 0 `idle_loop`**, supaya perpindahan ke idle tidak terlihat.

### `celebrate_once` — 1,2 detik (29 frame), tidak loop, dari `celebrate.png`

1. **Antisipasi (4 frame):** squash, skala 106% × 90%, anchor di kaki.
2. **Lompat (6 frame):** naik 120 px dengan stretch 96% × 105%.
3. **Puncak:** tahan 2 frame.
4. **Jatuh (5 frame):** stretch ringan.
5. **Mendarat (4 frame):** squash 108% × 92%.
6. **Settle:** kembali ke 100%.

### Pose diam

`clipboard`, `phone`, dan `point`:
- Diperkecil ke 768 px WebP statis di `flutter/assets/mascot/static/`.
- Gerakan melayangnya dibuat di Flutter, tidak dirender.

## 4. Motion di Flutter

Pedoman: animasi UI aplikasi tetap 150–300 ms, seperti yang sudah dipakai (paling sering 200 ms). Momen maskot boleh 450–1200 ms karena onboarding hanya dilihat sekali dan memang dimaksudkan menyenangkan.

| Elemen | Animasi |
|--------|---------|
| Ganti slide (`PageView`) | Maskot keluar: opacity → 0, skala 0,96, 180 ms. Maskot masuk: opacity 0 → 1, naik 12 px → 0, skala 0,94 → 1, 450 ms `easeOutBack` ringan. Keluar dibuat lebih halus daripada masuk. |
| Judul dan teks | Opacity + naik 8 px, 300 ms `easeOutCubic`. Teks muncul 60 ms setelah judul. |
| Melayang (pose diam) | Naik-turun ±6 px, 3 detik, sinus, berulang |
| Bayangan lantai | Elips blur di bawah kaki. Menyempit 90% saat maskot naik dan saat `celebrate_once` (waktunya disamakan dengan render). |
| Slide 2: kartu tugas | Masuk berurutan tiap 120 ms. Centang (scale 0,6 → 1 + warna mint) berurutan tiap 250 ms setelah kartu terakhir. |
| Slide 3: gelembung chat | Scale 0,8 → 1 + opacity, berurutan tiap 180 ms, kiri-kanan bergantian |
| Slide 4: konfeti | 18 partikel warna mint/butter/lilac, 900 ms, hanya sekali saat tap Mulai |
| Indikator titik | Lebar 8 → 20 px, 200 ms |
| Tombol | Saat ditekan: skala 0,97 (`GLTap` yang sudah ada). Tombol **Lewati** di kanan atas, **Lanjut** di bawah. |
| Haptic | `selectionClick` saat ganti slide, `lightImpact` saat tap Mulai |

## 5. Aksesibilitas

- Jika `MediaQuery.disableAnimationsOf(context)` aktif:
  - Tampilkan PNG statis (frame 0).
  - Matikan efek melayang, konfeti, dan efek berurutan.
  - Ganti slide hanya crossfade.
- Maskot dianggap dekorasi, jadi dibungkus `ExcludeSemantics`. Makna disampaikan oleh teks.
- Loop hanya berjalan di slide yang sedang tampil, dan berhenti saat app ke background.
- Layout tetap bisa di-scroll saat ukuran teks diperbesar. Tombol Lewati dan Lanjut minimal 44 pt.

## 6. Performa

- `precacheImage` untuk slide berikutnya.
- `cacheWidth` sesuai ukuran tampil.
- Animated WebP diputar dengan `Image.asset` (tanpa package baru).
- File sumber (pose 1254 px dan layer 2048 px) **tidak** didaftarkan di `pubspec.yaml`. Yang dibundel hanya `anim/` dan `static/`. Target total onboarding ≤ 2 MB.

## 7. Implementasi

- File baru `flutter/lib/features/onboarding_screen.dart`.
- `lib/app.dart` menampilkan onboarding sebelum `_Welcome` jika flag belum ada.
- Tes widget:
  - Muncul sekali.
  - Lewati menyimpan flag.
  - Mode reduced motion memakai gambar statis.

## 8. Urutan kerja

1. Render `idle_loop`, `wave_once`, `celebrate_once` di EffectCraft, lalu cek frame (celah leher, potongan, sambungan loop).
2. Optimalkan pose diam ke WebP 768 px.
3. Buat layar onboarding Flutter beserta flag.
4. Jalankan tes widget, lalu cek di simulator, termasuk mode reduced motion.


## 9. Catatan implementasi (14 November 2026)

Render ulang: `zsh flutter/assets/mascot/_src/build.sh` (EffectCraft CLI → PNG 768 px di `_render/` → WebP). Gerak ditulis sebagai ekspresi di `_src/mascot.ecproj`, jadi mengganti file di `layers/` atau `celebrate.png` dengan nama sama sudah cukup.

Penyesuaian dari rencana:
- Kepala naik ±15 px (pada 2048), tidak ±4 px, agar ikut leher yang memanjang 1,5%. Tertunda 0,12 detik, rotasi ±1,5°.
- `wave_once`: dengan sudut −110°, tangan tertutup kepala. Tangan diangkat sekitar 80° (lambaian 68–95°), dan salinan `tangan_kanan` di atas kepala muncul pada frame 3–33. Frame 0 dan 37 identik piksel dengan frame 0 `idle_loop`.
- Ukuran: dengan alpha lossless, idle 24 fps berukuran 1,7 MB. Karena itu alpha dikuantisasi ke 16 level, dan `idle_loop.webp` diencode 12 fps (gerak < 1 px/frame; PNG sumber tetap 24 fps). `wave_once` dan `celebrate_once` tetap 24 fps dengan loop count 1.
- Pose `point` menunjuk ke kiri, bukan ke tombol di bawah. Perlu pose baru kalau ingin menunjuk tombol.
- Pindah dari wave ke idle memakai `frameBuilder` (frame ke-38), bukan timer.
- Reduce Motion di iOS dikirim Flutter sebagai `accessibilityFeatures.reduceMotion`, bukan `MediaQuery.disableAnimations`, jadi `reduceMotionOf()` memeriksa keduanya. Sudah dicek di simulator iPhone 17. Kalau setelan diubah saat onboarding sedang terbuka, perubahannya baru dipakai pada build berikutnya.
- Total yang dibundel 1,53 MB (`anim/` 1,21 MB + `static/` 0,32 MB). `_render/` (37 MB) tidak dibundel; sebaiknya di-ignore Git.

## 10. Revisi: rig live dan penempatan di aplikasi (14 November 2026)

Masukan pengguna: animasi pra-render terasa kaku. Penyebabnya: 24 fps (idle 12 fps) di layar 60–120 Hz, semua gerak memakai sinus dengan periode sama, kedipan tepat tiap 3 detik, dan lambaian yang berhenti di setiap keyframe.

Solusi: Gupy digerakkan langsung di Flutter (`lib/ui/gupy.dart`) dari layer `assets/mascot/rig/` (crop 50%, total 177 KB; sebelumnya WebP animasi 1,2 MB).
- `GupyRig`: napas (3,2 dtk) dengan skala badan yang menjaga volume, goyang badan (5,3 dtk), kepala dan tangan menyusul sedikit tertunda, ekor dengan dua harmonik, kedipan acak 2,4–5,6 dtk (20% kedip ganda). Lambaian memakai spline Hermite, jadi tidak berhenti di setiap key, ditambah badan condong, kepala miring, dan mulut tertawa. Tap untuk melambai.
- `GupyPose`: pose diam melayang ±6 pt, bernapas dari kaki, dan bergoyang 0,6°.
- `GupyJump`: antisipasi, stretch, lompatan parabola dengan sedikit miring, squash saat mendarat, lalu settle. Bayangan menyempit sesuai tinggi lompatan.
- Reduce Motion (iOS `reduceMotion` / Android `disableAnimations`): rig diam di pose netral, tanpa ticker.
- `anim/*.webp` (EffectCraft) tidak lagi dibundel. File itu dan `_src/build.sh` disimpan untuk web/video.

Penempatan di aplikasi dipilih berdasarkan emosi momennya, bukan dipasang di semua layar:

| Tempat | Momen | Gupy | Alasan |
|---|---|---|---|
| Onboarding | Pertama buka app | Lambai lalu idle, pose, lompat | Perkenalan |
| Grup, kosong ("Belum ada grup") | Akun baru, langkah pertama | Melambai sekali, lalu diam (tap = lambai) | Menyambut dan mengarahkan ke Buat/Gabung grup |
| Tugas Saya, kosong ("Belum ada tugas") | Menunggu dibagi tugas | Diam dan tenang (tap = lambai) | Menenangkan, tidak mendesak |
| Tugas Saya, semua tugas selesai | Pencapaian | Pose rayakan di kartu mint (tap = lompat) | Penguat positif |

Sengaja tidak dipasang di: akses ditolak, error, form, chat, dashboard/fitur organisasi berbayar, dan toast. Konteks itu serius atau sering dilihat, sehingga maskot akan mengganggu. Di empty state Gupy tidak bergerak terus; hanya sekali saat muncul atau saat di-tap. Ikon Android memakai kepala Gupy (adaptive icon, latar #BEF5D2).

## 11. Aset layer tambahan (14 November 2026)

- **Lengan dua ruas** (`lengan_atas_*` + `lengan_bawah_*`, siku kanan (700,1175), siku kiri (1301,1198)): lambaian ditekuk di siku, lengan bawah sedikit tertinggal saat idle.
- **Ekor tiga ruas** (`ekor_pangkal/tengah/ujung`, sendi (1260,1550) → (1392,1513) → (1597,1386)): gelombang merambat dari pangkal ke ujung, sudut tiap ruas ditambahkan ke ruas sebelumnya.
- **Kedip tiga tahap** (`mata_setengah`) dan **mulut setengah tertawa** (senyum → setengah → tertawa saat lambaian naik).
- **Rayakan berlapis** (`layers/celebrate/*` → `rig/cel_*.webp`): lompatan tetap memakai squash/stretch yang sama, ditambah ayunan lengan, kaki menekuk hanya saat di udara, serta ekor dan kepala yang terlambat (follow-through). Urutan gambar: ekor, badan, kaki, tangan kiri, kepala, tangan kanan. `rig/celebrate.webp` tidak dipakai lagi.
- Pose diam baru: `point_kanan_bawah` (slide terakhir onboarding, mengarah ke tombol Mulai) dan `santai` (Tugas Saya kosong).
- Web memakai layer dan kurva yang sama (`web/src/lib/gupy/rig.ts`), disalin oleh langkah 5 `_src/build.sh`.

## 12. Revisi onboarding: satu layar sambutan + kode undangan (14 November 2026)

- Carousel 4 slide (`onboarding_screen.dart`, flag `grouply.onboardingSeen`) dihapus. Alasannya: riset NN/g menunjukkan tutorial bergaya deck tidak menaikkan keberhasilan, dan Material menyarankan *quickstart* untuk konsep yang sudah familiar.
- Layar Welcome berisi:
  - Gupy melambai (rig idle).
  - Kartu **Punya kode undangan?** dengan `GupyPose('undangan')`; amplopnya berayun di atas badan.
  - Tombol Masuk / Daftar.
- Alur kode undangan: kode (tautan `/invite/` dipotong jadi kodenya) disimpan di memori, lalu form daftar langsung terbuka. Setelah masuk, `joinGroup` dijalankan dan layar grup dibuka. Kalau gagal, dialog meminta kode baru ke koordinator.
- Tidak ada pertanyaan peran atau kampus: peran sudah ditentukan oleh tindakan pengguna (buat grup → koordinator, gabung → anggota).
- `GupyHint` (Gupy mengintip di atas kartu mint) ditampilkan sekali per id dan diingat di SharedPreferences. Saat ini hanya dipakai di detail tugas (`task-flow`) untuk menjelaskan alur kerjakan → kirim hasil → review.
