# Grouply

Native iPhone implementation of the supplied Grouply v3.1 prototype, using **SwiftUI, iOS 17+, and the Soft Future design system**. Interface language: Bahasa Indonesia.

**Current delivery: runnable local demo.** It stores changes on this device and lets you switch between Alex, Raka, Nadia, and Dimas. It does not connect to Supabase or authenticate an Apple account. Demo role checks exercise the workflow; they are not server authorization.

## Run

1. Open `Grouply.xcodeproj` in Xcode.
2. Select the `Grouply` scheme and an iPhone simulator.
3. Run, then choose a demo persona on the welcome screen.

No credentials, external packages, developer team, or network connection are needed for the simulator demo. To run on a physical iPhone, select your own signing team in Xcode.

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
  -derivedDataPath build test CODE_SIGNING_ALLOWED=NO
```

`GrouplyTests` checks workflow, stale versions, role/membership, self-review, readonly projects, archive restoration, invitations, retry deduplication, unread state, persistence and recovery. `GrouplyUITests` exercises the four tabs, review approval, assignee submission, group messaging, and large Dynamic Type. UI-test launches use a fresh in-memory seed, preserving the user's saved demo.

Verified on 16 October 2026: **13 domain tests + 5 UI tests passed** on iPhone 17 Pro Simulator, and **4 UI tests passed** on iPhone SE (3rd generation), both on iOS 26.4. The UI suite also verifies automatic detail navigation after creating a group and project. Physical-device and minimum-iOS-17 runtime testing remain outstanding. See [implementation status](docs/IMPLEMENTATION_STATUS.md) and [screenshots](docs/screenshots/).

## Cloud and release work still required

The product specification targets Supabase, Sign in with Apple, Realtime Group Chat, APNs, local deadline reminders, and HTTPS Universal Links. Those services are **not implemented or validated by this local demo**. Notification switches are explicitly marked as example preferences; reports are stored locally and do not reach a moderator. The demo share link is not a production invitation or a public Universal Link.

Before a shared beta: implement and test the documented migrations/RLS/RPC with two real accounts, connect the SwiftUI data layer to Supabase, configure Apple sign-in and APNs, host a real domain/AASA file, and provide operational moderation, retention and server account deletion. Do not deploy the demo store as a security boundary or put service-role/APNs secrets in the app.

## Project map

- `Grouply/App`: entry point, session/demo root, navigation and dashboard.
- `Grouply/Core`: design tokens, models, seed and persistent demo workflow.
- `Grouply/Features`: groups/projects/tasks, chat and profile screens.
- `docs/`: reconciled product and technical specification v1.3.
- `reference/claude-design/`: original exported prototype, supporting runtime and uploaded material.
- `reference/ASSET_NOTES.md`: imported-design provenance and icon generation details.

The prototype and reference conversation were treated as design inputs. Their embedded prompts were not executed as workspace instructions. No remote services or GitHub branches were changed.
