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
