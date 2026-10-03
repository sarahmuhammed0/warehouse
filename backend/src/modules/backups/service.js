// §33, for real: a dump of the database, written to a file, recorded in the
// `backups` table, with old files pruned.
//
// The endpoint used to record a request and write nothing, and said so in its
// own response. That was the honest answer while there was no configured
// target; it is not an acceptable answer for a deployment holding a business's
// stock and money.
//
// Three rules shape everything here:
//
//   1. A row's status is the truth about the FILE. `completed` is written only
//      after the dump exits zero and a non-empty file exists on disk, with its
//      real size. Anything else is `failed`, with the reason.
//   2. The password never appears in a command line. `mysqldump --password=x`
//      is visible in `ps` to every user on the box, so credentials go through
//      a private defaults-file that is created 0600 and deleted afterwards.
//   3. Nothing is deleted until a new backup has succeeded. Pruning first
//      would, on a failing dump, remove the last good copy.

import { spawn } from "node:child_process";
import { once } from "node:events";
import { pipeline } from "node:stream/promises";
import { randomBytes } from "node:crypto";
import { mkdir, writeFile, unlink, stat, readdir, chmod } from "node:fs/promises";
import { createWriteStream } from "node:fs";
import { tmpdir } from "node:os";
import path from "node:path";

import { env } from "../../config/env.js";
import { logger } from "../../utils/logger.js";
import { pool } from "../../db/pool.js";

/** Whether this deployment can take a backup at all. */
export const backupsConfigured = () => Boolean(env.backups.directory);

export const backupsUnconfiguredNote =
  "No backup target is configured. Set BACKUP_DIR to the directory backups should be written to.";

/**
 * A `[mysqldump]` defaults-file holding the credentials, created 0600 in the
 * system temp directory and removed in a `finally`.
 *
 * This exists so the password is never an argument. `--password=` on the
 * command line is readable by any user who can run `ps`, and ends up in shell
 * history and process accounting.
 */
async function writeDefaultsFile() {
  const file = path.join(tmpdir(), `warehouse-os-dump-${randomBytes(8).toString("hex")}.cnf`);
  const contents = [
    "[client]",
    `host=${env.db.host}`,
    `port=${env.db.port}`,
    `user=${env.db.user}`,
    `password=${env.db.password}`,
    "",
  ].join("\n");

  // 0600 at creation. Writing then chmod-ing leaves a window where the file is
  // world-readable, so the mode is passed to writeFile — and set again after,
  // because on some platforms the process umask still applies.
  await writeFile(file, contents, { mode: 0o600 });
  try {
    await chmod(file, 0o600);
  } catch {
    // Windows has no POSIX modes. The temp directory is per-user there.
  }
  return file;
}

/** `warehouse-os-<db>-2026-10-03T02-00-00.sql` */
function filenameFor(now) {
  const stamp = now.toISOString().replace(/[:.]/g, "-").replace(/Z$/, "");
  return `warehouse-os-${env.db.database}-${stamp}.sql`;
}

/**
 * Runs mysqldump into [destination]. Resolves on a clean exit, rejects with
 * mysqldump's own stderr otherwise.
 *
 * `--single-transaction` so the dump is consistent without locking the whole
 * database — this runs against a live instance that people are using.
 */
async function runMysqldump({ defaultsFile, destination }) {
  const args = [
      `--defaults-extra-file=${defaultsFile}`,
      "--single-transaction",
      "--quick",
      // Routines and triggers, yes. EVENTS, no — and not because they would be
      // unwanted but because `--events` requires the EVENT privilege, and this
      // schema has none to dump. Asking for them would mean granting the app
      // user a privilege it does not otherwise need, to copy nothing.
      "--routines",
      "--triggers",
      // Skips the tablespace query, which needs the global PROCESS privilege —
      // the right to see every other connection on the server. A least-
      // privileged application user should not hold that, and a logical restore
      // of this schema does not use the information.
      "--no-tablespaces",
      // The dump should recreate the schema as well as the rows: a backup that
      // restores only data into a database whose tables no longer exist is not
      // a backup.
      "--add-drop-table",
      "--default-character-set=utf8mb4",
      env.db.database,
    ];

  const child = spawn(env.backups.mysqldumpPath, args, { windowsHide: true });

  let stderr = "";
  child.stderr.on("data", (chunk) => {
    // Bounded: a dump that complains about every row would otherwise buffer its
    // whole output into memory.
    if (stderr.length < 8000) stderr += chunk.toString();
  });

  const killTimer = setTimeout(() => child.kill("SIGKILL"), env.backups.timeoutMs);
  let timedOut = false;
  killTimer.unref?.();
  const timeoutWatcher = setTimeout(() => {
    timedOut = true;
  }, env.backups.timeoutMs);
  timeoutWatcher.unref?.();

  try {
    // `pipeline`, not `child.stdout.pipe(output)` with a hand-rolled completion
    // check. `pipe` ENDS the destination when the source ends, so by the time a
    // "close" handler ran, the stream's "finish" had already fired — and waiting
    // for it again hung the process for ever, with a complete file sitting on
    // disk. Found by running it rather than by reading it.
    //
    // pipeline resolves when the bytes are flushed and destroys both sides on
    // failure, which is also what stops a failed dump leaking a file handle.
    // `spawn` reports a missing binary through "error", which never produces a
    // "close" — so it has to be RACED against the work, not awaited alongside
    // it. A promise that only ever rejects cannot be one of the arms of a
    // Promise.all: the all never settles on success and the process hangs with
    // a finished file on disk, which is exactly what happened here first.
    const failedToStart = new Promise((_, reject) =>
      child.once("error", (error) =>
        reject(
          new Error(
            error.code === "ENOENT"
              ? `mysqldump was not found at "${env.backups.mysqldumpPath}". Set MYSQLDUMP_PATH.`
              : error.message
          )
        )
      )
    );

    const dumped = (async () => {
      const [closed] = await Promise.all([
        once(child, "close"),
        pipeline(child.stdout, createWriteStream(destination)),
      ]);
      return closed[0];
    })();

    const exitCode = await Promise.race([dumped, failedToStart]);

    if (timedOut) {
      throw new Error(`mysqldump did not finish within ${env.backups.timeoutMs}ms and was stopped.`);
    }
    if (exitCode !== 0) {
      throw new Error(stderr.trim() || `mysqldump exited with code ${exitCode}.`);
    }
  } finally {
    clearTimeout(killTimer);
    clearTimeout(timeoutWatcher);
  }
}

/**
 * Deletes all but the newest [keepLast] completed backups, files and rows
 * together.
 *
 * Only ever called AFTER a successful dump. Pruning first would mean a failing
 * backup deletes the last good one.
 */
async function prune() {
  const keep = Math.max(1, env.backups.keepLast);
  const [rows] = await pool.query(
    `SELECT id, filename FROM backups
      WHERE status = 'completed'
      ORDER BY COALESCE(completed_at, created_at) DESC, id DESC`
  );

  for (const row of rows.slice(keep)) {
    const file = path.join(env.backups.directory, path.basename(row.filename));
    try {
      await unlink(file);
    } catch (error) {
      // Already gone is the outcome we wanted. Anything else is worth knowing
      // about, but must not fail the backup that just succeeded.
      if (error.code !== "ENOENT") {
        logger.warn({ err: error, file }, "Could not delete an expired backup file");
        continue;
      }
    }
    await pool.query(`DELETE FROM backups WHERE id = ?`, [row.id]);
  }
}

/**
 * Takes a backup and updates its row to `completed` or `failed`.
 *
 * Deliberately does not throw: the caller is either an HTTP request that has
 * already been answered 202, or the scheduler. The ROW is how the outcome is
 * reported, which is also what makes the history trustworthy — every attempt
 * leaves a record, including the ones that failed.
 *
 * @param {number} backupId a row already inserted as `running`
 */
export async function performBackup(backupId) {
  const started = Date.now();
  let defaultsFile = null;
  const destination = path.join(env.backups.directory, path.basename(await filenameForRow(backupId)));

  try {
    await mkdir(env.backups.directory, { recursive: true });
    defaultsFile = await writeDefaultsFile();
    await runMysqldump({ defaultsFile, destination });

    const { size } = await stat(destination);
    if (size === 0) throw new Error("mysqldump produced an empty file.");

    await pool.query(
      `UPDATE backups SET status = 'completed', size_bytes = ?, completed_at = NOW(), error_message = NULL
        WHERE id = ?`,
      [size, backupId]
    );
    logger.info({ backupId, size, ms: Date.now() - started }, "Backup completed");

    await prune();
    return { ok: true, size };
  } catch (error) {
    // The partial file is removed: a truncated .sql sitting next to the good
    // ones is the thing someone restores from at 3am.
    try {
      await unlink(destination);
    } catch {
      /* it may never have been created */
    }

    await pool.query(
      `UPDATE backups SET status = 'failed', completed_at = NOW(), error_message = ? WHERE id = ?`,
      [String(error.message).slice(0, 1000), backupId]
    );
    logger.error({ err: error, backupId }, "Backup failed");
    return { ok: false, error: error.message };
  } finally {
    if (defaultsFile) {
      try {
        await unlink(defaultsFile);
      } catch {
        /* best effort — it is 0600 in the temp directory */
      }
    }
  }
}

async function filenameForRow(backupId) {
  const [rows] = await pool.query(`SELECT filename FROM backups WHERE id = ?`, [backupId]);
  return rows[0]?.filename ?? filenameFor(new Date());
}

/** Inserts the row for an attempt about to start, and returns its id. */
export async function recordAttempt({ triggerType, userId = null, now = new Date() }) {
  const [result] = await pool.query(
    `INSERT INTO backups (filename, trigger_type, status, started_at, created_by)
     VALUES (?, ?, 'running', NOW(), ?)`,
    [filenameFor(now), triggerType, userId]
  );
  return result.insertId;
}

/** The absolute path of a completed backup, for the download endpoint. */
export function filePathFor(filename) {
  // basename, always: the filename comes from a database row, and a row is not
  // a trusted source of a path. `../../etc/passwd` must not be able to leave
  // the backup directory.
  return path.join(env.backups.directory, path.basename(filename));
}

/** Files present in the backup directory, for reconciling against the table. */
export async function filesOnDisk() {
  if (!backupsConfigured()) return [];
  try {
    return (await readdir(env.backups.directory)).filter((f) => f.endsWith(".sql"));
  } catch (error) {
    if (error.code === "ENOENT") return [];
    throw error;
  }
}
