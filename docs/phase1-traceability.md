# Phase 1 requirements traceability

Maps every Phase 1 UI/UX requirement — from the 44-page specification and
from the Phase 1 instruction set — to what actually implements it. Status
is one of:

- **✅ Built** — the foundation exists and is exercised by the running app
  (a real screen renders it) or by an automated test.
- **🔶 UI FOUNDATION PREPARED — FUNCTIONAL IMPLEMENTATION DEFERRED** — the
  component/structure exists and is ready to be filled with real data/logic,
  but no business logic, backend connection, or persisted state exists yet.
  Never read this status as "done."

| # | Requirement | Spec source | Component / file | Future dependency | Test status |
|---|---|---|---|---|---|
| 1 | Global search | §32 | `shared/search/global_search_bar.dart` | Products/Orders/Customers/Suppliers search APIs (Phase 2+) | 🔶 renders in `AppTopBar`; no query wired |
| 2 | Module/date/product/category/user/location filters | §17/§25 | `shared/search/filter_bar.dart` (`AppFilterBar`, `FilterChipData`) | Per-module filter definitions + query params | 🔶 generic chip UI only |
| 3 | Pagination, server-side | §18/§26 | `shared/pagination/pagination_bar.dart` | Real paginated API responses | 🔶 UI-only; `flutter analyze` clean |
| 4 | Professional data tables (Products/Orders/Sales/Customers/Suppliers/Purchases/Returns/Employees/Reports/Audit) | §11/§42/§43 | `shared/tables/app_data_table.dart`, `table_column.dart`, `table_row_actions.dart` | Per-module column definitions + repositories | 🔶 no real rows yet; loading/empty/error states implemented |
| 5 | Sorting UI | §11 | `AppDataTable`'s `sortColumnIndex`/`onSort` (delegates to `DataColumn.onSort`) | Server-side sort per module | 🔶 UI signal only, no-op until wired |
| 6 | Row selection | §11 | `AppDataTable`'s `selectable`/`selectedIds`/`onSelectionChanged` | Bulk actions (a later phase) | 🔶 mechanism present, unused |
| 7 | Row actions / action menus | §11/§42/§43 | `shared/tables/table_row_actions.dart` | Per-module actions (view/edit/delete/etc.) | 🔶 renders an empty/example menu only where used |
| 8 | Table responsive behavior (card list on mobile, scroll only if needed) | §11/§40 | `AppDataTable`'s internal `_CardList`/`_DesktopTable` switch | — (self-contained) | ✅ **run-verified** (Phase 1.5): widget test pumps `AppDataTable` at desktop width and confirms a real `DataTable` renders with real row data |
| 9 | Forms: text/password/number/dropdown/searchable select/date/date range/checkbox/radio/switch/image upload/file upload/multi-select/textarea | §12 | `shared/forms/*` (`app_text_field.dart`, `app_select_field.dart`, `app_date_field.dart`, `selection_controls.dart`, `upload_placeholder.dart`) | Per-module form schemas + submission | 🔶 no business form uses these yet |
| 10 | Consistent labels/required indicators/helper/error/disabled/focus | §12 | `shared/forms/form_field_wrapper.dart` + Flutter's themed `InputDecoration` (`theme/app_theme.dart`) | — | ✅ implemented, shared by every form field |
| 11 | Buttons: primary/secondary/outline/text/destructive/icon, loading/disabled | §13/§41 | `shared/buttons/app_button.dart` | — | ✅ unit-tested (tap + disabled state) |
| 12 | Status badges (19-status catalog) | §14/§16/§22/§24/§34-25 | `shared/badges/status_badge.dart` (`BusinessStatus`, `StatusTone`) | Real status transitions per module (Phase 2+) | ✅ unit-tested (renders every catalog label) |
| 13 | Loading states (page/section/button/skeleton) | §15/§41 | `shared/feedback/app_loading.dart`, `app_skeleton.dart` | — | 🔶 used by `AppDataTable`'s loading branch (structure test-verified, Phase 1.5); no live async call to observe yet outside `system_status` |
| 14 | Empty states | §15/§41 | `shared/feedback/app_empty_state.dart` | — | ✅ used by every `ModulePlaceholderScreen` (16 real usages) |
| 15 | Error states + retry | §15/§31/§41 | `shared/feedback/app_error_state.dart` | — | ✅ used by `AppDataTable`'s error branch; pattern proven by `system_status`'s real error handling |
| 16 | Toast/snackbar (success/error/warning/info) | §15/§41 | `shared/feedback/app_toast.dart` | Per-module actions to trigger it | 🔶 mechanism built, not yet called from any real action |
| 17 | Confirmation dialogs (delete/cancel/return/approve/reject/status change) | §15/§17 | `shared/feedback/confirm_dialog.dart` (`confirmAction()`) | Per-module destructive actions | 🔶 ✅ run-verified generically (Phase 1.5: test opens the dialog, taps Confirm, asserts the resolved value) — not yet called from a real business action |
| 18 | Dashboard: stat/KPI/chart/section/activity/alert cards, customizable widgets | §5/§16/§49 | `shared/dashboard/*`, demonstrated in `features/dashboard/dashboard_screen.dart` | Real statistics API, per-business widget preferences | 🔶 explicitly placeholder values (`—`), never fabricated numbers |
| 19 | Modals/drawers/bottom sheets, responsive | §19 | `shared/overlays/app_dialog.dart`, `app_overlay_panel.dart` | Per-module forms/details/filters | 🔶 ✅ run-verified generically (Phase 1.5: test opens both and asserts content renders) — no real per-module caller yet |
| 20 | Localization: English/Arabic/Kurdish Badini | §20 | `lib/l10n/app_en.arb`, `app_ar.arb`, `app_ku.arb` + `flutter gen-l10n` | Translating business-module strings as each is built | ✅ shell strings fully localized in all 3; `flutter gen-l10n` succeeds — see `docs/localization.md` for the flagged Kurdish-locale-code assumption |
| 21 | RTL foundation | §20/§21 | `lib/localization/app_locales.dart`, explicit `Directionality` in `app.dart`, manual glyph-mirroring at 2 call sites, `lib/localization/kurdish_localizations_fallback.dart` | — | ✅ **run-verified** (Phase 1.5, after the toolchain fix — see `docs/toolchain-fix.md`): automated tests confirm `Directionality` resolves correctly for en/ar/ku; testing itself caught and fixed a real Kurdish-locale crash (see `docs/localization.md`) |
| 22 | Accessibility foundation | §22 | Semantic color+label pairing everywhere (`StatusBadge` always shows text, never color alone); `Tooltip`s on icon-only controls; 34–42px touch targets on buttons/tiles | — | 🔶 followed as a convention; no automated a11y test written |
| 23 | Routing: public / business shell / admin shell, guard-ready | §23 | `routing/app_router.dart`, `app_routes.dart` | Phase 2's `redirect` auth/permission guard (extension point already commented in `app_router.dart`) | ✅ three route trees exist and are distinct; no guard logic (by design) |
| 24 | State management: theme/locale/sidebar UI state only | §24 | `theme/theme_controller.dart`, `localization/locale_controller.dart`, `shared/navigation/sidebar_controller.dart` | Persisting these once Settings is real | ✅ all three wired into `app.dart`/`AppShell` and exercised via Settings' preview controls |
| 25 | Application shell: sidebar, content, header, page title, breadcrumbs, account/notification placeholders | §6/§8/§9 | `shared/layout/app_shell.dart`, `app_sidebar.dart`, `app_topbar.dart`, `breadcrumbs.dart` | Real account/notification data (Phase 2+) | ✅ desktop + mobile/tablet variants both implemented |
| 26 | Main navigation (16 modules) + System Admin area | §6/§56/§57 | `shared/navigation/nav_items.dart` (`businessNavItems`, `adminNavItems`), one placeholder screen per module under `features/<module>/` | Real permission filtering (`NavItem.permissionKey`, unused until backend RBAC exists) | ✅ all 16 + 2 admin routes wired and reachable |
| 27 | Reusable standard page layout | §10 | `shared/layout/page_scaffold.dart` | — | ✅ used by every placeholder screen + Settings + Dashboard |
| 28 | Performance-oriented UI (no "load everything") | §26/§59/§60 | `AppDataTable` takes only already-paginated `rows`; `PaginationBar` never implies "load all" | Real paginated repositories | ✅ structurally enforced by the API these widgets expose |
| 29 | No business logic this phase (auth, CRUD, inventory, sales, etc.) | Phase 1 rule | — | Phases 2+ | ✅ verified by inspection — no module folder contains a repository beyond `system_status`'s (retained from Phase 0) |

## Smaller assumptions carried into Phase 1 (flagged, not silently decided)

- **Kurdish locale code (`ku`)** — see `docs/localization.md`.
- **`ThemeExtension` over static consts for color** — a Phase 0→1 upgrade;
  documented in `theme/app_colors.dart`'s doc comment.
- **`DashboardPlaceholderScreen` is richer than the other 15 placeholders**
  — it demonstrates the dashboard widget system (§16 explicitly asks for
  this), while every other module gets the generic `ModulePlaceholderScreen`.
  This is a deliberate asymmetry, not an oversight.
- **Settings includes a real theme/locale switcher**, unlike the other 15
  placeholders which are pure `ModulePlaceholderScreen`s — justified because
  §4/§24 explicitly require the theme/locale *foundation* to be
  demonstrably switchable, and §29's testing requirements ask that light/
  dark/LTR/RTL actually be checkable. It is clearly labeled "foundation
  preview," not real Settings, and nothing it changes persists anywhere.
- **No charting library added** (`ChartContainer` is an empty placeholder)
  — avoids a dependency no Phase 1 screen needs; revisit when Reports or
  the real Dashboard needs an actual chart.
- **`Icons.*` (Material) is the only icon set used** — no second icon
  family introduced, per the "consistent icon strategy" requirement.
