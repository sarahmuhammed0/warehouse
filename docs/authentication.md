# Authentication

Phase 2 implements real phone + password authentication for two distinct
account types — business users and System Admins — against a live MySQL 8.x
database, with no mock data, no hardcoded credentials, and no bypass path.

## Recorded deviations from the approved architecture

The [approved blueprint](architecture.md) (§8 "Auth & authorization", §25
"Security checklist") specified two things Phase 2 deliberately does
differently, both flagged rather than silently substituted:

1. **Two separate identity tables, not one `users` table with an
   `is_system_admin` flag.** The blueprint's original design put System
   Admins in the same `users` table (`business_id = NULL`,
   `is_system_admin = true`) sharing one login endpoint. The Phase 2
   instructions explicitly overrode this ("do NOT simply give a business
   user a magic `is_system_admin` flag if that would create a weak
   tenant-isolation model"). Phase 2 instead built **`users`** (business
   accounts, always `business_id NOT NULL`) and **`system_admins`**
   (platform accounts, no `business_id` column at all — not nullable, absent)
   as two structurally separate tables, with two separate login routes
   (`/api/auth/login` vs `/api/admin/auth/login`) sharing the same service
   logic through an adapter (see "Two account types, one service" below). A
   business user and a System Admin are different rows in different tables,
   not different values of the same flag — there is no column anywhere that
   could accidentally be misread as "give this business user admin rights."
2. **Bearer tokens in `Authorization` headers + secure device storage, not
   httpOnly cookies.** The blueprint assumed a browser (React) frontend and
   specified an httpOnly, Secure, SameSite=strict refresh cookie. Phase 0
   already recorded the React→Flutter deviation; a cookie jar tied to one
   browser origin doesn't map cleanly onto a Flutter app that also runs as
   Windows desktop and mobile builds with no shared browser cookie store.
   Phase 2 instead: issues the access token as a signed JWT and the refresh
   token as an opaque random value, both returned in the JSON response body,
   and stores them client-side in platform-appropriate secure storage
   (`flutter_secure_storage` — Keystore/Keychain/Credential Manager per
   platform; see `core/storage/secure_token_storage.dart`'s doc comment for
   the per-platform guarantee, including Web's documented weaker case). The
   access token is attached via `Authorization: Bearer <token>` on every
   request instead of an automatic cookie. The security properties this is
   meant to preserve — short-lived access token, revocable server-side
   refresh token, never logged — are all still enforced; only the transport
   changed.

## Phone uniqueness

The blueprint's original `users` table scoped phone uniqueness **per
business** (`UNIQUE(business_id, phone)`), reasoning that the same person
could plausibly hold accounts at two different businesses under one phone
number. Phase 2's `users` table instead makes `phone` **globally unique**
(`uq_users_phone` — see `database/migrations/..._create_users_table.js`).

This is a direct consequence of the login screen's own shape (spec §4): it
asks for a phone and a password with **no business selector** — there is
nothing else in the login request to disambiguate which business's row to
check if the same phone existed under two different businesses. Login looks
up the account by phone alone (`authService.login` calling
`adapter.findByPhone`) and only learns which business it belongs to *after*
a password is proven correct (see `login_screen.dart`'s doc comment:
branding can't be shown before login for exactly this reason). A
per-business-unique phone would require either a business-selection step
before password entry (not in the spec's described login flow) or a lookup
ambiguity the login endpoint has no way to resolve.

**Flagged, not silently decided:** if a real deployment needs the same
person to hold logins at two separate businesses with one phone number, this
constraint would need to be relaxed alongside adding a business-selection
step to the login flow — a product decision for a later phase, not
something Phase 2's scope (auth + tenancy foundation only) should decide
unilaterally.

## Two account types, one service

- **`backend/src/modules/auth`** — the core login/refresh/logout/me/
  change-password logic (`authService.js`), written once and parametrized by
  an **account adapter** (`accountAdapters.js`) rather than duplicated per
  account type. `businessUserAdapter` reads/writes `users` +
  `refresh_tokens`; `systemAdminAdapter` reads/writes `system_admins` +
  `system_admin_refresh_tokens`. `controller.js`'s `makeAuthController(adapter)`
  produces the HTTP handlers; `modules/auth/routes.js` mounts it at
  `/api/auth/*` with `businessUserAdapter`, `modules/admin-auth/routes.js`
  mounts the same controller factory at `/api/admin/auth/*` with
  `systemAdminAdapter`. One code path, two data stores, enforced by which
  adapter is injected — not by a runtime `if (isAdmin)` branch inside the
  service.
- Both login endpoints accept the same request shape (`phone`, `password`)
  and return the same response shape (`accessToken`, `refreshToken`,
  `account`, `business` — `business` is `null` for a System Admin).

## Login flow (`authService.login`)

1. **Lockout check first, phone-scoped.** `login_attempts` is queried for
   recent failures against the submitted phone (not the account row, which
   may not exist) — 5 failures in 15 minutes locks that phone out,
   independent of which IP is attempting it (spec §58: IP rotation alone
   must not bypass the lock).
2. **Look up the account by phone** in whichever table the adapter points
   at.
3. **Password verification always runs**, even if no account was found —
   against a real bcrypt hash of a fixed dummy value
   (`DUMMY_HASH`, generated once via `bcrypt.hashSync` at module load, not
   hand-typed) when there is no real account to compare against. This keeps
   the response time for "phone doesn't exist" statistically
   indistinguishable from "phone exists, wrong password" — a timing side
   channel that would otherwise let an attacker enumerate registered phone
   numbers.
4. **Generic error until the password is proven correct.** Whether the
   phone doesn't exist or the password is wrong, the caller sees the same
   `Invalid phone number or password.` — spec §58's explicit non-negotiable,
   verified in `tests/unit/authenticate...` and the login integration test.
   Only *after* a correct password is confirmed does the code check
   account/business status (disabled, etc.) and return a specific message —
   safe to disambiguate only once the caller has proven they know the
   password (documented in `authService.js` as "safe to disambiguate only
   after proof of knowledge").
5. **On success:** a JWT access token (`signAccessToken`, ~15 minutes,
   minimal claims — see "Token shape" below) and an opaque refresh token
   (`generateRefreshToken()`, 32 random bytes, hex-encoded) are issued. Only
   the **SHA-256 hash** of the refresh token (`hashRefreshToken()`) is
   persisted — the raw value is returned to the client once and never
   stored server-side, so a database read alone can never yield a usable
   token.
6. **Audit logged** (`login_success` / `login_failed`) regardless of
   outcome, via `writeAuditLog`.

## Token shape

- **Access token — JWT, ~15 minutes (`JWT_ACCESS_TTL=15m`).** Claims are
  deliberately minimal: `accountType` (`business_user` | `system_admin`),
  `userId`, `businessId` (present only for business users). No permissions
  list, no name, no phone — verified by a unit test
  (`token.test.js`: "access token payload never includes the raw password or
  a permissions list"). `businessId` in the token is what every backend
  tenant-isolation check reads — never a client-supplied value (see
  `docs/multi-tenancy.md`).
- **Refresh token — opaque random value, ~30 days (`JWT_REFRESH_TTL=30d`),
  not a JWT.** Chosen deliberately asymmetric to the access token: a JWT
  refresh token would be self-verifying and impossible to revoke without an
  extra denylist; an opaque token stored (hashed) server-side is revocable
  by simply deleting/marking the row, which is what logout, a session-reuse
  detection (below), and a password change all rely on.
- **Refresh rotation + reuse detection.** Every `POST /api/auth/refresh`
  consumes the presented refresh token and issues a brand-new one (the old
  hash is marked used/revoked, never reusable). If a refresh token that was
  already consumed is presented again — the signature of a stolen token
  being replayed after the legitimate client already rotated past it — every
  refresh token for that account is revoked, forcing a full re-login. This
  is `authService.refresh`'s reuse-detection branch.

## Logout & change-password

- **Logout** revokes the specific refresh token presented (`revoked_at` set)
  — not just a client-side discard. The Flutter side's `logout()` also
  always clears local storage even if the network call fails (best-effort;
  a stuck "still logged in" UI from a flaky connection would be worse than a
  server-side refresh token that simply expires on its own in ≤30 days).
- **Change password** (`authService.changePassword`) revokes **every**
  refresh token for that account, including the one making the request —
  the Flutter `AuthController.changePassword()` then clears local storage
  and forces a fresh login, by design, not a bug.

## Login protection / rate limiting

Two independent layers (spec §58), enforced together:

1. **Phone-scoped lockout** (above) — 5 failed attempts / 15 minutes,
   regardless of source IP.
2. **IP-scoped rate limiting** on the login routes specifically — a
   dedicated, stricter limiter (20 requests / 15 minutes) mounted only on
   `/api/auth/login` and `/api/admin/auth/login`, separate from and in
   addition to the app-wide API rate limiter from Phase 0
   (`backend/src/modules/auth/routes.js`).

`getClientIp(req)` (`backend/src/utils/requestInfo.js`) reads
`req.socket.remoteAddress` rather than `req.ip`, since this deployment does
not configure Express's `trust proxy` — using `req.ip` without that
configured would silently trust a client-supplied `X-Forwarded-For` header,
undermining the IP-scoped limiter entirely. Documented in that file; revisit
if/when a reverse proxy is introduced in front of the API.

## Flutter scope (deliberately narrower than the backend)

The backend fully supports System Admin login (`/api/admin/auth/*`). Phase
2's Flutter app does **not** build a System Admin login screen —
`authRepositoryProvider` is hardwired to `AccountType.businessUser`
(`features/auth/presentation/providers/auth_controller.dart`). This is a
scope decision, not a capability gap: a System Admin console is out of
Phase 2's UI scope per the phase instructions (no admin management screens
this phase), and the routing guard independently prevents a business-user
session from reaching `/admin/*` (see `docs/multi-tenancy.md`'s "System
Admin boundary").

## What Phase 2 does not implement (deferred, not silently dropped)

- **Password reset / forgot password** — the blueprint's §8 describes a
  generic-response, single-use, short-lived reset token; Phase 2's
  instructions did not include a reset flow in scope, and building one
  requires an out-of-band delivery channel (SMS/email) the architecture doc
  itself already flagged as an unresolved infra decision. No UI, no
  endpoint, no `password_reset_tokens` table exist yet.
- **Full RBAC / roles / permissions** (`roles`, `permissions`,
  `role_permissions`, `user_roles` from the blueprint's §9) — explicitly out
  of scope this phase (business modules and employee/role management are
  Phase 3+ work). The `accountType` distinction (`business_user` vs.
  `system_admin`) is the only authorization axis Phase 2 implements.
