# GROUPLY: Native iOS Technical Architecture

> **Versi:** 1.3 · **Tanggal:** 16 Oktober 2026 · **Status:** Target arsitektur; native demo tersedia sebagai demo lokal  
> **Platform:** Swift 5.9+ / SwiftUI / iOS 17+ · **Cloud:** Supabase  
> [PRD](PRD.md) · [User Flow](USER_FLOW.md) · [Design System](DESIGN_SYSTEM.md) · [Database Schema](DATABASE_SCHEMA.md) · [Roadmap](ROADMAP.md)

## Keputusan v1.3 yang telah direkonsiliasi

- Group Chat + Supabase Realtime masuk MVP (bukan P1). Task Discussion memakai fetch + pull to refresh + foreground/push.
- Semua mutasi tugas/proyek lewat RPC server yang memvalidasi: peran koordinator, status tugas, status proyek (aktif/selesai/arsip), dan aturan pelaksana ≠ reviewer. Client hanya menyembunyikan/mengunci kontrol; otorisasi akhir di RLS + RPC.
- RPC baru: `update_task`, `reassign_task`, `complete_project`, `reopen_project`, `archive_project`, `restore_project`, `create_group_invite`, `revoke_group_invite`, `redeem_group_invite`. Setiap RPC menulis audit event dan, bila relevan, pesan aktivitas di chat grup dalam satu transaksi.
- Optimistic concurrency: RPC menerima `expected_version` dan menolak bila data sudah berubah ("Tugas ini sudah berubah").


## Status implementasi dan batas verifikasi

Per 17 Oktober 2026 tersedia demo dan **server Supabase lokal** dengan Auth, RLS, RPC transactional serta SwiftUI async. Workflow tiga akun dan Group Chat Realtime/unread/reconnect/revoke membership teruji lintas client native pada satu simulator + localhost. Deployment cloud, provider Apple nyata, Realtime pada dua perangkat fisik/jaringan nyata, APNs, Universal Links, moderasi operasional dan penghapusan akun server belum diverifikasi/tersedia. Lihat [Backend Setup](BACKEND_SETUP.md); bagian lain mendeskripsikan target produk P0.


## 1. Architecture decision record

**Implementasi slice server lokal (17 Oktober 2026):** native `SupabaseBackend` memakai URLSession untuk Auth, dua public RPC `grouply_snapshot()` / `grouply_mutate(action,payload)`, dan WebSocket Realtime. Aksi domain pada tabel kontrak di bawah didispatch melalui `action` camelCase, bukan endpoint per aksi. `DemoStore` menyajikan demo atau bridge async server. Migration aktual ada di `supabase/migrations`; struktur berlapis di bawah tetap target berikutnya. Keychain menyimpan sesi; JSON lokal hanya untuk demo. Subscription aktif selama foreground untuk semua pesan grup yang diizinkan RLS agar unread tab ikut berubah, ditambah read markers/revision akun sendiri. Event menginvalidasi snapshot; burst digabung, fetch gagal dicoba ulang, dan reconnect memulihkan gap. [Detail setup dan batas](BACKEND_SETUP.md).

| Keputusan | Pilihan | Alasan | Trade-off |
|---|---|---|---|
| Client | **Native SwiftUI** | Gesture, animation, accessibility dan standar iOS | Hanya iOS pada MVP |
| Platform | **iPhone-only di MVP** | Keputusan produk: fokus satu platform dulu | Kelompok dengan anggota non-iOS belum terlayani; jumlahnya dicatat saat rekrutmen pilot |
| Deployment | **iOS 17+** | Observation, SwiftUI modern | Pengguna OS lebih lama tidak didukung |
| App structure | **Feature-based MVVM + Repository** | Cukup modular tanpa over-engineering | Perlu disiplin boundary |
| State | **`@Observable` + `@MainActor`** | Native observation | Harus jelas lifecycle/concurrency |
| Async work | **Swift Concurrency** | `async/await`, structured cancellation | Perlu menangani cancellation |
| Auth | **Supabase Auth + Sign in with Apple** | Sesuai native iOS | OAuth nonce/config butuh setup |
| Persistence bersama | **Supabase PostgreSQL** | Relasi group, task, review, chat | Internet wajib untuk mutasi |
| Authorization | **RLS + audited RPC** | Multi-tenant isolation dan transaksi | SQL testing cukup intensif |
| Chat sync | **Group Chat Realtime P0; Task Discussion fetch/pull to refresh/foreground/push** | Sinkronisasi sesuai konteks | Fetch/pagination/reconnect tetap diperlukan; backend live belum dikonfigurasi |
| File attachment | **Tidak ada di P0** | URL referensi sudah cukup | Tidak bisa kirim file langsung |
| Local storage | **AppStorage + memory cache** | Sederhana | Offline history belum lengkap |
| Push notification | **P0: APNs via Supabase Edge Function + outbox table** | Tanpa push, tidak ada yang tahu ada review menunggu | Setup APNs key, sandbox vs production, butuh Apple Developer Program |
| Deadline reminder | **Local notification** | Tidak butuh server atau cron | Dijadwalkan ulang tiap app dibuka; deadline yang diubah saat app tertutup bisa telat terupdate |
| Deep link | **Universal Links (HTTPS) + domain sendiri** | Link invite/share bisa dibuka langsung dari WhatsApp | Butuh domain dan file `apple-app-site-association` |

**Keputusan eksplisit:** versi pertama **online-first**, bukan offline-first. Backend adalah sumber kebenaran untuk seluruh objek bersama.

## 2. High-level architecture

```mermaid
flowchart LR
    subgraph iOS[GROUPLY iOS App]
        UI[SwiftUI Views / TabView]
        VM[@Observable Feature Models]
        USE[Use Cases / Validation]
        REP[Repository Protocols]
        ADAPTER[Supabase Repository Adapters]
        UI --> VM --> USE --> REP --> ADAPTER
    end
    ADAPTER --> AUTH[Supabase Auth]
    ADAPTER --> API[PostgREST SELECT + RPC]
    API --> DB[(PostgreSQL + RLS + notification_outbox)]
    DB -- Database Webhook --> EF[Edge Function send-push]
    EF --> APNS[Apple Push Notification service]
    APNS -. push .-> UI
```

**Data flow baca:** View → Feature Model → Repository → authorized select → DTO mapping → domain model → observable UI state.

**Data flow mutasi:** user action → validation client → Use Case → RPC server transactional → authorized result → refresh lokal → UI state. Bila gagal, kembalikan status error, bukan mengasumsikan sukses.

**Data flow diskusi:** `send_chat_text` lewat RPC yang memvalidasi membership, rate limit, dan idempotency, lalu menulis baris `notification_outbox` dalam transaksi yang sama. Client berlangganan Realtime pada Group Chat aktif. Task Discussion memakai fetch saat dibuka, pull to refresh, foreground, atau push terkait. Pesan sistem berasal dari RPC server.

**Data flow notifikasi:** RPC menulis outbox → Database Webhook memanggil Edge Function `send-push` → Edge Function membaca token penerima di server dan mengirim ke APNs → status kirim dicatat di outbox. Kegagalan push tidak membatalkan transaksi utama.

## 3. Struktur target saat integrasi cloud

```text
Grouply/
├── App/
│   ├── GrouplyApp.swift
│   ├── AppContainer.swift
│   ├── RootView.swift
│   └── AppRouter.swift
├── Core/
│   ├── DesignSystem/
│   │   ├── GLColors.swift
│   │   ├── GLTypography.swift
│   │   ├── GLButton.swift
│   │   ├── GLCard.swift
│   │   ├── GLStatusChip.swift
│   │   └── GLChatBubble.swift
│   ├── Networking/
│   │   ├── NetworkMonitor.swift
│   │   └── APIError.swift
│   ├── Notifications/
│   │   ├── PushRegistrar.swift
│   │   └── LocalReminderScheduler.swift
│   └── Utilities/
├── Domain/
│   ├── Models/              # Group, Project, Task, Submission, Review, ChatMessage
│   ├── Repositories/        # Protocols
│   └── UseCases/            # SubmitWork, ApproveWork, RedeemInvite, SendMessage
├── Data/
│   ├── DTOs/
│   ├── Supabase/
│   │   ├── SupabaseClientFactory.swift
│   │   └── RealtimeChatSource.swift   # P0, Group Chat
│   └── Repositories/        # Concrete implementations
├── Features/
│   ├── Authentication/
│   ├── Home/
│   ├── Groups/
│   ├── Projects/
│   ├── Tasks/
│   ├── Submissions/
│   ├── Reviews/
│   ├── Discussion/
│   ├── Notifications/
│   ├── Safety/              # report & block
│   └── Profile/
├── Resources/
│   └── Assets.xcassets/
└── Tests/
    ├── DomainTests/
    ├── RepositoryTests/
    ├── WorkflowTests/
    └── UITests/
```

Struktur di atas adalah target, bukan daftar file yang dijamin sudah tersedia. Demo lokal boleh memakai shared store sederhana tanpa adapter kosong.

Repo yang sama nantinya menyimpan `supabase/migrations/`, `supabase/functions/send-push/`, dan `site/.well-known/apple-app-site-association` untuk domain Universal Links.

Mulai dengan **satu Xcode target**. Jangan pecah menjadi banyak Swift Packages sebelum ada kebutuhan nyata. Konfigurasi environment debug/staging/prod dipisahkan, tetapi semua memakai shape interface yang sama.

## 4. Interface antar-layer

Contoh kontrak domain (pseudocode Swift yang perlu disesuaikan dengan implementasi final):

```swift
protocol ChatRepository {
    func latestMessages(roomID: UUID, limit: Int) async throws -> [ChatMessage]
    func olderMessages(roomID: UUID, before: MessageCursor, limit: Int) async throws -> [ChatMessage]
    func sendText(roomID: UUID, content: String, clientID: UUID) async throws -> ChatMessage
    func newerMessages(roomID: UUID, after: MessageCursor) async throws -> [ChatMessage]
    // observeRoom(roomID:) untuk Realtime P0; batalkan subscription saat keluar
}

protocol TaskRepository {
    func getTask(_ id: UUID) async throws -> GroupTask
    func submitWork(taskID: UUID, expectedVersion: Int, note: String,
                    links: [URL], clientID: UUID) async throws -> Submission
    func reviewWork(submissionID: UUID, expectedVersion: Int,
                    decision: ReviewDecision, feedback: String?, clientID: UUID) async throws -> Review
    func reassignTask(taskID: UUID, expectedVersion: Int,
                      assigneeID: UUID?, reviewerID: UUID?) async throws -> GroupTask
}

protocol NotificationRepository {
    func registerDeviceToken(_ token: Data, environment: APNsEnvironment) async throws
    func unregisterCurrentDevice() async throws
}
```

`MessageCursor` menggunakan `(createdAt, id)`; UUID membuat urutan stabil bila ada timestamp sama. `expectedVersion` wajib dikirim untuk perubahan status yang rawan race.

Contoh prinsip state:

```swift
@MainActor
@Observable
final class ChatModel {
    var messages: [ChatMessage] = []
    var sendingIDs: Set<UUID> = []
    var error: String?
    // dependency injection via init(repository:)
    // cancellation subscriptions saat view hilang/sign out
}
```

Hindari satu `AppViewModel` raksasa. Setiap fitur punya model dan dependency sendiri; `AppContainer` menyediakan repository saat dibutuhkan.

## 5. Authentication & account lifecycle

1. iOS menampilkan `SignInWithAppleButton`.
2. Buat **cryptographically secure random nonce**, kirim hash nonce pada permintaan Apple bila sesuai alurnya, dan teruskan nonce original ke Supabase.
3. Dapatkan identity token dari Apple; gunakan Supabase Auth `signInWithIdToken` dengan provider `.apple`, token dan nonce.
4. Setelah sesi valid, buat/update `profiles` melalui RPC terbatas.
5. Simpan sesi via mekanisme aman resmi library Auth; **jangan** menaruh refresh token di `UserDefaults`, Analytics, atau logs.
6. Saat logout, panggil `unregister_device_token`, batalkan `Task` yang berjalan, bersihkan cache diskusi, hapus local notifications terjadwal, kemudian sign out.
7. Account deletion dilakukan lewat server-side workflow terotorisasi; coordinator perlu transfer kepemilikan atau memilih penutupan group sesuai kebijakan.

Tidak ada login email/password tambahan pada MVP. Sediakan deskripsi privacy, control penggunaan data, dan opsi delete account yang dapat ditemukan di Settings.

## 6. Backend contracts

**Semua operasi kompleks melalui RPC transaksional**, bukan serangkaian update dari client yang bisa terputus di tengah.

| Operasi | Metode | Validasi backend penting |
|---|---|---|
| `create_group(name)` | RPC | auth valid, name valid, coordinator/member/room atomik |
| `create_group_invite(group_id, ttl, max_uses)` | RPC | hanya coordinator, token acak, simpan hash |
| `revoke_group_invite(invite_id)` | RPC | coordinator aktif; set revoked_at atomik |
| `redeem_group_invite(token)` | RPC | hash cocok, expiry, max use, capacity, idempoten |
| `remove_group_member(group_id, user_id)` | RPC | coordinator aktif; tolak pending review dan tugas aktif; reassignment dahulu; target bukan coordinator |
| `leave_group(group_id)` | RPC | member aktif keluar sendiri; coordinator transfer dahulu; tolak tugas aktif/pending review; hapus membership atomik |
| `transfer_coordinator(group_id, new_user_id)` | RPC | kedua user member, unique coordinator |
| `create_project(group_id, ...)` | RPC | coordinator, deadline valid |
| `create_task(project_id, assignee, reviewer, ...)` | RPC | coordinator aktif; proyek aktif/tidak diarsipkan; keduanya member, berbeda |
| `update_task(task_id, expected_version, ...)` | RPC | coordinator aktif; judul 1–120, deskripsi ≤2000; reviewer valid; tolak in_review/done dan proyek readonly |
| `complete_project(project_id)` | RPC | coordinator; ≥1 task, semua done; proyek tidak diarsipkan |
| `reopen_project(project_id)` | RPC | coordinator; completed → active setelah konfirmasi eksplisit |
| `archive_project(project_id)` / `restore_project(project_id)` | RPC | coordinator; ubah archived_at saja, pertahankan status sebelumnya |
| `start_task(task_id, expected_version)` | RPC | hanya assignee, status yang diizinkan |
| `submit_work(task_id, expected_version, note, links, client_id)` | RPC | assignee, content valid, revision/transition atomik |
| `review_work(submission_id, expected_version, decision, feedback, client_id)` | RPC | reviewer tepat, bukan author, active submission |
| `reassign_task(task_id, expected_version, assignee_id?, reviewer_id?)` | RPC | coordinator aktif; keduanya member dan berbeda; tolak in_review/done atau proyek readonly; needs_revision tetap needs_revision; event + push |
| `ensure_task_chat_room(task_id)` | RPC | anggota valid, room tunggal |
| `upsert_my_profile(display_name)` | RPC | auth.uid adalah pemilik |
| `request_account_deletion()` | controlled workflow | cek coordinator + anonimisasi data bersama |
| Fetch groups/projects/tasks/messages | RLS SELECT | membership group selalu diperiksa |
| `send_chat_text(room_id, content, client_message_id)` | RPC | sender=auth.uid; room group/task accessible; task room readonly bila proyek selesai/arsip; text only; idempotency; rate limit; enqueue push |
| `register_device_token(token, environment)` | RPC | token diikat ke auth.uid; upsert memindahkan token dari user lain |
| `unregister_device_token(token)` | RPC | hanya pemilik token |
| `report_content(target_type, target_id, reason)` | RPC | pelapor satu group dengan target; rate limit |
| `block_user(user_id)` / `unblock_user(user_id)` | RPC | tidak bisa block diri sendiri |

Semua aksi membaca/menulis memeriksa membership aktif pada saat operasi, termasuk start/submit/review, retry idempoten, membuka chat, edit proyek, report dan pengalihan. Proyek completed atau archived_at terisi mengunci semua mutasi task/submission/review dan composer diskusi tugas; Group Chat tetap aktif.

`leave_group` mengembalikan `{group_id, left: true}` hanya setelah commit; `forbidden` untuk nonmember, `coordinator_transfer_required` bila coordinator, `active_assignment` bila punya tugas aktif, dan `pending_review` bila terkait review berjalan. Remove/leave mengunci grup dan tugas relevan agar assignment baru tidak berlomba dengan penghapusan membership. Setelah sukses, client menutup layar terkait, membuang cache dan langganan room, serta membatalkan pengingat grup.

**API error codes (kontrak aplikasi):** `unauthorized`, `forbidden`, `invalid_input`, `invite_expired`, `invite_full`, `group_full`, `stale_version`, `already_reviewed`, `rate_limited`, `coordinator_transfer_required`, `active_assignment`, `pending_review`, `project_read_only`, `offline`, `unknown`. Tampilkan teks lokal yang ramah pengguna.

## 7. Task Discussion, push, dan delivery semantics

### Model data & urutan

- `chat_rooms`: `type=group|task`, `group_id`, `task_id?`.
- `chat_messages`: `sender_id?`, `type=text|system`, `content`, `metadata`, `client_message_id?`, `created_at`.
- Pesan sistem berasal dari RPC submit/review; tidak bisa dibuat langsung oleh client.
- Untuk pengiriman teks, client membuat `client_message_id = UUID` sebelum request pertama dan **memakainya lagi untuk retry**. Unique `(sender_id, client_message_id)` mencegah duplikat.
- DB memberi `created_at`; jangan mengandalkan waktu device untuk final order.
- Query berurut `(created_at DESC, id DESC)` dengan keyset pagination; render ascending di layar.

### Siklus pengiriman

```text
Compose → local pending bubble → RPC send_chat_text(room_id, content, client_message_id)
      ├── success → merge by server ID / client_message_id → sent
      └── error   → failed → retry with SAME client_message_id
```

Jika request timeout setelah server berhasil menulis, RPC `send_chat_text` mengembalikan pesan lama berdasarkan idempotency key yang sama; jangan membuat message ID client baru. Pastikan pemeriksaan membership tetap dilakukan sebelum mengembalikan pesan lama.

### Fetch dan pemulihan koneksi (P0)

1. Saat thread dibuka: panggil `ensure_task_chat_room`, lalu fetch 30 komentar terbaru.
2. Refresh (ambil komentar setelah cursor terbaru) saat pull to refresh, app kembali ke foreground, atau push untuk task yang sedang terbuka diterima.
3. Hasil refresh di-merge berdasarkan ID dan di-dedupe.
4. Pagination ke atas memakai keyset cursor `(created_at, id)`.
5. Error `forbidden` saat refresh berarti akses dicabut: tutup layar dan bersihkan cache room.

### Push notification (P0)

- iOS meminta izin lewat `UNUserNotificationCenter` setelah layar penjelasan; token APNs dikirim via `register_device_token`.
- Event pemicu: task ditugaskan/reassign (assignee & reviewer baru), submission baru (reviewer), keputusan review (assignee), komentar baru (assignee & reviewer, kecuali pengirim).
- RPC menulis `notification_outbox` dalam transaksi yang sama dengan perubahan data. Database Webhook memanggil Edge Function `send-push`, yang membaca token penerima dengan service role **di server**, mengirim ke APNs memakai APNs auth key dari secrets, lalu menandai `sent_at` atau menaikkan `attempts`.
- Token yang dilaporkan APNs tidak valid dihapus dari `device_tokens`.
- Payload hanya berisi jenis event, judul task, dan `task_id` untuk deep link. Isi komentar/catatan tidak pernah dikirim ke APNs.
- Token disimpan per environment (`sandbox` untuk build debug, `production` untuk TestFlight/App Store).
- Push itu best-effort. Home → Needs Attention selalu dihitung dari data server, bukan dari push.
- Pengingat deadline memakai local notification (`UNCalendarNotificationTrigger`) untuk task milik sendiri yang belum `done`, dijadwalkan ulang setiap app dibuka atau data task berubah. Batas iOS 64 notifikasi lokal terjadwal per app cukup untuk skala MVP.

### Realtime (P0: Group Chat)

Untuk Group Chat: fetch terbatas, subscribe Postgres Changes untuk `chat_messages` room yang dibuka, dedupe event berdasarkan ID, re-fetch saat reconnect/foreground/perubahan sesi untuk *gap recovery*, dan unsubscribe saat keluar room. Realtime tetap bukan pengganti push saat app tertutup.

**Keamanan Realtime:** gunakan SELECT RLS yang sama dengan fetch message; Postgres Changes hanya untuk row yang boleh dibaca. Jangan membuka channel Broadcast publik untuk data sensitif. Jika kelak beralih ke Broadcast/private channel, tambahkan policy `realtime.messages` khusus dan cek efek pencabutan akses.

### Pengendalian abuse

- Batasi panjang teks: 1–2.000 karakter setelah trimming.
- Batas kirim awal (misalnya 20 pesan/menit per pengguna/room) diterapkan **di backend**, bukan hanya client. Nilai akhir divalidasi di test.
- Tidak ada HTML rendering mentah. Link submission dibatasi `https` (ditegakkan di DB dan RPC); link di komentar hanya dibuat tappable bila scheme-nya `https`.
- **Report** (komentar/user), **Block user**, dan **Leave group** wajib ada sebelum TestFlight eksternal, karena App Review Guideline 1.2 meminta mekanisme report dan block untuk konten buatan pengguna. Laporan masuk ke `content_reports` dan diteruskan ke email pengembang; targetkan tindak lanjut dalam 24 jam selama pilot.
- Block menyembunyikan pesan dari tampilan utama. Aksi Tampilkan mengambil pesan secara eksplisit melalui jalur terotorisasi dengan membership tetap diperiksa; jangan menjanjikan Tampilkan jika filtering RLS tidak menyediakan jalur itu.

## 8. Permissions & RLS

PostgreSQL RLS bekerja sebagai perimeter utama. **Client bukan sumber otoritas.**

- Data hanya terbaca oleh member aktif pada group terkait.
- `profiles` boleh dibaca user sendiri atau orang yang berbagi group, tidak semua pengguna publik.
- Mutasi group/project/task/submission/review hanya melalui RPC dengan pemeriksaan role dalam transaksi.
- Insert chat, termasuk teks, **hanya melalui RPC** `send_chat_text` dengan rate limit, idempotency, dan membership. Client tidak diberi hak INSERT langsung pada tabel chat.
- `invitations.token_hash` tidak tersedia via query public; hanya RPC terotorisasi yang mengakses hash.
- `device_tokens`, `notification_outbox`, dan `content_reports` tidak bisa dibaca client; `user_blocks` hanya bisa dibaca pemiliknya.
- SECURITY DEFINER function wajib fixed `search_path`, pemeriksaan `auth.uid()` internal, REVOKE execute dari PUBLIC/anon, GRANT hanya role yang perlu.
- Gunakan test multiuser untuk membuktikan user A tidak dapat membaca/menulis group B dengan mengganti UUID manual.

**Lihat detail desain SQL di [DATABASE_SCHEMA.md](DATABASE_SCHEMA.md).**

## 9. Local data, cache, dan offline

P0:
- `AppStorage`: preferensi lokal nonrahasia (misal onboarding flag).
- `@Observable` state: data sementara selama view aktif.
- Tidak ada local write queue. Jika offline, tidak dapat mutasi task, review, atau kirim pesan.
- Draft chat boleh disimpan di memori selama screen/session berjalan; pengguna diberi informasi jika belum terkirim.
- Clear cache sensitif dan hapus local notifications terjadwal ketika logout, deletion, atau akses grup dicabut.

P1 yang **tidak** dipaksakan sekarang: SwiftData local read cache, draft persistence, pencarian offline, background sync.

## 10. Threat model ringkas

| Ancaman | Dampak | Mitigasi | Test |
|---|---|---|---|
| IDOR mengganti `group_id`/`room_id` | Kebocoran data | RLS membership + RPC authorization | Cross-account SELECT/INSERT ditolak |
| User mengirim system message palsu | Manipulasi status | `type=system` backend-only | INSERT system ditolak |
| Reviewer approve pekerjaan sendiri | Konflik kepentingan | server assert reviewer ≠ author | Self-review gagal |
| Race pada review dan submit | Status inkonsisten | Row lock + optimistic version + unique key | Dua keputusan menghasilkan satu hasil |
| Invite ditebak/diulang | Member ilegal | Random token, stored hash, TTL, quota, rate limit | Token invalid/revoked/full gagal |
| Spam chat/invite | Gangguan/biaya | Server rate limiting, report/remove | Flood test |
| Secrets bocor dari aplikasi | Eskalasi akses | Hanya publishable/anon key di client, tidak ada service_role | Binary/config audit |
| Auth token tertulis ke log | Pembajakan sesi | Redaction + secure SDK storage | Log audit |
| Membership dicabut saat diskusi terbuka | Komentar terus terbaca dari cache | RLS di setiap refresh, screen teardown, hapus cache, short JWT lifetime | Revoke test dengan dua device |
| Tautan berbahaya / konten abusive | Phishing / pelecehan | Aman membuka URL, report workflow, block, content policy | Manual abuse test |
| Link submission non-https | Phishing / skema berbahaya | CHECK constraint https-only + validasi RPC | Insert `javascript:` dan `http:` ditolak |
| Isi push tampil di lock screen | Kebocoran isi diskusi | Payload tanpa isi komentar/catatan | Cek payload di test Edge Function |
| Token push tertinggal setelah logout | Notifikasi nyasar ke akun lain | `unregister_device_token` saat logout, token unik per user | Logout lalu login akun lain di device sama |
| APNs key bocor | Spam push atas nama app | Key hanya di Edge Function secrets, tidak di repo/bundle | Secret audit |

## 11. Testing dan observability

**Unit:** status transition table, form validations, computed progress, DTO mapping, dedup chat.

**Repository integration:** error mapping, paging cursor, refresh merge, retries.

**Push:** satu outbox per penerima per event, Edge Function retry, token invalid dihapus, payload tanpa konten sensitif, uji di iPhone fisik dengan build debug (sandbox) dan TestFlight (production).

**Database integration (wajib):** 2–3 akun uji, RLS SELECT/INSERT silang group, invalid JWT, self approval, invite capacity, review race, idempotency, access revoke.

**UI:** VoiceOver, Dynamic Type, keyboard, offline/error, long messages, sheet dismissal, deep links.

**Logging:** log event teknis teranonimkan (API error code, latency, reconnect), **jangan** log body chat, Apple identity token, invite token, token push, atau tautan privat. Gunakan error reporting dengan kebijakan privasi yang jelas.

## 12. Build and deployment

0. Prasyarat: Mac dengan Xcode terbaru, akun Apple Developer Program berbayar (wajib untuk Sign in with Apple, push, dan TestFlight), iPhone fisik, dan domain untuk Universal Links.
1. Buat Supabase project `dev` dan `staging` terpisah bila memungkinkan; SQL migrasi disimpan di repo.
2. Jangan commit `.env`, token, service key, sertifikat atau file kredensial.
3. Konfigurasi `SUPABASE_URL`, `SUPABASE_PUBLISHABLE_KEY` via build config, jangan masukkan `service_role` ke bundle.
4. Jalankan migrasi, seed **data dummy**, dan integration tests sebelum Xcode app diarahkan ke environment.
5. Setup App ID dengan capability Sign in with Apple, Push Notifications, dan Associated Domains; Supabase Apple provider; APNs auth key (.p8) di Edge Function secrets; file `apple-app-site-association` di domain.
6. Distribusi melalui TestFlight, siapkan feedback channel, privacy policy, dan account deletion.
7. Lakukan review security/UX/feature sebelum mengundang pengguna nonteknis.

## 13. References resmi (cek versi SDK saat implementasi)

- [Apple: Managing model data in SwiftUI](https://developer.apple.com/documentation/SwiftUI/Managing-model-data-in-your-app)
- [Apple: Understanding NavigationStack](https://developer.apple.com/documentation/swiftui/understanding-the-navigation-stack)
- [Supabase: Native Apple ID-token sign-in (Swift)](https://supabase.com/docs/reference/swift/auth-signinwithidtoken)
- [Supabase: Row Level Security](https://supabase.com/docs/guides/database/postgres/row-level-security)
- [Supabase: Database functions](https://supabase.com/docs/guides/database/functions)
- [Supabase: Realtime Postgres Changes](https://supabase.com/docs/guides/realtime/postgres-changes)
- [Supabase: Realtime security](https://supabase.com/docs/guides/realtime/authorization)
- [Supabase: Edge Functions](https://supabase.com/docs/guides/functions)
- [Supabase: Database Webhooks](https://supabase.com/docs/guides/database/webhooks)
- [Apple: User Notifications](https://developer.apple.com/documentation/usernotifications)
- [Apple: Supporting universal links](https://developer.apple.com/documentation/xcode/supporting-universal-links-in-your-app)
- [Apple: App Review Guidelines 1.2 User-Generated Content](https://developer.apple.com/app-store/review/guidelines/#user-generated-content)

> SQL di dokumentasi berikut adalah **rancangan basis implementasi**. Harus diuji dan dimigrasikan secara bertahap pada project dev sebelum digunakan di production.
