# Frontend requirements coverage

Maps every functional requirement from the 44-page specification (67
numbered sections, per the approved [architecture blueprint](architecture.md)'s
own requirements inventory and traceability matrix) to what the Flutter
frontend actually implements as of this "frontend-first" phase. This phase
deliberately **paused backend development** — every module below is real,
navigable Flutter UI over a clearly-isolated local/demo data layer (see
`docs/frontend-backend-contract-notes.md` for exactly what a real API needs
to return to replace each one).

Status legend:
- **✅ Built** — a real screen exists, is reachable via routing/navigation,
  and is exercised against (demo) data — not a static mockup.
- **🔶 Partial** — the screen/structure exists and is usable, but some
  sub-feature is intentionally lighter than the full spec text (documented
  per row).
- **❌ Deferred** — not built this phase; reason given.

## Methodology note: tests found real bugs, not just missing coverage

Every module below was exercised by real `flutter test` widget tests, not
only inspected by reading code (§51 of the master prompt: "actually run the
Flutter application"). Doing so caught four genuine rendering/state bugs
before they could ship, all fixed at the shared-widget level rather than
patched per screen:

1. **`AppDropdownField` overflow** — missing `isExpanded: true` meant a
   long option label (a real category name, not a short test fixture)
   silently overflowed its `Row` instead of truncating. Fixed once in
   `shared/forms/app_select_field.dart`; every dropdown in the app
   (Products' category filter, status pickers, payment methods, etc.)
   inherited the fix.
2. **`AppCard` had no `Material` ancestor** — any card whose content
   included a `ListTile` (System Admin's recent-businesses list, search
   results) triggered a real Flutter "background color or ink splashes may
   be invisible" assertion. Fixed once in `shared/cards/app_card.dart`.
3. **`SearchResultsScreen`'s `FutureBuilder` anti-pattern** — the search
   `Future` was constructed inline in `build()`, so it restarted on every
   rebuild and never settled. Fixed by memoizing the future in
   `initState`/`didUpdateWidget`, the standard correct pattern.
4. **A nested `ListView` inside `PageScaffold`'s own `SingleChildScrollView`**
   — an unbounded-height viewport crash, since `PageScaffold` already
   provides scrolling. Fixed by using a plain `Column` instead.

None of these were hypothetical — each was caught by a real, run-for-real
`flutter test` failure with a genuine stack trace, then root-caused and
fixed (not worked around in the test).

All screens in this table are demo-data-backed (`Local*Repository`
implementations, clearly isolated per module under `features/*/data/`) —
none are wired to a live backend. Phase 2's real, backend-verified
authentication is untouched and still fully functional.

| Spec § | Requirement group | Flutter screen / component | Status | Notes |
|---|---|---|---|---|
| §1 | System concept | Whole app | ✅ | Multi-tenant shell, business-scoped nav |
| §2–4, 58 | Admin, business creation, login, session security | `features/auth/*` (Phase 2, untouched) | ✅ | Real, backend-verified — see `docs/authentication.md` |
| §5 | Dashboard: stats/charts/quick actions | `features/dashboard/dashboard_screen.dart` | ✅ | All 15 statistics and all 10 chart subjects the PDF lists, derived from the demo repositories; 8 quick actions each opening a create workflow; §44's inventory alerts. KPI cards drill down only where the filter investigates that number — the dashboard is not a second sidebar. Full audit: **[`docs/business-dashboard-audit.md`](business-dashboard-audit.md)** |
| §6 | Sidebar navigation, module visibility | `shared/navigation/nav_items.dart`, `routing/app_router.dart`'s `_enabledBusinessNavItems` | ✅ | Filters by `businessTypeModules` (§33) |
| §7 | Categories | `features/categories/*` | ✅ | List, create/edit dialog, parent/subcategory, archive/activate, search |
| §8 | Products (full field set) | `features/products/*` | ✅ | Adaptive form (Basic/Inventory/Financial/collapsed Optional), list, detail, image slot (no real upload — see contract notes) |
| §9 | Product variants | `product_detail_screen.dart`'s `_VariantsCard` | 🔶 | Add/remove variant UI works; in-memory only, not yet its own repository/table |
| §10–12, 44, 47 | Inventory, movements, locations, transfers, alerts | `features/inventory/inventory_screen.dart` (4 tabs) | ✅ | Stock overview, movement history, warehouses/locations, transfers; negative-inventory toggle in Settings → Inventory |
| §13 | Sales | `features/sales/sales_screen.dart`, `orders/presentation/order_form_screen.dart` | ✅ | Cart-style create, live totals, payment section |
| §14–15, 17 | Orders, edit history, cancellation | `features/orders/*` | 🔶 | Full status state machine + confirmation-gated cancel; edit-history section is a real, labeled empty state (no field-level diff tracking yet) |
| §16 | Returns | `features/returns/*` | ✅ | Whole/partial-quantity return, condition-gated, Requested→Approved/Rejected→Completed |
| §18 | Customers | `features/customers/*` | ✅ | List, create/edit, detail with balance/purchase stats |
| §19 | Suppliers | `features/suppliers/*` | ✅ | Same pattern as Customers |
| §20 | Purchases | `features/purchases/*` | ✅ | Create, list, detail, pending→completed/cancelled |
| §21–22 | Production, BOM, production history | `features/production/*` | ✅ | BOM auto-loads per finished product, scales with batch qty, Planned→In Progress→Completed/Cancelled |
| §23 | Employees / Users | `features/employees/employees_screen.dart` | ✅ | List, create/edit, activate/deactivate, role assignment |
| §23–24, 9 | Permission system — model, editor, AND enforcement | `features/employees/presentation/roles_screen.dart`, `features/auth/presentation/providers/permission_providers.dart` | ✅ | Real module×action matrix (unchanged from before), now actually *consulted*: sidebar nav, and create/edit/delete/export/financial-visibility controls on Products/Categories/Employees/Reports/Customers, are gated by the signed-in demo identity's resolved role. Nine demo identities (System Admin + one per business role) prove it changes per role. Full model, defaults, test matrix, and exactly which modules got action-level (not just nav-level) wiring: **[`docs/roles-and-permissions.md`](roles-and-permissions.md)** |
| §25–26, 48 | Reports (operational + business), export | `features/reports/reports_screen.dart` | 🔶 | Two report areas, real data wiring for Current Inventory + Sales; other report types are real, navigable cards without a live query yet — see contract notes |
| §27–29 | PDF documents, templates, numbering | `features/documents/documents_screen.dart`, Settings → PDF/Sales sections | ✅ | Live preview reflects real order data + real template toggles; actual PDF file generation is explicitly backend work (§25's own instruction) |
| §30, 55 | Audit log | `features/activity_history/*` | ✅ | Same shape as the backend's real Phase 2 `audit_logs` table/writer |
| §31 | Notifications | `features/notifications/*`, topbar bell | ✅ | Low/out-of-stock derived live from real product data; other types seeded (no live trigger source yet) |
| §32–33 | Search, barcode | `features/search/presentation/search_results_screen.dart`; barcode label preview in product detail | ✅ | Cross-module search (Products/Customers/Suppliers/Orders); barcode scanning itself is a documented mock (§31 of the brief explicitly allows this) |
| §34, 50, 11 | Settings, business-type config | `features/settings/settings_screen.dart` (10 sections), `business_type_config.dart` | ✅ | All settings sections are real, interactive, in-memory (no backend to persist to yet — same precedent as Phase 1's theme/locale) |
| §49 | Dashboard customization | `dashboard_widgets_controller.dart` | ❌ | **Not implemented.** The controller and its `toggle()` exist but nothing calls them — there is no UI to choose which dashboard cards show. The dashboard deliberately does not gate any §5 statistic on it, since that would silently drop a required KPI with no way to restore it. See `docs/business-dashboard-audit.md` |
| §35–36, 25 | Security & multi-tenant isolation | N/A this phase | ✅ (unchanged) | Phase 2's real backend enforcement untouched; nothing in this phase's demo data layer claims to be a security boundary |
| §37–39 | MySQL schema, API architecture, frontend structure | N/A this phase | — | Backend-only concerns, explicitly out of scope this phase |
| §40–43 | Responsive design, UI/UX, product/order table anatomy | Every screen (via `ResponsiveLayout`, `AppDataTable`) | ✅ | Verified live at desktop/tablet/mobile widths — see §51 of this report below |
| §45–46, 53–54, 59–61 | Soft delete, transactions, error handling, validation, performance, business rules | Archive/deactivate patterns throughout; `AppErrorState`/`AppEmptyState`/loading states; `PagedListController` (pagination, never "load all") | ✅ | Structural — no fabricated business logic; see `core/repositories/paged_list_controller.dart` |
| §51 | Custom fields | Settings → Custom Fields section | 🔶 | Add/remove field-name UI works; not yet attached to any entity's actual form |
| §52 | Backup / restore | Settings → Backup & Restore section | 🔶 | Manual/scheduled backup buttons, confirmation-gated restore, history list — all UI-only, explicitly per the brief's "do NOT implement actual backup logic this phase" |
| §56–57 | System Admin dashboard, business detail | `features/admin/*` | ✅ | Previously deferred (Phase 2 built no System Admin UI) — now real: cross-tenant aggregate stats, the three-level drill-down below, and all six §57 business controls wired to real actions (see the §57 section below) |
| §65 | Seed/demo data | Every `Local*Repository`'s `_seed()` | ✅ | Clearly isolated per module — see §48 rule below |

## System Admin drill-down (aggregate → business → records → record)

A System Admin has no selected business, so a platform statistic can't open
a business's operational table — there'd be no answer to "whose records?".
Tapping **Employees / Products / Orders / Sales** on the admin dashboard
therefore opens a per-business *overview* first:

| Level | Route | Screen |
|---|---|---|
| 1 — platform total | `/admin` | `admin_dashboard_screen.dart` |
| 2 — per business | `/admin/<metric>` | `presentation/admin_overview_screen.dart` |
| 3 — that business's records | `/admin/<metric>/<businessId>` | `presentation/admin_business_records_screen.dart` |
| 4 — one record | `/admin/<metric>/<businessId>/<recordId>` | `presentation/admin_record_detail_screen.dart` |

All four metrics share those three screens, parameterised by
`presentation/admin_metric.dart` — adding a fifth drillable statistic means
adding an enum value, not four more screens. Each level is a real route, so
every step is an ordinary `context.push` and the back arrow pops exactly one
level (`context.pop()`, never a hard-coded destination).

**Businesses / Active / Disabled stay direct** — they open the Businesses
list, filtered. A *business* statistic's records are the business list, so
there is no business left to choose.

**The numbers are derived, not seeded.** `data/admin_metrics.dart` computes
every count from the same `listForBusiness` calls level 3 uses to build its
table, so a card's number is by construction the number of rows behind it.
`AdminBusiness` deliberately carries no `productCount`/`orderCount`/
`salesTotal`/`userCount` field any more — a stored count would be a second,
silently diverging source of truth. Three tests in
`test/widget_test.dart`'s *Admin drill-down total consistency* group hold
that line.

Levels 3 and 4 are read-only. A platform admin oversees a tenant's records
rather than operating them; the tenant's own staff do that in the business
shell under their own permissions (`docs/roles-and-permissions.md`).

## §57 business controls — what each one does (and what the PDF does not say)

§57 lists six controls on a System Admin's business-details page: **Edit,
Disable, Activate, Reset password, Manage users, View reports**. It lists
them by name and says *nothing at all* about what any of them should do
when clicked — no form spec, no dialog spec, no destination. The behaviours
below are therefore this frontend's interpretation, recorded here as
interpretation rather than presented as requirement. None of them is a
no-op; a widget test asserts every control on that page has a live callback.

| Control | Does | Demo behaviour |
|---|---|---|
| **Edit** | Pushes `/admin/businesses/:id/edit` — form prefilled from that business | Save writes through `AdminRepository.updateBusiness`; the Businesses table, dashboard and every drill-down title show the new value. Cancel/Back pop without writing. |
| **Disable** | Confirmation naming the business → sets status Disabled | Real repository write; the dashboard's Active/Disabled counts follow, since they're folded from the same list. |
| **Activate** | Same, in reverse | Offered **only** when the business is disabled — the page shows one status action, never both. |
| **Reset password** | Dialog: new + confirm password, validated against the app's own `minPasswordLength` policy | Records `lastPasswordResetAt`, shown back on the detail page. See below. |
| **Manage users** | Pushes the drill-down's own `/admin/employees/:businessId` | That business's staff only — one screen for "this business's users" rather than two that could disagree. |
| **View reports** | Pushes `/admin/businesses/:id/reports` | Inventory, Sales and Users reports computed from that business's own records. |

Each control carries the business id in the route or acts on the record the
screen already loaded, so none of them can operate on a tenant other than
the one on screen.

**Reset password is the honest exception.** `DemoAuthRepository` holds no
per-account password at all — its `login` ignores the password argument and
its `changePassword` is a no-op — so there is nothing a frontend reset could
truthfully change. Leaving the button dead was the defect being fixed;
showing a success toast for an action that changed nothing would have been
worse. Instead it validates the input, records a real timestamp the detail
page displays, and states on screen that no real password was stored or
changed. §38 lists no admin reset endpoint; when one exists this becomes a
call to it and the notice goes away.

**Per-business reports are scoped to what the demo data can honestly
support.** §26 defines nine-odd report categories; only products, orders and
employees carry a `businessId` (see `core/repositories/demo_businesses.dart`),
so Inventory, Sales and Users are reported per business and Purchases,
Returns and Production are not. The screen says so rather than splitting
records that have no split.

Not built, and deliberately: §57's **Activity** block (recent logins, sales,
changes, errors) — nothing in the frontend records those events yet. The
**Logo** field is absent from both the profile and the Edit form because no
upload pipeline exists and `AdminBusiness.logoUrl` is never populated. §3's
wider create-time field set (city, country, website, tax/registration
number, currency, language, time zone) is not in the frontend's business
model, and inputs for fields nothing stores would be a form that lies about
what it saves.

## Business-side functionality audit

Every interactive control on the business side was audited for dead, fake,
partial and missing behaviour, and the gaps fixed in demo mode. The largest
finding was that **no module wrote a cross-module side effect** — selling,
purchasing, returning and producing never moved stock. Full module-by-module
findings, what each control does now, and an honest list of what remains
backend-dependent: **[`docs/business-frontend-functionality-audit.md`](business-frontend-functionality-audit.md)**.

## §48 rule — demo data isolation (explicit, verified)

Every repository backed by local data implements the `DemoRepository`
mixin (`core/repositories/demo_data_source.dart`) — a mechanical marker so
it's never ambiguous, from the type alone, which repositories are
demo-backed and still need a real API implementation. No screen claims or
implies a backend connection it doesn't have; every list/detail screen that
reads from one of these repositories is one `Provider` override away from
reading from a real API instead (see `docs/frontend-backend-contract-notes.md`).

## What this phase did not change

Phase 2's authentication (login, JWT/refresh handling, secure token
storage, auth state, routing guards, System Admin auth foundation) is
**fully intact** — no file under `features/auth/`, `core/network/
auth_interceptor.dart`, or `core/storage/secure_token_storage.dart` was
modified this phase, per the master prompt's explicit §49 instruction.

## Deferred / lighter-depth items (honest list, not silently dropped)

- **Product variants, custom fields**: real add/remove UI, not yet backed
  by their own repository/table (in-memory `Map` instead).
- **Order edit history**: the section exists on every order's detail
  screen; it shows a real empty state rather than fabricated before/after
  entries, since no field-level change tracking is implemented yet.
- **Reports**: 12 report types are real, navigable cards; 2 (Current
  Inventory, Sales) query real demo data end-to-end. The rest need their
  own query implementation, not new UI.
- **Barcode scanning**: a label *preview* exists; actual camera/hardware
  scanning is explicitly out of a Flutter-only phase's reach per the
  brief's own §31.
- **Backup/restore, PDF file generation**: UI-only by explicit instruction
  (§25, §35 of the brief) — no backend engine exists to call yet.
- **Permission enforcement's action-level coverage**: every module's nav
  visibility is gated (all 15 business sidebar items). Action-level
  (create/edit/delete/export/financial-visibility) gating is fully wired
  on Products, Categories, Employees, Reports (export), and Customers
  (financial figures) — the modules the roles-and-permissions brief's own
  worked examples and test matrix center on. Sales, Orders, Inventory,
  Purchases, Returns, Production, and Settings are reachable-or-not exactly
  per role (nav-level; a System Admin session no longer reaches any
  business route at all — see the drill-down section above), but their
  individual buttons don't yet check
  `hasPermission` the way Products' do — same reusable pattern
  (`ref.watch(currentPermissionsProvider)` + `hasPermission(...)`), not
  wired into every remaining screen in this pass. See
  `docs/roles-and-permissions.md`'s permission test matrix for the full
  default grant list this would extend to.
