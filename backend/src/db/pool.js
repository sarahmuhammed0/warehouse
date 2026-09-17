// Database connection foundation (Phase 0).
//
// A single mysql2/promise pool, created once and reused everywhere. This
// file is the *only* place that knows how to reach MySQL — no other module
// constructs its own connection.
//
// IMPORTANT: this must point at the isolated MySQL 8.x instance (see root
// docker-compose.yml + /docs/environment.md), never at the pre-existing
// local MariaDB install. The connection details below come entirely from
// backend/.env (DB_HOST/DB_PORT/...), which is why that file's comments
// call this out explicitly.

import mysql from "mysql2/promise";
import { env } from "../config/env.js";
import { logger } from "../utils/logger.js";

export const pool = mysql.createPool({
  host: env.db.host,
  port: env.db.port,
  database: env.db.database,
  user: env.db.user,
  password: env.db.password,
  waitForConnections: true,
  connectionLimit: env.db.connectionLimit,
  connectTimeout: env.db.connectTimeoutMs,
  namedPlaceholders: true,
});

/**
 * Used by the /api/health/db route (and safe to call from anywhere else that
 * needs a fast, side-effect-free "is the database actually reachable" check).
 * Never throws — always resolves to a result object so a down database can
 * never crash a request path that merely wants to report its status.
 */
export async function checkDatabaseConnection() {
  try {
    const [rows] = await pool.query("SELECT VERSION() AS version");
    return {
      reachable: true,
      version: rows?.[0]?.version ?? null,
      host: env.db.host,
      port: env.db.port,
      database: env.db.database,
    };
  } catch (error) {
    logger.warn({ err: error }, "Database health check failed");
    return {
      reachable: false,
      host: env.db.host,
      port: env.db.port,
      database: env.db.database,
      error: error.code || error.message,
    };
  }
}

/**
 * The one place a multi-statement write is wrapped in a transaction
 * (architecture §13/§29). `fn` receives a checked-out connection — every
 * query inside it must use that connection, not the shared `pool`
 * directly, or it won't be part of the transaction. Commits on success,
 * rolls back and rethrows on any error; the connection is always released
 * back to the pool either way.
 *
 * @template T
 * @param {(conn: import('mysql2/promise').PoolConnection) => Promise<T>} fn
 * @returns {Promise<T>}
 */
export async function runInTransaction(fn) {
  const conn = await pool.getConnection();
  try {
    await conn.beginTransaction();
    const result = await fn(conn);
    await conn.commit();
    return result;
  } catch (error) {
    await conn.rollback();
    throw error;
  } finally {
    conn.release();
  }
}

export async function closePool() {
  await pool.end();
}
