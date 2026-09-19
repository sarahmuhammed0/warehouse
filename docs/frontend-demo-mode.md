# Frontend-only demo mode

A way to run and test the entire Flutter UI with the Node.js/MySQL backend
completely off — added on top of the frontend-first phase's already-local
business-module repositories, whose one remaining hard dependency on a live
backend was the **login gate** itself (`ApiAuthRepository` calling the real
`/api/auth/login`). This document explains that one addition; the business
modules themselves were already demo-data-backed — see
[`docs/frontend-coverage.md`](frontend-coverage.md).

## How it works

One central compile-time switch, `AppModeConfig` (`core/config/app_mode.dart`),
following the same pattern `core/config/env.dart` already established:

```dart
enum AppMode { demo, backend }
```

`authRepositoryProvider` (`features/auth/presentation/providers/auth_controller.dart`)
reads it through one pure function, `buildAuthRepository(mode, client,
accountType)`, and returns either:

- **`DemoAuthRepository`** (demo mode, the default) — implements the exact
  same `AuthRepository` interface as the real one, resolves every method
  (`login`/`refresh`/`me`/`logout`/`changePassword`) from fixed in-memory
  demo identities, and never constructs or calls Dio/`ApiClient`.
- **`ApiAuthRepository`** (backend mode) — unchanged from Phase 2, calls the
  real `/api/auth/*` / `/api/admin/auth/*` endpoints.

`AuthController`, the login screen's form, the Dio interceptor, secure
token storage, and every route guard are **unmodified** — they all still
just talk to "the `AuthRepository`," with no `if (demo)` branch anywhere
outside this one selection point. That's the whole point of the interface
having existed since Phase 2.

## Running it

```bash
cd frontend
flutter run                                    # DEMO mode — no backend needed (the default)
flutter run --dart-define=APP_MODE=backend      # real backend required, same as before
```

`flutter build web --release` / `flutter test` also default to demo mode
(no `--dart-define` passed).

## Logging in

The login screen shows two one-click buttons whenever `AppModeConfig.isDemo`
is true (never in backend mode):

- **Continue as Business (Demo)** — logs in as a demo business owner
  (`Demo Owner`, business `Demo Furniture Factory`) and lands on the
  business dashboard.
- **Continue as System Admin (Demo)** — logs in as a demo System Admin and
  lands on the System Admin dashboard.

The real phone/password form is still present below a divider and still
works (any input logs in as the business demo, since there's no backend to
validate credentials against in this mode) — this is a testing convenience,
not a security feature; demo mode has no accounts to protect.

## Which identity reaches which shell

`AuthSession`/`AuthIdentity.business` is `null` for a System Admin identity
— that was already the documented signal the backend sends (see
`auth_models.dart`'s own doc comment), just never previously exercised by
the Flutter app, since Phase 2 only ever authenticated business users. The
router's redirect guard (`routing/app_router.dart`'s `_redirect`) now reads
that same signal — `business == null` → System Admin shell, otherwise →
business shell — instead of the previous "any authenticated session is a
business user" assumption. **This is additive, not a weakening**: in
backend mode, Flutter still only ever produces business-user sessions
today (no System Admin login screen was added), so this branch remains
unreachable there exactly as before; it only activates for the new demo
System Admin path.

## What still uses the real, already-built local repositories

Every business module — Products, Categories, Inventory, Sales, Orders,
Customers, Suppliers, Purchases, Returns, Production, Employees/Roles,
Reports, Documents, Activity History, Notifications, Search, Settings —
was already backed by a `Local*Repository` from the frontend-first phase,
completely independent of auth mode. Logging in via demo mode simply
removes the one gate that was blocking you from reaching them without a
backend; nothing about how those modules work changed.

## Session persistence

Demo sessions use the same `flutter_secure_storage`-backed `TokenStorage`
real sessions use — no new persistence layer was added (per the explicit
"do not introduce unnecessary infrastructure" instruction). `DemoAuthRepository`
encodes which demo identity a token belongs to in the token string itself
(`demo-refresh-token-business` / `demo-refresh-token-admin`), so
`AuthController`'s existing restore-session flow (`refresh()` → `me()`)
works unmodified and a demo session survives an app restart, same as a
real one would.

## The "DEMO MODE" indicator

A small badge appears in the application shell's top bar (`AppTopBar`,
next to the page title) whenever `AppModeConfig.isDemo` is true — so it's
never ambiguous whether an action (create/edit/archive/etc.) is touching
real backend data or local demo state. It does not appear on the public
login route itself (nothing to disambiguate there yet).

## Why not a runtime toggle

The mode is a compile-time `--dart-define`, not a button or a setting a
user can flip while the app is running, and demo mode is never
auto-entered as a fallback when a real backend call fails. Both are
deliberate: a real production connection failure must show a real error
(`Couldn't connect to server`), never silently substitute fake local data
that could be mistaken for a real session — see `docs/security.md`'s "no
fake authentication" principle, which this feature does not relax.

## Backend safety

This feature touches **zero files under `backend/`** — no MySQL
configuration, no migrations, no Node.js route/auth changes. Confirmed via
`git diff --stat` before committing (see the phase's final report for the
exact command output).
