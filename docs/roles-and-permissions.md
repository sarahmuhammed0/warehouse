# Roles & permissions — frontend model

This document defines who can do what in the frontend, grounded explicitly
in the 44-page/67-section specification PDF ("Factory / Warehouse / Storage
Management System — Complete Full-Stack Development Prompt"). Where the PDF
states something outright, this document says so and cites the section.
Where the frontend had to make a concrete choice the PDF only implies (e.g.
the exact permission set for "Manager" beyond "can manage most business
operations"), that's called out explicitly as an interpretation, not
represented as a literal PDF requirement.

**Scope.** This is the frontend's role/permission *model* and the UI
behavior it drives. Per §35 of the PDF ("Never trust frontend
permissions... all important authorization must be enforced on the Node.js
backend"), nothing described here is a security boundary — it controls what
the UI shows, never what's actually allowed. The real backend doesn't
implement role/permission enforcement yet (that's backend work, out of
scope for this pass); see "Backend mode" below for exactly what that means
in practice today.

## A. System Admin responsibilities

Per §2 ("Account Structure") and §56–57, the System Admin can:

- Create factory / warehouse / storage-store accounts (§2)
- Edit, disable, activate, and (where appropriate) delete business accounts (§2)
- Reset passwords (§2)
- View business information and system statistics (§2, §56)
- Control permissions and system settings (§2)
- View activity logs and reports (§2)
- Manage system-wide configuration, subscriptions/licenses, backups (§2)
- Monitor system health (§2)
- Manage all factories/warehouses (§2)
- Open a business and inspect its profile, statistics, and recent activity (§57)

The System Admin dashboard (§56) shows: total/active/disabled businesses,
total users, total products, total orders, total sales across the system,
recent activity, recently created businesses, and system alerts. The
frontend's `AdminDashboardScreen` implements the first eight of these from
real (demo) data; "system alerts" is not yet built — see
`docs/frontend-coverage.md`.

**What the PDF does NOT give System Admin** (§ "Product Creation
Clarification" in this pass's brief, and confirmed by re-reading §2/§56/§57
in full): a global "Add Product" workflow, or any other business-module
CRUD action performed *as* the platform operator rather than *by* a
business user. §66's own final system flow is explicit about this — the
System Admin's part of the flow ends at "Business account created"; every
step after that ("Create categories", "Create products", "Configure
locations"...) belongs to "Business logs in → Business Dashboard". The
frontend's admin dashboard cards reflect this: Products/Orders/Sales/
Employee open the real Products/Orders/Sales/Employees screens (so the
admin can *inspect* live data, per §57's "Admin can open a business and
inspect its system"), but none of those screens' create/edit/delete actions
are exposed to the admin identity — creating a product is still a Products
module action, gated by the business-side permission system below, not an
admin capability.

## B. Business user responsibilities

Business users (§3's factory/warehouse account) operate only inside their
own business, per role/permission (§23: "Do NOT give every user full
access. Use role-based permissions."). The business-side modules (§6's
sidebar) are: Dashboard, Products, Categories, Inventory, Sales, Orders,
Customers, Suppliers, Purchases, Returns, Production, Employees/Users,
Reports, Documents, Activity History, Settings.

## C. Role descriptions (from the PDF, verbatim where quoted)

§23 lists these roles with these exact one-line descriptions:

| Role | PDF description |
|---|---|
| Business Owner/Admin | "Full access to their business." |
| Manager | "Can manage most business operations." |
| Warehouse Manager | "Inventory, products, transfers, stock." |
| Sales Staff | "Sales and customers." |
| Inventory Staff | "Stock operations." |
| Production Manager | "Production and materials." |
| Accountant | "Financial records and reports." |
| Viewer | "Read-only access." |

The PDF gives no more detail than this per role — it explicitly says
"Permissions should be configurable," not that this list is the final
grant. Section D/E below is this frontend's own reasonable interpretation
of those one-liners into concrete module/action grants, built to be
*changed* (see "Configurability" below), not treated as gospel.

## D. Permission actions (spec §24)

Permissions exist at module/action level. Actions: **View, Create, Edit,
Delete, Approve, Export**. Not every module supports every action (§24's
own example: "Reports has no delete"). The frontend's `PermissionCatalog`
(`lib/features/employees/data/employee_models.dart`) encodes this:

- `approve` — only Returns and Purchases (matches §16 return
  Requested→Approved→Rejected→Completed and §20 purchases)
- `export` — only Reports (matches §25/§48's PDF/Excel export requirement)
- `delete` — every module except Reports and Settings
- `financial` — **view only**, see below

§24 also names three permissions that aren't per-module actions:
**Manage Users**, **Manage Settings**, **View Financial Information**. The
frontend maps the first two onto the existing `users`/`settings` modules
(`users.edit` ≈ "Manage Users", `settings.edit` ≈ "Manage Settings" — no
new modeling needed). "View Financial Information" got its own pseudo-module
(`financial`, view-only) since it isn't really a *module* — it's a
visibility flag over monetary figures other modules already display
(purchase cost, customer/supplier balances, revenue/margin in Reports).

## E. Module/action examples — default role grants

This is the interpretation from C, expressed as the seeded `Role` records
(`lib/features/employees/data/employee_repository.dart`). Every role also
implicitly gets `dashboard.view`, `documents.view`, and `audit.view` — the
PDF never ties Dashboard, Documents, or Activity History visibility to a
specific role, so restricting those would be inventing a rule the spec
doesn't state, not representing one.

| Role | Explicit grants (beyond the implicit three above) |
|---|---|
| Business Owner/Admin | Every module, every supported action — "Full access" (§23) |
| Manager | Products/Inventory/Sales/Orders/Customers/Suppliers/Purchases/Reports: view+create+edit |
| Warehouse Manager | Products/Inventory: view+create+edit+delete; Sales/Orders: view |
| Sales Staff | Sales/Orders: view+create+edit; Customers/Products: view |
| Inventory Staff | Inventory: view+edit; Products: view |
| Production Manager | Production: view+create+edit+delete; Inventory: view |
| Accountant | Reports: view+export; Purchases: view+approve; **financial.view** |
| Viewer | Every module: view only (never financial — see note) |

**Note on Viewer + financial:** "Read-only access" (§23) is read broadly
here — view-only on every operational module — but `financial.view` is
deliberately *not* auto-granted to Viewer, since it's a separately-named
permission (§24) and defaulting every read-only user into seeing monetary
figures isn't something the PDF states either way. It's one checkbox away
via `RolesScreen` if a business wants that.

**Permissions are data, not code** (§24's "configurable", and the
project's own existing architecture note in `employee_models.dart`): every
grant above is editable per-role at runtime through `RolesScreen`
(`Settings → Employees → Roles`), a real permission-matrix editor that
already existed before this pass — this document describes the *seeded
defaults*, not a hard-coded ceiling.

## F. Business type vs. user role

These are two independent axes, never conflated in the frontend:

- **Business type** (§50: Furniture Factory, General Factory, Warehouse,
  Storage Store, Wholesale Store, Distribution Center, Custom) determines
  which *modules exist at all* for this business — `businessTypeModules`
  in `lib/features/settings/data/business_type_config.dart`. A Storage
  Store never has a Production module, regardless of who's logged in.
- **User role** (section C above) determines what a signed-in *person* can
  do within the modules their business type enables.

The sidebar (`_enabledBusinessNavItems` in `lib/routing/app_router.dart`)
applies both filters independently and combines them with AND: a nav item
only shows if the module is relevant to this business type **and** the
signed-in user has `view` on it. Removing either module or role does not
implicitly grant the other back.

## G. Tenant/business context

Business users only ever operate within their own business (§2, §36) — the
frontend's `Local*Repository`s are single-tenant by construction in this
demo-mode phase (see `docs/frontend-demo-mode.md`), so there's no
cross-tenant data to leak in the UI regardless. System Admin is the
explicit, separately-gated exception (§36: "System Admin can access all
businesses. Business users can only access their own business.") —
`routing/app_router.dart`'s `_redirect` keeps the System Admin and business
shells structurally separate (never the same rendered shell instance), and
"inspecting a business" (System Admin opening `AdminBusinessDetailScreen`)
is never the same code path as "operating as a business user" — there is
no "log in as this business" feature, on purpose; §57's business-details
page is read/administer-only (Edit, Disable, Activate, Reset password,
Manage users, View reports), never a way to act on the business's own data
as if signed in as one of its employees.

## H. Product creation clarification

Restated plainly because the brief marked it especially important: the
System Admin dashboard's Products/Orders/Sales/Employee cards
(`admin_dashboard_screen.dart`) open the real business-module screens so
the admin can *inspect* them (§57), but every create/edit/delete action on
those screens is still gated by the business-side permission model in
section E — the admin identity itself carries no
`products.create`/`orders.edit`/etc. grant, because it isn't a business
role at all (`permission_providers.dart`'s `currentRoleProvider` only
resolves a role for a session with a linked business `Employee` record;
System Admin has none). Concretely: the "Add Products" button that a
Business Owner demo sees does not appear when the same screen is reached
from the System Admin dashboard.

## I. Demo-role testing

**Demo mode only** (§16 of this pass's brief) — never a production
feature; every button below only renders when `AppModeConfig.isDemo` is
true (default), and is visually inside the login screen's existing
"DEMO MODE" card.

Nine demo identities, one per role in section C plus System Admin — the
login screen's two primary buttons stay "Business (Demo)" (Owner) and
"System Admin (Demo)" (unchanged from the earlier demo-mode pass); a
"Try another role (demo)" toggle reveals the other seven. Each business
identity's phone number matches a seeded `Employee` record
(`employee_repository.dart`), so its role — and therefore its actual
permission set — resolves for real through the same code path a linked
real account would use, not a hard-coded per-button special case:

| Demo login button | Phone constant | Linked Employee | Role |
|---|---|---|---|
| Business (Demo) | `kDemoBusinessPhone` | Demo Owner | Business Owner/Admin |
| System Admin (Demo) | `kDemoAdminPhone` | *(none — not a business role)* | — |
| Manager | `kDemoManagerPhone` | Zana Hussein | Manager |
| Warehouse Manager | `kDemoWarehouseManagerPhone` | Rezan Ali | Warehouse Manager |
| Sales Staff | `kDemoSalesStaffPhone` | Dilan Omar | Sales Staff |
| Inventory Staff | `kDemoInventoryStaffPhone` | Ary Karim | Inventory Staff |
| Production Manager | `kDemoProductionManagerPhone` | Soran Najat | Production Manager |
| Accountant | `kDemoAccountantPhone` | Lana Faraj | Accountant |
| Viewer | `kDemoViewerPhone` | Hero Salih | Viewer |

### Permission test matrix

Module × action, current seeded defaults (✓ = granted). Blank = not
granted by default (still editable via `RolesScreen`). Every role also has
`dashboard.view`/`documents.view`/`audit.view` (omitted from the table —
see section E's note).

| Module | Owner | Manager | Wh. Mgr | Sales | Inv. Staff | Prod. Mgr | Accountant | Viewer |
|---|:-:|:-:|:-:|:-:|:-:|:-:|:-:|:-:|
| Products (V/C/E/D) | ✓✓✓✓ | ✓✓✓ | ✓✓✓✓ | V | V | — | — | V |
| Categories (V/C/E/D) | ✓✓✓✓ | — | — | — | — | — | — | V |
| Inventory (V/C/E/D) | ✓✓✓✓ | ✓✓✓ | ✓✓✓✓ | — | V,E | V | — | V |
| Sales (V/C/E/D) | ✓✓✓✓ | ✓✓✓ | V | ✓✓✓ | — | — | — | V |
| Orders (V/C/E/D) | ✓✓✓✓ | ✓✓✓ | V | ✓✓✓ | — | — | — | V |
| Customers (V/C/E/D) | ✓✓✓✓ | ✓✓✓ | — | V | — | — | — | V |
| Suppliers (V/C/E/D) | ✓✓✓✓ | ✓✓✓ | — | — | — | — | — | V |
| Purchases (V/C/E/D/Ap) | ✓✓✓✓✓ | ✓✓✓ | — | — | — | — | V,Ap | V |
| Returns (V/C/E/D/Ap) | ✓✓✓✓✓ | — | — | — | — | — | — | V |
| Production (V/C/E/D) | ✓✓✓✓ | — | — | — | — | ✓✓✓✓ | — | V |
| Users (V/C/E/D) | ✓✓✓✓ | — | — | — | — | — | — | V |
| Reports (V/Ex) | ✓✓ | V | V | — | — | — | V,Ex | V |
| Settings (V/E) | ✓✓ | — | — | — | — | — | — | V |
| Financial (V) | ✓ | — | — | — | — | — | ✓ | — |

Columns: V=View, C=Create, E=Edit, D=Delete, Ap=Approve, Ex=Export.

### Manual verification (per the brief's §23)

From the login screen, in demo mode, with the backend off:

1. **System Admin** → the admin-only interface (Businesses list, business
   details, no business-side modules reachable except the four the
   dashboard cards intentionally open — see §H).
2. **Business Owner** → the full business interface, every module, every
   action.
3. **Manager** → business interface minus Returns/Production/Users/Settings.
4. **Warehouse Manager** → inventory/product-oriented interface,
   Sales/Orders visible read-only, Production/Settings hidden.
5. **Sales Staff** → sales/customer interface, Inventory/Production/Settings hidden.
6. **Inventory Staff** → stock-oriented interface (Inventory only, Products
   read-only), everything else hidden.
7. **Production Manager** → production/material interface, Sales/Customers hidden.
8. **Accountant** → Reports + Purchases (read) + financial figures visible
   elsewhere (e.g. Products' Purchase cost column); no product/sales/
   inventory CRUD.
9. **Viewer** → every module visible, zero create/edit/delete/approve/export
   actions anywhere, financial figures hidden.

## Backend mode

The real backend (Phase 2) does not return role/permission data in its
`/api/auth/login`/`/me` response today — adding that is backend work this
pass explicitly did not do (per the brief's "Do NOT start backend work").
`permission_providers.dart`'s `currentRoleProvider` resolves to `null` for
any session with no linked demo `Employee` (i.e. every real backend-mode
login), and `hasPermission` treats `null` permissions as **unrestricted**
— every gate in this document defaults to "allowed" rather than "denied"
when there's no role to check against. This is a deliberate asymmetry: it
lets demo mode demonstrate real per-role restriction without silently
taking any capability away from a real backend-mode user that predates
this pass. When the backend gains real role/permission support, the fix is
localized to `currentRoleProvider` (resolve from the real session instead
of a phone lookup) — nothing else in this document's model changes.
