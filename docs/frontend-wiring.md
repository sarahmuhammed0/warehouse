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

## 5. The rest of the screens — no demo data left

Everything the previous section listed as "still on demo data" now reads the
API. The mechanism is unchanged: an `Api*Repository` behind the same interface,
chosen by a `switch` in that module's provider. Demo mode still works untouched.

| Module | Reads |
|---|---|
| Staff + Roles | `/users`, `/roles`, `PUT /roles/:id/permissions` |
| Activity history | `/audit-logs` |
| Notifications | `/notifications`, `/unread-count`, `/:id/read`, `/read-all` |
| Settings | `/business`, `/settings`, `/documents/numbering`, `/documents/pdf-template` |
| Variants | `/products/:id/variants`, `/inventory/adjust` |
| Transfers | `/stock-transfers` (was the movement ledger) |
| Custom fields | `/custom-fields` |
| Backups | `/admin/backups` |
| System Admin | `/admin/businesses/*`, `/admin/activity` |
| Documents | `GET /orders/:id/pdf` |

Reports needed no repository: every report is computed from modules that were
already wired, so they have been showing real figures since the last phase.
System status was already reading `/health`.

---

## 6. The session now knows what it may do

This is the change with the most reach, and it was a real gap rather than a
missing screen.

`currentPermissionsProvider` resolved a role only in demo mode, by matching the
demo login's phone to a seeded employee. A **backend** session matched nothing,
resolved to `null`, and `hasPermission` treats `null` as unrestricted — so every
nav item was offered to every role and the server refused on the click. Signing
in as a salesperson looked exactly like signing in as the owner.

`/api/auth/login` and `/api/auth/me` now return the user's role and its grants,
resolved server-side, and the session carries them.

**This is not a weakening of §8's minimal token claims.** The access token still
carries no permissions — a test asserts it — because a token that carried them
would keep them until it expired, up to fifteen minutes after an administrator
revoked them. This is a per-request server lookup handed to a UI, and
`middleware/authorize.js` still re-reads the grants on every request. It is a
snapshot: a role edited mid-session reaches that user's sidebar on their next
session restore. The server refuses on the very next request either way.

### The three keys with nothing behind them

The sidebar gates Dashboard, Documents and Activity History on `dashboard.view`,
`documents.view` and `audit.view` — none of which exist in the permission
catalogue, because they are screens assembled from other modules rather than
modules of their own. Granting them to everyone (as the demo roles do) would
have offered Activity History to a salesperson whose `/api/audit-logs` request
then 403s.

So the server **derives** them from what it actually enforces: Dashboard for
everyone, Documents with `orders.view`, Activity History with `settings.view` —
which is what `/api/audit-logs` checks. They are deliberately absent from
`GET /api/roles`, which feeds the permission editor, because a checkbox for a
key the server does not store would be unsaveable.

---

## 7. Decisions this pass forced

**A phone number cannot be edited, and the form still shows one.** It is the
credential (§3) and the identity. The update schema has no `phone`, and zod
strips a key it does not know — so passing the field through would answer 200
with the number unchanged, and the owner would leave believing they had changed
it. `ApiEmployeeRepository.update` refuses it outright instead, and sends
nothing.

**Settings save as you type, because the screen has no Save button.** The
controller debounces 600ms and sends a **diff** — only the fields that actually
changed, each to whichever of the four endpoints owns it. A blanket write would
PATCH the business record, the settings store, four document sequences and the
PDF template on every keystroke, and a numbering counter that only moves forward
would start refusing writes it never needed to be sent.

**Settings fields re-seed when they are not being typed in.** `SettingsField`
deliberately seeded its controller once, to fix a caret bug. In backend mode the
values arrive *after* the first build, so a field seeded once kept showing `USD`
after the server said `IQD`. It now re-seeds when the incoming value changes
**and** the field is unfocused, which keeps the original fix intact.

**A transfer is created as a document.** `createTransfer` posted to
`/inventory/transfer`, a bare two-legged movement. The list now reads
`/stock-transfers`, so a transfer filed the other way would have moved the goods
and then never appeared in the list of transfers. The list also shows `pending`
transfers, which reading the ledger could never do — a movement row only exists
once the goods have moved.

**A variant's opening quantity is a real stock movement.** The add-variant
dialog collects a quantity; the variant create endpoint has no such field,
because a variant is its own stock slot. The repository creates the variant and
then files a `manual_increase` against `(product, variant, warehouse)`, so the
stock can be explained later by the same history as every other quantity in the
system. This needed `variantId` on `/inventory/adjust`: `adjustStock` already
accepted one and the route schema stripped it — the same defect class as
`taxAmount` last phase. The variant is scoped by business *and* product when it
is checked, so a variant id from another tenant cannot name a slot in this one.

**A custom field's key is derived from its label, once.** The screen collects a
label; the server needs a stable machine key, because the label is what a
business renames and the key is what recorded values are filed under.

**The backup history is empty for a business owner, and says why.** Backups dump
a database holding every tenant, so the endpoint is System-Admin-only. The
section previously showed a hardcoded "Scheduled backup — Yesterday, 02:00 —
Completed", which is the most convincing lie in the application: a screen about
disaster recovery asserting that a recoverable file exists. It now shows what
the server has actually recorded, and the button reports the server's own answer
— including `fileProduced: false`. It never says "Backup complete".

**No password-reset date is invented.** `AdminBusiness.lastPasswordResetAt` was
demo-only local state. The server does not record it, so in backend mode it is
null rather than a timestamp the detail screen would present as a fact about the
account.

---

## 8. Two things the server had to grow

Both because a screen existed with no endpoint under it, not to make the wiring
easier.

**`GET /api/admin/businesses/:id/{users,products,orders}`** — §57's drill-downs
list a tenant's records, and every business route is scoped to the caller's own
session (§36). They are read-only: an admin who could edit a tenant's stock
would be a second, invisible author of that tenant's data, and §57 gives the
platform operator oversight, not operation. Capped at 200 with
`limit`/`truncated` in the response rather than a silent cut. The orders
response carries its line items, because this model computes an order's total
from its lines and an order without them reads as `0.00` — worse than unknown,
because it looks like a figure.

**`GET /api/admin/activity`** — §56's platform feed: the same `audit_logs`,
unscoped, each row naming its business. Read-only, for the same reason §30's
trail is.

---

## 9. Verification

| Check | Result |
|---|---|
| `flutter analyze` | No issues found |
| `flutter test` | 227 passing (36 new) |
| `npm test` (backend) | 365 passing (6 new) |
| Live check against the running server | 162 checks |

The live check is the one that matters most, for the reason the previous phase
gives: canned JSON can itself be wrong. It signs in as an owner, a salesperson
and a System Admin, and asserts that every field these repositories read is
present in the real response, that the refusals actually refuse, and that a
variant's stock lands in the variant's own slot.

It found two key-name mistakes that compile, analyse clean and simply show
nothing — the notification badge read `unreadCount` where the server sends
`unread`, and the backup history read `fileSizeBytes`/`note` where the server
sends `sizeBytes`/`errorMessage`.

It also found a **test that proved nothing**: the §28 reprint test asserted that
two renders had the same *length*, while its comment claimed byte identity. A
length check passes with every figure on the page changed. It now compares the
bytes, excluding only the trailer's `/ID`, which pdfkit randomises per render
because the PDF spec requires a unique file identifier.

Separately, six new backend tests were written with an inverted
`requireDatabase` guard — they returned before asserting anything and reported
six passes in a second. Caught because the timings were implausible for a
bcrypt login. Both guards that matter were then checked by reintroducing the
defect: removing the session-role lookup fails two permission tests, and
removing the derived navigation keys fails the backend one.

---

## 10. What is still not done

- **§33's backup takes no dump.** Unchanged, and unchangeable from the client —
  see `docs/backend-phase9.md` for what completing it needs.
- **Session timeout and login-lockout attempts** are shown in Settings and are
  not stored. The first is the access token's TTL; the second is deliberately
  not per-business, because the lockout is checked before a phone is resolved to
  an account precisely so the response cannot reveal whether that account
  exists. Both are left at their defaults, and neither is ever sent.
- **The profit report is cash-basis**, as before.
- **Saving a file works only in the browser build.** `downloadBytes` refuses
  elsewhere rather than failing silently; a desktop build would need a file
  picker and a real path.
- **An order-level discount is still not displayed**, as the previous section
  records — it needs a model field and a row on the screen.
