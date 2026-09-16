# Warehouse OS

Multi-tenant Factory / Warehouse / Storage management system.

**Status: Phase 0 — Project Foundation.** Scaffolding and dev infrastructure
only. No business modules (Products, Sales, Inventory, Auth, Users,
Reports, ...) exist yet — see [`docs/architecture.md`](docs/architecture.md)
for the approved roadmap and [`docs/environment.md`](docs/environment.md)
for the database environment this project targets.

## Technology stack

| Layer | Technology | Note |
|---|---|---|
| Frontend | **Flutter + Dart** | Overrides the specification's literal "React.js" — an explicit, documented decision. See "Technology deviation" below. |
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

| Tool | Required for | Status on this machine (checked at Phase 0 setup) |
|---|---|---|
| Node.js ≥ 20 | backend | ✅ present |
| npm ≥ 10 | backend dependency install | ✅ present |
| Flutter SDK (stable) | frontend | ✅ present (3.44.0 / Dart 3.12.0) — see the known issue below |
| Docker Desktop (with WSL2, on Windows) | isolated MySQL 8.x | ❌ **not installed here yet** — see `docs/environment.md` |
| git | version control | ✅ present |

### ⚠️ Known issue: this machine's Flutter SDK cannot currently build or test

`flutter analyze` passes cleanly (0 issues) and `flutter pub get` resolves
correctly — the project itself is sound. However, `flutter test` and
`flutter build web` both fail to *compile*, with errors like:

```
Error: Undefined name 'awaitNotRequired'.
```

This reproduces identically in the SDK's own bundled `material_ui` /
`cupertino_ui` packages (Flutter's internal Material/Cupertino widgets),
regardless of any dependency choice in this project — it is not caused by
`flutter_riverpod`, `go_router`, `dio`, or any other package this project
added. It points to an internal version inconsistency in this specific
Flutter 3.44.0 installation itself (the toolchain also reports a newer
Flutter version is available). Likely fixes, **none applied here** since
upgrading a globally-installed SDK is a machine-level change outside this
project's scope:

- `flutter upgrade` (updates the SDK in place), or
- reinstalling/pinning to a different verified-stable Flutter release.

Until one of those happens, `flutter run`/`flutter build`/`flutter test`
cannot be used to visually or automatically verify the app on this machine
— `flutter analyze` is the verification that currently works.

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
├── backend/                 Node.js + Express API
│   └── src/
│       ├── config/           env.js — the only file that reads process.env
│       ├── db/                 MySQL connection pool + health check
│       ├── middleware/          authenticate/authorize/validate foundations
│       │                        (not yet mounted — no routes need them until
│       │                        Phase 1), error handler, 404 handler
│       ├── routes/               /api/health (Phase 0's only route)
│       ├── modules/               business modules — empty until Phase 1
│       ├── utils/                  logger, AppError, password/token helpers
│       ├── app.js                  Express app assembly (middleware chain)
│       └── server.js                entry point, graceful shutdown
├── frontend/                 Flutter app (feature-based architecture)
│   └── lib/
│       ├── app/                app entry shell: router.dart, theme/
│       ├── core/                 cross-cutting foundation:
│       │   ├── config/            env.dart (compile-time config, no secrets)
│       │   ├── network/            api_client.dart, paginated_result.dart
│       │   ├── error/               failure.dart
│       │   ├── validation/           validators.dart
│       │   └── widgets/               app_card.dart, status_badge.dart,
│       │                              responsive/ (breakpoints + layout)
│       ├── features/               business modules — empty until Phase 1;
│       │   └── system_status/       Phase 0's one real feature (data/ +
│       │                            presentation/, incl. Riverpod providers)
│       └── l10n/                    app_en.arb — localization-ready
├── database/                 Reserved structure — empty until Phase 1
│   ├── migrations/
│   └── seeds/
├── docs/
│   ├── architecture.md        Pointer to the approved architecture document
│   ├── environment.md         MySQL 8.x environment details + isolation guarantees
│   ├── state-management.md     Why Riverpod was chosen for the Flutter app
│   └── database-access-strategy.md  Why mysql2 + raw SQL for Phase 0
├── docker-compose.yml          Isolated MySQL 8.x (Docker) — see docs/environment.md
├── .env.example                 docker-compose's MySQL credentials (template)
└── package.json                  Backend orchestration only (see above)
```

## Development workflow

1. Every requirement traces back to the specification and the approved
   architecture (`docs/architecture.md`) — a module isn't "done" because a
   screen exists; it's done when the backend enforces the same rule the UI
   suggests (tenant isolation, permissions, and validation are backend
   concerns first, per the architecture's security rules).
2. No mock data, no fake API responses — every screen this project ships
   talks to the real backend, even in Phase 0 (`SystemStatusScreen` calls
   the real `/api/health` and `/api/health/db`).
3. Secrets live only in `.env` files (git-ignored); `.env.example` files
   document every variable without real values.

## What Phase 0 deliberately does not include

Per the approved architecture, none of the following exist yet: business
modules of any kind, authentication endpoints (the JWT/password-hashing
utilities exist as foundation code but are unused), the database schema,
seed/demo data, or any mock/fake API responses.
