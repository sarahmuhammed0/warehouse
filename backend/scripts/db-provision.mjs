// Creates the development database and the application's MySQL user.
//
// Run once, by a human, on a machine where the MySQL administrator password
// is known:
//
//     cd backend
//     npm run db:provision
//
// It prompts for the administrator password (input is hidden and is never
// written to disk, to a log, or to shell history) and reads everything else
// — host, port, database name, app user, app password — from `backend/.env`
// via `src/config/env.js`. That is deliberate: the credential the app will
// later authenticate with has exactly one source of truth, so provisioning
// cannot quietly create a user with a different password than the app uses.
//
// What it does, and nothing more:
//   1. CREATE DATABASE <DB_NAME>  utf8mb4 / utf8mb4_0900_ai_ci
//   2. CREATE USER <DB_USER>@localhost and @127.0.0.1
//   3. GRANT the data/DDL privileges the app and its migrations need —
//      scoped to <DB_NAME>.* only, never *.*
//
// It is idempotent: re-running it re-asserts the same grants and resets the
// app user's password to the one in .env.
//
// SAFETY: it only ever connects to DB_HOST:DB_PORT. It issues no statement
// that touches any other server, any other schema, or the `mysql` system
// database beyond creating/granting this one user. It never drops anything.

import mysql from "mysql2/promise";
import { env } from "../src/config/env.js";
import { readHidden } from "./lib/read-hidden.mjs";

// `readHidden` lives in scripts/lib/ because `admin:create` needs the same
// prompt, and the chunked-input and backspace handling inside it is too subtle
// to keep two copies of.

// Identifiers cannot be parameterized, so they are validated against a
// strict pattern and then backtick-quoted — never interpolated raw.
function identifier(value, label) {
  if (!/^[A-Za-z0-9_]+$/.test(value)) {
    throw new Error(`Refusing to use ${label} "${value}": expected only letters, digits and underscores.`);
  }
  return `\`${value}\``;
}

const { host, port, database, user, password } = env.db;

if (!password) {
  console.error("DB_PASSWORD is empty in backend/.env — set it before provisioning.");
  process.exit(1);
}

const db = identifier(database, "DB_NAME");

console.log(`Provisioning on ${host}:${port}`);
console.log(`  database  ${database}`);
console.log(`  app user  ${user}`);
console.log("");

let admin;
try {
  // Non-secret configuration, read through the same module as everything
  // else. The administrator PASSWORD is deliberately not configuration: it
  // exists only in the local variable below, only while this process runs.
  const { adminUser, useSsl } = env.provisioning;
  const adminPassword = await readHidden(`MySQL password for '${adminUser}'@${host}:${port}: `);

  admin = await mysql.createConnection({
    host,
    port,
    user: adminUser,
    password: adminPassword,
    connectTimeout: 8000,
    // Provisioning talks to a local server over loopback; allow the
    // caching_sha2_password handshake to fetch the server's public key
    // rather than failing when the connection is not TLS.
    ...(useSsl ? { ssl: {} } : {}),
  });

  const [[serverInfo]] = await admin.query("SELECT VERSION() AS version, @@port AS port");
  console.log(`Connected to MySQL ${serverInfo.version} on port ${serverInfo.port}.`);
  if (String(serverInfo.version).toLowerCase().includes("mariadb")) {
    throw new Error(
      "This server reports MariaDB. This project must use MySQL 8.x on its own port — refusing to provision."
    );
  }

  await admin.query(
    `CREATE DATABASE IF NOT EXISTS ${db} CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci`
  );
  console.log(`database ${database} ready (utf8mb4 / utf8mb4_0900_ai_ci).`);

  // Both hosts: mysql2 resolves "127.0.0.1" to the '127.0.0.1' account,
  // while some clients present as 'localhost' over a socket. Creating both
  // avoids an "access denied" that depends on how the client connected.
  for (const fromHost of ["localhost", "127.0.0.1"]) {
    await admin.query(`CREATE USER IF NOT EXISTS ?@? IDENTIFIED BY ?`, [user, fromHost, password]);
    await admin.query(`ALTER USER ?@? IDENTIFIED BY ?`, [user, fromHost, password]);
    // Exactly the privileges the application and its migrations need, on
    // this schema only. No GRANT OPTION, no SUPER, no access to any other
    // schema — §3's "only the intended development database access".
    await admin.query(
      `GRANT SELECT, INSERT, UPDATE, DELETE, CREATE, DROP, ALTER, INDEX, REFERENCES,
              CREATE TEMPORARY TABLES, LOCK TABLES, EXECUTE, CREATE VIEW, SHOW VIEW
         ON ${db}.* TO ?@?`,
      [user, fromHost]
    );
    console.log(`user ${user}@${fromHost} ready, granted on ${database}.* only.`);
  }

  await admin.query("FLUSH PRIVILEGES");
  console.log("\nDone. Next: `npm run migrate` then `npm run db:verify`.");
} catch (error) {
  console.error(`\nFAILED: ${error.code || error.name}: ${error.message}`);
  process.exitCode = 1;
} finally {
  if (admin) await admin.end();
}
