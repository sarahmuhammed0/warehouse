# Database (Phase 2)

Phase 2 ships the **minimal schema for authentication and tenancy only** —
per the phase's explicit scope, no Products/Categories/Inventory/Orders/etc.
tables exist yet. Every table below exists to support login, sessions,
lockout, and the one platform-level action (System Admin creating a
business) Phase 2 needs.

## Engine

**MySQL 8.x, port 3307** — the project's own instance, isolated from the
machine's pre-existing **MariaDB 10.4.32 on port 3306**, which Phase 2 never
touched, queried, or connected to. See `docs/environment.md` for the general
policy; this document covers what Phase 2 specifically added on top of it.

- Discovered this phase: a native Windows **MySQL80** service already
  running and listening on 3307 (separate from the earlier Phase
  0/1-assumed Docker-based MySQL). The standard "root, empty password"
  unconfigured-install case was checked once and failed (confirming the
  instance is genuinely secured) — no further credential guessing was
  attempted. The user chose to provision the database and app user
  themselves; the exact SQL handed off is reproduced below for the record.

```sql
CREATE DATABASE IF NOT EXISTS warehouse_os_dev
  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
CREATE USER IF NOT EXISTS 'warehouse_app'@'localhost' IDENTIFIED BY 'dev_app_pw_7c2e';
CREATE USER IF NOT EXISTS 'warehouse_app'@'127.0.0.1'  IDENTIFIED BY 'dev_app_pw_7c2e';
GRANT ALL PRIVILEGES ON warehouse_os_dev.* TO 'warehouse_app'@'localhost';
GRANT ALL PRIVILEGES ON warehouse_os_dev.* TO 'warehouse_app'@'127.0.0.1';
FLUSH PRIVILEGES;
```

As of this phase's final verification, `GET /api/health/db` still returns
`DATABASE_UNREACHABLE` (`ER_ACCESS_DENIED_ERROR` for `warehouse_app`) —
**provisioning had not completed yet.** Migrations and integration tests
were therefore validated statically only; see "Verification status" below.

## Migrations

**Knex.js, migrations only** — not the application's runtime query layer
(that's still raw parameterized `mysql2/promise`, unchanged from Phase 0;
see `docs/database-access-strategy.md`, which predicted exactly this split
before any migration existed). `backend/knexfile.js` reads the same env vars
as the app itself, so there is one source of truth for connection config,
not two. `database/package.json` sets `"type": "module"` — required
separately from the backend's own `package.json` because `database/` is
outside the backend package and Knex's migration loader needs to know it's
loading ESM.

Six migrations, run in order:

| # | File | Creates |
|---|---|---|
| 1 | `20260917120001_create_businesses_table.js` | `businesses` — the tenant entity |
| 2 | `20260917120002_create_users_table.js` | `users` — business-tenant login accounts |
| 3 | `20260917120003_create_system_admins_table.js` | `system_admins` — platform accounts, structurally separate from `users` |
| 4 | `20260917120004_create_refresh_tokens_tables.js` | `refresh_tokens` + `system_admin_refresh_tokens` |
| 5 | `20260917120005_create_login_attempts_table.js` | `login_attempts` — lockout + rate-limit evidence |
| 6 | `20260917120006_create_audit_logs_table.js` | `audit_logs` — append-only, general-purpose |

All six use native MySQL 8.x `ENUM` (`useNative: true`), `utf8mb4`, and
InnoDB (Knex's default engine) — no MariaDB-specific syntax. Every table
follows the blueprint's stated conventions (`docs/architecture.md`'s
artifact §5): `BIGINT UNSIGNED AUTO_INCREMENT` primary keys,
`created_at`/`updated_at` timestamps, and — for `businesses`/`users`/
`system_admins` — a `deleted_at` column (soft-delete only; spec §61 rule 6,
"important records are never silently deleted," applies from the very first
tenant-owned table, not retrofitted later).

### Schema notes worth flagging

- **`users.phone` is globally unique**, not per-business — a deliberate
  deviation from the blueprint's original per-business-unique design. See
  `docs/authentication.md`'s "Phone uniqueness" section for the full
  reasoning (the login screen has no business selector).
- **`system_admins` has no `business_id` column at all** — not nullable,
  entirely absent — by design. See `docs/authentication.md`'s "Recorded
  deviations" and the migration file's own doc comment for why this is
  structurally safer than a flag on `users`.
- **`refresh_tokens` and `system_admin_refresh_tokens` are two separate
  tables**, each with a real foreign key into its own identity table, rather
  than one polymorphic table with a `subject_type` discriminator — chosen
  specifically to keep FK-enforced referential integrity (a polymorphic FK
  can't be enforced by MySQL itself). Both store only `token_hash` (SHA-256
  of the raw refresh token) — the raw value is never persisted anywhere.
- **`login_attempts` records every attempt, including against
  nonexistent phone numbers** — necessary so a lockout check never behaves
  differently for a real vs. fake phone number, which would itself leak
  which phones are registered (see `docs/authentication.md`'s anti-
  enumeration section).
- **`audit_logs.business_id` and `.actor_id` are both nullable** — a System
  Admin action, or a failed login against an unrecognized phone, genuinely
  has no business/actor to attach.
- **No `roles`/`permissions`/`role_permissions`/`user_roles` tables yet** —
  the blueprint's §9 RBAC schema is explicitly deferred; `users.is_owner`
  is the one minimal elevation flag Phase 2 needs (distinguishing the
  initial administrator created alongside a business), not a permission
  system.

### Seed data

`database/seeds/system/001_system_admin.js` bootstraps exactly one System
Admin, from `SEED_ADMIN_PHONE` / `SEED_ADMIN_PASSWORD` / `SEED_ADMIN_NAME`
environment variables — **no hardcoded credentials**. If those env vars are
unset, the seed no-ops safely rather than failing or silently using a
default password.

## Verification status (honest, as of this phase)

| Check | Status |
|---|---|
| Migrations statically validated (`node --check` on every file + a dynamic-import shape check) | ✅ done |
| Migrations actually run against live MySQL 8.x (`npm run migrate`) | ❌ not run — database still unreachable as of the last check (`ER_ACCESS_DENIED_ERROR`) |
| Backend unit tests (31 tests: phone/password/token utilities, `authenticate`/`requireAccountType` middleware, Zod validation schemas) | ✅ run for real, 31/31 passing, no live DB required |
| Backend integration tests (login flow, session lifecycle, tenant isolation, admin business-creation) | 🟡 written, and confirmed to **skip cleanly** (not fake-pass) when the database is unreachable — `requireDatabase(t)` calls `t.skip()` with the real driver error attached, rather than the tests reporting green with no real assertions run |
| Live MySQL query behavior (SQL injection resistance, actual constraint enforcement, tenant-isolation proof) | ❌ not verified — depends on the same unreachable database |

This is reported honestly rather than claimed: **no test was represented as
passing against a live database when it did not actually run against one.**
Once `warehouse_app` can connect, `npm run migrate` followed by `npm run
test:integration` in `backend/` will produce the first real result — see the
final Phase 2 report's "MySQL Verification" section for whatever that
status was at hand-off.
