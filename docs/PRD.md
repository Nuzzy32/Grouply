# GROUPLY: Product Requirements Document (PRD)

> **Versi:** 1.3 · **Tanggal:** 16 Oktober 2026 · **Status:** Spesifikasi MVP; implementasi native demo tersedia sebagai demo lokal  
> **Platform:** iOS 17+ native (Swift / SwiftUI) · **Backend:** Supabase  
> **Dokumen terkait:** [User Flow](USER_FLOW.md) · [Design System](DESIGN_SYSTEM.md) · [Architecture](ARCHITECTURE.md) · [Database](DATABASE_SCHEMA.md) · [Roadmap](ROADMAP.md)

## Keputusan v1.3 yang telah direkonsiliasi

**Scope MVP yang disetujui:** navigasi 4 tab (Beranda · Grup · Chat · Tugas Saya), Group Management, Member Management, Project Management, Task Management termasuk **Edit Tugas**, **Group Chat**, Task Discussion, Work Submission, Peer Review, Group Pulse, Account Settings, Report & Block. Group Chat realtime dan Task Discussion termasuk P0; Task Discussion memakai fetch + pull to refresh + foreground/push.

Aturan bisnis baru:
- **Edit Tugas** hanya koordinator. Field: judul (wajib, ≤120), deskripsi (≤2000), deadline (peringatan bila melewati deadline proyek, input tidak diubah diam-diam), reviewer (anggota aktif, ≠ pelaksana). Diizinkan pada *Belum dimulai / Sedang dikerjakan / Perlu revisi*; dikunci pada *Menunggu review* dan *Selesai*; ditolak bila proyek diarsipkan atau selesai.
- **Proyek Selesai** hanya bisa ditandai bila ada ≥1 tugas dan semuanya *Selesai*. Proyek selesai bersifat hanya-baca untuk tugas dan diskusinya (tidak bisa buat/edit/alihkan/kirim/review/komentar). Pembukaan kembali harus eksplisit lewat "Buka Kembali Proyek" + konfirmasi; tidak pernah otomatis.
- **Arsip** hanya koordinator, dengan konfirmasi. Proyek arsip hanya-baca (termasuk diskusi tugas), tetap bisa diakses lewat filter Arsip, dan **memulihkan status sebelumnya** (Aktif → Arsip → Aktif; Selesai → Arsip → Selesai).
- **Pengalihan tugas**: boleh pada Belum dimulai/Sedang dikerjakan; Perlu revisi dengan konfirmasi (riwayat dan penulis lama tetap); **tidak boleh** saat Menunggu review, Selesai, proyek selesai, atau arsip. Bila pelaksana baru adalah reviewer, koordinator wajib memilih reviewer lain.
- **Undangan** memiliki createdAt, expiresAt (7 hari), status (active/revoked), maxUses, useCount. Validasi berdasarkan perbandingan waktu, bukan status manual.
- Reviewer hanya bisa menyetujui/meminta revisi bila ditunjuk, tugas *Menunggu review*, kiriman masih pending, bukan penulis kiriman, dan proyek Aktif. Pelaksana hanya bisa mengirim bila ditugaskan, status mengizinkan, dan proyek Aktif.


## Status implementasi dan batas verifikasi

Per 17 Oktober 2026 tersedia demo dan **server Supabase lokal** dengan Auth, RLS, RPC transactional serta SwiftUI async. Workflow tiga akun dan Group Chat Realtime/unread/reconnect/revoke membership teruji lintas client native pada satu simulator + localhost. Milestone E menambahkan antrean laporan/CLI operator lokal, block lintas sesi, dan hapus akun password server dengan histori bersama dipertahankan tanpa referensi identitas. Deployment cloud, provider/pencabutan token Apple, dua perangkat fisik/jaringan nyata, APNs, Universal Links, moderasi production dan kebijakan retensi belum diverifikasi/tersedia. Lihat [Backend Setup](BACKEND_SETUP.md); bagian lain mendeskripsikan target produk P0.


## 1. Ringkasan produk

**GROUPLY** membantu kelompok mahasiswa membagi tugas, membahas pekerjaan, mengirim bukti hasil, dan menyetujui revisi di satu tempat. Tagline: **Make group work actually work.**

**Job to be done:** "Ketika mengerjakan tugas kelompok, gue mau tahu siapa mengerjakan apa, apa yang sudah dikirim, mana yang menunggu review, dan di mana pembahasannya, tanpa harus menggali chat yang panjang."

GROUPLY **tidak** mencoba menggantikan WhatsApp, Google Docs, atau aplikasi presentasi. Ia menjadi *coordination layer* di atas alat tersebut: tautan dokumen dibagikan lewat task, status pekerjaan dikelola di GROUPLY, dan obrolan umum kelompok tersedia melalui Group Chat. WhatsApp tetap didukung lewat Share Sheet.

### Kenapa bukan alat yang sudah ada?

| Alternatif | Yang sudah bisa | Yang kurang untuk kasus ini |
|---|---|---|
| WhatsApp group | Ngobrol cepat, semua orang sudah pakai | Status kerja tenggelam di chat, hasil kerja sulit dilacak |
| Notion / Trello | Board task fleksibel | Setup berat untuk kelompok sementara, tidak ada alur submit dan review bawaan |
| Google Sheets | Gratis, mudah dibagikan | Serba manual, tanpa notifikasi atau bukti hasil per task |

**Diferensiasi GROUPLY:** alur **submit → review → approved / revisi** yang tercatat per task, dengan reviewer yang jelas dan notifikasi ke orang yang harus bertindak. Jika pilot menunjukkan alur ini jarang dipakai, GROUPLY tidak punya alasan kuat untuk eksis di samping WhatsApp + Sheets. Ini hal paling penting untuk divalidasi.

### Keputusan platform

**iPhone-only adalah keputusan sadar untuk MVP**, bukan asumsi bahwa semua mahasiswa memakai iPhone. Konsekuensinya diterima: kelompok yang punya anggota non-iOS belum bisa memakai GROUPLY secara penuh. Saat rekrutmen pilot, catat berapa kelompok yang tidak bisa ikut karena alasan ini sebagai data keputusan setelah MVP.

### Hipotesis yang perlu divalidasi

1. Kelompok mengalami kebingungan tentang penanggung jawab dan status pekerjaan.
2. Diskusi yang dikaitkan ke task akan mengurangi pencarian pesan lama.
3. Review satu tap lebih berguna daripada klaim "sudah selesai" tanpa hasil.
4. Mahasiswa bersedia membuka aplikasi kedua selain WhatsApp ketika ada tugas aktif.

Ini **hipotesis**, bukan fakta pasar. Uji bersama 3–5 kelompok iPhone sebelum menambah fitur besar.

## 2. Pengguna dan konteks

| Persona | Masalah dominan | Kebutuhan utama |
|---|---|---|
| **Coordinator** | Harus menagih progres dan memeriksa hasil | Membuat proyek, assign, pantau, review |
| **Member** | Tidak jelas harus mengerjakan apa dan kapan | Task pribadi, diskusi, submit, tindak lanjuti revisi |
| **Reviewer** | Hasil dikirim di chat dan mudah terlewat | Review yang terkait submission yang tepat |

**Target MVP:** mahasiswa, kelompok **2–8 anggota**, satu atau beberapa proyek akademik per kelompok, koneksi internet tersedia ketika mengubah data, seluruh peserta memakai iPhone. **Bukan target awal:** organisasi besar, kelas guru, tim enterprise, Android, web.

## 3. Definisi objek

- **Group:** kelompok anggota tetap, mempunyai satu coordinator.
- **Project:** tugas kuliah/proyek dalam group, mempunyai deadline dan status.
- **Task:** unit pekerjaan, **satu assignee** dan **satu reviewer berbeda** untuk MVP.
- **Submission:** versi hasil yang diajukan assignee, berisi catatan dan URL hasil.
- **Review:** keputusan atas satu submission: `approved` atau `changes_requested`.
- **Task Discussion:** satu thread komentar kontekstual per task, dibuat saat pertama dibuka; P0 memakai fetch + pull to refresh + foreground/push.
- **Notification:** push ke perangkat untuk event yang butuh tindakan (assign, submit, keputusan review, komentar baru), plus pengingat deadline lokal di perangkat.
- **Group Chat (P0):** satu percakapan utama per group, dibuat atomik bersama group; tab Chat dan unread badge termasuk MVP.
- **Activity Event:** riwayat perubahan terstruktur, termasuk pesan sistem terkait task.

## 4. Tujuan, non-goals, dan ukuran keberhasilan

### Goals

- Satu kelompok bisa menyelesaikan alur **create group → invite → create project → assign task → discuss → submit → review → done**.
- Anggota selalu melihat assignee, deadline, status dan submission terbaru.
- Orang yang harus bertindak (reviewer, assignee) mendapat push notification tanpa perlu membuka aplikasi lebih dulu.
- Pengguna hanya bisa membaca data group yang diikutinya.
- UI mengutamakan keterbacaan meskipun visualnya playful dan modern.

### Tidak masuk MVP

AI, scoring kontribusi anggota, leaderboard, streak, DM personal, reaction emoji, typing indicator, read receipts, mention, edit/delete pesan, upload media/file di chat, pengeditan dokumen bersama, calendar sync, offline write queue, Android/web, dark theme khusus, analitik perilaku individual. Item-item tersebut **tidak boleh** diam-diam ditambahkan ketika pengerjaan.

### Success criteria uji awal (target eksploratif)

| Ukuran | Target evaluasi |
|---|---|
| Aktivasi | ≥70% penguji berhasil membuat/join group tanpa bantuan |
| Task clarity | ≥80% penguji menemukan task sendiri dalam ≤15 detik |
| End-to-end | ≥5 proyek dari ≥3 kelompok menuntaskan submit + review |
| Chat usability | ≥80% penguji dapat menemukan diskusi task tertentu |
| Review tidak nyangkut | Setiap task `in_review` lebih dari 48 jam terlihat oleh coordinator |
| Notifikasi | Reviewer dapat membuka review langsung dari push dalam ≤2 tap |
| Persepsi nilai | Mayoritas kelompok uji bersedia menggunakannya untuk tugas berikutnya |
| Keandalan | Tidak ada kebocoran lintas group atau kehilangan pesan yang terkonfirmasi |

**Catatan:** target ini bukan klaim retensi, proyeksi revenue, atau statistik pasar.

## 5. Scope MVP dan prioritas

**P0** harus ada sebelum TestFlight. **P1** ditambahkan setelah workflow stabil. **P2** hanya setelah validasi.

| ID | Fitur | Prioritas | Hasil yang harus tersedia |
|---|---|---|---|
| AUTH-01 | Sign in with Apple dan sesi | P0 | Login, logout, error, profil nama tampilan |
| GRP-01 | Group, membership, invite | P0 | Create/join lewat token undangan, revoke/expiry, anggota 2–8 |
| PRJ-01 | Project | P0 | Create, list, detail, deadline, complete/archive |
| TSK-01 | Task assignment | P0 | Title, description, assignee, reviewer, deadline, status, reassign oleh coordinator |
| SUB-01 | Work submission | P0 | Catatan + URL; revisi berurutan; waktu dan penulis |
| REV-01 | Peer approval | P0 | Approve / request changes + alasan; tidak boleh self-approve |
| DISC-01 | Task Discussion | P0 | Komentar teks/URL per task; fetch, pagination, pull to refresh dan refresh foreground/push |
| DISC-02 | System events di thread task | P0 | Submit/approve/revision muncul sebagai item sistem di Task Discussion terkait |
| DISC-03 | Sending / sent / failed | P0 | Retry aman tanpa duplikat komentar |
| NOTIF-01 | Push notification | P0 | Assign/reassign, submission baru (ke reviewer), keputusan review (ke assignee), komentar baru (ke assignee & reviewer) |
| NOTIF-02 | Pengingat deadline lokal | P0 | Local notification H-1 untuk task milik sendiri, dijadwalkan ulang saat app dibuka |
| SHARE-01 | Bagikan ke WhatsApp | P0 | iOS Share Sheet berisi ringkasan event + Universal Link ke task |
| SAFE-01 | Report & block | P0 (sebelum TestFlight eksternal) | Report komentar/user, block user, kanal laporan ke pengembang |
| PULSE-01 | Group Pulse sederhana | P0 | Ringkasan hitungan status task, progress %, deadline, penanda review pending |
| ACT-01 | Activity history | P1 | Timeline event penting per proyek |
| CHAT-01 | Group Chat realtime | P0 | Tab Chat, room group, Realtime Postgres Changes |
| CHAT-05 | Unread count | P0 | Badge per room |
| CHAT-06 | Reply, attachment, reactions | P2 | Sesudah pemakaian chat inti terbukti |

### Aturan penerimaan fitur kritis

**Group & invite**
- Pembuat group menjadi coordinator. Coordinator dapat mengundang dan menghapus anggota.
- Tautan/kode undangan punya masa aktif, batas penggunaan, dan dapat dicabut.
- Join dilakukan hanya oleh pengguna yang login; 8 anggota adalah batas MVP.
- Coordinator tidak boleh keluar sebelum menunjuk pengganti; group yang tersisa tanpa anggota ditutup lewat prosedur eksplisit.

**Task**
- Membership aktif diverifikasi pada setiap aksi, termasuk baca, edit, start, submit, review, reassign dan retry; peran/penunjukan saja tidak cukup.
- Task P0 membutuhkan judul, assignee, reviewer yang **berbeda**, dan deadline.
- Assignee/reviewer wajib anggota group yang sama; backend memvalidasi ulang.
- Coordinator bisa mengganti assignee atau reviewer lewat `reassign_task`; semua perubahan dicatat sebagai event dan memicu push ke orang yang baru ditunjuk.
- Edit dan pengalihan assignee maupun reviewer dikunci saat `in_review` dan `done`, serta saat proyek selesai/arsip.
- Pengalihan di `needs_revision` memerlukan konfirmasi dan mempertahankan status `needs_revision`; penulis dan riwayat submission lama tidak berubah. Pengalihan di `todo`/`in_progress` kembali ke `todo`.
- Task `in_review` lebih dari 48 jam ditandai **Review pending** di Home coordinator, supaya ia bisa mengingatkan reviewer; pengalihan tetap terkunci selama review.
- Ketika tidak ada task, progress menampilkan `Belum ada task`, bukan 100%.

**Submission dan review**
- Hasil kerja berupa catatan (wajib) dan 0 sampai 5 tautan `https://` (bukan upload berkas). Scheme lain seperti `http:`, `javascript:`, atau `file:` ditolak di server, bukan hanya di client.
- Submission selalu milik satu versi (`revision_number`) dan tidak diubah diam-diam setelah dikirim.
- Reviewer melihat submission aktif, memilih **Approve** atau **Request Changes**; permintaan revisi wajib ada catatan.
- Keputusan review dan perubahan status berlangsung dalam **satu transaksi** backend.
- Reviewer tidak dapat approve submission yang ia kirim sendiri, sekalipun ia coordinator.

**Task Discussion**
- Task Discussion dibuat saat pertama kali dibuka lewat `ensure_task_chat_room`.
- Anggota aktif group dapat membaca dan menulis komentar pada task di group miliknya.
- MVP hanya teks UTF-8 hingga **2.000 karakter**, termasuk URL sebagai teks. Link hanya dibuka melalui tindakan pengguna.
- Komentar memiliki ID dari client untuk retry idempoten; UI memisahkan `sending`, `sent`, dan `failed`.
- Riwayat diambil dengan pagination (contoh: 30 komentar per halaman) dan urutan deterministik `(created_at, id)`.
- Group Chat menargetkan Realtime; Task Discussion memakai fetch saat dibuka, foreground, pull to refresh, atau push terkait.
- Pesan sistem hanya boleh dibuat oleh operasi backend terpercaya dan muncul di thread task terkait.

**Notifikasi**
- Izin push diminta saat pertama kali relevan (setelah join group atau mendapat task), dengan layar penjelasan singkat sebelum dialog sistem iOS. Tidak diminta di layar pertama.
- Isi push hanya jenis event dan judul task. Isi komentar dan catatan submission **tidak** dikirim karena push tampil di lock screen.
- Menolak izin push tidak memblokir app.
- Token perangkat dicabut saat logout.

**Safety**
- Setiap komentar dan profil anggota punya aksi **Report**; laporan masuk ke tabel moderasi dan diteruskan ke email pengembang.
- **Block** menyembunyikan komentar user yang diblok bagi pemblokir; tidak mengubah keanggotaan group atau penugasan task.
- Coordinator tetap dapat remove member.

## 6. Model status

```text
todo → in_progress → in_review → done
                      │
                      └─→ needs_revision → in_progress
```

- **Assignee:** `todo → in_progress`, `in_progress → in_review` melalui submission, `needs_revision → in_progress`.
- **Reviewer:** `in_review → done` atau `in_review → needs_revision` melalui keputusan atas submission yang masih aktif.
- **Coordinator:** dapat membuka kembali proyek selesai melalui konfirmasi eksplisit. Task `done` tetap terkunci untuk edit/reassign; riwayat review tidak dihapus.
- Deadline terlewat bukan status task baru. Tampilkan label **Overdue** bila `due_at < now` dan task belum `done`.

## 7. Navigasi produk

Empat tab di MVP: **Beranda · Grup · Chat · Tugas Saya**. Semua detail menggunakan `NavigationStack`, sedangkan create/submit/review menggunakan sheet bila sesuai. Lihat [USER_FLOW.md](USER_FLOW.md).

| Tab | Hal utama | Aksi utama |
|---|---|---|
| Home | Deadline mendekat, pending review, proyek aktif | Buka pekerjaan yang perlu perhatian |
| Groups | Daftar group dan proyek | Buat group, invite, buat proyek |
| Chat | Percakapan grup dan unread badge | Buka Group Chat; aktivitas mengarah ke tugas |
| Tugas Saya | Task assigned pada pengguna | Mulai, submit, perbaiki revisi |

## 8. Persyaratan nonfungsional

**Reliability:** operasi perubahan status idempoten atau memiliki deteksi versi; pesan tidak hilang pada retry; error ditampilkan beserta tombol coba lagi.

**Performance (target uji, bukan SLA):** pembukaan layar dari cache terasa responsif; kirim pesan menunjukkan state `sending` seketika; daftar pesan memakai pagination dan rendering efisien.

**Accessibility:** Dynamic Type, VoiceOver label, sentuhan minimum 44×44 pt, kontras teks yang baik, Reduce Motion, status tidak berdasarkan warna saja.

**Privacy:** kumpulkan hanya nama tampilan, identitas akun, informasi tugas, dan percakapan yang diperlukan. Tidak memakai tracking ads; konten chat jangan dimasukkan ke analytics. Ada privacy policy, penghapusan akun, dan kebijakan masa simpan data bersama.

**Security:** RLS di setiap tabel exposed, transaksi RPC untuk operasi otoritatif, pembatasan frekuensi pesan/invite, report & block, dan pengelolaan anggota. Lihat [ARCHITECTURE.md](ARCHITECTURE.md).

**Network:** baca cache bila ada; pembuatan/ubah data membutuhkan koneksi. Jangan menampilkan kesuksesan sebelum konfirmasi server.

**Notifikasi:** push bersifat best-effort; sumber kebenaran tetap database. Kegagalan kirim push tidak boleh menggagalkan operasi utama.

## 9. Kasus tepi yang wajib ditangani

1. Undangan kadaluarsa/revoked/sudah habis kuotanya atau user sudah menjadi anggota.
2. Reviewer keluar dari group saat task sedang menunggu review.
3. Dua reviewer/perangkat menekan keputusan terhadap versi submission yang sama.
4. Pesan berhasil masuk database, tetapi client timeout dan mencoba mengirim ulang.
5. Token sesi kedaluwarsa atau membership dicabut ketika Task Discussion terbuka.
6. Task tidak memiliki URL (boleh), tetapi catatan submission kosong (tolak).
7. Coordinator menghapus anggota yang memiliki task aktif: minta reassignment eksplisit. Pending review memblokir remove/leave sampai review selesai; jangan reassign saat in_review.
8. Pengguna ingin menghapus akun yang masih menjadi coordinator: transfer group/selesaikan group terlebih dahulu.
9. Reviewer tidak merespons: task `in_review` lebih dari 48 jam ditandai untuk coordinator.
10. Pengguna menolak izin push: app tetap berfungsi, Needs Attention di Home jadi jalur utama.
11. Logout lalu login akun lain di perangkat yang sama: token push lama dicabut agar notifikasi tidak nyasar.

## 10. Rencana validasi

- **Minggu 0, sebelum coding:** wawancara 5–8 mahasiswa dari beberapa kelompok berbeda. Tanyakan cara mereka membagi tugas sekarang dan berapa anggota yang memakai iPhone.
- Uji prototype: masuk → join group → buka task → kirim hasil → review → diskusi.
- Jalankan satu proyek nyata bersama 3–5 kelompok pengguna iPhone.
- Ukur kejadian nyata: waktu menemukan task, pesan hilang/tidak, serta apakah diskusi task lebih mudah ditelusuri daripada chat umum.
- Tunda monetisasi sampai ada sinyal penggunaan berulang; **MVP gratis** untuk test.

## 11. Definition of Done MVP

- Semua P0 dapat diuji end-to-end oleh ≥2 akun/perangkat.
- Matrix izin, self-review, konkurensi, undangan, dan pembatasan chat lulus test.
- Loading, empty, offline, error, retry, serta account deletion tertangani.
- Tidak ada crash blocker di TestFlight dan tidak ada data grup bocor ke akun lain.
- Push notification untuk event P0 terkirim dan membuka task yang benar di iPhone uji.
- Dokumen privacy policy serta jalur report/block tersedia sebelum TestFlight eksternal.

## 12. Keputusan yang masih terbuka

- Batas retensi chat dan siapa yang boleh menghapus group harus disahkan sebelum rilis publik.
- Perlu tidaknya view-only web untuk anggota Android ditentukan dari riset, bukan dimasukkan MVP.
- Belum ada komitmen pricing.
- Uji pilot menentukan perbaikan Group Chat P0 dan Task Discussion; tidak mengubah cakupan tanpa keputusan eksplisit.

## 13. Prasyarat dan biaya

- Mac yang mampu menjalankan Xcode terbaru, plus minimal satu iPhone fisik untuk uji push.
- **Apple Developer Program (berbayar tahunan).** Wajib untuk Sign in with Apple, Push Notifications, Associated Domains, dan TestFlight.
- **Domain sendiri** untuk Universal Links (file `apple-app-site-association`) dan halaman fallback bila app belum terpasang.
- Supabase project `dev` dan `staging`; cek batas serta kebijakan pause project pada tier gratis sebelum pilot.

## 14. Changelog v1.2

- Riwayat v1.2: push naik ke P0. Keputusan penundaan chat pada v1.2 telah diganti oleh v1.3: Group Chat realtime serta Task Discussion fetch/pull to refresh termasuk P0.
- Tambah share ke WhatsApp via Universal Link, pengingat deadline lokal, reassign task, dan penanda review pending 48 jam.
- Tambah report & block sebagai syarat TestFlight eksternal.
- Link submission dibatasi `https` dan maksimal 5.
- iPhone-only ditulis sebagai keputusan sadar dengan trade-off yang diterima.
- Tambah analisis alternatif, prasyarat biaya, dan minggu 0 untuk validasi.
