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
