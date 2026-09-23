# Database environment — MySQL 8.x

This documents the target database environment per the approved architecture
review ("Database Engine Decision — MySQL vs MariaDB"). It is the answer to
"what are we actually connecting to," kept separate from setup instructions
(root `README.md`).

## Target environment

| | |
|---|---|
| Engine | **MySQL 8.4** (LTS) — `mysql:8.4` official Docker image |
| Isolation method | Docker container, dedicated named volume, dedicated port — see root `docker-compose.yml` |
| Host (from the backend / your machine) | `127.0.0.1` |
| Port | `3307` (host) → `3306` (container) |
| Database name | `warehouse_os_dev` |
| Connection method | `mysql2/promise` connection pool in `backend/src/db/pool.js`, credentials from `backend/.env` |
| App DB user | `warehouse_app` (dedicated, non-root — the backend never connects as root) |

**Port 3307, not 3306, is a deliberate choice** — it guarantees this
container can never collide with the pre-existing local MariaDB instance
(127.0.0.1:3306, MariaDB 10.4.32, the one phpMyAdmin is already pointed at).
That instance is not read from, written to, referenced by, or in any way
required by this project.

## Explicit isolation guarantees

- **Different engine:** MySQL 8.4, not MariaDB — resolves the engine
  decision from the architecture review.
- **Different container/process:** runs inside Docker, entirely separate
  from whatever process serves the existing MariaDB install.
- **Different port:** 3307 vs. the existing install's 3306 — no conflict
  possible even with both running simultaneously.
- **Different credentials:** `warehouse_app` / a password unique to this
  project, defined only in this repo's `.env` files.
- **Different storage:** a dedicated named Docker volume
  (`warehouse_os_mysql_data`), not any path the existing MariaDB install
  uses.
- **Nothing in this repository reads, modifies, or configures the existing
  MariaDB/phpMyAdmin setup.** No commands were run against it; no files
  belonging to it were touched.

## Current verification status

**Not yet verified live in this environment.** Docker (and the WSL2 feature
Docker Desktop needs on Windows) is not installed on this machine — see the
root `README.md`'s "Starting the database" section for exact next steps and
what running `npm run dev:db` will do once Docker is available.

Everything *except* the live database connection has been verified:

| Check | Result |
|---|---|
| Frontend dev server starts | ✅ verified |
| Backend dev server starts | ✅ verified |
| `GET /api/health` (liveness) | ✅ verified |
| `GET /api/health/db` (readiness) | ⏳ correctly reports the database as unreachable — expected, since no MySQL instance is running yet |
| MySQL 8.x container starts | ⏳ blocked on Docker/WSL2 installation |
| Backend → MySQL connection | ⏳ blocked on the above |

Once Docker is available, `npm run dev:db` followed by a re-check of
`GET /api/health/db` is the entire remaining verification — no code changes
are needed, since the backend's DB layer was built against this exact target
from the start.

## Update (Phase 2): the docker-compose path was superseded on this machine

Docker was never installed on this development machine. Instead, Phase 2
discovered a **native Windows service, "MySQL80"**, already running and
listening on `127.0.0.1:3307` — coincidentally the same isolated port this
project's `docker-compose.yml` was already configured to use, and still
entirely separate from the pre-existing MariaDB install on `3306`. The
standard "root, empty password" unconfigured-install case was checked once
(and failed, confirming the instance is genuinely secured); no further
credential guessing was attempted. Rather than guess further, the user was
asked and chose to provision the database and app user themselves, using
the SQL reproduced in `docs/database.md`'s "Engine" section.

**`backend/.env`'s `DB_HOST`/`DB_PORT`/`DB_NAME`/`DB_USER`/`DB_PASSWORD`
values target this native MySQL80 instance**, not a Docker container — the
`docker-compose.yml` file and `npm run dev:db` scripts documented above
remain valid for a machine that does have Docker (or as an alternative to
provisioning the native service by hand), but were not what this specific
environment ended up using. As of the last check performed this phase,
`GET /api/health/db` still reports `DATABASE_UNREACHABLE`
(`ER_ACCESS_DENIED_ERROR` for `warehouse_app`) — see `docs/database.md`'s
"Verification status" for the full honest breakdown.

## Update (Phase 3): the same instance, now with a repeatable way in

Phase 3 changed nothing about the environment itself. The target is still
the native **MySQL80** service on `127.0.0.1:3307`, still configured only
through `backend/.env`, and **MariaDB on 3306 was again never started,
stopped, reconfigured, or connected to**. Worth recording precisely: during
this phase nothing was listening on 3306 at all — a state this phase
neither created nor changed.

What Phase 3 added is a way to finish the provisioning that Phase 2 left
open, without anyone pasting a password into a terminal, a chat log, or a
file:

| Command (in `backend/`) | What it does |
|---|---|
| `npm run db:provision` | Creates `warehouse_os_dev` and the `warehouse_app` user. Prompts for the **administrator** password with hidden input; reads host, port, database, user and the *app* password from `.env`. Refuses to run if the server it reaches identifies itself as MariaDB. |
| `npm run db:verify` | Read-only. Prints the server's own version, port, engine, isolation level, charset, effective user, its grants, and every table with its engine and collation. |

Two details in `db:provision` are deliberate:

- **It reads the app password from `.env` rather than asking for it.** The
  credential the application authenticates with then has exactly one source
  of truth, so provisioning cannot create a user whose password differs from
  the one the app uses — which is a plausible reading of how Phase 2's
  attempt ended up denied.
- **It grants a specific privilege list, not `ALL PRIVILEGES`** — no
  `GRANT OPTION`, no `SUPER`, nothing outside `warehouse_os_dev.*`. This is
  narrower than the SQL recorded in `docs/database.md`, on purpose.

It also validates every identifier it interpolates against
`/^[A-Za-z0-9_]+$/` before quoting it, because a database or user name from
`.env` reaches `CREATE DATABASE` as SQL text and cannot be a bound
parameter.

### Status at the end of Phase 3

`warehouse_app` still cannot connect: `ER_ACCESS_DENIED_ERROR`, so
`GET /api/health/db` still correctly returns 503 `DATABASE_UNREACHABLE`.
Provisioning needs the MySQL administrator password, which only the user
has. Three administrative credentials that the repository itself documents
(the `MYSQL_ROOT_PASSWORD` env value, the root `.env` development password,
and an empty password) were each tried once and denied; no further guessing
was attempted, and the throwaway probe script was deleted rather than
committed.

Running `npm run db:provision` is therefore the one remaining step before
migrations and integration tests can execute — see
`docs/phase3-traceability.md`'s "Live verification status".
