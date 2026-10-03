#!/usr/bin/env node
// Take a backup now, from the command line.
//
// The same code path the API and the nightly schedule use — `performBackup` —
// so there is one implementation of "what a backup is" and one place a bug in it
// could hide. This exists for the cases an HTTP request cannot serve: a cron on
// the host, a dump taken before a deployment, or an operator checking that
// backups work at all without having to sign in as a System Admin.
//
// Usage:
//   node scripts/db-backup.mjs
//
// Exits non-zero if the backup fails, so a cron entry or a CI step fails too
// rather than reporting success over a file that was never written.

import { env } from "../src/config/env.js";
import { closePool } from "../src/db/pool.js";
import { backupsConfigured, backupsUnconfiguredNote, performBackup, recordAttempt } from "../src/modules/backups/service.js";

const RESET = "\u001b[0m";
const RED = "\u001b[31m";
const GREEN = "\u001b[32m";

function say(message) {
  // eslint-disable-next-line no-console
  console.log(message);
}

if (!backupsConfigured()) {
  // eslint-disable-next-line no-console
  console.error(`${RED}✗ ${backupsUnconfiguredNote}${RESET}`);
  process.exit(1);
}

say(`Backing up ${env.db.database} to ${env.backups.directory} ...`);

const backupId = await recordAttempt({ triggerType: "manual" });
const result = await performBackup(backupId);
await closePool();

if (!result.ok) {
  // eslint-disable-next-line no-console
  console.error(`${RED}✗ Backup failed: ${result.error}${RESET}`);
  process.exit(1);
}

say(`${GREEN}✓ Backup completed (${result.size} bytes), id ${backupId}${RESET}`);
