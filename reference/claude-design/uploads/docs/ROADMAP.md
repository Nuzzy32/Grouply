# GROUPLY: MVP Development Roadmap

> **Versi:** 1.3 · **Tanggal:** 16 Oktober 2026 · **Tim:** 1 developer (belajar native SwiftUI)  
> **Estimasi dasar:** **16 minggu** = 1 minggu discovery + 11 minggu implementasi + 4 minggu buffer. Ini target perencanaan, bukan janji tanggal rilis.  
> [PRD](PRD.md) · [User Flow](USER_FLOW.md) · [Design System](DESIGN_SYSTEM.md) · [Architecture](ARCHITECTURE.md) · [Database Schema](DATABASE_SCHEMA.md)

## Perubahan v1.3 (menggantikan bagian yang bertentangan di bawah)

- Group Chat realtime, tab Chats, unread counter, report & block dipindah dari P1 ke **MVP**. Estimasi perlu ditinjau ulang (perkiraan +2–3 minggu dari baseline 16 minggu).
- Item tambahan MVP: Edit Tugas, aturan proyek selesai/buka kembali, arsip dengan pemulihan status, pembatasan pengalihan tugas, undangan dengan masa berlaku + nonaktifkan.
- Prototipe desain v3.1 menjadi acuan design freeze sebelum implementasi SwiftUI.


## 1. Prinsip pengerjaan

**Prioritas:** workflow end-to-end yang dapat dipakai kelompok sungguhan, bukan banyak layar statis. Setiap minggu menghasilkan bagian yang bisa diuji. Fitur P1/P2 tidak boleh mengganggu P0. Obrolan umum kelompok tetap di WhatsApp; GROUPLY fokus ke status kerja, submit, review, diskusi per task, dan notifikasi.

**Tiga checkpoint:**
1. **Visual slice:** create project → task → submit → review dengan mock data, untuk memvalidasi UX.
2. **Secure vertical slice:** flow sama menggunakan Supabase + 2 akun dengan RLS.
3. **Notified slice:** Task Discussion + push notification + share link berjalan di 2 iPhone.

**Definition of Done (semua minggu):** build jalan, error ditangani, state kosong/loading/error terlihat, kode mengikuti penamaan projek, dan scope tidak melebar tanpa keputusan.

**Dokumentasi:** PRD dan Roadmap adalah *living docs* yang diperbarui tiap akhir minggu. Architecture, Database Schema, Design System, dan User Flow hanya diperbarui saat ada keputusan yang berubah, bukan tiap commit. Waktu untuk dokumen tidak boleh melebihi waktu implementasi.

## 2. Prasyarat sebelum minggu 1

- [ ] Mac yang mampu menjalankan Xcode terbaru, plus minimal satu iPhone fisik (push perlu diuji di perangkat nyata)
- [ ] Akun **Apple Developer Program** (berbayar tahunan). Tanpa ini Sign in with Apple, Push Notifications, Associated Domains, dan TestFlight tidak bisa dipakai
- [ ] **Domain** + hosting statis untuk `apple-app-site-association` dan halaman fallback
- [ ] Supabase project `dev` (cek batas dan kebijakan pause tier gratis)
- [ ] Email khusus untuk kanal laporan penyalahgunaan

## 3. Jadwal 16 minggu

| Minggu | Outcome | Tugas utama | Gate sebelum lanjut |
|---|---|---|---|
| **0** | Discovery & validasi | Wawancara 5–8 mahasiswa, prototype Figma alur submit/review, catat jumlah anggota iPhone per kelompok, siapkan semua prasyarat | Masalah koordinasi terkonfirmasi oleh mayoritas narasumber; ada kandidat 3–5 kelompok pilot full iPhone |
| **1–2** | Foundation + belajar SwiftUI | Xcode project, `TabView` 3 tab (Home, Groups, My Tasks), `NavigationStack`, tokens Soft Future, mock Home/Groups/My Tasks/Task Detail | Screen utama dapat dibuka di simulator & iPhone, Dynamic Type dasar |
| **3** | Auth + database foundation | Supabase migrations, Sign in with Apple, profile, RLS read, trigger coordinator, automated test setup | Login/logout sukses; user A tidak membaca data user B |
| **4** | Groups & invitations | `create_group`, redeem invite, member list, Universal Links + AASA, share invite, expiry/revoke | 2 akun join lewat link yang dibuka dari WhatsApp; expired/full/repeated invite tertangani |
| **5** | Projects & tasks | Create project/task, assignment, `reassign_task`, deadline, task list, start | Assignee ≠ reviewer; permission coordinator lulus |
| **6** | Submission & review | Note + link https, versioned submission, approve/request changes, progress, penanda review pending 48 jam | Full workflow end-to-end; self-review/race ditolak |
| **7** | Task Discussion | `ensure_task_chat_room`, `send_chat_text`, pagination, sending/sent/failed, pull to refresh, refresh saat foreground, system event di thread | Retry tidak gandakan komentar; event submit/review muncul di thread yang benar |
| **8–9** | Push & share | `device_tokens`, outbox, Database Webhook + Edge Function `send-push`, layar izin, deep link dari push, pengingat deadline lokal, Share Sheet | Push assign/submit/review/komentar sampai di iPhone lain; tap push membuka task yang benar |
| **10** | Usability, safety, privacy | Layout, form errors, keyboard, VoiceOver, Reduce Motion, report + block, account deletion, privacy policy | Semua screen punya loading/empty/error; deletion dan block berjalan |
| **11** | QA + TestFlight | Integration tests, security audit multi-akun, beta review, UAT 3–5 kelompok, crash fixes | Tidak ada blocker; release checklist lulus |
| **12–15** | Buffer | Bug, migrasi, penyesuaian UX dari pilot, kurva belajar SwiftUI | Tidak menambah fitur baru kecuali blocker |

Jika buffer sudah banyak terpakai sebelum minggu 8, potong sesuai urutan di bagian 6. Gate keamanan tidak boleh digeser.

## 4. Deliverable per tahap

### Milestone A: navigasi & design foundation (akhir minggu 2)

- [ ] iOS deployment target 17+
- [ ] SwiftUI `TabView`: Home, Groups, My Tasks
- [ ] `NavigationStack` untuk deep screens
- [ ] Soft Future tokens, reusable button/card/status chip
- [ ] Mock Project Detail + Task Detail + Discussion bubble
- [ ] SwiftUI preview dan basic VoiceOver labels

**Jangan mulai backend sebelum alur utama bisa dijelaskan dengan prototype.**

### Milestone B: akses anggota yang aman (akhir minggu 4)

- [ ] Apple sign-in, session restoration, logout
- [ ] PostgreSQL schema dengan key, index, constraints, RLS, trigger tepat satu coordinator
- [ ] Role `coordinator` / `member`
- [ ] Create group, create/revoke/redeem invite
- [ ] Universal Links aktif di domain sendiri
- [ ] Group capacity & membership test lintas akun

**Release gate:** UUID group orang lain tidak dapat digunakan untuk membaca atau menyunting data.

### Milestone C: work accountability (akhir minggu 6)

- [ ] Group → Project → Task
- [ ] Single assignee dan reviewer yang berbeda, plus reassign oleh coordinator
- [ ] State `todo / in_progress / in_review / needs_revision / done`
- [ ] Submission versi + link https (maksimal 5)
- [ ] Review transaction, optimistic version, audit event
- [ ] Progress berdasarkan task yang sudah approved
- [ ] Penanda review pending lebih dari 48 jam

**Release gate:** dua review serentak tidak menghasilkan state ganda; self-review ditolak server.

### Milestone D: diskusi & notifikasi (akhir minggu 9)

- [ ] Task Discussion teks + URL
- [ ] System event submit/approve/revision di thread task
- [ ] Pagination deterministik, dedupe, `sending/sent/failed`
- [ ] Refresh saat dibuka, pull to refresh, foreground, dan push
- [ ] Push untuk assign, submission, keputusan review, komentar baru
- [ ] Pengingat deadline lokal H-1
- [ ] Share ke WhatsApp via Universal Link
- [ ] Keanggotaan dicabut = tidak bisa baca/kirim, cache dibersihkan, push berhenti

**Release gate:** tes dua akun di dua iPhone, jaringan buruk, dan izin push ditolak.

### Milestone E: TestFlight readiness (akhir minggu 11 + buffer)

- [ ] Empty/loading/error/offline/permission states
- [ ] UI/UX audit ukuran layar, VoiceOver, Dynamic Type, Reduce Motion
- [ ] Privacy policy, account deletion, report + block (App Review Guideline 1.2)
- [ ] Security test RLS, invites, spam, role, race, secrets, push payload
- [ ] TestFlight build + feedback channel
- [ ] 3–5 kelompok menggunakan untuk proyek asli

## 5. Backlog setelah MVP (sengaja ditunda)

| Fitur | Tahap | Syarat sebelum dikerjakan |
|---|---|---|
| Group Chat realtime + tab Chats | P1 | Data pilot menunjukkan kelompok butuh chat di app, bukan nyaman di WhatsApp |
| Unread counters | P1 | Group Chat aktif dan stabil |
| Activity timeline UI penuh | P1 | Riwayat event akurat |
| Pengingat deadline dari server | P1 | Pengingat lokal terbukti kurang (misalnya deadline diubah saat app tertutup) |
| Attachments foto/PDF | P2 | Storage RLS + file moderation/quotas |
| Reply, reactions, typing | P2 | Bukti dibutuhkan pengguna |
| Collaborative document editing | Out of scope | Bukan diferensiasi inti |
| Android/web companion | Discovery | Data rekrutmen pilot menunjukkan banyak kelompok tertolak karena anggota non-iOS |
| AI task manager/auto scoring | Out of scope | Risiko bias/biaya dan nilai belum dibuktikan |
| Dark theme | P2 | Light-first sudah aksesibel dan diuji |

## 6. Risiko yang bisa mengubah jadwal

| Risiko | Probabilitas | Dampak | Tindakan |
|---|---|---|---|
| Baru mempelajari SwiftUI | Tinggi | Sedang | 2 minggu foundation + 4 minggu buffer, slice mock lebih dulu |
| Auth Apple + Universal Links | Sedang | Tinggi | Siapkan domain di minggu 0, spike teknis di minggu 3–4 |
| Setup push (APNs key, sandbox vs production, webhook) | Sedang | Tinggi | Uji kirim push manual di awal minggu 8 sebelum menyambungkan event |
| Complex RLS / RPC | Tinggi | Tinggi | Integration test SQL sejak minggu 3 |
| Scope creep visual | Tinggi | Sedang | Bekukan component list; gunakan Soft Future sederhana |
| iPhone-only (keputusan sadar) | Pasti | Tinggi untuk adopsi | Rekrut pilot full iPhone; catat jumlah kelompok yang tertolak karena anggota non-iOS sebagai data keputusan pasca-MVP |
| Prasyarat biaya & perangkat belum siap | Sedang | Tinggi | Pastikan Apple Developer Program, Mac, iPhone, dan domain tersedia di minggu 0 |
| Kelompok tetap di WhatsApp dan jarang buka app | Tinggi | Tinggi | Push untuk event penting + share link ke WhatsApp; ukur di pilot |
| Moderasi konten & App Review UGC | Sedang | Tinggi | Report + block + kanal laporan sebelum TestFlight eksternal; coordinator remove member |

**Urutan yang boleh dikurangi jika terlambat:** visual Group Pulse kompleks → activity timeline UI → animasi dekoratif → pengingat deadline lokal. **Tidak boleh dikurangi:** RLS, integritas review, idempotensi komentar, push untuk submission dan keputusan review, login/logout, account deletion, report & block.

## 7. Test plan per ukuran task

### Quick checks per fitur kecil

- Build iOS sukses tanpa warning kritis.
- Tidak ada error konsol relevan.
- Happy path & satu negative path diuji.

### Audit menyeluruh menjelang TestFlight

**Security**
- [ ] Akses silang group ditolak untuk query dan RPC.
- [ ] Client tak bisa membuat pesan sistem, approve diri sendiri, reassign, atau mengubah role.
- [ ] Token invitation tidak bocor di response/log; expiry/quota berjalan.
- [ ] Tidak ada service_role, APNs key, private keys, `.env` di bundle/repo.
- [ ] Link submission hanya https; konten user divalidasi; rate limit backend efektif.
- [ ] `device_tokens`, outbox, dan laporan tidak terbaca client; payload push tanpa isi komentar.

**UI/UX**
- [ ] Cocok dengan Soft Future; tidak berlebihan card/dekorasi.
- [ ] Layar kecil/besar, keyboard, safe areas, loading/error/empty, VoiceOver.
- [ ] Tidak kehilangan konteks saat membuka task dari push atau share link.
- [ ] Layar izin notifikasi dan state izin ditolak.

**Features**
- [ ] Create group, invite, project, task, reassign, submission, review, diskusi bekerja dengan dua akun.
- [ ] Simulasi timeout saat komentar sudah tersimpan tidak membuat duplikasi.
- [ ] Refresh saat foreground menampilkan komentar yang masuk selama app di background.
- [ ] Push untuk 4 event sampai, dan tap push membuka task yang benar.
- [ ] Logout lalu login akun lain di device sama tidak menerima push akun lama.
- [ ] Perubahan status gagal bila revision/version stale.
- [ ] Uninstall/reinstall/login tetap memuat data server.

## 8. Uji pengguna nyata dan keputusan lanjut

**Pilot:** 3–5 kelompok, masing-masing 2–8 anggota iPhone, tugas sungguhan selama 1–2 minggu. Saat rekrutmen, catat berapa kelompok yang tidak bisa ikut karena ada anggota non-iOS.

**Pertanyaan pengukuran:**
- Adakah kebingungan soal siapa mengerjakan apa?
- Adakah aktivitas submit/review yang berhasil tanpa chat tambahan?
- Berapa lama dari submit sampai keputusan review, dan apakah push mempercepatnya?
- Seberapa sering Task Discussion dipakai dibanding chat WhatsApp kelompok?
- Apakah ada komentar tidak terkirim/duplikat, atau push yang tidak sampai?
- Apakah kelompok meminta chat group di dalam app (sinyal untuk P1)?
- Apakah kelompok akan memilih GROUPLY untuk tugas berikutnya?

**Decision gate:** jika hanya sedikit anggota menggunakan task/review walau diskusi aktif, jangan langsung menambah fitur. Evaluasi apakah approval terlalu formal atau integrasi ke kebiasaan mahasiswa kurang praktis.

## 9. Git dan rilis

- Gunakan branch kecil per fitur, commit deskriptif dan test sebelum merge.
- Audit `git status` dan `git diff --cached` sebelum push; jangan commit credentials, `.env`, APNs key, ataupun file konfigurasi tool AI yang tidak relevan.
- Simpan SQL migrations, Edge Function `send-push`, dan file AASA dalam version control, **bukan** hanya di Supabase dashboard. APNs key hanya di Supabase secrets.
- Catat perubahan skema dengan migration version; uji migrasi ulang di database bersih.
- Tag build TestFlight MVP setelah semua P0 pass dan feedback channel siap.

## 10. Status proyek saat dokumen dibuat

Semua milestone dan checklist di dokumen ini berstatus **belum dikerjakan**. Ini adalah rencana implementasi, bukan laporan progres.
