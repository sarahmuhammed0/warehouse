# Warehouse OS

Multi-tenant Factory / Warehouse / Storage management system.

**Status: Phase 3 — Database + Backend Foundation, written but NOT yet
verified against a live database.** The full operational schema (43 tables
across 18 migrations) and the shared backend machinery every business module
will use are written: transactions, parameterised data access, validation,
error mapping, pagination, and allowlisted filtering/sorting. Unit tests pass
(67/67) and the frontend is unaffected (`flutter analyze` clean, 139/139
tests).

**One step is outstanding and it blocks the rest:** the development database
and its application user have never been provisioned on this machine's MySQL
instance, so **no migration has ever been applied and the integration tests
have never run** — see "Database" below for the command to fix that, which
has to be typed by a human because it prompts for the MySQL administrator
password.

**No business-module API exists yet** — no products, categories, inventory,
sales, orders, customers, suppliers, purchases, returns, production, reports
or PDF endpoints, and no RBAC enforcement. Those are later phases,
deliberately. The Flutter app therefore still runs in Demo Mode with the
backend off, exactly as before. Read
[`docs/backend-phase3.md`](docs/backend-phase3.md) for the design and
[`docs/phase3-traceability.md`](docs/phase3-traceability.md) for exactly what
is verified versus what still needs a live database.

**Previously: frontend-first phase — the full business-module UI is built.**
Backend development is deliberately paused this phase (per explicit
instruction) in favor of completing the Flutter frontend for every module
the specification describes: Products (incl. variants), Categories,
Inventory (stock/locations/transfers/alerts), Sales, Orders, Customers,
Suppliers, Purchases, Returns, Production (incl. BOM), Employees/Roles/
Permissions, Reports, Documents/PDF preview, Activity History,
Notifications, Global Search, Settings (10 sections), and — previously
deferred — the System Admin dashboard and business-detail screens. Every
screen is real and navigable, built on the shared design system, backed by
a clearly-isolated local/demo data layer (never a live backend) — see
[`docs/frontend-coverage.md`](docs/frontend-coverage.md) for the full
requirement-by-requirement status and
[`docs/frontend-backend-contract-notes.md`](docs/frontend-backend-contract-notes.md)
for exactly what each module expects a real API to look like once backend
work resumes.

Phase 2's real, backend-verified authentication (phone + password login,
JWT/refresh handling, secure token storage, routing guards, System Admin
auth foundation) is **untouched** — see
[`docs/authentication.md`](docs/authentication.md),
[`docs/multi-tenancy.md`](docs/multi-tenancy.md),
[`docs/security.md`](docs/security.md),
[`docs/database.md`](docs/database.md), and
[`docs/phase2-traceability.md`](docs/phase2-traceability.md) for that
phase's design in full — none of it changed this phase.

## Technology stack

| Layer | Technology | Note |
|---|---|---|
| Frontend | **Flutter + Dart** | Overrides the specification's literal "React.js" — an explicit, documented decision. See "Technology deviation" below. |
| State management | **Riverpod** | See `docs/state-management.md`; Phase 2 adds the auth state machine (`AuthController`/`AuthState`) |
| Routing | **go_router** | Public / business-shell / admin-shell route trees, now with real auth-based redirect guards — `frontend/lib/routing/app_router.dart` |
| HTTP client | **Dio** | `core/network/`; Phase 2 adds `AuthInterceptor` (token attach + single loop-safe refresh-and-retry) |
| Secure storage | **flutter_secure_storage** | Access/refresh tokens — Keystore/Keychain/Credential Manager per platform, see `core/storage/secure_token_storage.dart` |
| Backend | Node.js + Express.js | REST API |
| Auth | **JWT (access) + opaque hashed refresh tokens** | Not both JWT — see `docs/authentication.md`'s "Token shape" for why |
| Database | **MySQL 8.x** (never the existing local MariaDB) | See "Database" below and `docs/database.md` / `docs/environment.md` |
| Migrations | **Knex.js** (migrations only — runtime queries stay raw `mysql2/promise`) | See `docs/database-access-strategy.md` |

### Technology deviation from the written specification

The 44-page specification (in this repo) states the frontend as React.js.
By explicit instruction, this project instead uses **Flutter + Dart** for
the frontend. This is recorded here — not silently substituted — because
the rest of the specification's *functional* requirements (multi-tenancy,
the module list, permissions, inventory rules, etc.) remain the source of
truth regardless of frontend framework; only the technology used to build
the UI changed. Backend and database decisions from the previously
approved architecture are unaffected.

Phase 2 records two further deviations, both driven by consequences of the
React→Flutter switch and by the Phase 2 brief's own explicit instruction —
see `docs/authentication.md`'s "Recorded deviations" for the full reasoning:
System Admin identity lives in a **structurally separate table**
(`system_admins`), not an `is_system_admin` flag on business users; and
sessions are carried as **Bearer tokens in secure device storage**, not
httpOnly cookies (a browser-only mechanism that doesn't map onto Flutter's
desktop/mobile/web targets uniformly).

## Prerequisites

| Tool | Required for | Status on this machine |
|---|---|---|
| Node.js ≥ 20 | backend | ✅ present |
| npm ≥ 10 | backend dependency install | ✅ present |
| Flutter SDK (stable) | frontend | ✅ present (3.44.0 / Dart 3.12.0) — see `docs/toolchain-fix.md` if you hit the resolved Phase 1.5 SDK issue |
| MySQL 8.x reachable on `127.0.0.1:3307` | backend database | 🟡 **not yet reachable on this machine** — see "Database" below |
| git | version control | ✅ present |

## Database

**MySQL 8.x on port 3307 — never the pre-existing local MariaDB on port
3306.** This project's `docker-compose.yml` provisions an isolated MySQL 8.4
container for machines with Docker available. On *this* development
machine, Docker isn't installed; instead, Phase 2 found a **native Windows
MySQL80 service** already listening on the same isolated port and asked the
user to provision the app database/user directly rather than guess
credentials. Either path is valid — what matters is that `backend/.env`
points at an isolated MySQL 8.x instance on port 3307, not at MariaDB on
3306. See [`docs/environment.md`](docs/environment.md) and
[`docs/database.md`](docs/database.md) for the full story, including the
exact provisioning SQL used and the **current honest verification status**.

Phase 3 added the full operational schema — 43 tables across 18 migrations —
and a repeatable way to finish provisioning:

Run these **in a real terminal window** — `db:provision` reads its password
from the TTY and will refuse to run through a pipe or a tool that captures
output:

```bash
cd backend
npm run db:provision   # prompts for the MySQL administrator password (hidden,
                       # never logged or written to disk); reads everything else
                       # from .env, and grants the app user only what it needs
npm run migrate
npm run migrate:status
npm run db:verify      # read-only: prints the server's own version, engine,
                       # charset, grants and every table
npm run test:integration
```

**The app database user still cannot connect** (`ER_ACCESS_DENIED_ERROR`),
because the database and user have never been provisioned on this MySQL
instance — the MySQL 8 server itself is up and verified on 3307, only the
schema and the user are missing. So **migrations have never been applied and
the integration tests have never executed** (0 passed, 22 skipped, 0
failed — skipped is not passed). Everything about the schema is validated
statically only. See
[`docs/phase3-traceability.md`](docs/phase3-traceability.md)'s "Live
verification status" for the per-check breakdown. Read
[`docs/backend-phase3.md`](docs/backend-phase3.md) before changing the
schema.

## Environment variables

`backend/.env` (git-ignored; copy from `backend/.env.example`):

| Variable | Purpose |
|---|---|
| `NODE_ENV`, `PORT`, `CORS_ORIGIN`, `LOG_LEVEL` | Server basics (Phase 0) |
| `DB_HOST`, `DB_PORT`, `DB_NAME`, `DB_USER`, `DB_PASSWORD`, `DB_CONNECTION_LIMIT`, `DB_CONNECT_TIMEOUT_MS` | MySQL 8.x connection — must point at the isolated instance, see "Database" above |
| `JWT_SECRET` | Access-token signing key — generate locally with `node -e "console.log(require('crypto').randomBytes(48).toString('hex'))"`, never commit a real value |
| `JWT_ACCESS_TTL` / `JWT_REFRESH_TTL` | Token lifetimes (`15m` / `30d` in dev) |
| `BCRYPT_SALT_ROUNDS` | Password hashing cost factor (`12`) |
| `SEED_ADMIN_PHONE` / `SEED_ADMIN_PASSWORD` / `SEED_ADMIN_NAME` | Optional — bootstraps exactly one System Admin via `npm run seed`; no hardcoded credentials, no-ops if unset |
| `MYSQL_ADMIN_USER` / `MYSQL_ADMIN_SSL` | Optional, used only by `npm run db:provision` (defaults: `root`, off). **There is deliberately no `MYSQL_ADMIN_PASSWORD`** — the administrator password is typed at a hidden prompt and never stored; see [`docs/environment.md`](docs/environment.md)'s "The one documented exception" |

Every variable above is declared in `backend/src/config/env.js`, which is the
only file in the project that reads `process.env` — the app, `knexfile.js`,
both `backend/scripts/`, and the System Admin seed all import `env` from it.

Root `.env` (git-ignored; copy from root `.env.example`) is read only by
`docker-compose.yml`, for machines using the Docker path.

## First-time setup

```bash
# Backend
cd backend
npm install
cp .env.example .env   # fill in real local values — see "Environment variables" above

# Frontend
cd frontend
flutter pub get

# Database (pick one)
#   A) Docker available: cp .env.example .env at the repo root, then `npm run dev:db`
#   B) Otherwise: point backend/.env at a MySQL 8.x instance on 127.0.0.1:3307,
#      then run: cd backend && npm run db:provision
#      (prompts for the MySQL administrator password; creates the database
#       and the app user with least-privilege grants)
```

## Starting the development environment

```bash
# Database (Docker path — skip if you provisioned MySQL yourself, see above)
npm run dev:db               # starts in the background
npm run dev:db:logs          # optional: watch it come up / confirm healthy

# Backend
npm run dev:backend          # http://localhost:4000
# Run migrations once the database is reachable:
cd backend && npm run migrate && npm run db:verify

# Frontend
cd frontend && flutter run -d chrome     # or -d windows / a connected device
```

### All root-level scripts (`package.json`)

| Script | Does |
|---|---|
| `npm run dev:backend` | backend only, with reload on change |
| `npm run dev:frontend` | `flutter run -d chrome` |
| `npm run dev:db` | start the MySQL 8.x container (background) |
| `npm run dev:db:stop` | stop the container, keep its data |
| `npm run dev:db:down` | stop and remove the container (data persists in its named volume) |
| `npm test` | runs the backend's test script |

### Backend scripts (`backend/package.json`)

| Script | Does |
|---|---|
| `npm run dev` | `nodemon src/server.js` |
| `npm test` | unit + integration tests (`node --test`) |
| `npm run test:unit` | unit tests only — no live database required |
| `npm run test:integration` | integration tests — skip cleanly (not fake-pass) if MySQL is unreachable |
| `npm run migrate` / `migrate:rollback` / `migrate:status` | Knex migrations |
| `npm run migrate:make <name>` | scaffold a new migration in `database/migrations/` |
| `npm run db:provision` | create the database + app user; prompts for the administrator password (hidden), reads the rest from `.env` |
| `npm run db:verify` | read-only report of what the live server actually says: version, port, engine, charset, grants, tables |
| `npm run seed` | runs `database/seeds/system/001_system_admin.js` |

The frontend is a standalone Flutter project (`frontend/pubspec.yaml`), not
an npm workspace — use `flutter` commands directly inside `frontend/`.

## Authentication

Phone + password login for two structurally separate account types —
business users (`POST /api/auth/login`) and System Admins
(`POST /api/admin/auth/login`) — backed by a short-lived JWT access token
and a rotating, revocable, hashed opaque refresh token. No hardcoded
credentials, no mock login, no bypass path anywhere in the codebase.

Full design, the account-separation rationale, token lifetimes, login
protection/rate limiting, and the two recorded deviations from the original
architecture: **[`docs/authentication.md`](docs/authentication.md)**.

## Frontend-only demo mode

The frontend can run **fully independently of the backend** for UI testing —
default in every local/test run, no `--dart-define` needed. The login screen
offers two one-tap demo entry points (Business and System Admin) that sign in
through a local `DemoAuthRepository`, never touching Dio/the network; every
business module still reads from the same `Local*Repository`/demo-data layer
described above, so the whole app — every module, CRUD, search/filter/
pagination, System Admin screens, logout/re-login — is fully navigable with
the backend completely off. A small "DEMO MODE" badge marks the shell
whenever this mode is active. The real backend-mode auth path
(`ApiAuthRepository`, JWT/refresh, secure storage, route guards) is untouched
and selectable via `--dart-define=APP_MODE=backend` — see
**[`docs/frontend-demo-mode.md`](docs/frontend-demo-mode.md)** for the full
architecture, the central `AppModeConfig` switch, and why the mode is never
silently auto-selected after a real backend error.

## Multi-tenancy

Shared database, shared schema — every business-owned row carries
`business_id`, sourced only from the authenticated session
(`req.auth.businessId`), never from client input. System Admin is the one
explicit, separately-gated exception. A mandatory automated test proves two
businesses' data never leaks across a session.

Full enforcement mechanism and the System Admin boundary:
**[`docs/multi-tenancy.md`](docs/multi-tenancy.md)**.

## Security

Full item-by-item review against the approved architecture's security
checklist — what's built and verified, what's built but pending live-DB
verification, and what's explicitly deferred:
**[`docs/security.md`](docs/security.md)**.

## Testing

**Backend** (`backend/`, `node --test` + `supertest`):

```bash
npm test              # unit + integration
npm run test:unit      # 31 tests — phone/password/token utilities, authenticate/
                        # requireAccountType middleware, Zod validation schemas
                        # (no live database required)
npm run test:integration  # login flow, session lifecycle, mandatory tenant-isolation
                            # test, admin business-creation — skip cleanly (not
                            # fake-pass) when MySQL is unreachable, see docs/database.md
```

**Frontend** (`frontend/`, `flutter_test`):

```bash
flutter analyze        # 0 issues
flutter test           # 136 tests — app shell, RTL/localization, routing guards,
                         # data table states, pagination, dialogs/overlays, the full
                         # login-screen suite (Phase 2), this phase's business-module
                         # suite: product list/detail/create validation, category
                         # creation, dashboard stat cards, settings section switching,
                         # System Admin business list, global search, factory-type
                         # module filtering, the demo/backend mode selection suite
                         # (buildAuthRepository, DemoAuthRepository, full business-demo
                         # and System-Admin-demo login → dashboard → logout → re-login
                         # flows, all with the backend off), the System Admin's
                         # three-level drill-down (dashboard stat → per-business
                         # overview → that business's records → one record, walked
                         # forward and back for all four metrics, plus the negative:
                         # a platform statistic never opens a business's own table),
                         # admin total consistency (every card's number is derived
                         # from real records and equals the rows behind it),
                         # all six §57 business controls (Edit prefills and really
                         # saves, Disable/Activate confirm by name and swap so only
                         # the action matching the current status is offered, Reset
                         # password validates and records, Manage users and View
                         # reports open the selected business — verified at desktop,
                         # tablet and mobile width, and that no control is a no-op),
                         # the Active/Disabled filter matching its card's own count,
                         # and global detail-page back navigation (a real Navigator
                         # pop — not a fresh route — returning to the exact previous
                         # list/search/filtered state, verified for both LTR and RTL)
flutter build web --release   # confirms the release build still succeeds
```

Several real rendering/state bugs were caught and fixed by writing these
tests, not just inspecting code — see `docs/frontend-coverage.md`'s
methodology note. Concretely: `AppDropdownField` was missing
`isExpanded: true` (long option labels silently overflowed), `AppCard` had
no `Material` ancestor (a real Flutter assertion once any card contained a
`ListTile`), `SearchResultsScreen` built a fresh `Future` inline in every
`build()` (a `FutureBuilder` anti-pattern that never settles), and one
screen nested a `ListView` inside `PageScaffold`'s own scroll view
(unbounded-height viewport crash). All four are fixed at the shared-widget
level, not papered over per screen.

## Repository structure

```
warehouse-os/
├── backend/
│   └── src/
│   ├── scripts/                           db-provision.mjs (create db + user, hidden
│   │                                        password prompt), db-verify.mjs (read-only)
│   └── src/
│       ├── config/, db/                  env; pool (+ runInTransaction, withConnection,
│       │                                   queryOne/queryAll/queryCount); pagination.js;
│       │                                   listQuery.js (allowlisted filter/search/sort)
│       ├── middleware/                    authenticate, requireAccountType, authorize,
│       │                                   validate (reports every failing field),
│       │                                   errorHandler (+ databaseError mapping)
│       ├── validation/                     common.js — reusable id/money/quantity/
│       │                                    date/enum/list-query schemas
│       ├── modules/
│       │   ├── auth/                        login/refresh/logout/me/change-password —
│       │   │                                 account-adapter-parametrized (business user)
│       │   ├── admin-auth/                   same controller, System Admin adapter
│       │   └── businesses/                   System-Admin-only business+owner creation
│       ├── routes/, utils/                  route mounting; phone/token/password/
│       │                                     requestInfo/logger/AppError utilities
│       └── tests/
│           ├── unit/                          67 tests, no live DB required
│           └── integration/                    login/session/tenant-isolation/
│                                                 admin-business-creation/schema-integrity/
│                                                 transaction-rollback — needs MySQL
├── database/
│   ├── migrations/                    18 migrations — 6 for identity/auth (Phase 2),
│   │                                   12 for the operational schema (Phase 3): RBAC,
│   │                                   configuration, locations, master data, inventory,
│   │                                   parties, purchases, orders, returns, production,
│   │                                   system. 43 tables total.
│   └── seeds/system/                   bootstraps one System Admin from env vars
├── frontend/
│   └── lib/
│       ├── core/
│       │   ├── config/                     app_mode.dart — the one demo/backend mode switch
│       │   ├── network/                  ApiClient, AuthInterceptor, shared providers
│       │   └── storage/                   TokenStorage interface + SecureTokenStorage
│       ├── core/repositories/               PagedQuery, PagedListController (shared
│       │                                     pagination/search/filter state, one
│       │                                     implementation for every list screen),
│       │                                     DemoRepository mixin + paginateInMemory
│       ├── features/
│       │   ├── auth/                       data/ (models, repository, DemoAuthRepository —
│       │   │                               this phase), presentation/ (login_screen with
│       │   │                               its demo entry points, AuthController/AuthState)
│       │   ├── products/, categories/, inventory/, sales/, orders/, customers/,
│       │   │   suppliers/, purchases/, returns/, production/, employees/, reports/,
│       │   │   documents/, activity_history/, notifications/, search/, settings/,
│       │   │   admin/                        each: data/ (models + Local*Repository +
│       │   │                                  Riverpod providers) + presentation/
│       │   │                                  (list/detail/form screens) — this phase
│       │   └── system_status/                real, unchanged since Phase 0
│       ├── routing/                        app_router.dart — auth guards (Phase 2) +
│       │                                    business-type module filtering (this phase,
│       │                                    routerProvider, Riverpod-backed)
│       └── shared/, theme/, l10n/, localization/   design system — extended, not replaced
│   └── test/
│       ├── fakes/fake_auth.dart              test doubles — never referenced by
│       │                                      production code (main.dart)
│       └── widget_test.dart                  139 tests total
├── docs/
│   ├── architecture.md, environment.md, state-management.md,
│   │   database-access-strategy.md, ui-architecture.md, localization.md,
│   │   toolchain-fix.md, phase1-traceability.md         (Phase 0/1, updated where noted)
│   ├── authentication.md                Phase 2 — login/token/session design + deviations
│   ├── multi-tenancy.md                  Phase 2 — isolation enforcement + System Admin boundary
│   ├── security.md                        Phase 2 — full checklist review
│   ├── database.md                         Phase 2 + Phase 3 — schema map, migrations,
│   │                                         verification status
│   ├── backend-phase3.md                    Phase 3 — the schema and backend foundation
│   │                                         design, and why each decision went that way
│   ├── phase3-traceability.md                Every Phase 3 requirement → file → evidence
│   ├── phase2-traceability.md                 Every Phase 2 requirement → file → status
│   ├── frontend-coverage.md                 This phase — every spec section → screen → status
│   ├── frontend-backend-contract-notes.md    This phase — what each module expects a real API to look like
│   └── frontend-demo-mode.md                 This phase — the frontend-only demo mode architecture
├── docker-compose.yml          Isolated MySQL 8.x (Docker path) — see docs/environment.md
├── .env.example                 docker-compose's MySQL credentials (template)
└── package.json                  Backend orchestration only (see above)
```

See `docs/ui-architecture.md` §1 for the full annotated `frontend/lib/`
tree and the reasoning behind the `core/` vs. `shared/` split.

## Development workflow

1. Every requirement traces back to the specification and the approved
   architecture (`docs/architecture.md`) — a module isn't "done" because a
   screen exists; it's done when the backend enforces the same rule the UI
   suggests. Phase 2's routing guard is the concrete example: explicitly
   documented as UX convenience only — every real security boundary (tenant
   isolation, account-type authorization) is re-checked server-side on
   every request, never trusted from the client. That principle is
   unchanged this phase even though backend work is paused.
2. This phase's business-module screens are demo-data-backed by explicit
   instruction (backend work paused) — but the isolation is real: every
   `Local*Repository` implements `DemoRepository`
   (`core/repositories/demo_data_source.dart`) so it's mechanically
   obvious, from the type alone, which repositories still need a real API.
   Phase 2's authentication remains fully real — the login screen still
   talks to the real `/api/auth/login`, full stop; nothing about auth was
   weakened or mocked to build the rest of the UI.
3. Secrets live only in `.env` files (git-ignored); `.env.example` files
   document every variable without real values. `JWT_SECRET` is a real
   locally-generated random value, never a repo-committed constant.
4. New screens follow `docs/ui-architecture.md` §5 — build on
   `PageScaffold`/`AppDataTable`/the shared form fields, add a
   `features/<module>/data/` repository, never call the network layer
   directly from a widget. New backend modules follow `docs/multi-tenancy.md`'s
   pattern: `businessId` from `req.auth`, never from client input.

## What Phase 2 deliberately did not include (superseded)

Phase 2's own scope excluded every business module by design — see
`docs/phase2-traceability.md` for that phase's requirement-by-requirement
status. This frontend-first phase builds the Flutter UI for all of those
modules (see "Frontend-first phase" below); Phase 2's authentication scope
boundary itself is unaffected.

## What this frontend-first phase deliberately does not include

Per the master prompt's explicit scope: **no backend work** — no MySQL
provisioning, no migrations beyond Phase 2's six, no new database schema,
no backend CRUD/reports/PDF generation/transactions, no changes to Node.js
APIs or Phase 2's tenant enforcement. Every business-module screen reads
from a clearly-isolated local/demo repository, never a live endpoint — see
`docs/frontend-coverage.md`'s "deferred/lighter-depth items" for the
handful of sub-features (variant/custom-field persistence, order edit-
history entries, most report types' live queries, barcode *scanning* vs.
*preview*) that are UI scaffolding without a data layer yet, and
`docs/frontend-backend-contract-notes.md` for exactly what each module
expects a real API to look like when backend work resumes.

## What Phase 3 deliberately does not include

Phase 3's scope is the **foundation**: the schema, and the machinery every
business module will share. Explicitly excluded, and not a gap:

- **No business-module API.** No endpoint, controller, service or repository
  for Products, Categories, Inventory, Sales, Orders, Customers, Suppliers,
  Purchases, Returns, Production, Reports or PDF generation. `backend/src/modules/`
  still holds only `auth`, `admin-auth`, `businesses` and `health`.
- **No RBAC enforcement.** The schema (`permissions`, `roles`,
  `role_permissions`, `users.role_id`) is ready and the `permissions`
  catalogue is deliberately **empty** — deciding what each built-in role
  grants belongs to the RBAC phase.
- **No document-number allocation service, no status-transition rules, no
  backup execution, no notification generation.** Each has its storage; each
  needs its own phase.
- **Demo Mode is untouched.** Every `Local*Repository` still exists and the
  Flutter app still runs with the backend off. Converting the frontend to
  real API repositories is a later phase; no frontend file changed this
  phase.
- **Phase 2's authentication was not rewritten.** Two additive schema
  changes only: `audit_logs.module` and `users.role_id`.
- **MariaDB on port 3306 was not touched** — not started, stopped,
  reconfigured, or connected to.

See [`docs/phase3-traceability.md`](docs/phase3-traceability.md) for the
requirement-by-requirement breakdown, including which items are verified and
which are still waiting on a live database connection.
