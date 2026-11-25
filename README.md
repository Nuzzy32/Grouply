<p align="center">
  <img src="docs/assets/readme/logo-gupy.png" width="112" alt="Grouply logo">
</p>

<h1 align="center">Grouply</h1>

<p align="center">
  <strong>Make group work actually work.</strong><br>
  Task ownership, peer review and group chat for student projects and campus organisations,<br>
  on iOS, Android and the web.
</p>

<p align="center">
  <img alt="Flutter" src="https://img.shields.io/badge/Flutter-iOS%20%7C%20Android-02569B?logo=flutter&logoColor=white">
  <img alt="SwiftUI" src="https://img.shields.io/badge/SwiftUI-iOS%2017%2B-F05138?logo=swift&logoColor=white">
  <img alt="SvelteKit" src="https://img.shields.io/badge/SvelteKit-Svelte%205-FF3E00?logo=svelte&logoColor=white">
  <img alt="Supabase" src="https://img.shields.io/badge/Supabase-Postgres%20%2B%20RLS-3FCF8E?logo=supabase&logoColor=white">
  <img alt="Status" src="https://img.shields.io/badge/status-pre--release-lightgrey">
  <a href="LICENSE"><img alt="License: Apache 2.0" src="https://img.shields.io/badge/License-Apache%202.0-blue.svg"></a>
</p>

<p align="center">
  <a href="#overview">Overview</a> ·
  <a href="#features">Features</a> ·
  <a href="#meet-gupy">Gupy</a> ·
  <a href="#architecture">Architecture</a> ·
  <a href="#getting-started">Getting started</a> ·
  <a href="#testing">Testing</a> ·
  <a href="#project-status">Status</a> ·
  <a href="#documentation">Docs</a>
</p>

---

## Overview

Group assignments usually live in a chat thread: tasks get buried, results are hard to find, and nobody is sure what is still waiting for review. Grouply does not replace WhatsApp or Google Docs. It is the coordination layer on top of them:

- **Clear ownership.** Every task has one assignee, one reviewer and a deadline.
- **Submit → review → approve or revise.** Work is submitted as an append-only, versioned record and reviewed against the current version only.
- **Discussion where it belongs.** A realtime chat per group, plus a discussion thread on each task.
- **Built for organisations too.** Divisions, committees, meetings, approvals and period handover for student organisations on the paid Organization Plan.

The product interface is in Bahasa Indonesia.

## Features

### Core (free)

| Area | Included |
|---|---|
| **Groups** | Invite codes (7-day expiry, revocable, usage limit, up to 8 members), coordinator transfer, guarded leave and remove |
| **Projects** | Progress tracking, completion only when every task is done, explicit reopen, archive that keeps the previous status |
| **Tasks** | Create, edit and reassign (coordinator), versioned submissions with a note, HTTPS links and up to 3 files (PDF, images, Office documents, 10 MB each), approve or request revision |
| **Contribution** | Per-member share of completed tasks on each project, shown in the app and on the web |
| **Chat** | Realtime group chat, unread counters, retry with deduplication, report and block |
| **Account** | Email sign-in and sign-up, password reset by emailed code, profile, account deletion that anonymises shared history |
| **Experience** | Onboarding with Gupy, light and dark mode, the Soft Future design system across all clients |

### Organization Plan (paid)

| Stage | Included |
|---|---|
| **Foundation** | Organisation workspace with divisions, roles (Chair, Board, Division Head, Staff, Advisor), per-person seats, multi-use invites, organisation dashboard |
| **Daily work** | Cross-division committees, tiered approvals, meetings with minutes and follow-up tasks, announcements with read receipts |
| **Yearly cycle** | Project templates, period close and handover with a read-only archive, activity report (LPJ) recap and CSV export |

Activation is handled manually by an operator for now; there is no in-app payment. Organisation features are available in the Flutter client only.

Business rules (membership checks, read-only completed projects, review locks, invite and seat limits, storage access) are enforced on the server through row-level security and transactional RPCs. Clients only add input validation.

## Meet Gupy

<table>
  <tr>
    <td align="center" width="25%"><img src="docs/assets/readme/gupy/wave.png" width="140" alt="Gupy waving"><br><sub>Hello</sub></td>
    <td align="center" width="25%"><img src="docs/assets/readme/gupy/clipboard.png" width="140" alt="Gupy holding a clipboard"><br><sub>Split the work</sub></td>
    <td align="center" width="25%"><img src="docs/assets/readme/gupy/phone.png" width="140" alt="Gupy holding a phone"><br><sub>Submit, review, chat</sub></td>
    <td align="center" width="25%"><img src="docs/assets/readme/gupy/celebrate.png" width="140" alt="Gupy celebrating"><br><sub>Done together</sub></td>
  </tr>
</table>

Gupy is Grouply's mascot, a friendly purple clay-style dino. Gupy guides new users through onboarding and appears across the Flutter app and the website. Animations are pre-rendered (24 fps, transparent animated WebP) from a layered rig; see [the mascot design notes](docs/DESIGN-onboarding-mascot.md) and the [character sheet](docs/assets/grouply-mascot-character-sheet.png).

## Architecture

```
┌──────────────────┐  ┌──────────────────┐  ┌──────────────────┐
│ Flutter          │  │ SwiftUI          │  │ SvelteKit web    │
│ iOS · Android    │  │ iOS 17+ (legacy) │  │ landing + app    │
└────────┬─────────┘  └────────┬─────────┘  └────────┬─────────┘
         └──── Supabase Auth · RPC · Realtime · Storage ────┘
                              │
                ┌─────────────┴─────────────┐
                │ Supabase (PostgreSQL)     │
                │ RLS · grouply_snapshot    │
                │ grouply_mutate · storage  │
                └───────────────────────────┘
```

- **One contract for every client.** All clients call the same public RPCs (`grouply_snapshot`, `grouply_mutate`) with camelCase payloads. The server is the single source of truth.
- **Server-first writes.** The UI waits for the server before showing a change; there is no local write fallback.
- **Private file storage.** Submission files live in a private bucket; only the assignee of an open task can upload, and only group members can read.
- **Secure sessions.** Tokens live in the Keychain (iOS) or platform secure storage (Flutter), never in preferences or plain files.
- **Realtime.** Chat messages, read receipts and sync state arrive over WebSockets and trigger a snapshot refresh; reconnects catch up on missed changes.

| Layer | Stack |
|---|---|
| Mobile client | Flutter, Dart, `supabase_flutter`, `flutter_secure_storage`, `file_picker` |
| Web client | SvelteKit, Svelte 5, TypeScript, plain CSS, `@supabase/supabase-js` |
| Legacy iOS client | Swift, SwiftUI, URLSession WebSocket, XcodeGen |
| Backend | Supabase Auth, PostgreSQL with RLS, PL/pgSQL RPCs, Realtime, Storage |
| Tests | `flutter_test`, XCTest, SQL assertions, local HTTP and integration suites |

## Getting started

### Prerequisites

- [Flutter](https://docs.flutter.dev/get-started/install) 3.41+ (Xcode for iOS, Android Studio for Android)
- Node.js 20+ for the web client
- [Supabase CLI](https://supabase.com/docs/guides/cli) and Docker (or OrbStack)
- Python 3 for the local setup scripts

### 1. Start the local backend

```sh
supabase start -x imgproxy,postgres-meta,studio,edge-runtime,logflare,vector,supavisor
python3 scripts/backend_local.py setup
```

The setup script writes the public client configuration (`flutter/dart_defines.local.json`, `web/.env`, `Config/Local.xcconfig`) and keeps local test-account credentials outside the repository. Grouply uses its own ports (API `55321`, database `55322`, mail `55324`) so it does not clash with other Supabase projects. Details: [docs/BACKEND_SETUP.md](docs/BACKEND_SETUP.md).

### 2. Run a client

**Flutter (iOS or Android)**

```sh
cd flutter
flutter pub get
flutter run --dart-define-from-file=dart_defines.local.json
```

On the Android emulator the local API is `http://10.0.2.2:55321`. More in [flutter/README.md](flutter/README.md).

**Web**

```sh
cd web
npm install
npm run dev
```

The site runs at `http://localhost:5173`. More in [web/README.md](web/README.md).

**SwiftUI (legacy iOS)**

Open `Grouply.xcodeproj`, select the `Grouply` scheme and an iPhone simulator, then run. The SwiftUI client is kept for reference and does not include organisation, attachment or mascot features.

## Testing

```sh
# Flutter: static analysis and unit/widget tests
cd flutter && flutter analyze && flutter test

# Flutter: integration tests against the local backend (opt-in)
GROUPLY_LOCAL_INTEGRATION=1 flutter test test/local_backend_test.dart

# Web: type check and production build
cd web && npm run check && npm run build

# Organisation lock order and billing checks
python3 scripts/billing_local.py check-locks

# SwiftUI: unit, integration and UI tests
xcodebuild -project Grouply.xcodeproj -scheme Grouply \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -derivedDataPath build test CODE_SIGN_IDENTITY=- CODE_SIGNING_ALLOWED=YES
```

The SQL suites in `supabase/tests/` cover RLS, workflow rules, organisations, submission files and account deletion. Integration tests run only against the local backend and create their own fixtures.

## Project status

Grouply is in active development and **not yet released**.

| Built and tested locally | Not done yet |
|---|---|
| Auth, RLS and transactional RPCs on local Supabase | Deployment to a Supabase cloud project |
| Realtime chat with unread sync and reconnect | Testing on physical devices and real networks |
| Organization Plan stages 1, 2 and 3a (Flutter) | Push notifications (APNs/FCM) and server reminders |
| Submission files and contribution card | Sign in with Apple and token revocation |
| Website: landing page and signed-in app | Web hosting, app store and Play Store builds |
| Onboarding with Gupy, light and dark mode | In-app payment for the Organization Plan |

Verification evidence and known gaps: [docs/IMPLEMENTATION_STATUS.md](docs/IMPLEMENTATION_STATUS.md) and [docs/FLUTTER_MIGRATION.md](docs/FLUTTER_MIGRATION.md).

## Repository layout

```
flutter/            Flutter client for iOS and Android (primary)
web/                SvelteKit landing page and web app
supabase/           Migrations, SQL tests, config and email templates
scripts/            Local backend setup, billing and operator tools
docs/               Product and technical specification
Grouply/            SwiftUI client (legacy)
GrouplyTests/       XCTest unit and integration tests
GrouplyUITests/     XCTest UI tests
reference/          Original design prototypes (reference only)
```

## Documentation

The specification is written in Bahasa Indonesia.

| Document | Contents |
|---|---|
| [PRD](docs/PRD.md) | Product requirements and business rules |
| [Organization Plan PRD](docs/PRD-organization-plan.md) | Paid plan scope and pricing tiers |
| [Organisation design](docs/DESIGN-org-tahap1.md) · [stage 2](docs/DESIGN-org-tahap2.md) · [stage 3](docs/DESIGN-org-tahap3.md) | Organisation data model and flows |
| [User flow](docs/USER_FLOW.md) | Screens and flows |
| [Architecture](docs/ARCHITECTURE.md) | System design and contracts |
| [Database schema](docs/DATABASE_SCHEMA.md) | Target data model |
| [Design system](docs/DESIGN_SYSTEM.md) · [Dark theme](docs/DARK_THEME.md) | Soft Future tokens and components |
| [Mascot](docs/DESIGN-onboarding-mascot.md) | Gupy poses, animation and onboarding |
| [Roadmap](docs/ROADMAP.md) | Milestones and test plan |
| [Backend setup](docs/BACKEND_SETUP.md) | Local Supabase, accounts and security tests |

## License

Licensed under the [Apache License 2.0](LICENSE).
