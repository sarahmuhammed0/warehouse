# Business frontend functionality audit

A module-by-module audit of every interactive control on the **business**
side of the Flutter app, what it did before, and what it does now in demo
mode. The System Admin side was audited separately — see
`docs/frontend-coverage.md`'s §57 section.

The audit covered buttons, icon buttons, row actions, menu items, cards,
tabs, dropdowns, switches, checkboxes, search fields, filters, pagination,
dialogs and form submits across every business screen, looking for four
failure modes:

- **DEAD** — empty callback, or `null` where that disables the control.
- **FAKE** — reports success without changing any local state.
- **PARTIAL** — opens something inert, or a cross-module effect is missing.
- **MISSING** — the repository can do it; nothing in the UI calls it.

## The headline finding: no module wrote a cross-module effect

Every list/detail/form screen persisted correctly into its **own**
repository, and not one of them touched another module. You could sell a
sofa, complete the order, and the sofa's quantity never changed — the Sales
list said one thing and Inventory said another. `MovementType` had declared
`sale`, `purchase`, `returnMovement` and `production` from the start;
nothing ever emitted them.

`features/inventory/data/stock_engine.dart` is now the one place stock
moves. It pairs the quantity change with a movement row (§12's append-only
ledger), invalidates every provider that displays a quantity, and reverses
symmetrically.

| Action | Effect now |
|---|---|
| Quick sale created | Stock out (a quick sale is born Completed) |
| Order → Completed | Stock out |
| Order → Cancelled (after completing) | Stock back |
| Purchase → Completed | Stock in |
| Return → Completed | Restocks **sellable** lines only; damaged lines record a movement with no stock change |
| Production → Completed | Consumes BOM materials × units built, adds finished goods |
| Manual adjustment | Stock in/out |

Two knock-on fixes came with it: `ProductReturn.restocksOnCompletion` finally
has a call site (so the Sellable/Damaged dropdown stops being decorative),
and completing a return sets its order to Returned or Partially Returned so
the two modules agree.

## Module by module

### Dashboard (§5)
| Before | Now |
|---|---|
| 4 statistics | 15, all derived from the repositories |
| No stat card was tappable | Every card drills into the list its number was counted from, with the filter pre-applied |
| Chart panel rendered the literal text "Chart will render here once connected to real data" | Four real series: daily sales, monthly sales, top products, sales by category |
| 6 quick actions, 4 of which opened a list screen instead of a workflow; New order and Add stock absent | 8, each opening its create form or dialog, all permission-gated |

Add stock previously had no entry point that didn't require finding a
product first; it now asks which product, and the Save button is disabled
until one is chosen rather than being a silent no-op.

### Products (§8)
- **Stock** and **History** row actions were missing, although
  `showStockAdjustmentDialog` took exactly a `Product` and `listMovements`
  had always supported a `productId` filter nothing passed. Both added, plus
  the same two actions on the detail screen.
- The detail screen's "Order history" card was a hard-coded empty state. It
  now shows the product's real recent movements, with a new
  `/products/:id/history` screen for the full ledger.
- Removing a filter chip called `setFilters({})`, which also silently
  cleared the category dropdown while leaving it displaying the category it
  was no longer filtering by. It drops one filter now.

### Orders and Sales (§13/§14)
- `_CartLine.tax` was computed in the constructor while quantity was still
  its default of 1 and never recomputed, so a ten-unit line was taxed as
  one — on screen *and* in the saved draft. It is a getter now.
- The per-line **discount** had no editor at all, so the Discount row in the
  totals permanently read 0.00.
- The extra-charges input was labelled "Reference Number" while feeding
  `extraCharges` and the grand total.
- **Return** on a completed order flipped the status and created no return
  record, leaving Returns empty while the order claimed to have been
  returned. It now opens the return form with that order preselected.
- Orders and Sales gained a status/period filter bar, so a dashboard
  drill-down is visible and clearable rather than an unexplained subset.

### Customers and Suppliers (§18/§19)
`totalPurchases`, `outstandingBalance` and `orderCount` were seeded values
nothing ever changed: a customer you created started at zero and stayed
there however many orders you placed, so the table and detail stats were
permanently wrong for every non-seeded customer. Creating an order now rolls
into the customer's totals (`CustomerRepository.applyOrder`).

### Inventory (§10/§11/§12)
`LocalInventoryRepository.createTransfer` was fully implemented — generating
a TRF number, inserting the row, defaulting to pending — and had **no caller
anywhere in the app**. The Transfers tab was a read-only table of seeded
rows. There is now a New Transfer dialog; it excludes the source warehouse
from the destination list rather than rejecting the choice afterwards.

Manual adjustments used to rebuild a full 20-field `ProductDraft` by hand
and forget to reload the Movements tab, so a new adjustment could silently
fail to appear there.

### Reports (§25/§26)
Ten of the twelve cards passed `onTap: null` and rendered "Coming soon",
while the provider each one needed already existed and was already being
read elsewhere. All twelve now open a real report over real rows.

Both Export buttons were `onPressed: () {}` — a non-null empty closure, so
they rendered **fully enabled** and silently did nothing. Export now builds
the real CSV for exactly the rows on screen (filtered, not the whole set),
displays it and copies it. Server-side file generation stays backend work
and the dialog says so.

### Permissions (§24) — real data with no effect
Editing the matrix called `updateRolePermissions` and the repository really
changed, but `currentRoleProvider` depends only on auth state and the
repository, neither of which changes identity when a role is edited. Its
cached `Role` survived the whole session: revoking `products.view` moved the
checkbox and nothing else. A `rolesVersionProvider` counter, bumped by the
edit, makes it recompute — so the sidebar and the gated buttons respond
immediately.

Doing that safely required moving the sidebar's nav filtering and brand
label **out of `routerProvider`'s build** and into `AppShell`. A provider
watched while building the router makes the router rebuild, which
constructs a brand-new `GoRouter` and discards the navigation stack. That
hazard was already latent; live permissions would have triggered it on
every edit.

### Settings (§34)
Every section was already bound to a real Notifier, so values survived
navigation — but **eleven** inputs built `TextEditingController(text: ...)`
inline in `build()`. `BusinessSettingsData` has no `==`, so each keystroke
produced a new state object, rebuilt the section, and handed the field a
brand-new controller seeded from the provider: the caret jumped out of
position on every character, number fields could not be cleared (the failed
parse re-rendered the old value), and one controller leaked per keystroke.
`SettingsField` seeds once and writes through.

There is no Save button in Settings and never was — every section applies
immediately. That is a deliberate design, not a missing control.

### Notifications (§31)
Tapping one only marked it read and dismissed the menu. Entries now carry
the route of what they are about, so "Low stock — 3-Seat Sofa" opens that
product. `markAllRead()` existed with no caller; it is now a menu item.

### Shared widgets
`AppSwitch.onChanged` was non-nullable, so four dialogs passed `(_) {}` to
lock the switch while saving — which leaves it looking fully interactive
while silently swallowing taps. It is nullable now, so `null` greys it out
like the buttons beside it.

`PaginationBar`'s rows-per-page dropdown renders only when
`onPageSizeChanged` is passed. Six list screens passed `pageSizeOptions`
without the callback, so the control never appeared at all.

Purchase and Production cancel now confirm first, as Orders already did.

## What remains backend-dependent (honest list)

These stay UI-only, and the UI says so rather than pretending:

- **Backup / restore** — UI-only by explicit instruction in the original
  brief; no backup engine exists to call.
- **PDF file generation** — the template editor and live preview are real
  and the preview reflects the real settings, but producing a PDF file is
  backend work (§38 lists no endpoint). Report export shows the real CSV
  content instead of writing a file.
- **Barcode scanning** — a label preview exists; camera/hardware scanning is
  out of reach for a Flutter-only phase per the brief's own §31.
- **Settings persistence** — settings live in memory and reset on restart;
  there is no backend to save to, and claiming durability would be a lie.
- **Product images** — `Product.imageUrl` round-trips through the
  repository, but there is no upload pipeline, so no screen sets or renders
  one.
- **Product variants** — add and remove work and survive navigation, but
  they live in a provider rather than a repository (lost on restart) and
  there is no edit action. Noted rather than fixed in this pass.
- **Custom fields** — the add/remove UI works but the list is local widget
  state, unreadable by the product/customer forms that would need to render
  the fields. Noted rather than fixed in this pass.
- **Settings fields with no reader** — negative-inventory allowance,
  default reorder level, invoice/order/production number prefixes, payment
  method toggles, session timeout and lockout attempts all persist to the
  settings provider but no module consults them yet.

## Tests

`test/widget_test.dart` covers each of the flows above. The groups added or
extended by this audit: *Stock engine*, *Business dashboard*, *Reports*,
*Permissions actually change the UI when edited*, and *Cross-module effects
beyond stock*. Each stock test asserts **both** halves — the quantity moved
and the movement row exists, with `previousQuantity`/`newQuantity`
agreeing — because asserting only the first would pass against the bug this
work fixed.
