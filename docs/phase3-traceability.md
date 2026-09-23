# Phase 3 requirements traceability

Maps every requirement Phase 3 was asked to lay a foundation for to the thing
that actually implements it, and says plainly what has been verified versus
what has not.

Two distinctions matter when reading this, and they are not the same thing:

- **Foundation complete** vs. **later phase.** Phase 3's scope is the schema
  and the shared backend machinery. A row marked 🔶 is *not a gap* — the
  storage and plumbing exist and are verified, and the module API that uses
  them is deliberately out of this phase's scope.
- **Verified** vs. **not yet verified.** Anything that needs a live MySQL
  connection is marked 🟡 and is listed again in "Live verification status"
  at the end. Nothing here is reported as passing against a live database
  unless it actually ran against one.

| | Meaning |
|---|---|
| ✅ | Built, and verified for real — a test ran, or the behaviour was observed against the running server |
| 🟡 | Built, but verification needs a live MySQL connection that was not available at hand-off |
| 🔶 | Foundation built and verified; the feature that consumes it belongs to a later phase by explicit scope |
| ❌ | Explicitly out of Phase 3's scope; not built |

Spec references (`§n`) are to the numbered sections of the project
specification PDF.

---

## Data model — master data and catalogue

| Spec | Requirement | Foundation implemented | Evidence | Status |
|---|---|---|---|---|
| §7 | Categories, hierarchical, per-business codes | `categories` with self-referencing `parent_id`, `uq_categories_code` scoped to `business_id`, `deleted_at` + `status` | `…120040_create_master_data_tables.js`; `schema.integrity.test.js` asserts existence, tenancy, soft delete | 🔶 storage ✅ / category API later |
| §8, §42 | Products with all listed fields, per-product stock policy | `products` — identity, pricing, unit, category, tax, reorder level, `track_inventory`, `allow_negative_stock`, `default_location_id` | same migration; schema test asserts no FLOAT/DOUBLE on money | 🔶 |
| §8 | Product current / available quantity | **Derived, not stored** — `SUM(inventory.quantity)`, minus `reserved_quantity` | `docs/backend-phase3.md` §5; `products` deliberately has no quantity column | 🔶 |
| §9 | Product variants | `product_variants` with its own SKU/barcode/pricing and per-variant uniqueness | `…120040`; `uq_variants_sku`, `uq_variants_barcode` | 🔶 |
| §8 | Product images | `product_images` with `is_primary` + `sort_order`, `CASCADE` from the product | `…120040` | 🔶 |
| §8, §34 | Units of measurement | `units`, business-owned, referenced by `products` | `…120040` | 🔶 |
| §33, §54 | Barcode support, no duplicates | `uq_products_barcode`, `uq_variants_barcode`, both scoped per business | `…120040`; schema test's unique-index assertions | ✅ enforced by schema |
| §54 | Duplicate SKUs impossible | `uq_products_sku` / `uq_variants_sku`, `(business_id, sku)` — business first | `schema.integrity.test.js` asserts the column order | 🟡 asserted by a test that needs a live DB |

## Data model — inventory

| Spec | Requirement | Foundation implemented | Evidence | Status |
|---|---|---|---|---|
| §10 | Stock per product per location | `inventory` — one row per (product, variant, warehouse, location) | `…120050_create_inventory_tables.js` | 🔶 |
| §10, §54 | One stock row per slot, no ambiguous duplicates | `uq_inventory_slot` over `(product_id, variant_key, warehouse_id, location_key)` using **STORED generated columns**, so MySQL's "every NULL is distinct" cannot defeat it | `…120050`'s raw `ALTER TABLE`; schema test asserts the index covers exactly those four columns | 🟡 |
| §10 | Reserved vs. available quantity | `reserved_quantity` column + `ck_inventory_reserved_non_negative` | `…120050`; `transaction.rollback.test.js` proves the database refuses a negative | 🟡 |
| §12 | Stock movement history, never silently disappearing | `inventory_movements` — append-only, typed, with before/after quantities, reason and actor; **no `deleted_at`** | `…120050`; schema test asserts it is append-only and has no `deleted_at` | 🟡 |
| §12 | Movement types | native `ENUM` with §12's exact nine values | `…120050` | ✅ |
| §11 | Warehouses and storage locations | `warehouses`, `storage_locations` (created before products so `default_location_id` resolves) | `…120030_create_location_tables.js` | 🔶 |
| §11 | Stock transfers between locations | `stock_transfers` + `stock_transfer_items`, status enum, `uq_stock_transfers_number` | `…120050` | 🔶 |
| §44 | Low-stock / reorder alerts | `products.reorder_level` + `idx_inventory_product`; alert *generation* is later | `…120040`, `…120050` | 🔶 |
| §47 | Stock validation, no negative unless opted in | `allow_negative_stock` per product + CHECK constraints on every quantity | `…120040`, `…120050`; a CHECK is proven to refuse an invalid row in `transaction.rollback.test.js` | 🟡 |

## Data model — parties, sales, purchases, returns

| Spec | Requirement | Foundation implemented | Evidence | Status |
|---|---|---|---|---|
| §18 | Customers, searchable by name/phone | `customers` (phone deliberately **not** unique — §18 allows anonymous/cash customers), `idx_customers_name`, `idx_customers_phone` | `…120060_create_party_tables.js` | 🔶 |
| §18 | Customer total purchases / outstanding balance / order history | **Derived** from `orders` — deliberately not stored | `docs/backend-phase3.md` §5 | 🔶 |
| §19 | Suppliers + supplier-product links | `suppliers`, `supplier_products` (composite PK, no surrogate id) | `…120060` | 🔶 |
| §13, §14 | Sales and orders | One `orders` table with an `order_type` discriminator, plus `order_items` | `…120080_create_order_tables.js` | 🔶 |
| §14 | Order status list | `ENUM` with §14's exact nine values | `…120080` | ✅ |
| §55 | Historical documents keep their prices | `order_items.unit_price`, `order_items.product_name`, `purchase_items.unit_cost`, `production_items.unit_cost` — snapshots taken at transaction time | `…120070`, `…120080`, `…120100`, each with its migration comment | ✅ by design |
| §15 | Order edit history, never silently overwritten | `order_edits` — append-only; records field, old value, new value, who, when | `…120080`; schema test asserts append-only | 🟡 |
| §17 | Cancellation record | `orders.cancelled_at` / `cancelled_by` / `cancel_reason` / `status_before_cancel` | `…120080` | 🔶 |
| §13 | Payments, partial payments, methods | `payments` + `paid_amount` / `payment_status` on `orders` and `purchases`; `ck_payment_exactly_one_parent` | `…120080` | 🔶 |
| §43 | Order remaining amount | **Derived** (`grand_total - paid_amount`); `paid_amount` is stored because `payment_status` must be indexable | `docs/backend-phase3.md` §5 | 🔶 |
| §16 | Returns with a condition per item | `returns`, `return_items` with `item_condition` enum, status enum, `uq_returns_number` | `…120090_create_return_tables.js` | 🔶 |
| §20 | Purchases from suppliers | `purchases`, `purchase_items`, status + payment status, `uq_purchases_number` | `…120070_create_purchase_tables.js` | 🔶 |
| §45, §61.6 | Financial records archived, never hard-deleted | `deleted_at` on `purchases`, `orders`, `returns`; `RESTRICT` delete rules on every FK where history would be lost | schema test's soft-delete assertions | 🟡 |

## Data model — production

| Spec | Requirement | Foundation implemented | Evidence | Status |
|---|---|---|---|---|
| §21 | Bill of materials | `bill_of_materials` + `ck_bom_not_self_referencing` | `…120100_create_production_tables.js` | 🔶 |
| §21 | Raw materials | **Raw materials are products** — no separate table, so one stock ledger covers both sides of a production run | `…120100`'s header comment | ✅ decision recorded |
| §22 | Production orders and history | `production_orders` (planned vs. produced quantity), `production_items`, §22's exact status enum | `…120100` | 🔶 |

## Data model — configuration, RBAC, system

| Spec | Requirement | Foundation implemented | Evidence | Status |
|---|---|---|---|---|
| §23, §24 | Roles and permissions per business | `permissions` (platform catalogue, **no** `business_id`), `roles` (business-owned, `uq_roles_business_name`), `role_permissions`, `users.role_id` | `…120010_create_rbac_tables.js`; schema test asserts `permissions` has no tenant column | 🔶 storage ✅ / enforcement and catalogue contents later |
| §24 | Permission identifiers stable and unique | `uq_permissions_key`, `uq_permissions_module_action` | `…120010` | ✅ |
| §34, §49–§51 | Per-business settings (all listed groups) | `business_settings` — one JSON-valued row per key, `(business_id, setting_key)` unique | `…120020_create_business_configuration_tables.js` | 🔶 |
| §29, §14, §61.12 | Configurable document numbering; numbers unique | `document_sequences` (prefix, padding, next value, yearly-reset flag) — a lockable row — plus a unique index on every document number | `…120020`, and `uq_orders_number` / `uq_purchases_number` / `uq_returns_number` / `uq_stock_transfers_number` / `uq_production_number` | 🔶 storage ✅ / allocation service later |
| §51 | Custom fields | `custom_field_definitions` + `custom_field_values`, `uq_custom_field_values_record` | `…120020` | 🔶 |
| §27, §28 | PDF templates and per-field toggles | `pdf_templates` | `…120020` | 🔶 |
| §30 | Audit log with every listed field, filterable by module | Phase 2's `audit_logs` **plus `module`**, added this phase (backfilled, then `NOT NULL`, indexed) | `…120001_add_module_to_audit_logs.js`; schema test asserts every §30 field and that `module` is `NOT NULL` | 🟡 |
| §31 | Notifications, including platform-level alerts | `notifications` with §31's exact type list and a **nullable** `business_id` | `…120110_create_system_tables.js`; schema test asserts the nullable tenant column | 🟡 |
| §2, §34 | System-wide settings | `system_settings` — deliberately no tenant column | `…120110` | 🔶 |
| §52 | Backup history | `backups` — records that a backup happened and where; taking one is a later phase | `…120110` | 🔶 |
| §3 | Business/tenant entity | Phase 2's `businesses`, unchanged | `docs/database.md` | ✅ (Phase 2) |
| §4 | Authentication | Phase 2's `users`, `system_admins`, refresh-token and `login_attempts` tables — **not rewritten** | `docs/authentication.md` | ✅ (Phase 2) |

## Cross-cutting data-model requirements

| Spec | Requirement | Foundation implemented | Evidence | Status |
|---|---|---|---|---|
| §36 | A business can never reach another's data | `business_id` + a real FK on all 32 business-owned tables, including child tables where it is technically redundant, so a tenant predicate never depends on remembering a join | `schema.integrity.test.js` asserts all 32, and asserts the 6 platform tables have **no** `business_id` | 🟡 |
| §37 | Every table the specification lists | 43 tables total — 7 from Phase 2 plus 36 this phase | `schema.integrity.test.js`'s `EXPECTED_TABLES` | 🟡 |
| §61.6 | Important records never silently deleted | `deleted_at` on 20 entity tables; `RESTRICT` wherever history would be lost | schema test's soft-delete assertions | 🟡 |
| §12, §15, §30 | History is append-only | `audit_logs`, `inventory_movements`, `order_edits`, `login_attempts` have no `deleted_at`, and nothing in the application deletes from them | schema test asserts the absence | 🟡 |
| — | Timestamps | `created_at` on every table; `updated_at` on every mutable table; separate business dates on documents | schema test asserts `created_at` on all 43 | 🟡 |
| — | Money and quantity precision | `DECIMAL(14,2)` / `DECIMAL(14,3)` throughout | schema test asserts **zero** FLOAT/DOUBLE columns anywhere | 🟡 |
| §59 | Server-side paging, filtering, sorting; indexed queries | A named index for every query the spec asks for, all `(business_id, …)`-leading | schema test asserts the named indexes exist | 🟡 |
| — | Character set and engine | `utf8mb4` / `utf8mb4_0900_ai_ci` and InnoDB on every table | schema test asserts engine + charset per table; `npm run db:verify` prints them | 🟡 |

## Backend foundation

| Spec | Requirement | Foundation implemented | Evidence | Status |
|---|---|---|---|---|
| §46 | Multi-step writes are atomic | `runInTransaction` in `src/db/pool.js` — commit, rollback, release, original error preserved | `tests/integration/transaction.rollback.test.js`: commit persists both steps; an application error rolls back; an FK violation rolls back the earlier valid insert; 15 consecutive failures don't leak the pool | 🟡 written; skips cleanly without a DB |
| §35 | SQL injection protection | Parameterised `mysql2` only; `multipleStatements: false`; **column names never come from the client** | `tests/unit/listQuery.test.js` — injection attempts in filter keys, sort keys and sort direction are all neutralised | ✅ passing |
| §25, §32, §59 | Filtering, searching, sorting per module | `src/db/listQuery.js` — `defineListSpec` allowlists, validated at load time; `buildWhere`, `buildOrderBy` with a stable tiebreaker | ✅ unit tests, including LIKE-metacharacter escaping and inclusive date ranges | ✅ |
| §26, §59 | Every list paged and bounded | `src/db/pagination.js` — clamped `pageSize` (max 100), `totalPages` never 0 | `tests/unit/pagination.test.js` | ✅ |
| §54 | Input validation; all errors reported | `src/middleware/validate.js` (zod) reports **every** failing field; `src/validation/common.js` holds the reusable schemas | live check: `POST /api/auth/login {}` → 422 listing both `phone` and `password` | ✅ observed on the running server |
| §53 | Errors handled consistently; internals never leaked | `src/middleware/errorHandler.js` + `src/utils/databaseError.js` — actionable driver errors mapped (409/422/503), everything else generic | `tests/unit/databaseError.test.js`, including an explicit assertion that no constraint name, table name, SQL text or conflicting value reaches the message | ✅ |
| §38 | Consistent API response format | `src/utils/responseEnvelope.js` — `success` / `fail` / `paginated` | live checks: health 200, unknown route 404, DB health 503 — all enveloped | ✅ observed |
| §35 | Security middleware chain | helmet, CORS allowlist, global + login rate limits, 1 MB body cap, pino-http, central error handler, env-only secrets | live check: `Strict-Transport-Security`, `X-Content-Type-Options: nosniff`, `X-Frame-Options: SAMEORIGIN`, `RateLimit-Policy: 100;w=60` all present | ✅ observed |
| §59 | Performance foundation | `BIGINT` keys, mandatory paging, SQL-side filtering, tenant-leading composite indexes, `queryCount` sharing the page query's WHERE | `docs/backend-phase3.md` §10 | ✅ decisions recorded |
| §5, §56 | Dashboard aggregates | Indexes chosen to serve them | index comments in `…120050`, `…120080` | 🔶 |
| §24 | RBAC **enforcement** middleware | — | — | ❌ later phase (the schema is ready) |
| §25, §27 | Report endpoints and PDF export | — | — | ❌ later phase, explicitly forbidden this phase |
| §8–§22 | Business module APIs (products, categories, inventory, sales, orders, customers, suppliers, purchases, returns, production) | — | — | ❌ later phases, explicitly forbidden this phase |

## Scope guards — things deliberately *not* done

| Constraint from the phase brief | Verified how | Status |
|---|---|---|
| No business module API implemented | No route, controller or service for any business module exists — `backend/src/modules/` still holds only `auth`, `admin-auth`, `businesses`, `health` | ✅ verified by inspection |
| Demo Mode still available; `Local*Repository` classes intact | No file under `frontend/lib/` was modified this phase | ✅ verified by `git status` |
| Frontend not redesigned or broken | `flutter analyze` and `flutter test` re-run this phase | see "Frontend regression check" |
| MariaDB on 3306 untouched | Never started, stopped, reconfigured, or connected to. Observed: nothing is listening on 3306 — a state this phase neither created nor changed | ✅ |
| No credentials committed | `.env` files remain git-ignored; `db-provision.mjs` prompts for the administrator password with hidden input and never writes it anywhere | ✅ verified against `git status` and `.gitignore` |
| Phase 2 auth not rewritten | Two additive schema changes only (`audit_logs.module`, `users.role_id`); no auth code, token design or route guard altered | ✅ verified by `git diff` |
| Old commits not rewritten | One new commit; no rebase, amend or force-push | ✅ |

---

## Live verification status

Everything below needs an authenticated MySQL connection as `warehouse_app`
on `127.0.0.1:3307`. **As of hand-off that connection still fails with
`ER_ACCESS_DENIED_ERROR`** — the same wall Phase 2 documented
(`docs/database.md`), because the database and application user have never
been provisioned on this MySQL instance.

| Check | Status |
|---|---|
| Every backend source, script and migration parses (`node --check`) | ✅ done — all clean |
| Backend unit tests | ✅ **67/67 passing** (38 from Phase 2 plus 29 added this phase); no database needed |
| Server boots; envelope, validation, 404 and security headers correct | ✅ observed on a running server |
| `GET /api/health/db` correctly reports the database as unreachable | ✅ observed — 503 `DATABASE_UNREACHABLE`, which is the *correct* behaviour, not a passing database check |
| A MySQL 8 instance identified on 3307 | ✅ observed — native `mysqld`, Windows service `MySQL80` |
| `npm run db:provision` (create the database + app user) | ❌ not run — needs the MySQL administrator password, which only the user has |
| `npm run migrate` (apply all 18 migrations) | ❌ not run — blocked by the above |
| `npm run migrate:status` / `npm run migrate:rollback` | ❌ not run — blocked |
| `npm run db:verify` (live engine / charset / grants / table report) | ❌ not run — blocked |
| `npm run test:integration` (schema integrity + transaction rollback) | 🟡 written; **skips cleanly** via `requireDatabase(t)` rather than fake-passing |
| Live constraint enforcement (unique, CHECK, FK), live rollback, live tenant-column audit | 🟡 the tests that prove these are written and ready to run |

To unblock, in `backend/`:

```
npm run db:provision     # prompts for the MySQL administrator password
npm run migrate
npm run db:verify
npm run test:integration
```

The provisioning script reads host, port, database, user and the app password
from `backend/.env`, so the only thing it asks for is the administrator
password — which is never echoed, logged, or written to disk.

## Frontend regression check

Phase 3 changed no frontend file. `flutter analyze` and `flutter test` were
re-run to confirm it, and no test was modified to make anything pass — see
the Phase 3 final report for the exact figures.
