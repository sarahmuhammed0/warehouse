#!/usr/bin/env node
// Check that a backup file is worth keeping, without restoring it.
//
// A file with bytes in it is not a backup. The failures that matter are quiet
// ones: a dump truncated when a disk filled, or one that completed against a
// connection that could only see half the schema. Both leave a large, plausible
// .sql file that nobody discovers is useless until the morning they need it.
//
// So this checks the three things that can be checked cheaply:
//
//   1. mysqldump's own completion trailer is present — it is written last, so
//      its absence means the file was cut short.
//   2. every table in the live database has a CREATE TABLE in the dump.
//   3. every table that currently HAS rows has data in the dump.
//
// It does not prove the dump restores. Nothing short of restoring it does, and
// that needs a scratch database — see docs/deployment.md, "Rehearsing a restore".
//
// Usage:
//   node scripts/db-verify-backup.mjs <backup-file.sql>
//   node scripts/db-verify-backup.mjs --latest     (newest file in BACKUP_DIR)

import { createReadStream } from "node:fs";
import { readdir, stat } from "node:fs/promises";
import { createInterface } from "node:readline";
import path from "node:path";

import { env } from "../src/config/env.js";
import { pool, closePool } from "../src/db/pool.js";

const RESET = "\u001b[0m";
const RED = "\u001b[31m";
const GREEN = "\u001b[32m";
const YELLOW = "\u001b[33m";

const say = (m = "") => console.log(m); // eslint-disable-line no-console

async function newestBackup() {
  if (!env.backups.directory) {
    say(`${RED}✗ BACKUP_DIR is not set, so there is no --latest.${RESET}`);
    process.exit(1);
  }
  const files = (await readdir(env.backups.directory)).filter((f) => f.endsWith(".sql"));
  if (files.length === 0) {
    say(`${RED}✗ No .sql files in ${env.backups.directory}.${RESET}`);
    process.exit(1);
  }
  const withTimes = await Promise.all(
    files.map(async (f) => {
      const full = path.join(env.backups.directory, f);
      return { full, mtime: (await stat(full)).mtimeMs };
    })
  );
  withTimes.sort((a, b) => b.mtime - a.mtime);
  return withTimes[0].full;
}

const arg = process.argv[2];
if (!arg) {
  say("Usage: node scripts/db-verify-backup.mjs <backup-file.sql> | --latest");
  process.exit(1);
}

const file = arg === "--latest" ? await newestBackup() : path.resolve(arg);

let size;
try {
  size = (await stat(file)).size;
} catch {
  say(`${RED}✗ ${file} does not exist.${RESET}`);
  process.exit(1);
}

say(`Verifying ${file}`);
say(`  ${size.toLocaleString()} bytes`);
say();

// Streamed, a line at a time: a dump of a real database does not belong in
// memory, and these checks never need more than the current line.
const created = new Set();
const withInserts = new Set();
let completedTrailer = false;

const reader = createInterface({ input: createReadStream(file), crlfDelay: Infinity });
for await (const line of reader) {
  if (line.startsWith("CREATE TABLE")) {
    const match = line.match(/CREATE TABLE (?:IF NOT EXISTS )?`([^`]+)`/);
    if (match) created.add(match[1]);
  } else if (line.startsWith("INSERT INTO")) {
    const match = line.match(/INSERT INTO `([^`]+)`/);
    if (match) withInserts.add(match[1]);
  } else if (line.startsWith("-- Dump completed on")) {
    completedTrailer = true;
  }
}

const [liveTables] = await pool.query(
  `SELECT table_name AS name FROM information_schema.tables
    WHERE table_schema = ? AND table_type = 'BASE TABLE'`,
  [env.db.database]
);
const live = liveTables.map((r) => r.name);

const [nonEmpty] = await pool.query(
  // `rows` is a reserved word in MySQL 8 and cannot be a bare alias.
  `SELECT table_name AS name, table_rows AS row_estimate FROM information_schema.tables
    WHERE table_schema = ? AND table_type = 'BASE TABLE' AND table_rows > 0`,
  [env.db.database]
);
await closePool();

const problems = [];

if (!completedTrailer) {
  problems.push(
    "The dump has no completion trailer. mysqldump writes it last, so this file was cut short — do not rely on it."
  );
}

const missingSchema = live.filter((t) => !created.has(t));
if (missingSchema.length) {
  problems.push(`Tables in the database but not in the dump: ${missingSchema.join(", ")}`);
}

// `table_rows` is an estimate for InnoDB, so this is a warning and not a
// failure: a table it claims has rows may genuinely be empty.
const suspiciouslyEmpty = nonEmpty.map((r) => r.name).filter((t) => !withInserts.has(t));

say(`  completion trailer   ${completedTrailer ? `${GREEN}present${RESET}` : `${RED}MISSING${RESET}`}`);
say(`  tables in dump       ${created.size} (database has ${live.length})`);
say(`  tables with data     ${withInserts.size}`);
say();

if (suspiciouslyEmpty.length) {
  say(`${YELLOW}⚠ No rows dumped for: ${suspiciouslyEmpty.join(", ")}${RESET}`);
  say(`  InnoDB row counts are estimates, so these may really be empty. Worth a look.`);
  say();
}

if (problems.length) {
  for (const problem of problems) say(`${RED}✗ ${problem}${RESET}`);
  process.exit(1);
}

say(`${GREEN}✓ The dump is complete and covers every table in ${env.db.database}.${RESET}`);
say(`  This does not prove it restores. Rehearse that once, into a scratch`);
say(`  database — see docs/deployment.md.`);
