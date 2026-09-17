# Multi-tenancy

Shared database, shared schema, every tenant-owned row carries `business_id`
— the strategy the [approved architecture](architecture.md) (§7 "Multi-tenant
strategy", spec §36 "Multi-tenant data security") set out before any code
existed. Phase 2 builds the enforcement mechanism for the two tables it
introduces (`users`, and everything hanging off it); later phases inherit
the same rule for every business-owned table they add.

## The rule

No query that touches a tenant-owned table may run without a `business_id`
predicate that came from the **authenticated session** — never from a route
param, query string, or request body. Phase 2 has exactly one place a
`businessId` can legitimately originate: `req.auth.businessId`, set by the
`authenticate` middleware after verifying the JWT. Nothing else in the
request is trusted for it.

## How it's enforced, concretely, in Phase 2's code

1. **Token → tenant.** `authenticate` (`backend/src/middleware/authenticate.js`)
   decodes the access token and sets `req.auth = { accountType, userId,
   businessId }`. For a `system_admin` token, `businessId` is forced to
   `null` even if a payload somehow tried to smuggle one in — covered by a
   dedicated unit test (`authenticate.middleware.test.js`: "forces
   businessId to null for a system_admin token, even if the payload tried to
   smuggle one").
2. **Every repository function that touches `users` takes `businessId` (or
   an equivalent scoping value) from `req.auth`, never from `req.body` /
   `req.params` / `req.query`.** `backend/src/modules/auth/repository.js`'s
   business-user functions (`findByPhone`, `updateLastLogin`, refresh-token
   CRUD, etc.) are all scoped to the row identified by the authenticated
   session, not by a client-supplied id.
3. **`requireAccountType` is the account-type boundary**, not a tenant
   filter by itself — it answers "is this caller a business user / System
   Admin at all," a prerequisite check that runs before any tenant-scoped
   query executes. See `backend/src/middleware/requireAccountType.js`.
4. **System Admin is the one deliberate exception**, exactly as the
   blueprint specifies: `POST /api/admin/businesses`
   (`backend/src/modules/businesses/`) is gated by `authenticate` +
   `requireAccountType('system_admin')` and is the only Phase 2 endpoint
   allowed to create a row (a business + its owner) without an existing
   `businessId` in scope — because creating the tenant is exactly the
   action that can't itself be tenant-scoped.

## Verifying it — the mandatory tenant-isolation test

Per the Phase 2 instructions and the blueprint's own testing rule ("tenant
isolation is a first-class test category, not a side effect of feature
tests"), `backend/tests/integration/tenant-isolation.test.js` is a required
test, not an optional one. It creates two separate businesses, seeds each
with its own user, and asserts:

- A business user's JWT always carries **that** user's real `businessId` —
  never a client-supplied one — even if the request body/query string tries
  to pass a different `businessId`.
- A token issued for one account type is rejected on a route gated for the
  other (`requireAccountType` cross-checks, both directions).
- A token signed with a different/forged secret is rejected outright
  (`verifyAccessToken` throws; caught by Express's synchronous-throw
  handling — confirmed live via a garbage-Bearer-token curl check during
  manual verification, not just unit-tested).

This test requires a live MySQL connection (`requireDatabase(t)` in
`tests/integration/helpers.js`) and is honestly reported as **skipped, not
passed**, when the database is unreachable — see `docs/database.md` and the
Phase 2 final report's "MySQL Verification" section for the actual run
status as of this phase.

## System Admin boundary (separate from tenant isolation, related to it)

System Admin accounts are not a "super business user" — see
`docs/authentication.md`'s recorded deviation for why they live in a wholly
separate table (`system_admins`) rather than a flag on `users`. Two
independent layers keep a System Admin session and a business-user session
from ever being confused with each other:

- **Backend:** `requireAccountType('system_admin')` vs.
  `requireAccountType('business_user')` — a JWT's `accountType` claim is
  fixed at issuance (which login endpoint was used) and can't be escalated
  by anything the client sends afterward.
- **Frontend (UX only, not a security boundary):** `routing/app_router.dart`'s
  `_redirect` sends any authenticated session that reaches an `/admin/*`
  route back to the business dashboard, and — since Phase 2's Flutter app
  never authenticates as a System Admin in the first place (see
  `docs/authentication.md`) — any authenticated Flutter session is
  necessarily a business user by construction. The file's own top comment
  is explicit that this redirect is UX convenience only: "it stops a
  signed-out user from *seeing* a business screen's empty shell, nothing
  more... every route's actual data comes from backend endpoints that
  independently re-check `req.auth` on every request."

## What Phase 2 does not yet add to the isolation model

- No business-owned data tables exist yet beyond `users` itself (Products,
  Orders, Inventory, etc. are Phase 3+) — so there is, as of this phase, only
  one tenant-scoped table to prove the pattern against. The pattern
  (`businessId` from `req.auth`, composite indexes/unique constraints
  leading with `business_id`) is what every future module's migrations and
  repositories are expected to follow, per the blueprint's §5 "Database
  design" conventions.
- No cross-tenant reporting/aggregation exists (System Admin "system stats"
  from spec §2) — out of Phase 2 scope.
