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
