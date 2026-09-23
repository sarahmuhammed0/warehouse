# Phase 3 — Database + backend foundation

What this phase built, and why each decision went the way it did. Phase 3 is
**foundation only**: the schema every later module needs, and the backend
machinery those modules will share. No business module API exists yet, and
none should — see "Phase boundary" at the end.

The Flutter frontend is untouched by this phase and **Demo Mode remains the
default**, so the app still runs with the backend off
(`docs/frontend-demo-mode.md`).

---

## 1. MySQL environment

| | |
|---|---|
| Server | MySQL 8.x, native Windows service `MySQL80` |
| Address | `127.0.0.1:3307` |
| Database | `warehouse_os_dev` |
| Charset / collation | `utf8mb4` / `utf8mb4_0900_ai_ci` |
| Engine | InnoDB throughout |
| App user | `warehouse_app` (`@localhost` and `@127.0.0.1`) |

**MariaDB on 3306 is not touched by this project** — not started, stopped,
reconfigured, queried or connected to. `docs/environment.md` covers the
isolation policy; nothing in this phase changed it.

Everything above comes from `backend/.env`, read through
`backend/src/config/env.js`. Nothing in the codebase reads `process.env`
directly outside that file, so "which database" has one answer.

### Provisioning

`npm run db:provision` (in `backend/`) creates the database and the app user.
It prompts for the administrator password — hidden input, never written to
disk, a log, or shell history — and reads host, port, database name, user and
**the app password** from `.env`. That last point is the reason it is a
script and not a pasted SQL snippet: the credential the app authenticates
with has one source of truth, so provisioning cannot quietly create a user
whose password differs from the one the app uses.

It differs from the SQL recorded in `docs/database.md` in one way, and
deliberately: it grants a specific privilege list rather than
`ALL PRIVILEGES`, because the phase brief asks that the application user have
"only the intended development database access". No `GRANT OPTION`, no
`SUPER`, nothing outside `warehouse_os_dev.*`.

`npm run db:verify` then prints what the server itself reports — version,
port, engine, charset, effective user, its grants, and every table with its
engine and collation. It only reads.

---

## 2. Migration architecture

Unchanged from the established decision in
`docs/database-access-strategy.md`: **Knex for migrations only**, raw
parameterised `mysql2/promise` for every runtime query. Knex's query builder
and ORM features are not used, and `backend/knexfile.js` reads the same env
vars as the app.

| Command (in `backend/`) | Does |
|---|---|
| `npm run migrate` | apply all pending migrations |
| `npm run migrate:status` | list applied/pending |
| `npm run migrate:rollback` | undo the last batch |
| `npm run migrate:make <name>` | scaffold a new migration |

Migrations live in `database/migrations/`, named
`YYYYMMDDHHMMSS_description.js`, so order is lexicographic and therefore
deterministic. Every file this phase adds has a real `down()` that drops
exactly what its `up()` created, in reverse dependency order — a rollback
that leaves a table behind is worse than no rollback, because the next
`migrate` then fails on a table that "already exists".

Phase 3 adds twelve migrations:

| File | Creates |
|---|---|
| `…120001_add_module_to_audit_logs` | `audit_logs.module` (see §8 below) |
| `…120010_create_rbac_tables` | `permissions`, `roles`, `role_permissions`, `users.role_id` |
| `…120020_create_business_configuration_tables` | `business_settings`, `document_sequences`, `custom_field_definitions`, `custom_field_values`, `pdf_templates` |
| `…120030_create_location_tables` | `warehouses`, `storage_locations` |
| `…120040_create_master_data_tables` | `units`, `categories`, `products`, `product_variants`, `product_images` |
| `…120050_create_inventory_tables` | `inventory`, `inventory_movements`, `stock_transfers`, `stock_transfer_items` |
| `…120060_create_party_tables` | `customers`, `suppliers`, `supplier_products` |
| `…120070_create_purchase_tables` | `purchases`, `purchase_items` |
| `…120080_create_order_tables` | `orders`, `order_items`, `order_edits`, `payments` |
| `…120090_create_return_tables` | `returns`, `return_items` |
| `…120100_create_production_tables` | `bill_of_materials`, `production_orders`, `production_items` |
| `…120110_create_system_tables` | `notifications`, `system_settings`, `backups` |

Locations are created **before** master data so `products.default_location_id`
has a target. That ordering is load-bearing; changing it breaks `migrate`
on a fresh database.

---

## 3. Tenant ownership model

Spec §36 is the strictest requirement in the document: a user from one
business must never be able to reach another's records. The schema's job is
to make that *expressible*; enforcing it is Phase 4's authorization layer.

**Business-owned** — carries `business_id`, FK to `businesses`:

`users`, `roles`, `business_settings`, `document_sequences`,
`custom_field_definitions`, `custom_field_values`, `pdf_templates`,
`warehouses`, `storage_locations`, `units`, `categories`, `products`,
`product_variants`, `product_images`, `inventory`, `inventory_movements`,
`stock_transfers`, `stock_transfer_items`, `customers`, `suppliers`,
`supplier_products`, `purchases`, `purchase_items`, `orders`, `order_items`,
`order_edits`, `payments`, `returns`, `return_items`, `bill_of_materials`,
`production_orders`, `production_items`.

Child tables carry `business_id` **as well as** their parent FK, even though
it is reachable through the parent. That is a deliberate, small
denormalisation: it means a tenant predicate can be applied directly to the
table being queried, so the isolation clause never depends on remembering a
join. A missing join is the likeliest way this requirement gets broken, and
this removes the opportunity.

**Platform-level** — deliberately has *no* tenant column:

- `businesses` — is the tenant.
- `system_admins`, `system_admin_refresh_tokens` — a System Admin belongs to
  no business. Kept in their own tables (not a flag on `users`) for the
  reasons in `docs/authentication.md`.
- `permissions` — names a capability the *software* has. Every business draws
  from one catalog; what varies per business is which permissions its roles
  hold, which is `roles` + `role_permissions`.
- `system_settings`, `backups` — the platform's own records (§2/§34's
  system-wide configuration, §52's backup history).

**Nullable tenant** — legitimately either:

- `audit_logs.business_id` — a System Admin action, or a failed login against
  an unrecognised phone, has no tenant context.
- `notifications.business_id` — §31 ends its list with "important system
  alert", and §56's admin dashboard shows platform-level alerts.

`tests/integration/schema.integrity.test.js` asserts all three lists against
`information_schema`, including that the platform tables have *not* acquired
a `business_id` — §7's warning against handing every table one "just because
most tables do", turned into a test.

---

## 4. Keys, constraints and indexes

**Primary keys.** `BIGINT UNSIGNED AUTO_INCREMENT` on every table, except two
link tables (`role_permissions`, `supplier_products`) where the pair of
foreign keys *is* the row and a surrogate id would only permit duplicates.
BIGINT because the specification expects years of accumulated history and a 32-bit key
runs out at 4.3 billion — a ceiling that is cheap to avoid now and expensive
to raise later.

**Foreign keys.** Every relationship is a real FK with a chosen delete rule,
and the rule encodes intent:

- `RESTRICT` where history must not be destroyed — a product that has been
  sold, a customer with orders, a warehouse with stock. This is what makes
  §45 and §61 rule 6 structural rather than a policy someone must remember.
- `CASCADE` only where the child is meaningless alone — order lines with
  their order, a product's images, a role's permission grants, a business's
  settings.
- `SET NULL` where the reference is informational and the record outlives it
  — `created_by` on every document, so archiving an employee does not delete
  last year's invoices.

Three references are intentionally **not** foreign keys, because the referent's
table varies by a sibling column and SQL has no polymorphic FK:
`inventory_movements.reference_id`, `notifications.reference_id`, and
`custom_field_values.entity_id`. Each is paired with a discriminator
(`reference_type`, `notification_type`, or the definition's `entity_type`) so
the join is unambiguous, and each is noted in its migration as a deliberate
exception.

**Unique constraints** — the ones the specification makes authoritative:

| Requirement | Enforced by |
|---|---|
| §54 duplicate SKUs | `uq_products_sku`, `uq_variants_sku` (per business) |
| §33/§54 barcodes | `uq_products_barcode`, `uq_variants_barcode` |
| §54/§61.12 document numbers | `uq_orders_number`, `uq_purchases_number`, `uq_returns_number`, `uq_stock_transfers_number`, `uq_production_number` |
| §7 category codes | `uq_categories_code` |
| §24 role names per business | `uq_roles_business_name` |
| §24 permission identifiers | `uq_permissions_key`, `uq_permissions_module_action` |
| Login identity | `uq_users_phone`, `uq_system_admins_phone` (Phase 2) |
| One stock row per slot | `uq_inventory_slot` (see below) |
| One value per custom field per record | `uq_custom_field_values_record` |

All are scoped to `business_id` where the value is a tenant's own identifier
— two businesses may both use "SKU-001", and a global constraint would leak
one tenant's namespace into another's.

**The `inventory` uniqueness problem, and its fix.** A stock row is identified
by (product, variant, warehouse, location), and two of those are nullable.
MySQL treats every `NULL` in a `UNIQUE` index as distinct, so the obvious
index would accept the same (product, warehouse) pair without limit whenever
variant and location were `NULL` — exactly the duplicate that makes a stock
figure ambiguous. The table therefore carries two **generated** columns,
`variant_key` and `location_key` (`COALESCE(col, 0) STORED`), and the unique
index is on those. Zero is safe as the "none" sentinel because both parents
are `AUTO_INCREMENT` from 1. Written as raw SQL because Knex has no
generated-column API.

**CHECK constraints.** MySQL 8 enforces them, so §54's "prevent invalid" is
partly the database's job rather than only the service's — which matters
because §35's "never trust the frontend" applies to bugs in our own service
code too. §47's stock validation and §54's invalid-input rules become structural:
quantities on order, purchase, return, transfer and production lines must be
`> 0`; prices, costs, refunds and paid amounts must be `>= 0`;
`inventory.reserved_quantity >= 0`; a bill-of-materials row cannot reference
its own product; and `payments` must point at exactly one of an order or a
purchase, never both and never neither.

**Indexes.** Every index in this schema exists for a query the specification
names — each module's list-and-filter requirements, §25's report filters,
§32's searches, §5's dashboard aggregates. Each is commented in its migration with
the query it serves. None was added speculatively: the phase brief asks that
performance work not be speculative, and an index that serves no query still
costs every write.

---

## 5. Derived vs. stored

The specification lists several figures as *fields* which are really
*aggregates*. Storing an aggregate beside the rows it summarises creates a
second source of truth, and §61 rules 4 and 5 exist because those two drift
the first time a document is edited, cancelled or returned. The line this
schema draws:

**Derived, never stored:**

| Spec calls it a field | Actually |
|---|---|
| §8 product "current quantity" | `SUM(inventory.quantity)` over its slots |
| §8 "available quantity" | `quantity - reserved_quantity` |
| §18 customer "total purchases" | `SUM` over that customer's orders |
| §18/§19 "outstanding balance" | `SUM(grand_total - paid_amount)` |
| §18/§19 "order/purchase history" | the rows referencing the party |
| §43 order "remaining" | `grand_total - paid_amount` |
| Returned quantity of an order line | `SUM(return_items.quantity)` for it |

**Stored, with a reason:**

- `inventory.quantity` is *state*, not an aggregate of the movement ledger.
  Recomputing it by summing millions of movements is the query §59 cannot
  afford; the ledger is the audit trail, and §46 keeps the two consistent by
  writing both in one transaction.
- `orders.paid_amount` / `purchases.paid_amount` are running totals. They are
  stored because `payment_status` is a function of them and §25's
  outstanding-payments report filters on it — a status the database cannot
  derive is a status it cannot index. Maintained inside the same transaction
  as the payment row, never separately. The *remaining* amount stays derived,
  because two stored numbers that must sum to a third is one too many.
- Document line snapshots (`order_items.unit_price`,
  `purchase_items.unit_cost`, `order_items.product_name`,
  `production_items.unit_cost`) are copies taken at the time of the
  transaction. §55 requires a historical document to keep answering "what
  prices?" after the product's price has moved.

---

## 6. Status fields

Modelled as native MySQL `ENUM`s, one per entity, with exactly the values the
specification lists — so a status the software does not understand cannot be
stored at all. Valid *transitions* between them are a service-layer concern
and belong to the module phases; the schema provides the vocabulary.

| Entity | Values | Spec |
|---|---|---|
| `orders.status` | draft, pending, confirmed, processing, ready, completed, cancelled, returned, partially_returned | §14 |
| `orders.payment_status`, `purchases.payment_status` | paid, partially_paid, unpaid | §13 |
| `returns.status` | requested, approved, rejected, completed | §16 |
| `production_orders.status` | planned, in_progress, completed, cancelled | §22 |
| `stock_transfers.status` | draft, pending, in_transit, completed, cancelled | §11 |
| `purchases.status` | draft, pending, completed, cancelled | §20 |
| `businesses.status`, `users.status` | active, disabled | §2/§3 |
| `inventory_movements.movement_type` | purchase, sale, return, damage, adjustment, transfer, production, manual_increase, manual_decrease | §12 |
| `payments.method` | cash, bank_transfer, card, other | §13 |
| `notifications.notification_type` | §31's eight kinds | §31 |

§13 calls payment methods "configurable". That is satisfied by the enum being
the closed set of methods the *software* implements, while which subset a
business **offers** is a row in `business_settings` — the database still
refuses a method no code handles.

§17's cancellation record is columns on `orders`
(`cancelled_at`, `cancelled_by`, `cancel_reason`, `status_before_cancel`)
rather than a separate table, because §17 lists exactly those five facts and
an order is cancelled at most once.

---

## 7. Soft delete and timestamps

**Soft-deletable** (`deleted_at`, plus a `status` enum where the entity has
one): `businesses`, `users`, `system_admins`, `roles`,
`custom_field_definitions`, `pdf_templates`, `warehouses`,
`storage_locations`, `units`, `categories`, `products`, `product_variants`,
`customers`, `suppliers`, `purchases`, `orders`, `returns`,
`stock_transfers`, `bill_of_materials`, `production_orders`.

**Append-only — no `deleted_at`, and nothing in the application deletes from
them**: `audit_logs`, `inventory_movements`, `order_edits`,
`login_attempts`. §12 requires that stock records "never silently
disappear" and §15 that order changes are never silently overwritten; giving
these tables a soft-delete column would be an invitation to hide exactly the
history they exist to keep. The schema test asserts the absence.

`status` and `deleted_at` answer different questions and both are needed: a
deactivated category still appears in historical documents (`status =
inactive`), whereas an archived one is gone from every list (`deleted_at`).

**Timestamps.** `created_at` on every table; `updated_at` on every mutable
one. Documents additionally carry their own business date —
`order_date`, `purchase_date`, `return_date`, `production_date`,
`transfer_date`, `moved_at` — separate from the row's creation time, because
a back-dated correction must report the date of the event and the date it was
entered.

**Timezone strategy.** Timestamps are stored in the server's UTC-based
`TIMESTAMP` type; `businesses.timezone` records each tenant's zone for
*presentation*. The pool sets `dateStrings: true`, so a value does not
silently shift as it passes through a Node process whose zone differs from
the business's. Formatting for a tenant is the presentation layer's job.

---

## 8. Changes to existing (Phase 2) tables

Exactly two, both minimal and both required:

1. **`audit_logs.module`** added (backfilled to `'auth'`, then `NOT NULL`,
   plus an index). §30 lists `module` among the fields an audit record must
   carry, and §30 also requires filtering by it. Phase 2 omitted it because
   every event it wrote was an auth event.
2. **`users.role_id`** added, nullable, FK to `roles`. §23/§24 need users to
   have roles. Nullable because Phase 2's users predate roles, and
   `users.is_owner` is kept alongside it — that flag records *who set up the
   business*, which must stay true even if the role row is later edited.

No Phase 2 authentication code, token architecture, repository or route guard
was rewritten.

---

## 9. Backend foundation

### Transactions (§46)

`runInTransaction(fn)` in `src/db/pool.js` — begins, commits on success,
rolls back and rethrows on any error, and releases the connection in a
`finally` either way. A failed rollback is logged but the original error is
the one that propagates, because a failed rollback is usually a symptom of
the same lost connection.

`fn` receives the checked-out connection, and every query inside must use it
rather than the shared pool — a query on the pool inside a transaction
callback silently runs outside the transaction and does not roll back. That
is the easiest mistake here, which is why the connection is a parameter
rather than ambient state.

Also provided: `withConnection` (several statements needing one session, no
transaction), and `queryOne` / `queryAll` / `queryCount` so the
parameterised form is the shortest to write.

Proven by `tests/integration/transaction.rollback.test.js`: a commit
persists every step; an application error partway through leaves nothing
behind; a foreign-key violation rolls back the valid insert before it; and 15
consecutive failing transactions do not exhaust the pool.

### Query safety (§35)

Runtime queries are parameterised `mysql2` calls. The pool sets
`multipleStatements: false`, removing the class of injection that turns one
bound statement into two, and `decimalNumbers: false` so `DECIMAL` money
arrives as an exact string rather than a lossy float.

### Pagination (§26/§59)

`src/db/pagination.js`. `parsePagination` is tolerant of junk (these values
come from URLs people edit) and **clamps** `pageSize` to a hard
`PAGE_SIZE_MAX` of 100 rather than rejecting — an unbounded page size is a
denial of service the client gets to choose. `paginationMeta` produces the
`{ page, pageSize, total, totalPages, hasPreviousPage, hasNextPage }` block,
and `totalPages` is never 0 so a client never renders "Page 1 of 0".

### Filtering, searching, sorting (§25/§32/§59)

`src/db/listQuery.js`, built around one rule: **a column name never comes
from the client.** Parameterising values is not sufficient for a list
endpoint, because `ORDER BY ?` is not valid SQL — the naive way to support
`?sort=name` is to interpolate the client's string, which no amount of value
binding makes safe.

So each module declares a `defineListSpec({ filters, search, sort,
dateRange })` in code. Clients send *keys*; the builder looks them up and
emits the column the developer wrote. An unknown key is ignored. Sort
direction is mapped through a two-entry table so only `ASC`/`DESC` can
appear. Search escapes `%`, `_` and `\` so a term containing them matches
literally. Date ranges are inclusive of the whole end day. `buildOrderBy`
takes a tiebreaker column, because rows sharing a sort value have no defined
order in SQL and without one a row can appear on two pages or neither.

The spec is validated at definition time, so a malformed or unsafe spec fails
when the server starts rather than when a customer first filters a list.

### Validation (§54)

`src/middleware/validate.js` (zod, as established in Phase 0) now reports
**every** failing field in `error.details.fields`, not just the first — a form
with three empty required inputs should light up all three on one round trip.
`validateRequest({ body, query, params })` validates several parts of one
request together. On success the parsed value replaces `req[source]`, so
downstream code reads validated data only and unknown keys are dropped
(mass-assignment protection).

`src/validation/common.js` holds the reusable pieces: ids, required/optional
strings, `moneySchema` (bounded to what `DECIMAL(14,2)` holds),
`quantitySchema`, `percentSchema`, dates, enums, and `listQuerySchema` for
the common list parameters.

### Errors (§53)

`src/middleware/errorHandler.js` is the only place an exception becomes a
response, and handles three cases: a deliberate `AppError` passes through; a
MySQL driver error that the client can actually fix is translated by
`src/utils/databaseError.js`; anything else is logged in full and answered
with one generic message.

That middle case is the part worth explaining. Mapping every driver error to
a 500 loses real information — a duplicate SKU is the user's problem and they
can fix it. So `ER_DUP_ENTRY` becomes a 409, a dangling FK reference a 422, a
`CHECK` violation a 422, a deadlock a retryable 409 `CONCURRENT_UPDATE`, and a
lost connection a 503. Everything else — every syntax error, every access
denial — returns `null` and takes the generic path, because those are bugs or
misconfiguration and never something to describe to a user.

The message never contains the SQL, the table or column names, the constraint
name, the driver's text, or any value from the row. Constraint names leak the
schema; echoing a conflicting value back could confirm another tenant's
record exists. A module that wants field-specific wording passes a
`constraintMessages` map, written in code. A unit test asserts none of those
strings survives into a message.

### Response format (§38)

`src/utils/responseEnvelope.js`:

```
success  { "success": true,  "data": <payload>, "meta": <optional> }
failure  { "success": false, "error": { "code", "message", "details"? } }
list     { "success": true,  "data": [...], "meta": { "pagination": {...} } }
```

`success` is always present and always boolean, so a client branches on one
field. An endpoint returning nothing returns `data: null`, never an empty
body. `paginated(rows, meta)` is here rather than per module so every list
reports paging identically.

### Security (§35)

Unchanged from Phase 2's chain and re-verified this phase: `helmet` headers,
CORS restricted to configured origins, a global rate limit plus a tighter one
on login, a 1 MB JSON body cap, `pino-http` request logging, centralized
error handling, and env-var configuration with no secret carrying a real
default. Phase 3 adds parameterised-query helpers, `multipleStatements:
false`, database-level CHECK constraints, and the column allowlisting above.

RBAC enforcement is **not** here — §24's middleware is Phase 5.

---

## 10. Performance and scalability (§59)

Decisions taken now because they are expensive to retrofit:

- `BIGINT` keys, for years of accumulated history.
- Every list is paged, with a hard ceiling.
- Filtering, searching and sorting happen in SQL, never in Node.
- Composite indexes ordered `(business_id, …)` so the tenant predicate is the
  index's leading column — every query in a multi-tenant app carries it.
- `COUNT(*)` for a page total takes the same WHERE and parameters as the page
  query (`queryCount`), so the total can never describe a different filter
  than the rows.
- Movement and audit ledgers are indexed by `(business_id, …, date)` for
  range scans rather than sorts.
- Stock is stored state, not a fold over the ledger.

Deliberately **not** done: no caching layer, no read replicas, no
partitioning, no materialised aggregates. The brief asks that performance work
not be speculative, and there is no measurement yet to justify any of them.

---

## 11. Phase boundary

**Foundation complete:** schema, migrations, tenant model, keys/constraints/
indexes, soft delete, timestamps, statuses, document-numbering storage,
custom-field storage, audit/notification/PDF-template storage, transactions,
parameterised access, validation, error handling, response format,
pagination, filter/sort, security infrastructure.

**Deliberately later:** every business module API (products, categories,
inventory, sales, orders, customers, suppliers, purchases, returns,
production, reports, PDF); RBAC enforcement and the permission catalog's
contents; document-number allocation service; state-machine transition rules;
backup execution; notification generation; the Demo Mode → real API
migration.

The `permissions` table is created but **empty**. Populating it, and creating
each business's default roles from §23's list, is the RBAC phase's work
because that phase owns the decision of what each built-in role grants.
