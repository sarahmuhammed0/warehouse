# Flutter state management — decision record

**Chosen: Riverpod** (`flutter_riverpod`, plain provider style — no
code generation in Phase 0).

## What it has to handle

Per the approved architecture, this app eventually carries a lot of
independent, mostly-async state: authentication/session, the current
business's branding + enabled modules, products, inventory, orders, sales,
customers, suppliers, notifications, settings, and per-user permissions
(§9) — each fetched from the REST API, each cached differently, several of
them needed simultaneously on the same screen (e.g. an order screen reading
products, customers, and permissions at once).

## Options considered

| | Provider (package) | Bloc | GetX | **Riverpod** |
|---|---|---|---|---|
| Boilerplate for a simple async fetch | Low | High (event → state classes per feature) | Very low | Low |
| Compile-time safety | Relies on `BuildContext`, easy to read the wrong provider by mistake | Strong, but verbose | Weak (relies on strings/globals in places) | Strong — no `BuildContext` needed to read state, provider identity is a compile-time object |
| Testability (no widget tree needed) | Awkward without a `BuildContext` | Good | Poor (heavy on globals/singletons) | Good — providers are plain Dart objects, overridable in tests |
| Async data (loading/data/error) | Manual | `Emitter`/state classes, verbose | Manual | `AsyncValue`/`FutureProvider` built in — this is most of what this app needs |
| Scales to dozens of independent feature domains without one giant store | OK | OK, but each feature needs its own Bloc + Event + State boilerplate | Risk of a global-state grab-bag | Yes — one small provider per concern, composed via `ref.watch` |

## Why Riverpod, specifically for this app

- **Matches the domain shape.** Almost everything this app fetches is
  "some async data, scoped to the current business" — `AsyncValue` (via
  `FutureProvider`/`AsyncNotifier`) models exactly that with built-in
  loading/data/error states, which is why Phase 0's own `health_providers.dart`
  needed zero manual `isLoading` bookkeeping (compare to the equivalent
  hand-rolled `useState` triple in the earlier React prototype of the same
  screen).
- **No BuildContext threading.** Business context (current tenant, enabled
  modules, permissions) needs to be readable from repositories and from deep
  in the widget tree alike — Riverpod providers are readable from both
  without passing `BuildContext` around or relying on `InheritedWidget`
  lookups.
- **Per-feature isolation without per-feature boilerplate.** Each feature
  folder (`features/<name>/presentation/providers/`) declares only the
  providers it needs — no event/state class pair per feature the way Bloc
  requires, which matters once there are 15+ feature modules (§10's module
  list).
- **Testable without a running app.** A provider can be overridden with a
  fake repository in a plain Dart test — important for §32's testing
  strategy, which expects business logic to be tested independently of the
  UI.

## What this deliberately does NOT do yet (avoiding over-engineering)

- No code generation (`riverpod_generator`/`build_runner`) — plain
  `Provider`/`FutureProvider`/`Notifier` declarations are enough for Phase 0
  and for most of Phase 1; generation can be adopted later per-feature if a
  feature's provider graph gets complex enough to benefit from it, not
  applied blanket up front.
- No global app-wide state object — each feature's providers stay scoped to
  that feature's file, composed via `ref.watch`, not merged into one big
  store.
- Authentication/session state (the provider every other feature will
  eventually depend on for `businessId`/permissions) is not built yet — it
  arrives with Phase 1's real login, not invented ahead of the feature that
  needs it.
