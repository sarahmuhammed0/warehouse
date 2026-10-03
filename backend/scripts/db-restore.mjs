#!/usr/bin/env node
// Restore the database from a backup file.
//
// Deliberately a command on the server and not an API endpoint. Restoring
// replaces every business's data in one irreversible step, and an HTTP request
// is the wrong authority for that: a stolen session or a mis-click would destroy
// the platform, and no confirmation dialog guards it when the attacker is the
// one answering the dialog. Running this requires shell access to the machine
// and the ability to read the dump — which is the authority the action deserves.
//
// Usage:
//   node scripts/db-restore.mjs <backup-file.sql>
//   node scripts/db-restore.mjs <backup-file.sql> --yes      (skip the prompt)
//
// What it does, in order:
//   1. refuses unless the API is stopped, so nothing writes mid-restore
//   2. takes a safety dump of the CURRENT database first
//   3. asks for the database name to be typed back, in full
//   4. restores, and tells you where the safety dump is either way

import { spawn } from "node:child_process";
import { createInterface } from "node:readline/promises";
import { randomBytes } from "node:crypto";
import { mkdir, writeFile, unlink, stat, chmod } from "node:fs/promises";
import { createReadStream, createWriteStream } from "node:fs";
import { tmpdir } from "node:os";
import path from "node:path";

import { env } from "../src/config/env.js";

const RESET = "\u001b[0m";
const BOLD = "\u001b[1m";
const RED = "\u001b[31m";
const YELLOW = "\u001b[33m";
const GREEN = "\u001b[32m";

function say(message = "") {
  // eslint-disable-next-line no-console
  console.log(message);
}

function fail(message) {
  // eslint-disable-next-line no-console
  console.error(`${RED}✗ ${message}${RESET}`);
  process.exit(1);
}

async function credentialsFile() {
  const file = path.join(tmpdir(), `warehouse-os-restore-${randomBytes(8).toString("hex")}.cnf`);
  await writeFile(
    file,
    ["[client]", `host=${env.db.host}`, `port=${env.db.port}`, `user=${env.db.user}`, `password=${env.db.password}`, ""].join("\n"),
    { mode: 0o600 }
  );
  try {
    await chmod(file, 0o600);
  } catch {
    /* Windows has no POSIX modes; the temp directory is per-user there. */
  }
  return file;
}

function run(command, args, { stdinFrom, stdoutTo } = {}) {
  return new Promise((resolve, reject) => {
    const child = spawn(command, args, { windowsHide: true });
    let stderr = "";
    child.stderr.on("data", (c) => {
      if (stderr.length < 8000) stderr += c.toString();
    });

    if (stdinFrom) createReadStream(stdinFrom).pipe(child.stdin);
    if (stdoutTo) {
      const out = createWriteStream(stdoutTo);
      child.stdout.pipe(out);
      child.on("close", (code) => {
        out.end();
        out.once("finish", () =>
          code === 0 ? resolve() : reject(new Error(stderr.trim() || `exit ${code}`))
        );
      });
    } else {
      child.on("close", (code) =>
        code === 0 ? resolve() : reject(new Error(stderr.trim() || `exit ${code}`))
      );
    }

    child.on("error", (error) =>
      reject(
        new Error(
          error.code === "ENOENT"
            ? `${command} was not found. Set MYSQLDUMP_PATH (and make sure the mysql client is installed).`
            : error.message
        )
      )
    );
  });
}

/** Is something still serving on the API port? */
async function apiStillRunning() {
  try {
    const response = await fetch(`http://127.0.0.1:${env.server.port}/api/health`, {
      signal: AbortSignal.timeout(1500),
    });
    return response.ok;
  } catch {
    return false;
  }
}

const [fileArg, ...rest] = process.argv.slice(2);
const skipPrompt = rest.includes("--yes");

if (!fileArg) {
  fail("Which file? Usage: node scripts/db-restore.mjs <backup-file.sql>");
}

const source = path.resolve(fileArg);
try {
  const info = await stat(source);
  if (!info.isFile() || info.size === 0) fail(`${source} is not a non-empty file.`);
} catch {
  fail(`${source} does not exist.`);
}

if (await apiStillRunning()) {
  fail(
    `The API is still answering on port ${env.server.port}. Stop it first — restoring underneath a ` +
      `running server leaves whatever it writes during the restore in an inconsistent state.`
  );
}

say(`${BOLD}Restore${RESET}`);
say(`  from      ${source}`);
say(`  into      ${env.db.database} on ${env.db.host}:${env.db.port}`);
say();
say(`${YELLOW}This replaces EVERY business's data in that database.${RESET}`);
say();

const mysqlClient = env.backups.mysqldumpPath.replace(/mysqldump(\.exe)?$/i, (m) =>
  m.toLowerCase().endsWith(".exe") ? "mysql.exe" : "mysql"
);

let safetyCopy = null;
const credentials = await credentialsFile();

try {
  // The safety dump comes BEFORE the prompt, so that saying yes cannot be the
  // thing that loses the current data. If this fails, the restore does not run.
  const directory = env.backups.directory || path.join(process.cwd(), "backups");
  await mkdir(directory, { recursive: true });
  safetyCopy = path.join(
    directory,
    `pre-restore-${env.db.database}-${new Date().toISOString().replace(/[:.]/g, "-").replace(/Z$/, "")}.sql`
  );

  say("Taking a safety copy of the current database first...");
  await run(env.backups.mysqldumpPath, [
    `--defaults-extra-file=${credentials}`,
    "--single-transaction",
    "--quick",
    "--routines",
    "--triggers",
    "--events",
    "--add-drop-table",
    "--default-character-set=utf8mb4",
    env.db.database,
  ], { stdoutTo: safetyCopy });

  const { size } = await stat(safetyCopy);
  if (size === 0) throw new Error("the safety copy came out empty");
  say(`${GREEN}✓${RESET} Safety copy: ${safetyCopy} (${size} bytes)`);
  say();

  if (!skipPrompt) {
    const rl = createInterface({ input: process.stdin, output: process.stdout });
    const typed = await rl.question(`Type the database name (${env.db.database}) to continue: `);
    rl.close();
    if (typed.trim() !== env.db.database) {
      fail("That is not the database name. Nothing was changed.");
    }
  }

  say("Restoring...");
  await run(mysqlClient, [`--defaults-extra-file=${credentials}`, env.db.database], { stdinFrom: source });

  say();
  say(`${GREEN}✓ Restored ${env.db.database} from ${path.basename(source)}${RESET}`);
  say(`  The pre-restore copy is kept at ${safetyCopy}`);
  say(`  Start the API again, then check /api/health/db.`);
} catch (error) {
  say();
  // eslint-disable-next-line no-console
  console.error(`${RED}✗ Restore failed: ${error.message}${RESET}`);
  if (safetyCopy) {
    say(`  The database may be partially restored. The pre-restore copy is at:`);
    say(`    ${safetyCopy}`);
    say(`  Re-run this script against THAT file to get back to where you started.`);
  }
  process.exit(1);
} finally {
  try {
    await unlink(credentials);
  } catch {
    /* best effort — it is 0600 in the temp directory */
  }
}
