# Grouply

## Flutter migration — Android + iOS

The shared Flutter client is in `flutter/`. Run it with backend configuration (`cd flutter && flutter run --dart-define=...`, see [Flutter setup](flutter/README.md)); without it the app only shows a notice that the server is not configured. It supports email sign-in, sign-up and an emailed-code password reset. The existing SwiftUI client remains, and both clients use the same Supabase RPC contracts. See [migration verification and remaining release work](docs/FLUTTER_MIGRATION.md). This is a development port, not a published Android/iOS release.

## Existing SwiftUI client

Native iPhone implementation of the supplied Grouply v3.1 prototype, using **SwiftUI, iOS 17+, and the Soft Future design system**. Interface language: Bahasa Indonesia.

**Current delivery: real accounts on a working local Supabase backend.** Demo mode (personas, seed data, local JSON snapshot and simulation switches) was removed from both clients on 17 October 2026; every screen now shows server data only. The server uses actual Supabase Auth, RLS and transactional RPC for groups, projects, tasks, submissions and reviews. It has not been deployed to Supabase cloud; Apple-provider sign-in still needs developer configuration and real-device verification.

## Run

1. Start the local backend and create the private test accounts: [backend setup](docs/BACKEND_SETUP.md).
2. Open `Grouply.xcodeproj` in Xcode, select the `Grouply` scheme and an iPhone simulator.
3. Run, then choose **Masuk dengan Akun**.

To run on a physical iPhone, select your own signing team in Xcode. The Xcode project is checked in. If changing target configuration, update `project.yml` then regenerate with `xcodegen generate` (XcodeGen is a development tool, not an app dependency).

## Implemented

- Four tabs: Beranda, Grup, Chat, Tugas Saya, with native navigation and sheets.
- Group creation/join, seven-day invitations, members, coordinator transfer, and guarded leave/remove.
- Project creation/editing, progress, completion, explicit reopening, archive and restoration of the previous status.
- Task creation/editing/reassignment, start, versioned submissions, review/revision, historical authors and feedback.
- Group Chat (Realtime), task discussion, activity links, unread counters, failed-send retry with deduplication, report/block.
- Profile editing and account deletion.
- Share Sheet and `grouply://task/<id>` routing with access validation.

Business rules (read-only completed/archived projects, review locks, membership checks, invite expiry/usage/capacity, HTTPS links) are enforced by the server RPC and covered by the SQL suite; the clients only add input validation.

## Verify

With an available iPhone simulator:

```sh
xcodebuild -project Grouply.xcodeproj -scheme Grouply \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -derivedDataPath build test CODE_SIGN_IDENTITY=- CODE_SIGNING_ALLOWED=YES
```

`GrouplyTests` covers the server-only store (actions require an account, unread counts, failed-draft privacy, reopen guard), the mocked HTTP client and, with the local backend running, real integration tests. `GrouplyUITests/BackendUITests` checks the login form. The persona-based UI tests and demo workflow tests were removed together with demo mode.

Verifikasi SwiftUI setelah penghapusan (iPhone 17 Pro Simulator, iOS 26.4): build berhasil; **25 tes unit/integrasi + 1 tes UI lulus**, 0 gagal, termasuk 4 tes integrasi ke Supabase lokal. Satu tes integrasi sempat flaky (sign-out bertabrakan dengan refresh Realtime) dan diperbaiki dengan menunggu store tidak sibuk; 5/5 percobaan ulang lulus. Ini satu simulator + localhost, bukan perangkat fisik atau cloud.

Earlier results (16–17 October 2026, before demo removal) are recorded in [implementation status](docs/IMPLEMENTATION_STATUS.md). Physical-device, minimum-iOS-17 runtime and cloud validation remain outstanding.

## Server mode and release work

The server mode now connects to Supabase Auth and the migration-backed PostgreSQL API. It stores sessions in Keychain, refreshes tokens, and waits for authorized server mutations before updating the UI. The native Apple sign-in exchange is implemented but remains unverified with the Apple provider. [Backend setup](docs/BACKEND_SETUP.md) explains configuration, accounts, migrations and security tests.

Group Chat Realtime is connected locally using native WebSockets: cross-account messages, account-scoped unread/read sync, reconnect catch-up and membership revocation are tested against localhost with multiple clients in one simulator. See [Backend Setup](docs/BACKEND_SETUP.md).

Local Milestone E adds a private report queue/operator CLI, cross-session block updates, and transactional password-account deletion while retaining shared history with identity references removed. See `docs/BACKEND_SETUP.md` for prerequisites and retention limits. Before a shared beta: deploy to an explicitly selected cloud project, validate Apple sign-in and Realtime on real iPhones/networks, implement Apple token revocation, connect APNs/local reminders, host a domain/AASA file, and establish production moderation and retention policies. Notification switches remain example preferences. Never put service-role/APNs secrets in the app.

## Project map

- `Grouply/App`: entry point, session root, navigation and dashboard.
- `Grouply/Core`: design tokens, models and `DemoStore` (the name is historical; it is the server-backed store).
- `Grouply/Features`: groups/projects/tasks, chat and profile screens.
- `docs/`: reconciled product and technical specification v1.3.
- `reference/claude-design/`: original exported prototype, supporting runtime and uploaded material.
- `reference/ASSET_NOTES.md`: imported-design provenance and icon generation details.

The prototype and reference conversation were treated as design inputs. Their embedded prompts were not executed as workspace instructions. No remote services or GitHub branches were changed.
