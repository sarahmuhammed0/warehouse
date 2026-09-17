// Knex is used ONLY for schema migrations (its `knex.schema.*` builder) —
// per docs/database-access-strategy.md's Phase 0 decision, all runtime
// application queries go through `mysql2/promise` directly
// (`src/db/pool.js`), never through Knex's query builder or an ORM. This
// file exists solely so `npx knex migrate:*` has somewhere to read
// connection settings and the migrations directory from.
//
// Reads the same environment variables as the app itself (backend/.env) —
// one source of truth for "which database," never a second, hand-typed
// connection string.

import "dotenv/config";

const connection = {
  host: process.env.DB_HOST || "127.0.0.1",
  port: Number(process.env.DB_PORT) || 3307,
  database: process.env.DB_NAME || "warehouse_os_dev",
  user: process.env.DB_USER || "warehouse_app",
  password: process.env.DB_PASSWORD || "",
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
