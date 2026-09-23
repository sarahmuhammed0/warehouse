// Prints what the application is actually connected to.
//
// This exists because "the database is fine" is not a claim anyone should
// make from reading a config file. It connects with the very same
// environment the app uses (`src/config/env.js`), then reports the server's
// own answers: version, port, engine, charset, the effective user and its
// grants, and every table with its engine and collation.
//
// Run: npm run db:verify   (from backend/)
//
// Safe to run any time: it only reads. It never creates, alters or drops
// anything, and it touches no server other than the one DB_PORT names.

import { env } from "../src/config/env.js";
import { pool, closePool } from "../src/db/pool.js";

const q = async (sql, params = []) => (await pool.query(sql, params))[0];
const variable = async (name) => {
  const rows = await q("SHOW VARIABLES LIKE ?", [name]);
  return rows[0]?.Value ?? "(unset)";
};

function heading(text) {
  console.log(`\n${text}\n${"-".repeat(text.length)}`);
}

try {
  heading("Target (from backend/.env via src/config/env.js)");
  console.log(`host                    ${env.db.host}`);
  console.log(`port                    ${env.db.port}`);
  console.log(`database                ${env.db.database}`);
  console.log(`user                    ${env.db.user}`);
  console.log(`password                ${env.db.password ? "(set, not printed)" : "(EMPTY)"}`);

  heading("Server identity");
  console.log(`VERSION()               ${(await q("SELECT VERSION() v"))[0].v}`);
  console.log(`version_comment         ${await variable("version_comment")}`);
  console.log(`port                    ${await variable("port")}`);
  console.log(`default_storage_engine  ${await variable("default_storage_engine")}`);
  console.log(`transaction_isolation   ${await variable("transaction_isolation")}`);
  console.log(`foreign_key_checks      ${await variable("foreign_key_checks")}`);

  heading("Schema");
  console.log(`DATABASE()              ${(await q("SELECT DATABASE() d"))[0].d}`);
  console.log(`character_set_database  ${await variable("character_set_database")}`);
  console.log(`collation_database      ${await variable("collation_database")}`);

  heading("Effective user");
  console.log(`CURRENT_USER()          ${(await q("SELECT CURRENT_USER() u"))[0].u}`);
  for (const row of await q("SHOW GRANTS")) {
    console.log(`grant                   ${Object.values(row)[0]}`);
  }

  heading("Tables");
  const tables = await q(
    `SELECT TABLE_NAME, ENGINE, TABLE_COLLATION, TABLE_ROWS
       FROM information_schema.TABLES
      WHERE TABLE_SCHEMA = DATABASE()
      ORDER BY TABLE_NAME`
  );
  if (tables.length === 0) {
    console.log("(none — run `npm run migrate`)");
  } else {
    const width = Math.max(...tables.map((t) => t.TABLE_NAME.length));
    for (const t of tables) {
      console.log(
        `  ${t.TABLE_NAME.padEnd(width)}  ${String(t.ENGINE).padEnd(7)}  ${t.TABLE_COLLATION}`
      );
    }
    console.log(`\n${tables.length} table(s).`);
    const nonInnodb = tables.filter((t) => t.ENGINE !== "InnoDB");
    if (nonInnodb.length > 0) {
      console.log(
        `WARNING: not InnoDB, so not transactional: ${nonInnodb.map((t) => t.TABLE_NAME).join(", ")}`
      );
    }
  }
} catch (error) {
  console.error(`\nFAILED: ${error.code || error.name}: ${error.message}`);
  process.exitCode = 1;
} finally {
  await closePool();
}
