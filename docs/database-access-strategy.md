# Backend database access — decision record

**Chosen for Phase 0: `mysql2/promise`, a single connection pool, raw
parameterized SQL.** No ORM, no query builder yet — see below for when/how
that changes.

This documents the choice per the architecture blueprint's own comparison
table (artifact §5's "Node.js driver / ORM compatibility"), now made
concrete for what Phase 0 actually ships.

## Why `mysql2`

| Requirement | How `mysql2` satisfies it |
|---|---|
| MySQL 8.x compatibility | First-class — supports `caching_sha2_password` (MySQL 8's default auth plugin), which the older `mysql` package does not |
| Transaction support | `connection.beginTransaction()` / `commit()` / `rollback()` on a checked-out pool connection — exactly what §13's multi-step transactions (sale, purchase, return, production) need |
| Connection pooling | Built in (`mysql2.createPool`) — `backend/src/db/pool.js` creates exactly one, reused everywhere |
| Query safety | Parameterized queries (`?` placeholders / named placeholders) — the only way any query is ever written in this codebase; string-concatenated SQL is never used (§25's SQL-injection rule) |
| Maintainability | Thin layer over plain SQL — nothing to learn beyond SQL itself, and no ORM "magic" hiding what a query actually does when a module's repository is read later |

## Migration strategy for Phase 1+

Phase 0 creates no schema (by design). When Phase 1 needs real tables, the
architecture's plan is **hand-written, forward-only migration files** in
`database/migrations/` (already reserved, currently empty — see
`database/README.md`), run via a lightweight migration runner rather than
an ORM's auto-sync:

- Knex.js is the leading candidate purely as a **migration/schema-builder
  tool** (its `knex.schema.createTable(...)` API), used alongside — not
  instead of — `mysql2` for actual application queries. This keeps the
  query-safety and maintainability properties above unchanged; Knex would
  only own the "create/alter tables in order" concern.
- The alternative is a minimal hand-rolled runner (a `migrations` tracking
  table + a script that applies `.sql` files in filename order) — smaller
  dependency footprint, more code to maintain. This choice is deferred to
  Phase 1, when there's an actual first table to migrate and a real
  decision to make rather than a hypothetical one.

## Why not an ORM (Sequelize/Prisma) for Phase 0

Per the architecture's engine-decision review: an ORM's auto-introspection
and migration-diffing tooling adds a layer whose behavior differs between
MySQL and MariaDB in ways that are hard to notice until they matter (JSON
column typing was the concrete example found). Since this project commits
to hand-written migrations and parameterized SQL regardless of engine, an
ORM would add a large dependency and a new abstraction to learn without
solving a problem this project actually has. This can be revisited per
module later if a specific module's CRUD volume genuinely justifies it —
not adopted wholesale up front.

## Lock contention: the gap-lock trap, and why transactions retry

An intermittent 409 — "Another change was being saved at the same time" — had
been showing up in the test suite for several phases with the cause unproven.
It reproduced reliably once the suite stopped being CPU-bound (see below), and
the cause turned out to be a single `DELETE`.

`replaceBillOfMaterials` removed the lines no longer in a recipe with:

```sql
DELETE FROM bill_of_materials
 WHERE business_id = ? AND product_id = ? AND material_product_id NOT IN (?)
```

`uq_bom_product_material` is unique on `(product_id, material_product_id)` —
**`business_id` is not in it**. So a `NOT IN` over `material_product_id` is a
range scan inside one product's index group, and InnoDB's next-key locking
extends the gap lock to the *following* index record, which belongs to the next
`product_id` — very possibly a different business's product. The `INSERT ... ON
DUPLICATE KEY UPDATE` statements that follow then need to insert into that same
range.

Two recipes saved at the same moment, for unrelated products in unrelated
businesses, could each hold the gap the other's insert needed. One became the
deadlock victim and its user saw a 409 on a save that should simply have
worked.

**The fix is to stop range-scanning.** The current material ids are read first,
and only the rows actually being removed are deleted, by
`(business_id, product_id, material_product_id)` equality — a record lock on
exactly the row going away, and no gap lock at all. The common edit (changing a
quantity, adding a line) removes nothing and now issues no `DELETE` whatsoever.
Across six consecutive full runs afterwards, lock contention did not occur once.

**`runInTransaction` also retries, which is separate and deliberate.** InnoDB
chooses a victim whenever two transactions genuinely deadlock and rolls it back
whole; MySQL's own manual states that an application must be prepared to
re-issue such a transaction. A rolled-back transaction has applied nothing, so
repeating it is safe — which is why the retry covers exactly
`ER_LOCK_DEADLOCK` and `ER_LOCK_WAIT_TIMEOUT` and nothing else. A duplicate
key or a constraint violation fails identically on a second attempt; retrying
those would turn one honest error into three and delay it.

Three attempts, with a growing pause, because retrying instantly tends to
reproduce the interleaving that collided in the first place. The retry **is
not** a licence for a transaction body to have effects outside the database: a
retry would repeat them. Nothing passed to `runInTransaction` does.

Because the narrowed `DELETE` means the retry now almost never fires, it is
covered by unit tests over `withLockRetry` with the attempt passed in, rather
than by provoking a real deadlock — otherwise it would be exactly the kind of
recovery path that ships unexercised and is found to be wrong on the night it
is needed.

## Test-run configuration (`backend/tests/test.env`)

Two settings are overridden for `npm test`, via node's `--env-file`, which is
read before dotenv and which dotenv then declines to overwrite. Neither is a
secret, which is why the file can be committed while `.env` cannot.

**`BCRYPT_SALT_ROUNDS=4`.** Production hashes at cost 12 — roughly 300ms of
deliberate CPU per hash. `node:test` runs each test file as its own process,
as many at once as there are cores, and a suite that hashes hundreds of
passwords at cost 12 saturates the machine outright. Queries then slow down,
connections stay checked out, and the pool queue — which waits *without* a
limit — backs up until tests that were only waiting are reported as failures
with durations in the minutes. One run in seven failed this way, with reported
durations of nineteen minutes and six hours, which is what starvation looks
like rather than a logic error. Cost 4 changes nothing any test asserts: the
suite checks that a hash verifies and a wrong password does not, which holds at
any cost.

**`DB_CONNECTION_LIMIT=3`.** Ten per process is right for one server; across
~24 concurrent test processes it is up to 240 against a `max_connections` of
151. Three is more than a single test file needs, since tests inside a file run
in sequence.

Together these took the suite from ~128s to ~35s — and the speed-up is not the
point. Removing the CPU saturation is what made the gap-lock deadlock above
reproduce consistently enough to diagnose, after phases of it being written off
as flakiness.
