# Phase 9 — the rest of the backend

The endpoints that had no API: staff and roles, the activity log, variants,
stock transfers as documents, the Settings sections, reports, notifications, PDF
documents, custom fields, backups, and the System Admin's business management.

With this, **every module the specification names has a backend**. What remains
is frontend wiring for the modules added here, and the operational work §33
needs — both listed at the end.

---

## 1. What was built

| Area | Endpoints |
|---|---|
| Staff (§23) | `GET/POST /api/users`, `GET/PATCH/DELETE /api/users/:id`, `POST /api/users/:id/password` |
| Roles & permissions (§24) | `GET /api/roles`, `GET /api/roles/permissions`, `POST /api/roles`, `PATCH /api/roles/:id`, `PUT /api/roles/:id/permissions`, `DELETE /api/roles/:id` |
| Activity log (§30) | `GET /api/audit-logs`, `GET /api/audit-logs/actions` |
| Variants (§9) | `GET/POST /api/products/:id/variants`, `PATCH/DELETE /api/products/:id/variants/:variantId` |
| Transfers as documents (§11) | `GET/POST /api/stock-transfers`, `GET /api/stock-transfers/:id`, `PATCH /api/stock-transfers/:id/status` |
| Business profile (§34) | `GET/PATCH /api/business` |
| Document numbering (§29) | `GET /api/documents/numbering`, `PATCH /api/documents/numbering/:type` |
| Settings keys (§34/§43/§44) | four new keys on `GET/PATCH /api/settings` |
| Reports (§25) | `GET /api/reports` + eleven reports |
| Notifications (§31) | `GET /api/notifications`, `/unread-count`, `PATCH /:id/read`, `/read-all` |
| PDF (§28) | `GET /api/orders/:id/pdf`, `GET/PUT /api/documents/pdf-template` |
| Custom fields (§51) | `GET/POST /api/custom-fields`, `PATCH/DELETE /:id`, `GET/PUT /api/{products,customers,suppliers}/:id/custom-fields` |
| Backups (§33) | `GET/POST /api/admin/backups`, `GET /:id` |
| Admin business management (§57) | `GET/PUT /api/admin/businesses/:id`, `PATCH /:id/status`, `POST /:id/reset-password`, `GET /:id/reports` |

Four migrations, every one of them prompted by a test rather than planned:
`users.email`; a phone unique among **live** users only; `products.reorder_level`
and `min_stock` nullable; and §55's line snapshots on purchases and returns
(Phase 7).

---

## 2. Decisions worth recording

**A setting is only added if something honours it.** The catalogue records, per
key, *where* — and a test asserts every key carries that note and that changing
the value changes behaviour. A setting that stores cleanly and does nothing is
the worst outcome available here, because the business believes it has
configured something, and the PATCH returns 200 either way.

**The login lockout threshold is deliberately not a setting.** It looks like an
obvious one, and the Settings screen offers it. It cannot be honoured without
weakening §7: the lockout is checked *before* the phone is resolved to an
account, precisely so a locked-out response is identical whether or not the
phone belongs to anyone. Reading a per-business threshold means looking the
account up first, and a business that locks out after three attempts would then
behave observably differently from an unknown number — an account-enumeration
side-channel. The uniformity is the security property.

**Permissions are data, replaced as a whole set.** A permission editor saves a
grid; two calls that must both succeed to leave a coherent role is how a role
ends up half-granted. An unknown key is refused, and the INSERT joins the
catalogue so it could not be stored even if it were not. The owner role cannot
be narrowed, renamed or deleted — it is what a business falls back on to
administer itself, and a box accidentally unticked would remove the only account
that could tick it again.

**Role management is `users.*`, not a permission of its own.** §24 has no roles
module, and the authority is the same: anyone who can edit roles can grant
themselves anything. Inventing a narrower permission would make that authority
look smaller than it is.

**The activity log has no write path.** Evidence a client can add to is not
evidence. Rows are written by the trail middleware and the auth module as a side
effect of the action they describe.

**`in_transit` is not a stock state.** Modelling goods as "left the source but
not arrived" would need a third place for them to sit that every report would
then have to know about. The stock belongs to the source until it arrives; the
document says it is travelling.

**Notifications are raised by events, never posted.** Five triggers, each inside
the transaction that causes it, so a notification cannot describe something that
was rolled back — and none of them can throw, because the stock movement is the
fact and the message is only a message about it. They are de-duplicated while
unread: stock is checked on every movement, so one afternoon of picking would
otherwise bury the list under a hundred identical rows.

**Notifications are the one module with no permission gate.** "Stock has run
out" is for whoever is working, and gating it behind `inventory.view` would
silence it for the salesperson about to promise that stock. Each row links to a
record the reader still needs permission to open.

**A money report needs `financial.view`, and is refused rather than blanked.**
§23 gives financial figures to the owner and the accountant. Returning a report
with the numbers stripped would leave a reader unsure whether zero meant zero,
so the whole report is refused — and the index endpoint says so in advance, so
nothing appears on screen that then 403s.

**The PDF is built from the document, and computes nothing.** Every figure is
the order's own stored value and every name is §55's snapshot, so a reprint a
year later says what it says today — a test asserts two renders are identical
byte for byte, excluding two fields that describe the *file* rather than the
invoice: the trailer's `/ID`, which the PDF spec requires to be unique per
file, and `CreationDate`, which is when that copy was produced.

That assertion took two goes to get right, and both mistakes are worth
recording. It originally compared only the two renders' *length* — which would
pass with every figure on the page changed — and was caught by a live check
comparing actual bytes. The replacement excluded `/ID` but not `CreationDate`,
so it then failed whenever the two renders happened to straddle a second
boundary: a property of the clock, not of the document.

A generator that re-adds the lines its own way is how a customer ends up
holding paper the system disagrees with.

**A custom field's key and type are immutable.** Values are filed under the key
and read according to the type, so changing either would silently reinterpret
everything already recorded. Retiring a field hides it and **keeps** its values:
a business that stopped collecting something has not decided it never happened.

---

## 3. What is deliberately incomplete, and why

**§33's backup takes no dump.** The endpoint records the request as `pending`,
answers **202** with `fileProduced: false` and a note, and restore refuses
outright. Taking a real dump means running `mysqldump` against the live instance
and writing somewhere durable — decisions about credentials, disk, retention and
where the file may live that belong to whoever operates the deployment. Guessing
would produce the worst available outcome: a UI reporting a successful backup
while no recoverable file exists.

*To complete it:* a configured target (path or object store plus credentials, via
`env.js`), a worker that runs the dump and updates the row to `completed` with
its size, and a retention rule. Restore additionally needs a confirmation
mechanism far stronger than an API call, because it replaces every tenant's data.

**The profit report is cash-basis, and says so in its own response.** Revenue is
what was sold in the period; cost is what was bought in it. A true
cost-of-goods-sold needs the cost of each item *at the moment it sold*, and
`order_items` snapshots the selling price (§55) but not the cost. Using today's
purchase cost for a sale made a year ago would silently restate old profit every
time a supplier changed a price.

*To complete it:* a `unit_cost` column on `order_items`, filled at the same
moment as `unit_price` from the product's cost then. New orders would carry it;
older ones would not, so the report would have to say which period it can answer
accurately — which is worth doing deliberately rather than retrofitting a
guess.

**Session timeout is not a per-business setting.** The Settings screen offers
one. It is the access token's TTL, which is set when the token is signed and
lives in `env.js`; making it per business means resolving the business during
token issuance and is a change to the auth path rather than a settings key.

---

## 4. Verification

| Check | Result |
|---|---|
| `npm test` (backend) | 359 passing |
| Migrations | 7 batches, applied in order, each reversible |

Everything above has tests, and the ones worth naming are the refusals: a
business cannot disable its own last owner; a role in use cannot be deleted from
under its holders; a granted permission takes effect on a token the employee
already holds; a payment method switched off is refused server-side; a numbering
counter cannot move backward; an archived user's phone is freed without
overwriting the record; and neither account type can reach the other's routes.

### Mistakes these tests caught

Worth listing, because each was found rather than avoided:

- Freeing a deleted user's phone by writing a marker into the column overflowed
  `VARCHAR(20)`. The fix was to stop rewriting the number at all and make
  uniqueness apply only to live rows.
- `products.reorder_level` was `NOT NULL DEFAULT 0`, so "no threshold of its own"
  could not be expressed — §44's fallback could never fire, and a product nobody
  configured could run to nothing without appearing in the alert list. The same
  column also rejected the `null` the API accepts and means.
- The new-order notification read the customer's name from the request, which
  only carries an id — every named customer would have been announced as
  "Walk-in".
- The PDF template's `fields` map used `z.record` with an enum key, which is
  exhaustive in zod 4, so every partial save failed for the keys it did not
  mention.
- A comment of mine claimed a business's phone is unique platform-wide, with a
  constraint message to match. The migration says the opposite in as many words.

---

## 5. What is left

- **Frontend wiring** for everything added here. `docs/frontend-wiring.md`
  records the pattern and which modules already read the API.
- **§33's operational work**, as above.
- **Accrual-basis profit**, as above.
