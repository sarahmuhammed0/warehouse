import { Router } from "express";

import { authenticate } from "../../middleware/authenticate.js";
import { requireAccountType } from "../../middleware/requireAccountType.js";
import { authorize } from "../../middleware/authorize.js";
import { validate } from "../../middleware/validate.js";
import { listQuerySchema } from "../../validation/common.js";
import { ok, paginated } from "../../utils/responseEnvelope.js";
import { parsePagination, paginationMeta } from "../../db/pagination.js";
import { listAuditLogs, listAuditActions } from "./repository.js";

const tenant = (req) => req.auth.businessId;

const view = (row) => ({
  id: row.id,
  actorType: row.actor_type,
  actorId: row.actor_id,
  // A system event (a public self-registration) has no actor by design, and
  // shows as such rather than as an anonymous user.
  actorName: row.actor_name ?? null,
  module: row.module,
  action: row.action,
  description: row.description,
  ipAddress: row.ip_address,
  referenceType: row.reference_type,
  referenceId: row.reference_id,
  createdAt: row.created_at,
});

export const auditRouter = Router();
auditRouter.use(authenticate, requireAccountType("business_user"));

/**
 * READ ONLY, and deliberately so: §30's trail is evidence, and an endpoint that
 * could add to it or amend it would make it worthless. Rows are written by
 * `middleware/auditTrail.js` and the auth module, as a side effect of the action
 * they describe.
 *
 * Gated on `settings.view`, which by default only the owner role holds. The
 * trail names who did what across every module — a warehouse clerk needs their
 * own work, not a log of everyone else's. §24 has no module of its own for it,
 * and settings is where §34 puts administration.
 */
auditRouter.get("/", authorize("settings.view"), validate(listQuerySchema, "query"), async (req, res, next) => {
  try {
    const pagination = parsePagination(req.query);
    const { rows, total } = await listAuditLogs({
      businessId: tenant(req),
      query: req.query,
      pagination,
    });
    res.json(paginated(rows.map(view), paginationMeta(pagination, total)));
  } catch (err) {
    next(err);
  }
});

/** What this business has actually recorded, for the screen's filter list. */
auditRouter.get("/actions", authorize("settings.view"), async (req, res, next) => {
  try {
    const rows = await listAuditActions({ businessId: tenant(req) });
    res.json(
      ok(
        rows.map((row) => ({
          module: row.module,
          action: row.action,
          total: Number(row.total),
        }))
      )
    );
  } catch (err) {
    next(err);
  }
});
