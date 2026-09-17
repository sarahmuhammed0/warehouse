# Phase 2 requirements traceability

Maps every Phase 2 requirement to what actually implements it. Status:

- **✅** — built and verified for real (a test ran, or a live `curl` check
  was performed against the running backend).
- **🟡** — built, but verification is incomplete because the live MySQL
  database was not provisioned/reachable as of hand-off (see
  `docs/database.md`).
- **🔶** — foundation built, functional completion deferred to a later
  phase by explicit scope (not a gap — a deliberate boundary).
- **❌** — explicitly out of Phase 2's scope, not built at all.

| # | Requirement | Source | Component / file | Test status |
|---|---|---|---|---|
| 1 | Phone + password login, business users | spec §4 | `backend/src/modules/auth/*`, `frontend/lib/features/auth/*` | ✅ unit-tested (31 backend tests) + ✅ 30 Flutter tests, including a real submit→AuthAuthenticated→dashboard flow; 🟡 not yet run against live MySQL |
| 2 | Phone + password login, System Admin | spec §2/§4, Phase 2 brief | `backend/src/modules/admin-auth/routes.js` sharing `makeAuthController` | ✅ unit-tested at the middleware/service level; 🟡 no live-DB run yet; 🔶 no Flutter UI this phase (documented scope choice, see `docs/authentication.md`) |
| 3 | System Admin structurally separate from a business-user flag | Phase 2 brief's explicit warning | `system_admins` table, `accountAdapters.js`, `requireAccountType` | ✅ enforced by schema (no `business_id` column exists on `system_admins`) + `requireAccountType` unit tests (both directions blocked) |
| 4 | Business/tenant foundation (create a business + owner) | spec §3, blueprint §10 | `backend/src/modules/businesses/*` | ✅ atomic transaction (`runInTransaction`), Zod-validated, System-Admin-gated; 🟡 integration test written, not yet run live |
| 5 | Backend authorization middleware | spec §35, blueprint §8 | `middleware/authenticate.js`, `middleware/requireAccountType.js` | ✅ unit-tested, incl. cross-account-type rejection and JWT-forgery rejection; live-curl-verified (garbage Bearer token → clean 401) |
| 6 | Tenant isolation foundation | spec §36, blueprint §7 | `businessId` sourced only from `req.auth` everywhere in Phase 2's code | ✅ unit-tested (`authenticate` never trusts a client-supplied businessId); 🟡 the mandatory `tenant-isolation.test.js` integration test is written but not yet run against live MySQL |
| 7 | Secure session/token handling | spec §35, blueprint §8 | JWT access token (15min) + opaque hashed refresh token (30d), rotation + reuse detection | ✅ unit-tested round-trip, minimal-claims check, reuse-detection logic in `authService.refresh` |
| 8 | Password security | spec §3/§35 | bcryptjs, cost factor 12, dummy-hash timing mitigation | ✅ unit-tested (never returns plaintext, salted, correct/incorrect verification) |
| 9 | Login protection / rate limiting | spec §58 | phone-scoped lockout (`login_attempts`) + IP-scoped login-route rate limiter | ✅ logic unit-tested; 🟡 lockout behavior itself needs a live DB to exercise end-to-end (integration test written) |
| 10 | Auth-related audit logging | spec §30, blueprint §19 | `audit_logs` table, `writeAuditLog` calls in `authService`/`businesses/controller.js` | 🟡 write-path exists and is called on every login/logout/password-change/business-creation branch; not yet confirmed against a live table |
| 11 | Flutter auth UI | Phase 2 brief §17 | `features/auth/presentation/login_screen.dart` | ✅ run-verified: renders fields, validates, submits, shows loading/error/success states — all exercised by real widget tests, not just inspected |
| 12 | Riverpod auth state | Phase 2 brief §18 | `AuthState` sealed class + `AuthController` (`Notifier`) | ✅ every state (`Initial`/`Unauthenticated`/`Authenticating`/`Authenticated`/`Error`/`SessionExpired`) is reached and asserted on by a real test |
| 13 | Dio auth interceptor | Phase 2 brief §19 | `core/network/auth_interceptor.dart` | ✅ implemented (token attach, single loop-safe refresh-and-retry, concurrent-401 coalescing); not independently unit-tested in isolation this phase — exercised indirectly through the controller/repository tests, not a dedicated interceptor test |
| 14 | Secure token storage | Phase 2 brief §20 | `core/storage/secure_token_storage.dart` (`flutter_secure_storage`) | ✅ interface + real implementation built; platform guarantees documented; test coverage uses the `TokenStorage` interface's in-memory fake (real platform channel isn't testable in `flutter_test`) |
| 15 | Routing guards (redirect unauthenticated → login, authenticated-admin-route → dashboard) | Phase 2 brief §21 | `routing/app_router.dart`'s `_redirect` | ✅ run-verified: 3 widget tests cover login-when-unauthenticated, authenticated-session-blocked-from-admin-routes, and unauthenticated-redirected-from-protected-routes |
| 16 | Business branding hook (post-login) | Phase 2 brief §24 | `_businessBrandLabel` in `app_router.dart`, `AppShell`'s `brandLabel` | ✅ reads the real authenticated business's name; falls back to a generic label only pre-login (never a fabricated business name) |
| 17 | Minimal DB schema (auth/tenancy only) | Phase 2 brief | 6 migrations — see `docs/database.md` | ✅ statically validated (`node --check` + dynamic-import shape check); 🟡 not yet run against live MySQL |
| 18 | Migrations (Knex, forward-only) | Phase 2 brief, `docs/database-access-strategy.md`'s prediction | `database/migrations/*.js`, `backend/knexfile.js` | ✅ written per the Phase 0/1-predicted Knex-for-migrations-only split; 🟡 not yet executed live |
| 19 | Backend tests (unit) | Phase 2 brief | `backend/tests/unit/*.test.js` | ✅ 31/31 passing, run via `node --test`, no live DB required |
| 20 | Backend tests (integration incl. mandatory tenant isolation) | Phase 2 brief | `backend/tests/integration/*.test.js` | 🟡 written (login, session lifecycle, tenant isolation, admin business-creation); confirmed to skip cleanly (not fake-pass) via `requireDatabase(t)` when MySQL is unreachable — 4/4 honestly reported as skipped, 0 fail |
| 21 | Flutter tests (login screen states, validation, RTL) | Phase 2 brief | `frontend/test/widget_test.dart`, `frontend/test/fakes/fake_auth.dart` | ✅ 30/30 passing — includes en/ar/ku login-screen renders with correct `Directionality`, validation-blocks-submit, loading state (via a controlled `Completer`), backend-error display, successful-login navigation, logout, session-expiry banner |
| 22 | Live MySQL verification | Phase 2 brief | — | 🟡 database not provisioned/reachable as of hand-off — see `docs/database.md`'s "Verification status" table for the exact honest breakdown |
| 23 | Security review | Phase 2 brief §33 | `docs/security.md` | ✅ full checklist item-by-item, including explicit 🟡/❌ entries where verification or scope is incomplete |
| 24 | README overhaul | Phase 2 brief §34 | root `README.md` | ✅ (see Git section of the final report for confirmation this was completed same-session) |
| 25 | Docs: authentication/multi-tenancy/security/database/traceability | Phase 2 brief | `docs/*.md` (this file and its four siblings) | ✅ all five written this phase |
| 26 | No business-module scope creep (Products/Orders/Inventory/etc.) | Phase 2 brief, explicit forbidden list | — | ✅ verified by inspection — no such module folder/table/route exists; `frontend/lib/features/*` still only has the 16 Phase-1 placeholders + the new `auth` feature |
| 27 | No full Employees/RBAC/role-management UI | Phase 2 brief, explicit forbidden list | — | ✅ verified by inspection — `users.is_owner` is the only elevation concept; no `roles`/`permissions` tables or screens exist |

## Deviations flagged this phase (not silently decided)

- **System Admin as a separate table**, not a flag — see
  `docs/authentication.md`'s "Recorded deviations".
- **Bearer token + secure device storage instead of httpOnly cookies** —
  same section, driven by the Phase 0 React→Flutter deviation.
- **`users.phone` globally unique, not per-business** — see
  `docs/authentication.md`'s "Phone uniqueness".
- **MySQL80 native Windows service discovered mid-phase**, not the
  Docker-based instance Phase 0/1 assumed — see `docs/database.md`'s
  "Engine" section for how this was handled (asked the user rather than
  guessing credentials).

## Smaller assumptions carried into Phase 2

- **Dev-only integration-test simplification:** `backend/tests/integration/helpers.js`
  uses the same development database as the running app, rather than a
  fully isolated test database — documented in that file as a deliberate
  simplification, not an oversight; revisit if integration tests need to
  run in CI against a disposable database.
- **`is_owner` on `users`, not a full role system:** the minimal elevation
  flag needed to mark "who set up this business" ahead of the deferred RBAC
  system — see `docs/database.md`'s schema notes.
