# Phase 7 — Purchases, Returns, Production

The three modules that complete the goods lifecycle: stock comes in from a
supplier (§20), goes back out to one or comes back from a customer (§16), and
is turned into something else (§21–§22).

The Flutter frontend is untouched by this phase. Its screens for all three
already exist and still run on their `Local*Repository` demo data — swapping
each for an `Api*Repository` is the next step, and
`docs/frontend-backend-contract-notes.md` is the mapping.

---

## 1. What was built

| Endpoint | Purpose |
|---|---|
| `GET /api/purchases` | List, filter (`status`, `paymentStatus`, `supplierId`), search, date range |
| `GET /api/purchases/:id` | One purchase with its lines, and its payments if the role may see money |
| `POST /api/purchases` | Record a purchase; `draft`, `pending` (default) or already `completed` |
| `PATCH /api/purchases/:id/status` | Receive or cancel it — the only path that moves purchased stock |
| `POST /api/purchases/:id/payments` | Pay the supplier, in instalments if that is the arrangement |
| `GET /api/returns` | List, filter (`status`, `orderId`, `customerId`), search, date range |
| `GET /api/returns/:id` | One return with its lines and their conditions |
| `POST /api/returns` | Raise a return against an order's lines |
| `PATCH /api/returns/:id/status` | Approve, reject, or complete — completion is the only path that restocks or refunds |
| `GET /api/orders/:id/returnable` | What an order has left to return, and what was paid for it |
| `GET /api/products/:id/bom` | §21's bill of materials for a finished product |
| `PUT /api/products/:id/bom` | Replace that recipe whole |
| `GET /api/production-orders` | List, filter (`status`, `productId`, `warehouseId`, `assignedUserId`), search |
| `GET /api/production-orders/:id` | One run with its material snapshot |
| `POST /api/production-orders` | Plan a run; materials come from the recipe unless the caller sends its own |
| `PATCH /api/production-orders/:id/status` | Start, complete or cancel — completion is the only path that consumes or produces |

Every route is authenticated, tenant-scoped from the session (never from a
request parameter), permission-checked, and wrapped in §30's activity trail.

No new tables: Phase 3 created all seven. One migration
(`20260927090000_add_document_line_snapshots.js`) adds `product_name` and
`sku` to `purchase_items` and `return_items`, which `order_items` already had
— see §3 below.

---

## 2. Permissions

| Action | Permission | Why that one |
|---|---|---|
| Read purchases | `purchases.view` | |
| Create a purchase | `purchases.create` | |
| Receive or cancel a purchase | `purchases.approve` | §24 gives Purchases an Approve action, and deciding that a delivery has arrived is the decision that moves stock and commits the business to paying for it. Editing a note is not that decision. |
| Pay a supplier | `purchases.edit` | |
| Read returns | `returns.view` | |
| Raise a return | `returns.create` | |
| Approve, reject or complete a return | `returns.approve` | The other half of §24's Approve action. Completing one refunds money and puts goods back on a shelf. |
| Read a BOM or a run | `production.view` | |
| Create a run | `production.create` | |
| Edit a BOM, or change a run's status | `production.edit` | A BOM is a manufacturing recipe, so it follows Production rather than Products: a shop that does not manufacture never grants these and never sees any of it. |

---

## 3. Decisions worth recording

**A purchase is not stock until it is completed.** A pending purchase is an
order placed with a supplier. Counting it as inventory is how a warehouse comes
to believe it can sell goods still sitting on a lorry.

**A received delivery lands in the default warehouse, location-less.**
`purchases` carries no warehouse column, so there is nothing else it could
honestly mean, and it matches where §12's manual increase puts goods when no
shelf is named. A *reversal* then takes them back out of the slots the ledger
says they went into — and, if the receiving clerk has since shelved or
transferred them, out of wherever the warehouse actually has them. Insisting on
the original slot would refuse a perfectly reasonable cancellation.

**A completed purchase can still be cancelled; the goods go back out.** If they
have since been sold, §47 refuses the cancellation rather than inventing
negative stock — which is the honest answer: you cannot return what you no
longer have.

**Returns are two-stage and condition-gated**, as
`docs/architecture.md`'s decision table resolved §16's "per the configured
return process":

- Nothing moves on approval. An approval is a decision; the goods are still in
  the customer's car.
- On completion, **sellable** items go back into the slots they were sold from.
- **Damaged** items never re-enter stock. The return document records that they
  came back damaged; a warehouse that restocks a broken chair will eventually
  sell it.
- The refund is recorded against the order as money going **out**, so the
  order's paid figure falls and a refunded sale stops reading as paid.
- The order becomes `returned` or `partially_returned` from the returns it has
  actually completed. This is the one sanctioned way a completed order's status
  changes, which is why it does not go through the order module's
  `assertTransition` — that map makes `completed` terminal precisely so nothing
  else can move it.

**A return's refund is capped at what the customer paid for those quantities**,
pro-rated from the line's own total — so a part-return of a discounted line
refunds the discounted price, not the list price.

**A return claims its quantities as soon as it is requested.** Availability
counts every return that has not been *rejected*, not only completed ones:
otherwise two requests claim the same three chairs and both get refunded. A
rejection releases the claim again.

**A production run moves nothing until it completes.** Consuming materials when
work starts would be closer to a factory floor, but it makes cancellation a
restocking problem — how much of the wood is left, and in what state — that §22
says nothing about. At completion both sides are known, so both happen there,
in one transaction: materials out, finished goods in, or neither.

**Planned and produced quantities are kept apart**, because a batch yields what
it yields. Completion may state what was actually produced; the materials issued
to the batch were still cut.

**A run snapshots its materials.** Editing a recipe changes the next batch and
never what a past run consumed — `production_items` holds the quantities, and
nothing reads them back from `bill_of_materials`.

**A BOM is current-state only.** `uq_bom_product_material` is unique on
(product, material) with no regard for `deleted_at`, so soft-deleting a line and
re-adding the same material would collide on it. Replacing a recipe therefore
removes the lines that went away and upserts the rest. That is safe exactly
because past runs carry their own snapshot.

**§55's snapshot was extended to purchase and return lines.** A purchase line
already froze `unit_cost`; freezing the price but not the name is the
half-measure that leaves a two-year-old purchase reading as though it had always
been for the renamed product. The columns are nullable and deliberately not
backfilled — the name at the time is precisely what older rows never recorded,
so readers fall back to the product's current name, as they had to before.

---

## 4. Two things found while testing this phase

**A cancelled order could not be reopened.** `docs/architecture.md` approved
"Cancelled → Pending only, permission-gated" before Phase 0, but the order
module's transition map made `cancelled` terminal. It now allows `pending`, and
only `pending`: cancelling returned the goods to stock, so a reopened order has
no claim on them — it lands where nothing is committed, and the stock leaves
again when someone confirms it, through the one path that moves stock.
Reopening clears the cancellation fields, and §15's edit trail keeps the
history.

**The global rate limit throttled legitimate use.** It was a hardcoded 100
requests per minute per IP. An integration file that drives a realistic session
— sell, return, approve, complete, read it back — makes well over that in a
minute and started answering 429 to its own setup. It is now
`API_RATE_LIMIT`, defaulting to 100 in production and 5000 elsewhere, following
the registration limiter's existing pattern. **The production figure is worth
revisiting**: one busy screen, or several users behind one office NAT, can reach
100 requests in a minute without doing anything unusual. That is a decision
about real traffic rather than about a test, so it was left alone.

---

**An intermittent 409, and what was and was not concluded.** Twice during this
phase a test that expects 200 got 409 — once cancelling a purchase whose goods
had been shelved, once re-confirming a reopened order — and passed on the next
run. A 409 can come from three places: a refused status transition, insufficient
stock, or `databaseError.js` mapping a deadlock/lock timeout to
`CONCURRENT_UPDATE`. The captured log could not distinguish them, because a 4xx
was only logged at debug level and the response body was not in the log at all.

Two changes came out of it, and one non-conclusion:

- `stockedSlots` no longer reads `FOR UPDATE`. That range scan took gap locks
  across the index while `ensureSlot` inserted into the same gaps, which is a
  deadlock class — and it bought nothing, because the lock that prevents
  overselling is the per-slot one `adjustStock` takes anyway. A new test
  (two orders racing for the last of the stock) pins that invariant down.
- A `CONCURRENT_UPDATE` 409 is now logged at warn level, with the error, since
  it means contention in our own transactions rather than a client mistake. The
  affected tests also print the response body on failure now.
- **The cause was not proven.** It has not recurred in 18 stress runs since, and
  restoring the lock for 8 more runs did not reproduce it either, so the gap-lock
  explanation is plausible and unconfirmed. If it returns, the log will now name
  it.

---

## 5. Shared allocation

`src/modules/inventory/allocation.js` is new, and is where "which slots does
this quantity move through" now lives for every module. It was extracted rather
than copied because sales, purchase reversals, returns and production runs all
ask the same question, and the answer is not obvious: stock is tracked per slot
(§11's shelves), so an outbound move has to be planned across the slots that
actually hold the goods, fullest first, and an inbound move has to go back to
the slots the ledger says it came from, in the quantities it left in.

It returns a plan and moves nothing itself. Each leg still goes through
`adjustStock`, so the level and the ledger move together and §47 governs every
leg.

---

## 6. Verification

| Check | Result |
|---|---|
| `npm test` (backend) | 269 passing — 62 new: 21 purchases, 20 returns, 20 production, and one each for reopening and for two orders racing for the same stock |
| `flutter analyze` | No issues found |
| `flutter test` | 160 passing |
| Live run against the running server | 204 checks over HTTP, every mounted module, all passing |

The live run drives the deployed process the way a business would — register,
get approved, log in, build master data, stock it, sell it, take payment, cancel
it, buy more, receive it, return some, produce more — and deletes every row it
created. It lives in the session scratchpad rather than the repository, because
it needs a running server and is not part of `npm test`.

---

## 7. Phase boundary

Not built, and not started:

- **Frontend wiring.** Every screen for these three modules exists and still
  reads demo data. One `Api*Repository` per module, swapped in at one
  `Provider` each, is the whole job — no screen or widget changes.
- **Stock transfers as documents.** `POST /api/inventory/transfer` moves stock
  today, but the `stock_transfers` tables Phase 3 created are unused, and
  `docs/frontend-backend-contract-notes.md` expects `GET/POST
  /api/stock-transfers`.
- **Reports, PDF, notifications, backup, custom fields** (§25, §28, §31, §33,
  §51) — later phases.
