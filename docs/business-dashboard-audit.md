# Business dashboard — PDF §5 compliance and functionality audit

The business dashboard, checked line by line against the requirements PDF's
Section 5 (Dashboard) and Section 6 (Sidebar / main navigation), with every
remaining interactive element verified to work in demo mode.

## What the PDF actually says

Section 5 is short and exact. Quoted from the PDF:

> **5. DASHBOARD**
> After login, show a dashboard customized for that business.
> Dashboard should include: **Main statistics** … **Visual reports** — "Use
> charts for:" … **Quick actions** — "Buttons such as:" …

Three details of the wording matter and are easy to get wrong:

1. The statistics list and the chart list are **not hedged** — statistics
   appear under a bare heading, charts under the imperative *"Use charts
   for:"*. All fifteen statistics and all ten chart subjects are treated
   here as required.
2. Quick actions **are** hedged — *"Buttons such as:"* — so the eight named
   buttons are examples. All eight are implemented anyway; the hedge is what
   licenses treating them as *action shortcuts* rather than a fixed menu.
3. Section 5 **never mentions navigation, modules or links**. Module
   navigation is Section 6's subject (the sidebar's sixteen items).

Section 5 also never mentions alerts, recent activity or notifications.
Those come from elsewhere in the PDF:

- **§44 Inventory alerts** defines Low Stock (*"Current quantity <= reorder
  level"*), Out of Stock (*"Quantity = 0"*) and Overstock (*"Quantity >
  configured maximum"*) and ends: **"Show these on the dashboard."** That
  sentence is the only place the PDF asks for a dashboard alert block, and
  it is why the Alerts section exists.
- **§56** lists "Recent activity" and "System alerts", but for the *System
  Admin* dashboard, not this one.

## The dashboard-vs-sidebar decision

**The PDF is silent on duplication.** It neither requires module tiles on
the dashboard nor forbids them. The split below is therefore a **UX
decision, not a spec requirement**, and is recorded as such:

| | Question it answers |
|---|---|
| Sidebar (§6) | *Where do I go?* |
| Dashboard (§5) | *What is happening?* |

A card reading "Total products → Products" is a second, worse copy of a
sidebar entry that is already one click away. So a KPI is clickable **only
when tapping it investigates that specific number**.

### Two rows, not one wall of fifteen

All fifteen §5 statistics are present, but not all at once. Fifteen
equal-weight cards is a wall of numbers with no shape, and the three or four
that actually need acting on get lost in it.

The headline row is the six figures chosen as the ones a business owner
actually leads with:

> Total products · Total stock quantity · Low stock
> Out of stock · Today's sales · Pending orders

Four of the six drill into their own records. Total products and Total
stock quantity are informational — "all products" is the unfiltered
Products list, and that is the sidebar's job.

The remaining nine (plus profit, when cost data makes it known) are
reference figures: the other totals, the period figures, and the
closed-order counts. They sit behind one tap — a **"More statistics (10)"**
expander on the same page. Nothing is removed, nothing is two clicks away,
and the six that matter are legible at a glance.

Two widget tests hold this in place: one asserts exactly six cards before
expanding and all sixteen after, the other that it collapses again.

## Section order

    Header → Statistics → Alerts → Charts → Recent activity → Quick actions

Quick actions is the **last** major section on the page; nothing follows it
but page padding. The monitoring content — what is happening — comes first,
and the shortcuts sit at the bottom. A widget test measures the real
on-screen `dy` of each section and asserts the order, so it cannot drift.

### KPI cards — where each one lives, and what tapping it does

| Statistic (§5 order) | Shown | Behaviour |
|---|---|---|
| Total products | headline | informational |
| Total categories | collapsed | informational |
| Total stock quantity | headline | informational |
| Low-stock products | headline | → **Inventory**, filtered to low stock |
| Out-of-stock products | headline | → **Inventory**, filtered to out of stock |
| Today's sales | headline | → Sales, filtered to today |
| Today's orders | collapsed | → Orders, filtered to today |
| This month's sales | collapsed | → Sales, filtered to this month |
| Total sales | collapsed | informational |
| Pending orders | headline | → Orders, filtered to Pending |
| Completed orders | collapsed | → Orders, filtered to Completed |
| Cancelled orders | collapsed | → Orders, filtered to Cancelled |
| Returned orders | collapsed | → Orders, filtered to Returned |
| Total customers | collapsed | informational |
| Total suppliers | collapsed | informational |
| Gross profit (when cost data exists) | collapsed | informational |

Low/out-of-stock deliberately open **Inventory**, not Products: the question
behind the number is a stock question and Inventory is where stock is acted
on. Both screens read the same list controller, so the filter applies.

Informational cards carry **no `onTap` at all** rather than a decorative
one — §4's "do NOT make cards clickable just for decoration". A widget test
asserts exactly which cards are which, so this can't silently drift back.

An arriving filter announces itself: Inventory shows a removable chip, and
Orders/Sales have a status+period filter bar. Landing on a filtered subset
with no explanation and no way back would be worse than not filtering.

### What was removed

Seven cards previously navigated to a module with no filter — Total
Products, Total Categories, Total Stock Quantity, Total Sales, Total
Customers, Total Suppliers, and Gross Profit (which opened the Reports
grid). All seven duplicated the sidebar and are now informational. **No
statistic was removed** — §3's requirement that the KPIs stay is met; only
their redundant navigation went.

## Visual reports — all ten §5 subjects

| §5 chart subject | Series plotted |
|---|---|
| Daily sales | last 7 days of quick-sale revenue |
| Weekly sales | last 6 weeks, labelled by week-start |
| Monthly sales | last 6 months |
| Yearly sales | last 3 years |
| Product sales | top 6 products by revenue |
| Category sales | top 6 categories by revenue |
| Stock movement | units moved per movement type |
| Purchases | purchase totals per month |
| Returns | refund totals per month |
| Profit *if cost prices are available* | revenue − cost per month; the tab is **absent** when no product carries a cost, matching the PDF's own condition |

Switching tabs really re-plots — a widget test asserts the bar labels change
between series, not just the selected chip.

The PDF specifies chart *subjects*, never chart *shapes*. These render as
horizontal bars via `SimpleBarChart`, built from plain widgets because the
project deliberately takes no charting dependency.

**The placeholder is gone.** The panel used to render the literal sentence
*"Chart will render here once connected to real data"* in the largest
element on the page, while every number it needed was already in the
repositories.

### Known limitation, stated rather than hidden

Yearly sales shows three bars of which two are honestly zero: the demo
dataset spans a few weeks, so there is no multi-year history to plot.
Weekly sales has the same shape for older weeks. These are real renderings
of real data, not padding.

## Quick actions — all eight, each opening a workflow

| Action | Opens | Saves to |
|---|---|---|
| Add Product | Product create form | `LocalProductRepository` |
| Add Category | Category create dialog | `LocalCategoryRepository` |
| New Sale | Sale workflow | `LocalOrderRepository` (+ stock out) |
| New Order | Order workflow | `LocalOrderRepository` |
| Add Stock | Stock adjustment dialog, with a product picker | product quantity + movement row |
| Add Customer | Customer create dialog | `LocalCustomerRepository` |
| Add Supplier | Supplier create dialog | `LocalSupplierRepository` |
| Generate Report | Reports | — |

These are action shortcuts, not module links: each lands **inside a create
workflow**, not on a list screen. All are permission-gated (§24), so a Sales
Staff identity is not offered "Add product".

Add Stock has no product when opened from the dashboard, so the dialog asks
for one and its Save button is disabled until a product is chosen — rather
than being a silent no-op.

## Alerts (§44)

Low stock, out of stock and overstock come straight from §44's definitions;
pending orders and pending payments are the other two things worth pushing
at an owner. Rows appear only when their count is non-zero, and each drills
into the records behind it. When nothing needs attention the panel says so
rather than showing an empty frame.

## Recent activity

Assembled from real records across modules — stock movements, orders,
returns, purchases and production runs — newest first, each row opening the
record it describes. Nothing is seeded filler: if the demo data has no
returns, none appear.

## Layout

Header → Quick actions → Statistics → Alerts → Charts → Recent activity.

§5's own order is statistics, charts, quick actions; the quick actions sit
near the top because they are shortcuts and burying them under five sections
of reading defeats the point. The PDF does not specify layout or ordering.

## A third rendering bug: every button inside a Wrap was full-width

`AppButton` wrapped its content in a bare `Center`, which fills whatever
width it is offered. Inside a `Row` that is invisible, because a Row hands
its children unbounded main-axis constraints and the button sizes to its
label. Inside a `Wrap` it is not: a Wrap hands each child the full line
width, so every button became a full-width bar stacked one per row.

That affected the dashboard quick actions and the System Admin §57 Controls
row. Fixed once with `widthFactor: expand ? null : 1.0`, so a button
shrink-wraps unless it was deliberately asked to expand. A test measures the
rendered width of all eight quick actions and asserts each is under half the
card width.

## Dead interactions found and fixed

The audit found **no empty callbacks, no TODOs and no "coming soon"** on the
dashboard — those had already been cleared in the previous pass. What it did
find were two genuine rendering bugs, both caught by running the new
responsive tests rather than by reading code:

1. **`OrderFilterBar` overflowed a phone by 243px** — two fixed-width
   dropdowns plus a Clear button in a `Row`. Now a `Wrap`.
2. **`AppDataTable`'s mobile card overflowed by 94px** — the label/value
   `Row` had neither side bounded, so any long value (a customer name, a
   formatted date) ran off the card. Both sides are `Flexible` now; this
   fixes every mobile table in the app, not just the ones the dashboard
   opens.

## Demo-data consistency

Every figure comes from `dashboardMetricsProvider`, which derives all of
them from one snapshot of the same repositories the modules read — nothing
is hard-coded. A test asserts the derived numbers against the repositories
directly: total products equals the product count, low stock equals
`isLowStock`, the order status counts equal the orders with that status, and
total sales equals the summed quick-sale grand totals.

Because the statistics and the drill-down filters read the same source, the
number on a card is by construction the number of rows behind it.

## Verified

- **Responsive** — desktop 1400×900, tablet 800×1000, mobile 390×844. Tests
  render the dashboard at tablet and phone width, assert the statistics,
  alerts and quick actions are all present, and complete a drill-down at
  that width. Both overflows above were found this way.
- **Localization / RTL** — tests render under `ar` and `ku`, assert
  `Directionality` is RTL and that English literals are gone (a card still
  reading "Total products" would mean an unlocalized string).
- **Dark mode** — a test switches `themeModeProvider` to dark and asserts
  every section still renders.

## Still backend-dependent

- **§49 dashboard customization** ("Business admin should be able to
  configure which dashboard cards are displayed") is **not implemented**.
  `DashboardWidgetsController.toggle()` exists with no UI calling it. The
  dashboard no longer hides any §5 statistic behind it, since doing so would
  silently drop a required KPI with no way to restore it.
- Settings do not persist across a restart — there is no backend to save to.
- Chart data is computed client-side over the full record set. Real
  deployments want aggregate endpoints; see
  `docs/frontend-backend-contract-notes.md`.
