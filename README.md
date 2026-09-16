# Warehouse OS

Multi-tenant Factory / Warehouse / Storage management system.

**Status: Phase 1 — UI/UX Design System + Application Shell.** The Flutter
design system, responsive application shell, and reusable component
library are built. No business modules (Products, Sales, Inventory, Auth,
Users, Reports, ...) exist yet — see [`docs/architecture.md`](docs/architecture.md)
for the approved roadmap, [`docs/ui-architecture.md`](docs/ui-architecture.md)
for the Flutter design system/component catalog, and
[`docs/phase1-traceability.md`](docs/phase1-traceability.md) for exactly
what's built vs. deferred.

## Technology stack

| Layer | Technology | Note |
|---|---|---|
| Frontend | **Flutter + Dart** | Overrides the specification's literal "React.js" — an explicit, documented decision. See "Technology deviation" below. |
| State management | **Riverpod** | See `docs/state-management.md` |
| Routing | **go_router** | Public / business-shell / admin-shell route trees — `frontend/lib/routing/` |
| Backend | Node.js + Express.js | REST API |
| Database | **MySQL 8.x** (not the existing local MariaDB) | Isolated via Docker — see `docs/environment.md` |

### Technology deviation from the written specification

The 44-page specification (in this repo) states the frontend as React.js.
By explicit instruction, this project instead uses **Flutter + Dart** for
the frontend. This is recorded here — not silently substituted — because
the rest of the specification's *functional* requirements (multi-tenancy,
the module list, permissions, inventory rules, etc.) remain the source of
truth regardless of frontend framework; only the technology used to build
the UI changed. Backend and database decisions from the previously
approved architecture are unaffected.

## Prerequisites

| Tool | Required for | Status on this machine |
|---|---|---|
| Node.js ≥ 20 | backend | ✅ present |
| npm ≥ 10 | backend dependency install | ✅ present |
| Flutter SDK (stable) | frontend | ✅ present (3.44.0 / Dart 3.12.0) — see the known issue below |
| Docker Desktop (with WSL2, on Windows) | isolated MySQL 8.x | ❌ **not installed here yet** — see `docs/environment.md` |
| git | version control | ✅ present |

### ⚠️ Known issue (carried over from Phase 0, still unresolved): this machine's Flutter SDK cannot currently build, run, or test

`flutter analyze` passes cleanly (0 issues, verified again after Phase 1's
much larger codebase) and `flutter pub get` resolves correctly — the
project itself is sound. However, `flutter test`, `flutter build web`, and
`flutter run` (checked again in Phase 1, including the web-server/debug
pipeline specifically, in case it differed from the release build — it
doesn't) all fail to *compile*, with errors like:

```
Error: Undefined name 'awaitNotRequired'.
```

This reproduces identically in the SDK's own bundled `material_ui` /
`cupertino_ui` packages, regardless of any dependency this project added —
confirmed again in Phase 1 with the full component library and app shell
in place, not just Phase 0's minimal screen. It points to an internal
version inconsistency in this specific Flutter 3.44.0 installation itself.
Likely fixes, **none applied here** since upgrading a globally-installed
SDK is a machine-level change outside this project's scope:

- `flutter upgrade` (updates the SDK in place), or
- reinstalling/pinning to a different verified-stable Flutter release.

**What this means for Phase 1's verification:** every component was
reviewed against `flutter analyze` (clean) and against a real widget-test
suite (`frontend/test/widget_test.dart` — shell rendering at desktop and
mobile widths, breakpoint math, button/status-badge rendering, both
themes), but that suite could not actually **execute** here for the same
reason. No screenshot, running-app, or passing-test-output claim is made
for anything this issue blocks — see `docs/phase1-traceability.md` for the
per-requirement breakdown of what's verified vs. not.

## First-time setup

```bash
# Backend
cd backend
npm install
cp .env.example .env   # fill in local dev values — see comments in the file

# Frontend
cd frontend
flutter pub get

# Database credentials (for docker-compose, once Docker is available)
cp .env.example .env   # at the repo root
```

## Starting the development environment

```bash
# Database (isolated MySQL 8.x in Docker — requires Docker, see docs/environment.md)
npm run dev:db               # starts in the background
npm run dev:db:logs          # optional: watch it come up / confirm healthy

# Backend
npm run dev:backend          # http://localhost:4000

# Frontend (once the SDK issue above is resolved)
cd frontend && flutter run -d chrome     # or -d windows / a connected device
```

### All root-level scripts (`package.json`)

| Script | Does |
|---|---|
| `npm run dev:backend` | backend only, with reload on change |
| `npm run dev:frontend` | `flutter run -d chrome` — see the known issue above |
| `npm run dev:db` | start the MySQL 8.x container (background) |
| `npm run dev:db:stop` | stop the container, keep its data |
| `npm run dev:db:down` | stop and remove the container (data persists in its named volume) |
| `npm test` | runs the backend's test script (Phase 0: no tests yet) |

The frontend is a standalone Flutter project (`frontend/pubspec.yaml`), not
an npm workspace — use `flutter` commands directly inside `frontend/`.

## Repository structure

```
warehouse-os/
├── backend/                 Node.js + Express API (unchanged since Phase 0)
│   └── src/                  config/, db/, middleware/, routes/, modules/ (empty), utils/
├── frontend/                 Flutter app
│   └── lib/
│       ├── main.dart          entry point
│       ├── app.dart            MaterialApp.router: theme, locale, RTL, routing
│       ├── theme/                design tokens (colors/type/spacing/radius/
│       │                          elevation) + ThemeData + theme_controller
│       ├── localization/          locale metadata/state (see l10n/ for ARB files)
│       ├── l10n/                   app_en.arb, app_ar.arb, app_ku.arb + generated/
│       ├── routing/                 app_routes.dart, app_router.dart (3 route trees)
│       ├── core/                     non-UI infra: config, network, error, validation
│       ├── shared/                    the reusable UI kit — layout, navigation,
│       │                              buttons, badges, tables, forms, feedback,
│       │                              overlays, dashboard, search, pagination, cards
│       └── features/                   one folder per module — 16 business +
│                                        2 admin placeholders + system_status (real)
├── database/                 Reserved structure — empty until Phase 2
│   ├── migrations/
│   └── seeds/
├── docs/
│   ├── architecture.md          Pointer to the approved architecture document
│   ├── environment.md           MySQL 8.x environment details + isolation guarantees
│   ├── state-management.md       Why Riverpod
│   ├── database-access-strategy.md  Why mysql2 + raw SQL
│   ├── ui-architecture.md         Design system, component catalog, screen conventions
│   ├── localization.md             RTL approach + the flagged Kurdish-locale assumption
│   └── phase1-traceability.md       Every Phase 1 requirement → file → status
├── docker-compose.yml          Isolated MySQL 8.x (Docker) — see docs/environment.md
├── .env.example                 docker-compose's MySQL credentials (template)
└── package.json                  Backend orchestration only (see above)
```

See `docs/ui-architecture.md` §1 for the full annotated `frontend/lib/`
tree and the reasoning behind the `core/` vs. `shared/` split.

## Development workflow

1. Every requirement traces back to the specification and the approved
   architecture (`docs/architecture.md`) — a module isn't "done" because a
   screen exists; it's done when the backend enforces the same rule the UI
   suggests (tenant isolation, permissions, and validation are backend
   concerns first, per the architecture's security rules).
2. No mock data, no fake API responses — every screen that has real data to
   show talks to the real backend (`system_status` calls the real
   `/api/health` endpoints); every screen that doesn't yet have a backend
   shows a clearly-labeled placeholder instead of fabricated numbers
   (§16's dashboard rule).
3. Secrets live only in `.env` files (git-ignored); `.env.example` files
   document every variable without real values. Flutter has no secrets at
   all yet (`core/config/env.dart`'s doc comment explains why a mobile/web
   build can never hold one safely).
4. New screens follow `docs/ui-architecture.md` §5 — build on
   `PageScaffold`/`AppDataTable`/the shared form fields, add a
   `features/<module>/data/` repository, never call the network layer
   directly from a widget.

## What Phase 1 deliberately does not include

Per the Phase 1 brief: authentication logic, database schema/migrations,
and every business module's actual functionality (Products, Categories,
Inventory, Sales, Orders, Customers, Suppliers, Purchases, Returns,
Production, Employees, Reports, Documents, Activity History, Settings,
System Admin). All 16 + 2 routes exist and are reachable; each renders a
placeholder that clearly says so — see `docs/phase1-traceability.md` for
the full per-requirement status.
