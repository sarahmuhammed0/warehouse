# Flutter UI architecture — developer handbook

This is the reference for everyone building a screen in this app from
Phase 2 onward. It documents what Phase 1 built and how to build on it —
not a plan, a description of what's actually in `frontend/lib/`.

## 1. Directory structure

```
frontend/lib/
├── main.dart              entry point — wraps WarehouseOsApp in ProviderScope
├── app.dart                 MaterialApp.router: theme, locale, RTL resolution, routing
├── theme/                    design tokens + ThemeData
│   ├── app_colors.dart         semantic color tokens (ThemeExtension)
│   ├── app_typography.dart      named text styles
│   ├── app_spacing.dart          xs…xxl scale
│   ├── app_radius.dart            sm/md/lg/pill
│   ├── app_elevation.dart          shadow tokens
│   ├── app_theme.dart               builds light()/dark() ThemeData from the above
│   └── theme_controller.dart         Riverpod ThemeMode state
├── localization/               locale metadata + state (NOT the ARB files — see l10n/)
│   ├── app_locales.dart          AppLocale list, RTL flags, direction resolver
│   └── locale_controller.dart     Riverpod Locale state
├── l10n/                       ARB source files + `flutter gen-l10n` output
│   ├── app_en.arb / app_ar.arb / app_ku.arb
│   └── generated/                 regenerated on `flutter pub get` — not hand-edited
├── routing/
│   ├── app_routes.dart            path constants — the only place a route string exists
│   └── app_router.dart             GoRouter: public / business shell / admin shell
├── core/                        cross-cutting, non-UI infrastructure (from Phase 0)
│   ├── config/env.dart            compile-time config (no secrets — a Flutter build ships to the device)
│   ├── network/api_client.dart     unwraps the backend's {success,data}/{success,error} envelope
│   ├── error/failure.dart           the one error type repositories throw
│   └── validation/validators.dart    plain validator functions
├── shared/                     the reusable UI kit — see §3 below for the full catalog
└── features/                   one folder per module — see §5 below
```

**Why `core/` and `shared/` are two different things:** `core/` is
infrastructure a screen's *repository* uses (network, error types,
validators) — it renders nothing. `shared/` is what a screen's *widget
tree* is built from — buttons, tables, cards, dialogs. A file that renders
a `Widget` belongs in `shared/`; a file that doesn't belongs in `core/`.

## 2. Design tokens

| Concern | File | Access pattern |
|---|---|---|
| Color | `theme/app_colors.dart` | `context.colors.textMuted` (never a raw `Color(0x…)`) |
| Type | `theme/app_typography.dart` | `AppTypography.pageTitle.copyWith(color: …)` |
| Spacing | `theme/app_spacing.dart` | `AppSpacing.md` (never a bare pixel number) |
| Radius | `theme/app_radius.dart` | `AppRadius.mdRadius` |
| Elevation | `theme/app_elevation.dart` | `AppElevation.shadowFor(…)` — used sparingly, see below |

Colors are a `ThemeExtension<AppColors>`, not static constants, specifically
so light/dark both exist as one object Flutter can look up via
`Theme.of(context)` — a widget never branches on `Theme.of(context).brightness`
itself to pick a color; it just reads the token, which already resolved.

**Restraint is a rule, not a suggestion.** Per the design direction (§2 of
the Phase 1 brief): flat cards with a hairline `colors.border`, not stacked
shadows; modest type sizes (`pageTitle` is 22px, not 32+); radius capped at
`AppRadius.lg` (12px) for dialogs/sheets only — everyday cards and inputs
use `sm`/`md`. This is a business tool used for hours a day, not a
marketing surface.

## 3. Reusable component catalog (`shared/`)

| Folder | Components | Used for |
|---|---|---|
| `layout/` | `AppShell`, `PageScaffold`, `Breadcrumbs`, `responsive/` (`ResponsiveLayout`, `responsiveValue`, `AppBreakpoints`) | Every screen's outer structure |
| `navigation/` | `AppSidebar`, `AppTopBar`, `nav_items.dart` (`NavItem`, `businessNavItems`, `adminNavItems`), `sidebar_controller.dart` | The persistent shell |
| `buttons/` | `AppButton` (primary/secondary/outline/text/destructive, loading/disabled), `AppIconButton` | Every action |
| `badges/` | `StatusBadge`, `BusinessStatus` enum + catalog | Order/return/payment/production status everywhere |
| `tables/` | `AppDataTable<T>`, `AppTableColumn<T>`, `TableRowActions` | Every list-of-records screen |
| `forms/` | `AppTextField` (+ `.password`/`.number`/`.multiline`), `AppDropdownField`, `AppSearchableSelectField`, `AppMultiSelectField`, `AppDateField`, `AppDateRangeField`, `AppCheckbox`, `AppRadioGroup`, `AppSwitch`, `UploadPlaceholder`, `FormFieldWrapper` | Every form |
| `feedback/` | `AppLoading`, `AppSkeleton`/`AppSkeletonRow`, `AppEmptyState`, `AppErrorState`, `AppToast`, `confirmAction()`/`ConfirmDialog` | Every async state and every destructive action |
| `overlays/` | `showAppDialog()`, `showAppOverlayPanel()` | Forms-in-a-dialog, filters, details, quick actions |
| `dashboard/` | `StatCard`, `KpiCard`, `SectionCard`, `ActivityListCard`, `AlertCard`, `ChartContainer`, `DashboardWidgetContainer` | The dashboard, once it has real data |
| `search/` | `GlobalSearchBar`, `AppFilterBar`/`FilterChipData` | Top bar search, every module's filter row |
| `pagination/` | `PaginationBar` | Every `AppDataTable` |
| `cards/` | `AppCard` | The base every other card wraps |
| `placeholders/` | `ModulePlaceholderScreen` | Every not-yet-built module route |

None of these know about HTTP, Riverpod providers, or business data — they
take plain Dart values and callbacks. A feature's provider/repository layer
sits between them and the network.

## 4. Responsive strategy

Three breakpoints (`theme/../shared/layout/responsive/app_breakpoints.dart`):

| | Width | Shell behavior |
|---|---|---|
| Mobile | < 600px | `AppShell` renders a `Drawer` + `AppTopBar` with a menu button; `AppDataTable` renders a card-per-row list, not a table |
| Tablet | 600–1023px | Same drawer-based shell as mobile; `AppTopBar` hides inline search (icon still present) |
| Desktop | ≥ 1024px | Persistent, collapsible sidebar (`sidebarCollapsedProvider`); full `AppTopBar` including inline search; `AppDataTable` renders as a real table, horizontal scroll only if columns genuinely don't fit the available width |

Use `ResponsiveLayout(mobile:, tablet:, desktop:)` when the *structure*
differs (see `DashboardPlaceholderScreen`), or `context.isMobile` /
`responsiveValue(context, desktop: …, mobile: …)` when only a *value*
differs (column count, padding). Never solve responsiveness by shrinking
the same layout — see §5 of the Phase 1 brief.

## 5. How a future module builds a real screen

Follow `features/system_status/` structurally (the one feature with a real
repository) and `features/dashboard/` for composition style:

1. Replace the module's `*PlaceholderScreen` body — keep using
   `PageScaffold` for the chrome (title, breadcrumbs, actions, search/filter
   row) so the page still looks and behaves like every other page.
2. Add `features/<module>/data/`: a `*_models.dart` (plain classes matching
   the backend's JSON shape) and a `*_repository.dart` (the only thing that
   calls `core/network/api_client.dart` for this module).
3. Add `features/<module>/presentation/providers/`: a `FutureProvider`
   (list/detail) built on the repository, following
   `features/system_status/presentation/providers/health_providers.dart`.
4. Feed real data into `AppDataTable` (`columns`, `rows` from the provider's
   `AsyncValue.data`, `loading`/`errorMessage` from `.isLoading`/`.error`) —
   the table foundation already handles all three states.
5. Wire actions (`AppButton`, `TableRowActions`) to `confirmAction()` for
   anything destructive, then a repository method, then `AppToast.success`/
   `.error` on the result.

Nothing about `AppShell`, routing, or the design tokens changes when this
happens — that's the point of building the foundation first.

## 6. Connecting real API data (the pattern, once a module needs it)

```
UI (AppDataTable, forms, …)
   ▲ AsyncValue<T>
Riverpod FutureProvider/AsyncNotifier   (features/<module>/presentation/providers/)
   ▲ Future<T>
Repository                               (features/<module>/data/*_repository.dart)
   ▲ Map<String, dynamic>
ApiClient.getJson(path)                  (core/network/api_client.dart)
   ▲ HTTP + envelope unwrapping
Backend REST API
```

Every layer already exists except the module-specific repository/provider —
see `features/system_status/` for the working, real (not mocked) example
this pattern is extracted from.

## 7. Conventions

- No raw `Color`, font size, or pixel spacing outside `theme/*` — always a
  token.
- No widget calls `fetch`/`Dio` directly — always through a feature
  repository.
- No permission check in the UI decides what a user can *do* — `NavItem`
  carries a `permissionKey` for future filtering, but the backend remains
  the only authority (architecture §8/§9). The UI may hide a button; it
  never is the security boundary.
- Every list screen's table is fed already-paginated data — never "all
  records" (§26).
- Business status words (`BusinessStatus`) are English for now — see
  `docs/localization.md` for why translating them is deferred.
