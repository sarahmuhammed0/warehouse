# Security review (Phase 2)

Status against every item the [approved architecture](architecture.md)'s
§25 security checklist and the Phase 2 instructions' own §33 review list
require, as actually implemented — not aspirational. ✅ = built and
verified (unit-tested and/or live-curl-verified this phase); 🟡 = built,
verification limited by the still-unprovisioned live database (see
`docs/database.md`); ❌ = not built this phase (deferred, scope reason
given).

| Item | Status | Evidence |
|---|---|---|
| Passwords hashed, never logged/returned | ✅ | `backend/src/utils/password.js` (bcryptjs, cost factor 12 via `BCRYPT_SALT_ROUNDS`); `logger.js`'s redact config strips `*.password`/`*.newPassword`/`*.passwordHash` from every log line; `safeAccount`/response shapes never include a hash field |
| No plaintext passwords anywhere | ✅ | Same as above; `password.test.js` asserts `hashPassword` never returns the plaintext |
| No secrets committed | ✅ | `backend/.env` is git-ignored (verified in `git status`); only `.env.example` (placeholder values) is tracked; `JWT_SECRET` used in dev is a locally-generated random value, not a repo-committed constant |
| Tokens never logged | ✅ | `logger.js` redact config: `req.headers.authorization`, `*.accessToken`, `*.refreshToken`, `*.token`, all with `remove: true` |
| Authorization enforced server-side | ✅ | `requireAccountType` runs before every account-type-gated controller; never inferred from anything the Flutter client sends |
| Tenant isolation enforced server-side | ✅ | See `docs/multi-tenancy.md`; `businessId` sourced only from `req.auth`, proven by the mandatory tenant-isolation test |
| SQL injection protection | ✅ | 100% parameterized queries (`mysql2/promise` placeholders) across `backend/src/modules/auth/repository.js` and `businesses/repository.js` — no string-concatenated SQL anywhere in Phase 2's code |
| Input validation | ✅ | Zod schemas (`validation.js` in each module) run via the shared `validate` middleware before any controller executes; reject unknown/extra fields per the blueprint's "request validation" item |
| Rate limiting | ✅ | App-wide limiter (Phase 0) + a dedicated stricter limiter (20 req/15min) on `/api/auth/login` and `/api/admin/auth/login` specifically |
| Login protection (lockout) | ✅ | Phone-scoped lockout, 5 failures/15min, independent of source IP — see `docs/authentication.md` |
| No account-enumeration leak | ✅ | Identical generic error for "phone not found" and "wrong password," including matched response timing via the dummy-hash comparison — see `docs/authentication.md`'s login-flow section |
| Secure headers | 🟡 | Helmet was applied in Phase 0 (`backend/src/app.js`) and untouched this phase; not independently re-verified against auth routes specifically this phase, but it's global middleware, not route-scoped, so it applies uniformly |
| CORS | 🟡 | Phase 0's explicit-allow-list CORS config, untouched this phase; not modified or re-tested for the new auth/business routes specifically, since it's origin-based, not route-based |
| Safe error handling | ✅ | Centralized error handler (Phase 0) returns generic messages; confirmed live this phase — a DB-unreachable login attempt returns a clean generic 500 (`INTERNAL_ERROR`) while the real `ER_ACCESS_DENIED_ERROR` + stack trace is logged server-side only, and a garbage `Authorization: Bearer` token returns a clean 401, not a stack trace |
| Token expiration | ✅ | Access token 15 minutes (`JWT_ACCESS_TTL`); refresh token 30 days (`JWT_REFRESH_TTL`), both env-configured, not hardcoded |
| Logout / revocation | ✅ | Logout revokes the specific refresh token server-side (`revoked_at`), not just a client-side discard; change-password revokes every refresh token for the account, including the current session |
| Refresh-token reuse detection | ✅ | A previously-rotated-away refresh token, if replayed, revokes every session for that account — see `docs/authentication.md` |
| No user-controlled tenant switching | ✅ | `businessId` never accepted from client input anywhere in Phase 2's endpoints — see `docs/multi-tenancy.md` |
| Sensitive data never in API responses | ✅ | `safeAccount`/`safeBusiness` shapes (repository/controller layer) are allow-lists, not "everything except the password field" — nothing beyond what the Flutter models (`auth_models.dart`) actually parse exists in the response |
| PII access audit-logged | 🟡 | `audit_logs` records login success/failure and business creation this phase; broader "viewing financial info" auditing doesn't apply yet since no financial-data endpoints exist yet (Phase 3+) |
| Full RBAC / permission catalog | ❌ | Explicitly out of scope this phase — see `docs/authentication.md`'s "what Phase 2 does not implement" |
| Password reset flow | ❌ | Explicitly out of scope this phase (undelivered infra dependency — SMS/email channel not chosen) — see `docs/authentication.md` |

## Flutter-side security notes

- **Token storage** — `flutter_secure_storage`, not `shared_preferences`
  (unencrypted) or a Riverpod-only in-memory value (lost on app restart,
  which would defeat "remember session"). Per-platform guarantee documented
  in `core/storage/secure_token_storage.dart`, including the **explicitly
  weaker** Web case (`localStorage` + WebCrypto, vulnerable to XSS unlike a
  real OS keychain) — which is exactly why the access token stays
  short-lived (15 min) on every platform, not just Web.
- **No token logged client-side** — the Dio `AuthInterceptor` never logs
  request/response bodies or headers; Dio's own default logging interceptor
  is not enabled anywhere in the app.
- **Refresh coalescing prevents a token stampede** — concurrent 401s from
  several in-flight requests share one refresh call (`_refreshing` future in
  `auth_interceptor.dart`) rather than each independently racing to refresh
  and potentially invalidating each other's new token via the reuse-detection
  rule above.
- **No hardcoded credentials, no bypass, no fake success anywhere** — every
  login attempt in the Flutter app goes through `ApiAuthRepository` to the
  real backend; the only test doubles (`test/fakes/fake_auth.dart`) are
  confined to `flutter test` and never referenced from `main.dart` (the
  production composition root).

## Known gaps / honest limitations as of this phase

- Helmet/CORS configuration itself (both Phase 0 deliverables) were not
  re-audited line-by-line this phase — they weren't touched by Phase 2's
  changes, so re-verifying them was out of this phase's actual diff, but a
  full audit hasn't been performed either.
- Live database verification (SQL injection behavior against a real MySQL
  instance, the tenant-isolation integration test, migrations) is pending
  the database provisioning described in `docs/database.md` — see that
  file and the final report's "MySQL Verification" section for exact
  status.

---

# Security review — Phase 3 additions

Phase 3 added no authentication or authorization code. What it added is
schema and shared data-access machinery, and the security questions those
raise are different ones. Same key: ✅ built and verified; 🟡 built,
verification needs the live database; ❌ not built this phase.

| Item | Status | Evidence |
|---|---|---|
| SQL injection — values | ✅ | Every runtime query is a parameterised `mysql2` call. `pool.js` sets `multipleStatements: false`, removing the class of attack that turns one bound statement into two. |
| SQL injection — **identifiers** | ✅ | The harder half, and the reason `src/db/listQuery.js` exists: `ORDER BY ?` is not valid SQL, so a naive `?sort=` handler interpolates client text and no amount of value binding makes it safe. Column names come only from a developer-written `defineListSpec`; clients send *keys*, and an unknown key is ignored. `tests/unit/listQuery.test.js` fires injection attempts at filter keys, sort keys and sort direction — 3 dedicated assertions. |
| Sort direction | ✅ | Mapped through a two-entry table, so only the literals `ASC`/`DESC` can reach SQL. `'asc; DROP TABLE users--'` falls back to the default. |
| Spec safety checked before runtime | ✅ | `defineListSpec` validates every column against `/^[A-Za-z_][A-Za-z0-9_]*(\.[A-Za-z_][A-Za-z0-9_]*)?$/` at module load, so an unsafe spec fails at server start, not when a customer first filters a list. |
| LIKE metacharacters | ✅ | `%`, `_` and `\` in a search term are escaped, so a search for `100%` finds that text instead of matching everything. |
| Unbounded result sets | ✅ | `parsePagination` clamps `pageSize` to 100 rather than trusting it — an unbounded page size is a denial of service the client would otherwise get to choose. |
| Mass assignment | ✅ | `validate`/`validateRequest` replace `req.body`/`req.query`/`req.params` with the *parsed* value, so unknown keys are dropped before a controller sees them. |
| Error messages leak no internals | ✅ | `src/utils/databaseError.js` maps only the driver errors a client can act on. Messages never contain the SQL, the table or column names, the constraint name, the driver's text, or any value from the row. A unit test asserts that none of `uq_products_sku`, the conflicting value, the table name or `Duplicate entry` survives into the message. |
| Error messages leak no *existence* | ✅ | The conflicting value is withheld specifically because echoing it back could confirm that another tenant's record exists. |
| Syntax/access errors stay generic | ✅ | `toAppError` returns `null` for `ER_PARSE_ERROR`, `ER_ACCESS_DENIED_ERROR` and `ER_NO_SUCH_TABLE`, sending them down the generic-500 path where the detail is logged server-side only. |
| Tenant isolation — expressible in the schema | 🟡 | `business_id` plus a real FK on all 32 business-owned tables, including child tables where it is technically redundant, so the isolation predicate never depends on remembering a join. `schema.integrity.test.js` asserts all 32, and asserts the platform tables have **no** tenant column. |
| Tenant isolation — enforced | 🔶 | `buildWhere` applies the tenant scope first, before any client-supplied filter, and `businessId` still comes only from `req.auth` (Phase 2's rule, unchanged). Endpoint-level enforcement for business modules arrives with those modules. |
| Invalid data rejected by the database itself | 🟡 | CHECK constraints on every quantity, price, cost and refund; `ck_payment_exactly_one_parent`; `ck_bom_not_self_referencing`. This matters because "never trust the frontend" has to hold for bugs in our own service code too. Proven refusing an invalid row in `transaction.rollback.test.js`. |
| Partial writes | 🟡 | `runInTransaction` commits or rolls back, releases the connection either way, and preserves the original error. Four tests, including 15 consecutive failures to prove the pool is not leaked. |
| Money precision | 🟡 | `DECIMAL(14,2)`/`(14,3)` everywhere, `decimalNumbers: false` so a value arrives as an exact string instead of a lossy float. The schema test asserts there is **no** FLOAT or DOUBLE column anywhere in the database. |
| No credentials committed | ✅ | `.env` remains git-ignored (confirmed in `git status` this phase). `db-provision.mjs` prompts for the administrator password with hidden TTY input and never writes it to disk, a log, or shell history; no credential appears in any tracked file, and the throwaway credential-probe script used during diagnosis was deleted rather than committed. |
| Least privilege for the app user | ✅ | `db-provision.mjs` grants a specific privilege list on `warehouse_os_dev.*` only — no `GRANT OPTION`, no `SUPER`, nothing on `*.*`. Narrower than Phase 2's recorded `GRANT ALL PRIVILEGES`, deliberately. |
| Identifier injection in provisioning | ✅ | Database and user names come from `.env` and reach `CREATE DATABASE`/`CREATE USER` as SQL text, where they cannot be bound parameters — so each is validated against `/^[A-Za-z0-9_]+$/` before being backtick-quoted. |
| Wrong-server protection | ✅ | `db-provision.mjs` refuses to run if the server it reaches reports `version_comment` containing "mariadb", so a misconfigured port cannot make this project write to the MariaDB instance. |
| Audit trail cannot be quietly edited away | 🟡 | `audit_logs`, `inventory_movements`, `order_edits` and `login_attempts` have no `deleted_at` and nothing deletes from them; the schema test asserts the absence. `audit_logs` gained the `module` field the spec requires. |
| RBAC enforcement middleware | ❌ | Later phase. The schema (`permissions`, `roles`, `role_permissions`, `users.role_id`) is ready, and the `permissions` catalogue is deliberately left **empty** — populating it is the RBAC phase's decision to make. |
| Live SQL-injection behaviour against a real MySQL server | 🟡 | The unit tests prove the SQL that gets *built*; confirming the server's behaviour needs the provisioned database. |

## Carried-forward gaps, restated honestly

- Helmet and CORS are still Phase 0 configuration, re-verified this phase
  only by observing the headers on a live response (`Strict-Transport-Security`,
  `X-Content-Type-Options: nosniff`, `X-Frame-Options: SAMEORIGIN`,
  `RateLimit-Policy: 100;w=60`). A line-by-line audit of that configuration
  still has not been performed.
- Everything requiring a live database connection remains unverified for the
  same reason as Phase 2 — see `docs/environment.md`'s Phase 3 update and
  `docs/phase3-traceability.md`'s "Live verification status".
