# Architecture — source of truth

> **Recorded deviation (Phase 0):** the frontend technology is **Flutter +
> Dart**, not React.js as the published architecture artifact below and the
> written specification both state. This was an explicit instruction given
> at the start of Phase 0 implementation, after the architecture review's
> approval. It changes §4 (Repository Structure), §27 (Frontend UI/UX
> Architecture), §28 (Responsive Design), and §39/frontend-structure
> sections of the artifact below to their Flutter equivalents — see the
> root `README.md`'s repository structure, `docs/state-management.md`
> (Riverpod, the Flutter equivalent of the artifact's frontend state
> concerns), and `frontend/lib/features/README.md`. Every other decision in
> the artifact (database, backend, multi-tenancy, module architecture,
> security, the six ambiguity resolutions) is unchanged and still in
> effect. The artifact itself has not yet been rewritten for Flutter
> specifics — that's a reasonable follow-up, not done automatically since
> Phase 0's task was building the foundation, not revising the document.

The full architecture & implementation plan (Rev. 1) was reviewed and
**approved** before any code in this repository was written. It lives as a
published document, not copied wholesale into this file, so it stays the
single canonical version as it's updated:

**→ https://claude.ai/code/artifact/8307f402-3121-4ad6-b81d-8c42bcc984e7**

It covers: repository/requirements analysis, system architecture, database
design + ERD, multi-tenant strategy, auth/RBAC, module architecture,
business-type configuration, inventory/transaction logic, sales/order/
production architecture, reporting/PDF/numbering/audit/notifications/search/
barcode/custom-fields, backup strategy, security checklist, performance/
scalability plan, UI/UX design system, API architecture, validation/error
handling, testing strategy, the 9-phase roadmap, and a full requirements
traceability matrix.

## Decisions approved before Phase 0

| Decision | Approved direction |
|---|---|
| Database engine | **MySQL 8.x**, isolated via Docker — not the existing MariaDB 10.4.32 install |
| Sale vs. Order | One `orders` table, `order_type` flag |
| Return → inventory trigger | Restock on `Completed`, not `Approved`; condition-gated |
| Order reopening scope | `Cancelled → Pending` only, permission-gated |
| Raw materials schema | One `products` table, `product_type` flag |
| Multi-warehouse sale source | Explicit `source_location_id`, user-selected |
| Business account deletion | Never a true hard delete in-app — "Delete" means archive/disable |
| Six smaller assumptions | Negative-inventory default, multi-currency, barcode symbology, custom-field storage shape, backup split, unit conversion — see the artifact's "Ambiguities" section for each |

## Phase 1 status

UI/UX design system + responsive application shell — see the root
`README.md`, `docs/ui-architecture.md` (component catalog and conventions),
`docs/localization.md` (RTL/locale approach), and
`docs/phase1-traceability.md` (every requirement's status). Still no
business modules, database schema, or mock data. Phase 2 begins only on
explicit instruction, per the approved roadmap.
