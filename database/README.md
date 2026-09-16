# Database — deliberately empty in Phase 0

Per Phase 0's explicit scope, no production schema is created yet — this
directory only reserves the structure the approved architecture calls for
(§4 Repository Structure, §5 Database Design):

```
database/
  migrations/   forward-only, one change per file — created starting Phase 1
  seeds/
    system/     roles, permissions, business-type→module defaults, units
    demo/       optional seed data (§65), never auto-run in production
```

What Phase 0 *does* set up: the isolated MySQL 8.x instance itself (root
`docker-compose.yml`) and the backend's connection to it — see
`/docs/environment.md`. The database it creates (`warehouse_os_dev`) starts
empty; no tables exist until Phase 1's Products/Categories/Users work
begins.
