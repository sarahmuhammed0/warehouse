import { Router } from "express";
import { stat } from "node:fs/promises";
import path from "node:path";

import { logger } from "../../utils/logger.js";
import { writeAuditLog } from "../auth/repository.js";
import { getClientIp } from "../../utils/requestInfo.js";
import {
  backupsConfigured,
  backupsUnconfiguredNote,
  filePathFor,
  performBackup,
  recordAttempt,
} from "./service.js";
import { authenticate } from "../../middleware/authenticate.js";
import { requireAccountType } from "../../middleware/requireAccountType.js";
import { validate } from "../../middleware/validate.js";
import { idParamsSchema, listQuerySchema } from "../../validation/common.js";
import { ok, paginated } from "../../utils/responseEnvelope.js";
import { parsePagination, paginationMeta } from "../../db/pagination.js";
import { errors } from "../../utils/AppError.js";
import { pool, queryAll } from "../../db/pool.js";

/**
 * §33's backups — the System Admin's, and nobody else's.
 *
 * A backup here is a dump of the WHOLE database, every tenant in it. That makes
 * it a platform-operations concern, not a business one: a business asking for "my
 * backup" wants an export of its own records, which is a different feature (§25's
 * report exports serve most of it) and must not be served by handing over a file
 * containing every other tenant's data.
 *
 * So this router is `system_admin` only, and `backups` is the one table in the
 * schema with no `business_id` — which is the schema saying the same thing.
 */

const view = (row) => ({
  id: row.id,
  filename: row.filename,
  sizeBytes: row.size_bytes === null ? null : Number(row.size_bytes),
  triggerType: row.trigger_type,
  status: row.status,
  startedAt: row.started_at,
  completedAt: row.completed_at,
  errorMessage: row.error_message,
  createdBy: row.created_by,
  createdAt: row.created_at,
});

export const backupsRouter = Router();
backupsRouter.use(authenticate, requireAccountType("system_admin"));

backupsRouter.get("/", validate(listQuerySchema, "query"), async (req, res, next) => {
  try {
    const pagination = parsePagination(req.query);
    const rows = await queryAll(
      `SELECT * FROM backups ORDER BY id DESC LIMIT ? OFFSET ?`,
      [pagination.pageSize, pagination.offset]
    );
    const [[count]] = await pool.query(`SELECT COUNT(*) AS total FROM backups`);
    res.json(paginated(rows.map(view), paginationMeta(pagination, Number(count.total))));
  } catch (err) {
    next(err);
  }
});

backupsRouter.get("/:id", validate(idParamsSchema, "params"), async (req, res, next) => {
  try {
    const [rows] = await pool.query(`SELECT * FROM backups WHERE id = ? LIMIT 1`, [req.params.id]);
    if (rows.length === 0) throw errors.notFound("backup");
    res.json(ok(view(rows[0])));
  } catch (err) {
    next(err);
  }
});

/**
 * Records a requested backup, and says plainly that nothing has run yet.
 *
 * THIS DOES NOT PRODUCE A FILE, and the response says so rather than implying
 * otherwise. Taking a real dump means running `mysqldump` against the live
 * instance and writing somewhere durable — a decision about credentials, disk,
 * retention and where the file is allowed to live that belongs to whoever
 * operates the deployment, not to a hard-coded path chosen here. Guessing at it
 * would produce the worst possible outcome: a UI that reports a successful
 * backup while no recoverable file exists.
 *
 * Answers 202, not 201: a dump of a live database takes as long as it takes, and
 * holding an HTTP request open for it would make a slow backup look like a
 * broken server. The row is the status, and it is polled or re-listed.
 *
 * `fileProduced` is still in the response, and still means exactly what it says.
 * Where no target is configured it is false and the request is REFUSED rather
 * than recorded — a queue of intents nothing will ever drain is the thing that
 * makes an operator believe they have backups.
 */
backupsRouter.post("/", async (req, res, next) => {
  try {
    if (!backupsConfigured()) {
      throw errors.validation(backupsUnconfiguredNote);
    }

    const backupId = await recordAttempt({ triggerType: "manual", userId: req.auth.userId });
    const [rows] = await pool.query(`SELECT * FROM backups WHERE id = ?`, [backupId]);

    // Recorded in the trail as well as in the backups table. The row says a
    // backup happened; the trail says who asked for it and from where — which is
    // what makes a dump taken at an odd hour something anyone can notice.
    await writeAuditLog({
      actorType: "system_admin",
      actorId: req.auth.userId,
      module: "settings",
      action: "backup.started",
      description: `Started a manual database backup (${rows[0].filename}).`,
      ip: getClientIp(req),
      referenceType: "backups",
      referenceId: backupId,
    });

    // Deliberately not awaited. The dump runs on after the response; its outcome
    // is written to the row either way, and `performBackup` never throws, so
    // there is no unhandled rejection to lose the process to.
    performBackup(backupId).catch((error) =>
      logger.error({ err: error, backupId }, "Backup rejected unexpectedly")
    );

    res.status(202).json(
      ok({
        ...view(rows[0]),
        // The dump is running; nothing restorable exists until the row says
        // `completed`. Saying `true` here would be a guess about the future.
        fileProduced: false,
        note: "Started. The backup is listed as running, and becomes completed once the file is written.",
      })
    );
  } catch (err) {
    next(err);
  }
});

/**
 * The file itself. The only way a dump leaves the server.
 *
 * `completed` only: a `running` row's file is half-written, and handing that over
 * is how someone restores a truncated database. The filename is taken through
 * `basename` on the way to disk, so a row cannot name a path outside the backup
 * directory.
 */
backupsRouter.get("/:id/download", validate(idParamsSchema, "params"), async (req, res, next) => {
  try {
    const [rows] = await pool.query(`SELECT * FROM backups WHERE id = ?`, [req.params.id]);
    const row = rows[0];
    if (!row) throw errors.notFound("backup");

    if (row.status !== "completed") {
      throw errors.validation(
        `That backup is "${row.status}" — only a completed backup has a file that can be downloaded.`
      );
    }

    const file = filePathFor(row.filename);
    try {
      await stat(file);
    } catch {
      // The row says the file exists and it does not. Worth saying plainly
      // rather than sending a 404 that reads like "no such backup".
      throw errors.notFound("backup file");
    }

    // Written to the TRAIL, not only to the application log.
    //
    // This hands one person a file containing every tenant's customers, prices,
    // orders and payment history — the largest single disclosure the system can
    // make. A log line is rotated away and lives outside the database; §30's
    // trail is queryable, is part of the backup itself, and is what the platform
    // activity feed shows. An action of this size should be answerable months
    // later from the data, not from whatever happened to still be in the logs.
    //
    // `businessId` is null because the action belongs to no tenant: the feed
    // renders that as "Platform", which is exactly what it is.
    await writeAuditLog({
      actorType: "system_admin",
      actorId: req.auth.userId,
      module: "settings",
      action: "backup.downloaded",
      description: `Downloaded the full database backup ${path.basename(row.filename)}.`,
      ip: getClientIp(req),
      referenceType: "backups",
      referenceId: row.id,
    });

    logger.warn(
      { backupId: row.id, adminId: req.auth.userId },
      "A full database backup was downloaded"
    );
    res.download(file, path.basename(row.filename));
  } catch (err) {
    next(err);
  }
});

/**
 * Restore stays refused, and now for a better reason than "there is nothing to
 * restore from".
 *
 * It replaces every tenant's data in one irreversible step. An HTTP request is
 * the wrong authority for that: a stolen admin session, a mis-click in a list, a
 * CSRF against a logged-in browser — any of them would destroy the whole
 * platform's data, and no confirmation dialog meaningfully guards it, because
 * the attacker is the one answering the dialog.
 *
 * So it is done from a shell on the machine, by someone who can already read the
 * dump file, with the database named explicitly: `npm run db:restore`. That tool
 * requires the server to be stopped and makes its own safety copy first. See
 * docs/deployment.md, "Restoring".
 */
backupsRouter.post("/:id/restore", validate(idParamsSchema, "params"), async (req, res, next) => {
  try {
    throw errors.validation(
      "Restoring is deliberately not possible over the API — it would replace every business's data on one request. " +
        "Download the backup and run `npm run db:restore` on the server. See docs/deployment.md."
    );
  } catch (err) {
    next(err);
  }
});
