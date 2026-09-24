// Knex is used ONLY for schema migrations (its `knex.schema.*` builder) —
// per docs/database-access-strategy.md's Phase 0 decision, all runtime
// application queries go through `mysql2/promise` directly
// (`src/db/pool.js`), never through Knex's query builder or an ORM. This
// file exists solely so `npx knex migrate:*` has somewhere to read
// connection settings and the migrations directory from.
//
// Reads its connection settings from the app's own config module
// (`src/config/env.js`), not from `process.env` directly — one source of
// truth for "which database," never a second, hand-typed connection string,
// and no second set of env-var names and defaults to drift out of step with
// the first. `env.js` loads `backend/.env` itself.

import { env } from "./src/config/env.js";

const connection = {
  host: env.db.host,
  port: env.db.port,
  database: env.db.database,
  user: env.db.user,
  password: env.db.password,
};

/** @type {import('knex').Knex.Config} */
export default {
  client: "mysql2",
  connection,
  migrations: {
    directory: "../database/migrations",
    tableName: "knex_migrations",
    extension: "js",
  },
  seeds: {
    directory: "../database/seeds/system",
  },
};
