# Business modules — deliberately empty in Phase 0

Per the approved architecture (§10 Module Architecture), each business module
(Products, Categories, Inventory, Sales, Orders, Customers, Suppliers,
Purchases, Production, Users, Reports, …) gets its own folder here, each
containing:

```
modules/<name>/
  routes.js       thin — parses params, calls the controller
  controller.js   translates HTTP ⇄ service call, no business logic
  service.js      owns business rules, opens transactions
  repository.js   parameterized SQL, always WHERE business_id = :tenant
  validation.js   request-schema validation for this module
```

Nothing is created here yet. Phase 0's scope is project foundation only —
see `/docs/environment.md` and the root `README.md` for what Phase 0
actually delivers, and the approved architecture document for the full
phase-by-phase roadmap.
