# Warehouse OS

Multi-tenant Factory / Warehouse / Storage management system.

**Status: Phase 2 — Authentication + Multi-Tenancy Foundation.** Real phone
+ password login (business users and System Admins, structurally separate
accounts), backend-enforced tenant isolation, JWT + refresh-token session
handling, login protection/rate limiting, audit logging, and the matching
Flutter auth UI (Riverpod state, Dio interceptor, secure token storage,
routing guards) are built and tested. No business modules (Products,
Categories, Inventory, Sales, Orders, Customers, Suppliers, Purchases,
Returns, Production, Employees/RBAC, Reports, Documents) exist yet — those
begin in Phase 3+.

See [`docs/architecture.md`](docs/architecture.md) for the approved
roadmap, [`docs/authentication.md`](docs/authentication.md),
[`docs/multi-tenancy.md`](docs/multi-tenancy.md),
[`docs/security.md`](docs/security.md), and
[`docs/database.md`](docs/database.md) for this phase's design in full, and
[`docs/phase2-traceability.md`](docs/phase2-traceability.md) for exactly
what's built vs. deferred, requirement by requirement.

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
exact provisioning SQL used and the **current honest verification status**
(as of this phase, the app database user could not yet connect — migrations
and integration tests were validated statically only, not run live).

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
#   B) Otherwise: provision a MySQL 8.x instance yourself on 127.0.0.1:3307 —
#      see docs/database.md's "Engine" section for the exact SQL used here.
```

## Starting the development environment

```bash
# Database (Docker path — skip if you provisioned MySQL yourself, see above)
npm run dev:db               # starts in the background
npm run dev:db:logs          # optional: watch it come up / confirm healthy

# Backend
npm run dev:backend          # http://localhost:4000
# Run migrations once the database is reachable:
cd backend && npm run migrate

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
flutter test           # 30 tests — app shell, RTL/localization, routing guards,
                         # data table states, pagination, dialogs/overlays, and the
                         # full login-screen suite (render/validate/loading/error/
                         # success states, en/ar/ku locales, logout, session expiry)
flutter build web --release   # confirms the release build still succeeds
```

## Repository structure

```
warehouse-os/
├── backend/
│   └── src/
│       ├── config/, db/                  env, connection pool (+ runInTransaction)
│       ├── middleware/                    authenticate, requireAccountType, authorize,
│       │                                   validate, errorHandler
│       ├── modules/
│       │   ├── auth/                        login/refresh/logout/me/change-password —
│       │   │                                 account-adapter-parametrized (business user)
│       │   ├── admin-auth/                   same controller, System Admin adapter
│       │   └── businesses/                   System-Admin-only business+owner creation
│       ├── routes/, utils/                  route mounting; phone/token/password/
│       │                                     requestInfo/logger/AppError utilities
│       └── tests/
│           ├── unit/                          31 tests, no live DB required
│           └── integration/                    login/session/tenant-isolation/
│                                                 admin-business-creation — needs MySQL
├── database/
│   ├── migrations/                    6 migrations — businesses, users, system_admins,
│   │                                   refresh_tokens (×2), login_attempts, audit_logs
│   └── seeds/system/                   bootstraps one System Admin from env vars
├── frontend/
│   └── lib/
│       ├── core/
│       │   ├── network/                  ApiClient, AuthInterceptor, shared providers
│       │   └── storage/                   TokenStorage interface + SecureTokenStorage
│       ├── features/
│       │   ├── auth/                       data/ (models, repository), presentation/
│       │   │                               (login_screen, AuthController/AuthState)
│       │   └── ...                          16 business + 2 admin placeholders,
│       │                                     system_status (real, unchanged)
│       ├── routing/                        app_router.dart — now with real
│       │                                    authenticated/unauthenticated redirect
│       │                                    guards (routerProvider, Riverpod-backed)
│       └── shared/, theme/, l10n/, localization/   unchanged Phase 1 design system
│   └── test/
│       ├── fakes/fake_auth.dart              test doubles — never referenced by
│       │                                      production code (main.dart)
│       └── widget_test.dart                   30 tests total
├── docs/
│   ├── architecture.md, environment.md, state-management.md,
│   │   database-access-strategy.md, ui-architecture.md, localization.md,
│   │   toolchain-fix.md, phase1-traceability.md         (Phase 0/1, updated where noted)
│   ├── authentication.md                Phase 2 — login/token/session design + deviations
│   ├── multi-tenancy.md                  Phase 2 — isolation enforcement + System Admin boundary
│   ├── security.md                        Phase 2 — full checklist review
│   ├── database.md                         Phase 2 — schema, migrations, verification status
│   └── phase2-traceability.md               Every Phase 2 requirement → file → status
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
   suggests. Phase 2 is the concrete example: the Flutter routing guard is
   explicitly documented as UX convenience only — every real security
   boundary (tenant isolation, account-type authorization) is re-checked
   server-side on every request, never trusted from the client.
2. No mock data, no fake API responses, no fake authentication — every
   screen that has real data to show talks to the real backend; the login
   screen talks to the real `/api/auth/login`, full stop.
3. Secrets live only in `.env` files (git-ignored); `.env.example` files
   document every variable without real values. `JWT_SECRET` is a real
   locally-generated random value, never a repo-committed constant.
4. New screens follow `docs/ui-architecture.md` §5 — build on
   `PageScaffold`/`AppDataTable`/the shared form fields, add a
   `features/<module>/data/` repository, never call the network layer
   directly from a widget. New backend modules follow `docs/multi-tenancy.md`'s
   pattern: `businessId` from `req.auth`, never from client input.

## What Phase 2 deliberately does not include

Per the Phase 2 brief's explicit scope: Products, Categories, Inventory,
Sales, Orders, Purchases, Returns, Production, Reports, PDF generation,
Notifications, and full Employees/RBAC/role-management (beyond the single
`is_owner` elevation flag needed this phase) are all out of scope — Phase 3+
work. Password reset ("forgot password") is also deferred — see
`docs/authentication.md`. See `docs/phase2-traceability.md` for the
complete, requirement-by-requirement status.
