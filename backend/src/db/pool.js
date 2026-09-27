// Database connection foundation.
//
// A single mysql2/promise pool, created once and reused everywhere. This
// file is the *only* place that knows how to reach MySQL — no other module
// constructs its own connection.
//
// IMPORTANT: this must point at the project's own MySQL 8.x instance (see
// /docs/environment.md), never at the pre-existing local MariaDB install.
// The connection details below come entirely from backend/.env
// (DB_HOST/DB_PORT/...), which is why that file's comments call this out
// explicitly.

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
  // DECIMAL columns arrive as strings by default so that a value the
  // database stores exactly is not handed to JavaScript as a float that
  // cannot represent it. Money is DECIMAL(14,2) throughout this schema
  // (§61's financial correctness), and `0.1 + 0.2 !== 0.3` is not a
  // property any invoice total should have. Callers that need arithmetic
  // use a decimal-aware path; callers that only pass the value through —
  // most of them — keep full precision for free.
  decimalNumbers: false,
  // Prevents multiple statements in one call, which removes the class of
  // injection where a bound query is turned into two (§35).
  multipleStatements: false,
  // `affectedRows` on an UPDATE must mean "rows MATCHED", not MySQL's own
  // default of "rows CHANGED": every repository here reads `affectedRows === 1`
  // as "that row exists" and turns 0 into a 404, so under CHANGED semantics a
  // PATCH writing the values a row already holds would answer "not found".
  //
  // mysql2 sets this flag itself today, so this line changes nothing — it is
  // here to PIN the behaviour those 404s depend on, rather than leaving it to
  // a driver default that a future version could reasonably revisit.
  flags: ["FOUND_ROWS"],
  // Keeps DATE/DATETIME as strings rather than JS Date objects, so a date
  // does not silently shift when the process timezone differs from the
  // business's (§13's timezone strategy — see docs/backend-phase3.md).
  dateStrings: true,
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
 * (architecture §13, spec §46).
 *
 * `fn` receives a checked-out connection — every query inside it MUST use
 * that connection, not the shared `pool`, or it will not be part of the
 * transaction and will not roll back with it. That is the single easiest
 * mistake to make here, which is why the parameter is the connection rather
 * than the callback taking none.
 *
 * Commits on success; rolls back and rethrows on any error, so a caller
 * never has to remember to. The connection is released either way, even if
 * the rollback itself fails — a leaked connection would eventually exhaust
 * the pool and take the whole process down, which is worse than the error
 * that caused it.
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
    try {
      await conn.rollback();
    } catch (rollbackError) {
      // The original error is the one worth propagating; a failed rollback
      // is usually a symptom of the same lost connection.
      logger.error({ err: rollbackError }, "Rollback failed after a transaction error");
    }
    throw error;
  } finally {
    conn.release();
  }
}

/**
 * Runs `fn` with a dedicated connection but NO transaction — for the rare
 * read that needs several statements to see the same session state (a
 * temporary table, a session variable). Prefer `pool.query` for ordinary
 * reads, which needs no checkout at all.
 *
 * @template T
 * @param {(conn: import('mysql2/promise').PoolConnection) => Promise<T>} fn
 * @returns {Promise<T>}
 */
export async function withConnection(fn) {
  const conn = await pool.getConnection();
  try {
    return await fn(conn);
  } finally {
    conn.release();
  }
}

/**
 * `SELECT` returning at most one row, or null.
 *
 * Exists so the `rows[0] ?? null` dance is not repeated in every
 * repository, and so the parameterised form is the shortest one to write —
 * §21's rule is that runtime queries use placeholders, and the easiest path
 * should be the safe path.
 *
 * @param {string} sql               with `?` placeholders — never interpolation
 * @param {unknown[]} [params]
 * @param {import('mysql2/promise').PoolConnection} [conn] inside a transaction
 */
export async function queryOne(sql, params = [], conn = pool) {
  const [rows] = await conn.query(sql, params);
  return Array.isArray(rows) && rows.length > 0 ? rows[0] : null;
}

/**
 * `SELECT` returning every row.
 *
 * @param {string} sql
 * @param {unknown[]} [params]
 * @param {import('mysql2/promise').PoolConnection} [conn]
 */
export async function queryAll(sql, params = [], conn = pool) {
  const [rows] = await conn.query(sql, params);
  return Array.isArray(rows) ? rows : [];
}

/**
 * The `COUNT(*)` half of a paginated list (§26). Takes the same WHERE and
 * parameters as the page query so the total can never describe a different
 * filter than the rows.
 *
 * @param {string} sql   e.g. "SELECT COUNT(*) AS total FROM products p WHERE ..."
 * @param {unknown[]} [params]
 * @param {import('mysql2/promise').PoolConnection} [conn]
 */
export async function queryCount(sql, params = [], conn = pool) {
  const row = await queryOne(sql, params, conn);
  return Number(row?.total ?? 0);
}

export async function closePool() {
  await pool.end();
}
