# Frontend ↔ backend contract notes

What each module's `Local*Repository` (demo data, in-memory) expects to be
replaced by — one `Api*Repository` implementing the same abstract
interface, swapped in at exactly one `Provider` per module. No screen,
controller, or widget needs to change; every list/detail/form screen reads
the abstract interface, never the `Local*` class directly (see
`core/repositories/demo_data_source.dart`'s `DemoRepository` mixin for how
demo-backed repositories are kept mechanically identifiable).

General shape every module follows: `list(PagedQuery)` → the backend's
paginated list endpoint (`page`/`pageSize`/`search`/`filters`/`sortField`/
`sortAscending` query params, response `{ data: [...], meta: { page,
pageSize, total } }` — matches `PaginatedResult<T>`, architecture §26/§29).
`getById`, `create`, `update`, status-change methods map to the obvious
REST verbs. Every `businessId` scoping is expected to come from the
authenticated session server-side (§7 of `docs/multi-tenancy.md`) — no
repository interface below accepts a `businessId` parameter, by design.

| Module | Interface | Local implementation | Expected real endpoint(s) |
|---|---|---|---|
| Categories | `CategoryRepository` | `LocalCategoryRepository` | `GET/POST/PUT /api/categories`, `PATCH /api/categories/:id/status` |
| Products | `ProductRepository` | `LocalProductRepository` | `GET/POST/PUT /api/products`, `PATCH /api/products/:id/status` — image upload needs a real multipart endpoint (`imageUrl` is currently always `null`) |
| Product variants | none yet (`productVariantsProvider` is a bare in-memory `Map`) | — | `GET/POST/DELETE /api/products/:id/variants` — needs a real repository interface added, not just a provider swap |
| Inventory movements | `InventoryRepository.listMovements`/`recordAdjustment` | `LocalInventoryRepository` | `GET /api/inventory/movements`, `POST /api/inventory/adjustments` (should be the *only* write path — every other module's stock change should also write a movement row server-side) |
| Warehouses/locations | `InventoryRepository.listWarehouses` | `LocalInventoryRepository` | `GET /api/warehouses` |
| Stock transfers | `InventoryRepository.listTransfers`/`createTransfer` | `LocalInventoryRepository` | `GET/POST /api/stock-transfers` |
| Customers | `CustomerRepository` | `LocalCustomerRepository` | `GET/POST/PUT /api/customers` — `totalPurchases`/`outstandingBalance`/`orderCount` must be server-computed, never client-trusted |
| Suppliers | `SupplierRepository` | `LocalSupplierRepository` | `GET/POST/PUT /api/suppliers` — same aggregate-field caveat |
| Orders + Sales | `OrderRepository` | `LocalOrderRepository` | `GET/POST /api/orders`, `PATCH /api/orders/:id/status` (server must re-validate `allowedNextStatuses` — the frontend's state machine is UX only) — `orderType` filter serves both the Sales and Orders screens from one endpoint |
| Purchases | `PurchaseRepository` | `LocalPurchaseRepository` | `GET/POST /api/purchases`, `PATCH /api/purchases/:id/status` — completing a purchase must trigger a real inventory increase + movement row server-side |
| Returns | `ReturnRepository` | `LocalReturnRepository` | `GET/POST /api/returns`, `PATCH /api/returns/:id/status` — restock-on-Completed (two-stage policy) must be enforced server-side, not assumed from the frontend calling it |
| Production | `ProductionRepository` | `LocalProductionRepository` | `GET/POST /api/production-orders`, `PATCH /api/production-orders/:id/status`, `GET /api/products/:id/bom` — completion must decrement material stock + increment finished-goods stock atomically |
| Employees | `EmployeeRepository` (employee half) | `LocalEmployeeRepository` | `GET/POST/PUT /api/users`, `PATCH /api/users/:id/status` |
| Roles/permissions | `EmployeeRepository` (role half) | `LocalEmployeeRepository` | `GET /api/roles`, `PUT /api/roles/:id/permissions` — every backend route must independently check the resolved permission, never trust that the frontend only showed an allowed action (architecture §8's "never trust frontend permissions") |
| System Admin businesses | `AdminRepository` | `LocalAdminRepository` | `GET /api/admin/businesses`, `GET /api/admin/businesses/:id`, `PATCH /api/admin/businesses/:id/status` — business *creation* already has a real endpoint from Phase 2 (`POST /api/admin/businesses`), this screen only needs a real list/detail/status-change added |
| Activity history | `AuditRepository` | `LocalAuditRepository` | `GET /api/audit-logs` — the backend's real `audit_logs` table + `writeAuditLog` writer already exist (Phase 2, auth events only); this is "add more write call-sites + a list endpoint," not new schema |
| Notifications | none yet (`notificationsProvider` derives from `ProductRepository` directly) | — | `GET /api/notifications`, `PATCH /api/notifications/:id/read` — real triggers (new order, return request, etc.) need a push/poll mechanism, not just a repository swap |
| Reports | none — screens query `ProductRepository`/`OrderRepository` directly | — | Dedicated aggregate endpoints per report type (`GET /api/reports/inventory`, `GET /api/reports/sales?from=&to=`, etc.) — computing report totals client-side over `list()` pages doesn't scale and shouldn't be the final approach |
| Settings (all sections) | none — `businessSettingsProvider` is a bare in-memory draft | — | `GET/PUT /api/business-settings` (or one endpoint per section) — nothing here persists today, including the business-type selector that drives sidebar module visibility |
| Custom fields | none — plain `List<String>` in widget state | — | `GET/POST/DELETE /api/custom-field-definitions` |
| Backup/restore | none — buttons are no-ops behind a confirm dialog | — | `POST /api/backups`, `GET /api/backups`, `POST /api/backups/:id/restore` |
| Documents/PDF | reads `businessSettingsProvider` + `OrderRepository` | — | `GET /api/orders/:id/pdf` (binary/stream response) — the current screen renders an equivalent preview client-side; real PDF generation is backend work per the brief's own instruction |

## Already real (Phase 2, unaffected this phase)

Authentication (`AuthRepository`/`ApiAuthRepository`), the Dio
`AuthInterceptor`, secure token storage, and the auth Riverpod state
machine are fully backend-connected and were not touched — see
`docs/authentication.md`. Nothing above changes how those work.
