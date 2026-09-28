# Frontend wiring — pointing the screens at the real API

What is now reading the backend instead of demo data, what is still on demo
data and why, and the handful of decisions that wiring forced.

**No screen, widget, layout, string or style was changed.** The mechanism is the
one `docs/frontend-backend-contract-notes.md` describes: an `Api*Repository`
implementing the same interface as the `Local*` one, selected by a single
`switch` in that module's provider. Two data-layer call sites changed, both
invisible, both listed in §3 below.

---

## 1. Wired this phase

| Module | Repository | Endpoints |
|---|---|---|
| Inventory | `ApiInventoryRepository` | `/inventory/movements`, `/inventory/adjust`, `/inventory/transfer`, `/warehouses`, `/warehouses/options` |
| Customers | `ApiCustomerRepository` | `/customers` |
| Suppliers | `ApiSupplierRepository` | `/suppliers` |
| Orders + Sales | `ApiOrderRepository` | `/orders`, `/orders/:id/status`, `/orders/:id/payments` |
| Purchases | `ApiPurchaseRepository` | `/purchases`, `/purchases/:id/status` |
| Returns | `ApiReturnRepository` | `/returns`, `/returns/:id/status`, `/orders/:id/returnable` |
| Production | `ApiProductionRepository` | `/production-orders`, `/production-orders/:id/status`, `/products/:id/bom` |

Already wired before this phase: authentication, registration, the admin
approval queue, products, categories.

Demo mode is still the default and still works: `flutter run` with no
`--dart-define` uses every `Local*Repository` exactly as before.

---

## 2. The one that would have corrupted stock

`StockEngine` moves stock **client-side** and is called from six screens — the
order detail and form, the purchase detail, the return detail, the production
detail and the adjustment dialog. That is how stock moves in demo mode, and it
is why the demo tells the truth about quantities.

In backend mode the server moves stock itself, inside the same transaction that
changes a document's status. Wiring the modules without touching the engine
would therefore have moved every sale, purchase, return and production run
**twice** — once on the server, once again from the browser — and filed a
manual-looking adjustment row on top of the document's own ledger entry.

The fix keys off the movement type each caller already passes, so no screen
changed:

- `sale`, `purchase`, `return`, `production` — **server-owned**. In backend mode
  the engine skips the writes and only refreshes the providers that show a
  quantity, which is what the calling screen actually needed from it.
- `manual_increase`, `manual_decrease`, `adjustment`, `damage` — **not**
  server-owned. Nothing else records a manual adjustment, so in backend mode it
  still goes to `/inventory/adjust` like any other user action.

### The second half of the same rule, and the bug it hid

Skipping the server-owned types was not enough. For the types the engine *does*
still handle in backend mode — a manual adjustment — it wrote **twice**:

```
inventory.recordAdjustment(...)   → POST /inventory/adjust
products.adjustQuantity(...)      → POST /inventory/adjust   (again)
```

In demo mode those are two different stores that must be kept in step: the
movement row, and the product's own quantity. Against the real API they are the
same write — `/inventory/adjust` moves the level and writes the ledger row in one
transaction (§12), and `ApiProductRepository.adjustQuantity` routes through that
very endpoint. So a manual decrease of three took six.

It was invisible before this phase only because the inventory repository was
still demo-backed: `recordAdjustment` wrote to an in-memory list and just one
call reached the server. Wiring inventory turned that into two real writes.
`apply` now makes the product-side write demo-only, and a test asserts the
request count is exactly one and the quantity is exactly what was asked.

### Making the guard testable at all

`AppModeConfig.mode` is a compile-time constant and `flutter test` always
compiles as demo, so neither branch above could be reached by a test — safety
logic that cannot be exercised is a liability. The engine now reads
`appModeProvider`, which defaults to the constant and can be overridden in a
test. It is the only place with such a provider, deliberately: everywhere else
the mode merely *selects a repository*, and a test overrides that repository
instead.

---

## 3. The two invisible call-site changes

**A transfer now carries the product's id.** `createTransfer` took a product
*name*. The API moves stock by id, and §8 does not make product names unique —
resolving a name server-side could move a different product's stock, which is a
correctness bug rather than a limitation. The transfer dialog already held
`_productId` for its own picker, so it passes it; the parameter is optional so
the demo implementation is unchanged. The API repository refuses rather than
guesses if it is ever absent.

**A return resolves its order line.** The API records a return against an order
LINE, because the same product can appear twice on one order at two prices and
the refund has to know which. This module's models carry only the product, so
`ApiReturnRepository` reads `/orders/:id/returnable` — which is also where the
server says how much of each line is left — and matches on product id.

Where a product genuinely appears on two lines of one order, the first line with
enough remaining is taken. **That is a real ambiguity, not a safe default.** The
honest fix is a line id on `OrderLineItem` and a row on the return form, which
is a UI change and therefore not made here. The server still validates the
quantity and caps the refund, so the worst case is a refund priced from the
wrong line *of the same product* — never more than was paid.

---

## 4. Smaller things worth knowing

**An order-level discount is not shown.** The backend supports one; this
module's `Order` has only per-line discounts plus `extraCharges`, and computes
its own total from them. An order given an order-level discount through the API
will therefore display its lines' arithmetic rather than the server's lower
total. Folding it into `extraCharges` would render a negative "extra charge",
which would be a lie, so it is left visible. Fixing it needs a model field and a
row on the screen.

**A quick sale is created `confirmed`, then `completed`.** §13's sale hands the
goods over immediately, and `confirmed` is the status at which the backend moves
stock; `completed` then closes it, which is what this module's models mean by "a
quick sale is born Completed". Note the demo moves stock at *completion* and the
server moves it at *confirmation* — in backend mode the server's rule is the one
that applies, and the UI reflects server state.

**A cancellation sends a fixed reason.** §17 requires one; the screen confirms
the action but collects no text, so the repository records where it came from
rather than failing the request. A reason box is a UI change.

**Payment method is per payment, not per document.** §43 records a method on each
payment, because an order can be settled partly in cash and partly by transfer.
The `paymentMethod` the detail screens show is the most recent payment's.

**`purchases` has a `draft` status the frontend enum does not.** A draft purchase
reads as `pending`, which is what it is from the warehouse's point of view:
recorded, not yet received.

**Pickers read one page of 100.** `allForPicker` follows the existing product
repository's approach and its caveat: the backend caps `pageSize` at 100, so a
business with more than 100 customers needs a searchable picker — a UI change,
not a repository one.

---

## 5. Still on demo data

Each of these needs a backend endpoint first, not a repository:

| Module | Missing endpoint |
|---|---|
| Employees / users | `/api/users` |
| Roles & permissions | `/api/roles`, `PUT /api/roles/:id/permissions` |
| Activity history | `GET /api/audit-logs` (table and writer exist) |
| Notifications | `/api/notifications` |
| Reports | `/api/reports/*` (§25) |
| Documents / PDF | `GET /api/orders/:id/pdf` (§28) |
| Settings sections | only `inventory.allow_negative_stock` exists (§34/§47) |
| Product variants | `/api/products/:id/variants` |
| Custom fields, backup | §51, §33 |
| Admin per-business drill-downs | `listForBusiness` throws `UnimplementedError` in backend mode — every business route is scoped to the caller's own session, so a System Admin reading another tenant's orders needs a deliberate admin endpoint |

`listForBusiness` is the only method that throws rather than working. It is
reachable only from the System Admin's per-business reports screen, which is
itself listed above as unwired.

---

## 6. Verification

| Check | Result |
|---|---|
| `flutter analyze` | No issues found |
| `flutter test` | 190 passing — 30 new (21 mapping, 9 screen) |
| Live contract check against the running server | 27 checks, all passing |
| `npm test` (backend) | 269 passing |

The 9 screen tests mount the real app with a module's repository pointed at its
API implementation behind a stubbed HTTP layer, navigate to the module, and look
for the server's values on screen — then tap a row and check the detail view
fetched and rendered the right record. That is what catches a screen reading a
field the wiring leaves null, which no repository test can see. Two of them
exercise the stock guard from both sides: a confirmation must send the status
change and no adjustment, and a manual adjustment must send exactly one.

Both guard tests were checked against the defect: restoring the double write
fails the count assertion, and the fix passes it.

Two gaps remain, stated rather than papered over. The **create forms** are
covered at the request-body level but not through the screen — the flows that
follow a save keep a reload spinner animating, so `pumpAndSettle` never returns.
And the app in a real browser was launched and served but **not clicked
through**: no browser automation is available in this environment.

The 21 new tests pin the mapping in both directions — every field parsed out of
a response and every key sent in a request body — against a stubbed HTTP
adapter. That catches a repository that spells a field `name` where the server
says `fullName`, which compiles and analyses clean and simply shows a blank.

Because canned JSON could itself be wrong, a second check runs against the
**real running server**: it builds a business through the API and asserts that
every field these repositories read is actually present in the live responses.
That is what caught the one backend change this phase needed — `taxAmount` on an
order line was accepted by the service but stripped by the route's schema, so a
per-line tax typed as an amount silently vanished and the line came back
untaxed.
