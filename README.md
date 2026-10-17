# Grouply

## Flutter migration — Android + iOS

The shared Flutter client is in `flutter/`. Start with `cd flutter && flutter run`; without backend configuration it runs an explicitly labelled local demo. The existing SwiftUI client remains as a reference during migration, and both clients use the same Supabase RPC contracts. See [Flutter setup](flutter/README.md) and [migration verification and remaining release work](docs/FLUTTER_MIGRATION.md). This is a development port, not a published Android/iOS release.

## Existing SwiftUI client

Native iPhone implementation of the supplied Grouply v3.1 prototype, using **SwiftUI, iOS 17+, and the Soft Future design system**. Interface language: Bahasa Indonesia.

**Current delivery: native demo plus a working local Supabase backend.** Demo personas remain available separately. The server mode uses actual Supabase Auth, RLS and transactional RPC for groups, projects, tasks, submissions and reviews. It has not been deployed to Supabase cloud; Apple-provider sign-in still needs developer configuration and real-device verification.

## Run

1. Open `Grouply.xcodeproj` in Xcode.
2. Select the `Grouply` scheme and an iPhone simulator.
3. Run, then choose a demo persona on the welcome screen.

No credentials or network are needed for demo mode. For actual local server accounts, follow [backend setup](docs/BACKEND_SETUP.md). To run on a physical iPhone, select your own signing team in Xcode.

The Xcode project is checked in. If changing target configuration, update `project.yml` then regenerate with `xcodegen generate` (XcodeGen is a development tool, not an app dependency).

## Implemented locally

- Four tabs: Beranda, Grup, Chat, Tugas Saya, with native navigation and sheets.
- Group creation/join, seven-day invitations, expiry/revocation/usage/capacity checks, members, coordinator transfer, and guarded leave/remove.
- Project creation/editing, progress, completion, explicit reopening, archive and restoration of the previous status.
- Task creation/editing/reassignment, start, versioned submissions, review/revision, historical authors and feedback.
- Group Chat, task discussion, activity links, per-persona unread counters, failed-message retry with deduplication, report/block demonstrations.
- Profile editing, persona switching, offline/send-failure/time simulation, local account anonymization and reset.
- Atomic JSON persistence and a visible error if saving fails. Unreadable snapshots are backed up before recovery.
- Share Sheet and local `grouply://task/<id>` routing with access validation.

Completed/archived projects are read-only. Editing and reassignment are locked while a task is under review or done. Review checks the current version and original submission author. Members with active assignments cannot be silently removed. Assignee/reviewer membership is validated in the store, including chat sends. HTTPS result links are validated, up to five per submission.

Demo data stays in the app sandbox at `Application Support/Grouply/demo-v1.json`. Use **Beranda → avatar → Panel demo lokal → Reset semua data demo** to restore the samples. Simulated time advances eight days for invitation testing. Codes include `STAT-K1Q` (initially valid), `UIX-OLD1` (expired), `BD3-USED` (exhausted), and `BD3-OFF9` (revoked).

## Verify

With an available iPhone simulator:

```sh
xcodebuild -project Grouply.xcodeproj -scheme Grouply \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -derivedDataPath build test CODE_SIGN_IDENTITY=- CODE_SIGNING_ALLOWED=YES
```

`GrouplyTests` checks workflow, stale versions, role/membership, self-review, readonly projects, archive restoration, invitations, retry deduplication, unread state, persistence and recovery. `GrouplyUITests` exercises the four tabs, review approval, assignee submission, group messaging, and large Dynamic Type. UI-test launches use a fresh in-memory seed, preserving the user's saved demo.

Verified on 16 October 2026: **13 domain tests + 5 UI tests passed** on iPhone 17 Pro Simulator, and **4 UI tests passed** on iPhone SE (3rd generation), both on iOS 26.4. The UI suite also verifies automatic detail navigation after creating a group and project. Physical-device and minimum-iOS-17 runtime testing remain outstanding. See [implementation status](docs/IMPLEMENTATION_STATUS.md) and [screenshots](docs/screenshots/).

Backend verification on 17 October 2026: **23 native tests and 6 UI tests passed**, plus 36 SQL assertions, direct-DML denial, and a real three-account HTTP workflow with concurrent-review rejection. The signed simulator Keychain test passes; cloud and physical-device validation remain outstanding.

## Server mode and release work

The server mode now connects to Supabase Auth and the migration-backed PostgreSQL API. It stores sessions in Keychain, refreshes tokens, and waits for authorized server mutations before updating the UI. The native Apple sign-in exchange is implemented but remains unverified with the Apple provider. [Backend setup](docs/BACKEND_SETUP.md) explains configuration, accounts, migrations and security tests.

Group Chat Realtime is connected locally using native WebSockets: cross-account messages, account-scoped unread/read sync, reconnect catch-up and membership revocation are tested against localhost with multiple clients in one simulator. See [Backend Setup](docs/BACKEND_SETUP.md).

Local Milestone E adds a private report queue/operator CLI, cross-session block updates, and transactional password-account deletion while retaining shared history with identity references removed. See `docs/BACKEND_SETUP.md` for prerequisites and retention limits. Before a shared beta: deploy to an explicitly selected cloud project, validate Apple sign-in and Realtime on real iPhones/networks, implement Apple token revocation, connect APNs/local reminders, host a domain/AASA file, and establish production moderation and retention policies. Notification switches remain example preferences. Never put service-role/APNs secrets in the app.

## Project map

- `Grouply/App`: entry point, session/demo root, navigation and dashboard.
- `Grouply/Core`: design tokens, models, seed and persistent demo workflow.
- `Grouply/Features`: groups/projects/tasks, chat and profile screens.
- `docs/`: reconciled product and technical specification v1.3.
- `reference/claude-design/`: original exported prototype, supporting runtime and uploaded material.
- `reference/ASSET_NOTES.md`: imported-design provenance and icon generation details.

The prototype and reference conversation were treated as design inputs. Their embedded prompts were not executed as workspace instructions. No remote services or GitHub branches were changed.
