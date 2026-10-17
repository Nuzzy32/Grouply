# GROUPLY Design System: Soft Future

> **Versi:** 1.3 · **Tanggal:** 16 Oktober 2026 · **Platform:** SwiftUI, iOS 17+  
> **Acuan:** Prototype v3.1 di `reference/claude-design/Grouply App.dc.html`; gunakan Soft Future dan perilaku yang telah direkonsiliasi.  
> [PRD](PRD.md) · [User Flow](USER_FLOW.md) · [Architecture](ARCHITECTURE.md)

## Keputusan v1.3 yang telah direkonsiliasi

- Tab bar 4 item (Beranda, Grup, Chat, Tugas Saya) dengan label selalu terlihat; badge unread di Chat.
- Chats dan Group Chat masuk MVP (bukan P1). Unread badge masuk MVP.
- Pola baru: **kartu aktivitas** di chat (ikon status, kalimat aktivitas, tombol "Lihat tugas"); **banner status proyek** (mint untuk Selesai, abu #ECEEEB untuk Diarsipkan) berisi penjelasan + satu aksi; **dialog konfirmasi** in-app (judul, penjelasan konsekuensi, Batal + aksi; aksi destruktif merah #A8231B); **placeholder pesan diblokir** (border putus-putus + "Tampilkan"); **bar diskusi hanya-baca** menggantikan composer.
- Aksi yang tidak tersedia tetap terlihat dengan ikon gembok dan menjelaskan alasannya saat diketuk.
- Teks sekunder memakai #62676B (bukan #777777) agar kontras ≥ 4.5:1 di atas #F8F9F7.


## Status implementasi dan batas verifikasi

Per 17 Oktober 2026 tersedia demo dan **server Supabase lokal** dengan Auth, RLS, RPC transactional serta SwiftUI async. Workflow tiga akun dan Group Chat Realtime/unread/reconnect/revoke membership teruji lintas client native pada satu simulator + localhost. Milestone E menambahkan antrean laporan/CLI operator lokal, block lintas sesi, dan hapus akun password server dengan histori bersama dipertahankan tanpa referensi identitas. Deployment cloud, provider/pencabutan token Apple, dua perangkat fisik/jaringan nyata, APNs, Universal Links, moderasi production dan kebijakan retensi belum diverifikasi/tersedia. Lihat [Backend Setup](BACKEND_SETUP.md); bagian lain mendeskripsikan target produk P0.


## 1. Design principles

**Soft Future** = *playful, modern, calm, and useful*. Aplikasi terasa premium dengan card besar, banyak ruang napas, pastel accents, dan motion halus. Aspek futuristiknya datang dari respons interaksi dan visual progress, **bukan neon, efek glow berlebihan, atau 3D berat**.

1. **Clarity first:** deadline, status, assignee, dan CTA selalu mudah ditemukan.
2. **Context over decoration:** warna dipakai membedakan konteks/status, bukan asal ramai.
3. **Calm collaboration:** review terasa suportif, bukan sistem penghukuman.
4. **Native by default:** navigation, sheets, menus, haptic, Dynamic Type mengikuti kebiasaan iOS.
5. **Motion with purpose:** setiap animasi memberi feedback perubahan, dan tersedia alternatif Reduce Motion.

## 2. Theme dan color tokens

**Tema MVP: Light-first.** Warna didefinisikan sebagai semantic assets sehingga dark mode bisa ditambahkan setelah MVP; jangan mengunci komponen terhadap warna hardcoded di banyak file.

| Token | Hex light | Penggunaan |
|---|---|---|
| `background` | `#F8F9F7` | Latar utama |
| `surface` | `#FFFFFF` | Card & sheet |
| `surfaceMuted` | `#F0F3F1` | Input/background alternatif |
| `textPrimary` | `#202124` | Headings/body |
| `textSecondary` | `#62676B` | Metadata, hint |
| `border` | `#E8E9E7` | Pemisah halus |
| `lavender` | `#DED2FF` | Review / accent |
| `mint` | `#C9F2D6` | Approved / done |
| `sky` | `#D8EAF4` | In progress |
| `butter` | `#F9E9BE` | Due soon |
| `coral` | `#F6CED1` | Needs revision |
| `ink` | `#202124` | Primary button dan icon dark |
| `white` | `#FFFFFF` | Tombol primary text |

**Kontras:** semua teks di atas pastel umumnya memakai `textPrimary`, bukan warna pastel sebagai teks. Verifikasi kontras per kombinasi; gunakan target ≥4.5:1 untuk teks biasa dan ≥3:1 untuk teks besar. Status selalu memakai ikon/label selain warna.

### Status mapping

| Status | Chip bg | Label | Simbol SF Symbols (contoh) |
|---|---|---|---|
| `todo` | Butter | To do | `circle` |
| `in_progress` | Sky | In progress | `arrow.triangle.2.circlepath` |
| `in_review` | Lavender | In review | `eye` |
| `needs_revision` | Coral | Needs revision | `arrow.uturn.backward` |
| `done` | Mint | Done | `checkmark.circle.fill` |
| `overdue` (computed) | Coral + outline | Overdue | `exclamationmark.circle` |
| `review_stale` (computed) | Lavender + outline | Review pending | `clock.badge.exclamationmark` |

`overdue` adalah indikator turunan deadline, **bukan** status database. Begitu juga `review_stale`: muncul bila task `in_review` lebih dari 48 jam.

## 3. Typography

Pakai **SF Pro** dengan font system dan Text Styles agar Dynamic Type berjalan alami. Jangan memakai ukuran tetap untuk konten kritis.

| Peran | SwiftUI style | Weight | Catatan |
|---|---|---|---|
| Greeting/title | `.largeTitle` | Bold | 1–2 baris |
| Screen heading | `.title2` | Semibold | Judul project/group |
| Section heading | `.title3` | Semibold | Today, Projects |
| Card heading | `.headline` | Semibold | Task/room names |
| Main content | `.body` | Regular | Pesan chat, deskripsi |
| Supporting | `.subheadline` | Regular | Deadline, anggota |
| Metadata | `.caption` | Medium | Timestamp |

Gunakan batas panjang judul dan pembungkusan teks. Jangan paksa `minimumScaleFactor` terlalu kecil. `monospacedDigit()` untuk angka progress/countdown jika diperlukan.

## 4. Layout, spacing, shapes

| Token | Nilai |
|---|---|
| `space.1` | 4 pt |
| `space.2` | 8 pt |
| `space.3` | 12 pt |
| `space.4` | 16 pt |
| `space.5` | 20 pt |
| `space.6` | 24 pt |
| `space.8` | 32 pt |
| Screen horizontal margin | 20 pt default, responsif untuk ukuran perangkat |
| Card padding | 16–20 pt |
| Card radius | 24 pt |
| Large feature radius | 28–32 pt |
| Button radius | 16 pt |
| Pill radius | kapsul |
| Avatar | 32–40 pt |
| Minimum touch target | 44×44 pt |

**Elevasi:** minimal shadow, misalnya opacity ~0.04 dan blur kecil. Gunakan margin/surface separation daripada shadow tajam. Hindari terlalu banyak card bersarang.

## 5. Komponen reusable

| Komponen | Props utama | State |
|---|---|---|
| `GLButton` | title, variant, icon, isLoading, action | default/disabled/loading |
| `GLCard` | content, background, padding | default/pressed |
| `GLStatusChip` | TaskStatus, label | semua status |
| `GLAvatarStack` | avatars, maxVisible | empty/many |
| `GLProgressRing` | approved, total, diameter | zero/partial/done |
| `GLProjectRow` | title, group, progress, deadline | active/archived |
| `GLTaskRow` | title, status, due, assignee | overdue/review |
| `GLChatBubble` | message, senderType, delivery | mine/others/system/sending/failed |
| `GLComposer` | draft, onSend, enabled | composing/sending/offline |
| `GLEmptyState` | icon, heading, description, CTA | per feature |
| `GLFormField` | title, value, validation | focus/error/normal |
| `GLPermissionPrompt` | icon, title, reason, primaryAction, secondaryAction | default |

### Aksesibilitas komponen

- Progress Ring menyuarakan `"7 dari 10 task disetujui, 70 persen"`, bukan hanya `"70%"`.
- Avatar Stack punya label jumlah anggota serta nama yang dapat diakses.
- Bubble punya label nama pengirim, jam, isi, dan status pengiriman.
- Status Chip punya teks eksplisit, dan color status tidak menjadi satu-satunya sinyal.
- Semua action tap target ≥44pt, VoiceOver focus order logis.

## 6. Screen blueprint

### Home

```text
[Good morning, Alex! 👋]                         [Avatar]

[ Today                                ]
[ Due soon | Pending reviews           ]

[ Your Groups                           ]
[ Database Systems       6 / 10 done   ]
[ UI/UX Research         2 / 5 done    ]

[ Home ] [ Groups ] [ My Tasks ]
```

Gunakan satu featured card "Needs Attention" dan daftar group lebih compact. Bagi coordinator, task `in_review` lebih dari 48 jam ikut muncul di sana dengan chip **Review pending**. **Jangan** membuat semua informasi berupa card besar setinggi layar.

### Groups

Header `Groups` + CTA `+`, search tidak wajib. Group card berisi nama, jumlah anggota, progress kelompok dan proyek aktif. Dalam Group Detail, tampilkan proyek dan anggota. Shortcut Group Chat tersedia pada MVP.

### Project Detail

Judul, deskripsi ringkas, deadline, jumlah anggota, progress, dan task list. Ring progress **maksimum satu** per layar; gunakan `approved/total`, tidak membuat chart dekoratif yang mendominasi layar. Segmented filter `All / To Do / In Progress / In Review / Done` bila daftar panjang.

### My Tasks

Prioritaskan `Needs Action`, `Due Soon`, lalu semua task. Status sebagai pill; judul tetap elemen dominan. Filter tersedia melalui chip yang bisa di-scroll horizontal tanpa memotong teks.

### Chat (P0)

> Termasuk MVP; native demo lokal tidak menyiratkan koneksi Realtime live.

Daftar group chat saja. Setiap row menampilkan avatar/ikon group, nama, preview pesan terakhir, dan timestamp. Unread badge termasuk P0. Tidak menampilkan seluruh task discussion sebagai room utama.

### Group Chat (P0)

> Aturan bubble di bawah juga dipakai Task Discussion di MVP.

Bubble sendiri **lavender lembut** dengan teks gelap; bubble anggota lain **putih** di atas `background`. Pesan sistem berupa event row/callout ringkas, misalnya `Raka submitted ERD diagram · View task`.

- Avatar + nama hanya saat perlu untuk grup yang ramai.
- Timestamp tidak menguasai visual.
- Input composer menempel aman di atas keyboard menggunakan safe area.
- Failed bubble punya tindakan **Retry**.
- Scroll mempertahankan posisi saat history lebih lama dimuat; jangan auto-scroll paksa jika user sedang membaca pesan lama.

### Task Detail + Discussion

Overview dan submission tetap utama. Discussion adalah section/tab kontekstual di dalam detail tugas, dengan CTA "Discuss this task". Saat muncul keputusan review, tampilkan status dan revisi, bukan hanya notifikasi samar.

- Bubble mengikuti aturan Group Chat di atas: milik sendiri lavender, sistem sebagai event row, failed dengan **Retry**.
- Sediakan pull to refresh dan status koneksi. Task Discussion P0 memakai fetch/pull to refresh/foreground/push; label live hanya boleh muncul pada Group Chat bila koneksi Realtime benar-benar aktif. Typing indicator tidak termasuk MVP.
- Tombol **Share** di toolbar membuka iOS Share Sheet (`ShareLink`) berisi ringkasan + link task.

### Izin notifikasi

Tampilkan `GLPermissionPrompt` sebagai sheet sebelum dialog sistem iOS, saat user pertama kali join group atau mendapat task. Isi: satu ikon, satu kalimat manfaat (misalnya "Dapat kabar saat tugasmu direview"), tombol **Izinkan** dan **Nanti saja**. Jika user menolak, jangan tampilkan ulang otomatis; sediakan jalur ke Settings di halaman Profile.

## 7. Motion dan haptics

| Interaksi | Efek | Durasi panduan |
|---|---|---|
| Card tap | subtle scale / pressed | 120–180ms |
| Filter change | eased background selection | 150–220ms |
| Project progress update | short spring | 250–350ms |
| New comment (kirim/refresh) | gentle opacity + slide | 150–250ms |
| Sheet entrance | native system | native |
| Approve | minimal success haptic | sekali saat berhasil |
| Error/retry | warning feedback | jangan berulang agresif |

Respect `accessibilityReduceMotion`. Untuk list/large content, hindari animasi per item yang muncul bersamaan. Jangan memakai vibrasi setiap pesan masuk saat pengguna sedang membaca chat.

## 8. Implementation notes SwiftUI

```swift
import SwiftUI

enum GLSpacing {
    static let xs: CGFloat = 4
    static let sm: CGFloat = 8
    static let md: CGFloat = 12
    static let lg: CGFloat = 16
    static let xl: CGFloat = 24
    static let xxl: CGFloat = 32
}

enum GLRadius {
    static let button: CGFloat = 16
    static let card: CGFloat = 24
    static let feature: CGFloat = 32
}

// Gunakan Color("Background"), Color("Lavender"), dst.
// Definisikan warna nyata di Assets.xcassets sebagai semantic assets.
```

`TabView`, `NavigationStack`, `safeAreaInset`, `scrollDismissesKeyboard`, dan `sensoryFeedback` cukup untuk sebagian besar pengalaman ini. Jangan menambahkan design framework pihak ketiga sebelum ada kebutuhan nyata.

## 9. Design QA checklist

- [ ] Light palette konsisten dengan referensi *Soft Future*.
- [ ] Header, CTA, dan task status tidak kalah oleh dekorasi.
- [ ] Semua layar diuji di iPhone kecil dan besar, landscape bila relevan.
- [ ] Dynamic Type pada ukuran aksesibilitas tidak menyebabkan tombol hilang.
- [ ] Warna chips dan body text memenuhi kontras yang diverifikasi.
- [ ] VoiceOver dapat membaca task, chat, dan progress dengan jelas.
- [ ] Reduce Motion, keyboard, safe area, network error, empty state telah diuji.
- [ ] Tampilan diskusi tetap nyaman ketika komentar sangat panjang atau URL panjang.
- [ ] Layar izin notifikasi dan state izin ditolak sudah diuji.

## 10. Fase visual berikutnya (bukan MVP)

Dark theme semantic, Group Pulse lebih interaktif, shared-element transitions lebih kompleks, avatar custom, dan animasi fisika. Semua baru dipertimbangkan setelah usabilitas MVP lulus pengujian.
