// The nightly backup.
//
// A plain interval rather than a cron dependency: one daily job does not
// justify a scheduling library, and a library would hide the two things that
// actually matter here — that a missed window is not silently skipped, and that
// two instances of the API do not both dump at 02:00.

import { env } from "../../config/env.js";
import { logger } from "../../utils/logger.js";
import { pool } from "../../db/pool.js";
import { backupsConfigured, performBackup, recordAttempt } from "./service.js";

/** How often the window is checked. A minute is finer than any schedule here. */
const TICK_MS = 60 * 1000;

let timer = null;

function minuteOfDay(date) {
  return date.getHours() * 60 + date.getMinutes();
}

/**
 * Whether a scheduled backup has already been taken today.
 *
 * Asked of the DATABASE, not of a variable in this process, for two reasons: a
 * restart must not cause a second dump, and two API instances sharing one
 * database must not both run one. The row is the lock.
 */
async function alreadyRanToday() {
  const [rows] = await pool.query(
    `SELECT id FROM backups
      WHERE trigger_type = 'scheduled' AND DATE(started_at) = CURDATE()
      LIMIT 1`
  );
  return rows.length > 0;
}

async function tick() {
  try {
    const now = new Date();
    const target = env.backups.scheduleMinuteOfDay;
    const current = minuteOfDay(now);

    // A window rather than an equality check. An equality check misses the
    // backup entirely if the process happens to be busy or restarting during
    // that one minute; a window catches up afterwards, and `alreadyRanToday`
    // is what stops it running twice.
    if (current < target) return;
    if (await alreadyRanToday()) return;

    logger.info({ at: now.toISOString() }, "Starting the scheduled backup");
    const backupId = await recordAttempt({ triggerType: "scheduled", now });
    await performBackup(backupId);
  } catch (error) {
    // Never throws: an unhandled rejection in a timer takes the process down,
    // and a failed backup must not stop the API serving.
    logger.error({ err: error }, "The scheduled backup could not be started");
  }
}

/** Starts the nightly job, if this deployment has one. */
export function startBackupScheduler() {
  if (!env.backups.scheduleEnabled) {
    logger.info("Scheduled backups are off (BACKUP_SCHEDULE is not \"true\").");
    return;
  }
  if (!backupsConfigured()) {
    // Loud, because someone asked for scheduled backups and will otherwise
    // believe they have them.
    logger.warn("BACKUP_SCHEDULE is on but BACKUP_DIR is not set — no backup will be taken.");
    return;
  }

  const hh = String(Math.floor(env.backups.scheduleMinuteOfDay / 60)).padStart(2, "0");
  const mm = String(env.backups.scheduleMinuteOfDay % 60).padStart(2, "0");
  logger.info({ at: `${hh}:${mm}`, directory: env.backups.directory }, "Scheduled backups are on");

  timer = setInterval(tick, TICK_MS);
  // Must not hold the process open on its own: a shutdown should not wait up to
  // a minute for a timer that is only polling.
  timer.unref?.();
}

export function stopBackupScheduler() {
  if (timer) clearInterval(timer);
  timer = null;
}
