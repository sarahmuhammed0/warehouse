# Database

## Phase 2 — the authentication and tenancy layer

Phase 2 shipped the **minimal schema for authentication and tenancy only** —
per that phase's explicit scope, no Products/Categories/Inventory/Orders
tables existed yet (Phase 3 adds them — see below). Every table below exists to support login, sessions,
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

---

## Phase 3 — the full operational schema

Phase 3 takes the schema from 7 tables to **43**, covering every entity the
specification names. The design reasoning — why each table, column, index,
constraint and delete rule is the way it is — lives in
**[`backend-phase3.md`](backend-phase3.md)**, which is the document to read
before changing the schema. This section is the map.

Twelve migrations, in order:

| File | Adds |
|---|---|
| `20260923120001_add_module_to_audit_logs.js` | `audit_logs.module` — the one change to a Phase 2 table |
| `20260923120010_create_rbac_tables.js` | `permissions`, `roles`, `role_permissions`, `users.role_id` |
| `20260923120020_create_business_configuration_tables.js` | `business_settings`, `document_sequences`, `custom_field_definitions`, `custom_field_values`, `pdf_templates` |
| `20260923120030_create_location_tables.js` | `warehouses`, `storage_locations` |
| `20260923120040_create_master_data_tables.js` | `units`, `categories`, `products`, `product_variants`, `product_images` |
| `20260923120050_create_inventory_tables.js` | `inventory`, `inventory_movements`, `stock_transfers`, `stock_transfer_items` |
| `20260923120060_create_party_tables.js` | `customers`, `suppliers`, `supplier_products` |
| `20260923120070_create_purchase_tables.js` | `purchases`, `purchase_items` |
| `20260923120080_create_order_tables.js` | `orders`, `order_items`, `order_edits`, `payments` |
| `20260923120090_create_return_tables.js` | `returns`, `return_items` |
| `20260923120100_create_production_tables.js` | `bill_of_materials`, `production_orders`, `production_items` |
| `20260923120110_create_system_tables.js` | `notifications`, `system_settings`, `backups` |

**The order matters in one place:** locations are created before master data,
because `products.default_location_id` references `storage_locations`.
Reordering those two breaks `npm run migrate` on a fresh database.

Every one of the twelve has a real `down()` that drops exactly what its
`up()` created, in reverse dependency order.

### The two changes to Phase 2 tables

Both additive, both required, nothing rewritten:

- **`audit_logs.module`** — backfilled to `'auth'`, then made `NOT NULL`,
  then indexed. The spec lists `module` among an audit record's required
  fields and also requires filtering by it; Phase 2 omitted it because every
  event it wrote was an auth event.
- **`users.role_id`** — nullable FK to `roles`. Nullable because Phase 2's
  users predate roles. `users.is_owner` is kept alongside it: that flag
  records *who set up the business*, which must stay true even if the role
  row is later edited.

### Things about this schema that will surprise you

Each is explained at length in `backend-phase3.md`; flagged here so nobody
"fixes" one by accident.

- **`products` has no quantity column.** Stock lives in `inventory`, one row
  per (product, variant, warehouse, location). A product's quantity is a
  `SUM`.
- **`inventory` has two generated columns**, `variant_key` and
  `location_key` (`COALESCE(col, 0) STORED`). They exist because MySQL treats
  every `NULL` in a `UNIQUE` index as distinct, which would let the same
  (product, warehouse) pair be inserted without limit whenever variant and
  location were `NULL`. The unique index is on the generated columns, not the
  nullable ones.
- **Child tables carry `business_id` even though it is reachable through
  their parent.** A deliberate denormalisation, so a tenant predicate can be
  applied to the table being queried and never depends on remembering a
  join.
- **`permissions` has no `business_id`, and is deliberately left empty.** It
  names capabilities the *software* has; which permissions a business's roles
  hold is `roles` + `role_permissions`. Populating the catalogue is the RBAC
  phase's decision.
- **Sales and orders are one table** (`orders`, with an `order_type`
  discriminator), because they share every column and every line-item shape.
- **Customer totals, supplier balances and order "remaining" amounts are not
  stored.** They are derived. `paid_amount` *is* stored, because
  `payment_status` is a function of it and a status the database cannot
  derive is a status it cannot index.
- **Four tables have no `deleted_at` on purpose** — `audit_logs`,
  `inventory_movements`, `order_edits`, `login_attempts`. They are the
  history; giving them a soft-delete column would invite hiding it.
- **Three columns are intentionally not foreign keys** —
  `inventory_movements.reference_id`, `notifications.reference_id`,
  `custom_field_values.entity_id` — because their referent's table varies by
  a sibling discriminator column and SQL has no polymorphic FK.

### Verification status (Phase 3, honest)

| Check | Status |
|---|---|
| Every migration parses (`node --check`) | ✅ all 18 clean |
| Backend unit tests (67, of which 29 are new this phase) | ✅ 67/67 passing, no database needed |
| Schema integrity against a live database (`schema.integrity.test.js` — 43 tables, engine/charset, tenant columns, soft-delete vs. append-only, no FLOAT/DOUBLE, unique + named indexes, audit fields) | 🟡 written; skips cleanly when the database is unreachable |
| Transaction rollback against a live database (`transaction.rollback.test.js`) | 🟡 same |
| `npm run migrate` actually run | ❌ not yet — `warehouse_app` still gets `ER_ACCESS_DENIED_ERROR`; the database and user have never been provisioned on this instance |
| `npm run migrate:rollback` / `migrate:status` | ❌ blocked by the above |
| `npm run db:verify` | ❌ blocked by the above |

Phase 3 added `npm run db:provision` specifically to close this out — see
`docs/environment.md`'s Phase 3 update. Nothing above is reported as
verified against a live database, because none of it has been.
