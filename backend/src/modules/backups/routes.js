import { Router } from "express";

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
 * So the row is created as `pending` with an honest note, the endpoint answers
 * 202 rather than 201, and §33 is left with a recorded intent that an operator's
 * job can pick up. `docs/backend-phase9.md` records what completing it needs.
 */
backupsRouter.post("/", async (req, res, next) => {
  try {
    const stamp = new Date().toISOString().replace(/[:.]/g, "-");
    const filename = `warehouse-os-${stamp}.sql`;

    const [result] = await pool.query(
      `INSERT INTO backups (filename, trigger_type, status, started_at, error_message, created_by)
       VALUES (?, 'manual', 'pending', NOW(), ?, ?)`,
      [
        filename,
        "Requested. No dump has been taken: this deployment has no configured backup target.",
        req.auth.userId,
      ]
    );

    const [rows] = await pool.query(`SELECT * FROM backups WHERE id = ?`, [result.insertId]);
    res.status(202).json(
      ok({
        ...view(rows[0]),
        // Unambiguous, because a client that showed this as done would be lying
        // to whoever is relying on it.
        fileProduced: false,
        note: "Recorded as requested. No file has been written — configure a backup target to complete it.",
      })
    );
  } catch (err) {
    next(err);
  }
});

/**
 * Restore is deliberately absent.
 *
 * It is the most destructive operation in the system — it replaces every
 * tenant's data — and there is nothing to restore FROM while no dump is being
 * taken. An endpoint that accepted the request and did nothing would be worse
 * than none at all: it would be relied upon in exactly the moment it was needed.
 */
backupsRouter.post("/:id/restore", validate(idParamsSchema, "params"), async (req, res, next) => {
  try {
    throw errors.validation(
      "Restore is not available in this deployment. No backup target is configured, so there is no dump to restore from."
    );
  } catch (err) {
    next(err);
  }
});
