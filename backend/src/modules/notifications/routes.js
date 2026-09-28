import { Router } from "express";

import { authenticate } from "../../middleware/authenticate.js";
import { requireAccountType } from "../../middleware/requireAccountType.js";
import { validate } from "../../middleware/validate.js";
import { idParamsSchema, listQuerySchema } from "../../validation/common.js";
import { ok, paginated } from "../../utils/responseEnvelope.js";
import { parsePagination, paginationMeta } from "../../db/pagination.js";
import { errors } from "../../utils/AppError.js";
import * as repo from "./repository.js";

const tenant = (req) => req.auth.businessId;

const view = (row) => ({
  id: row.id,
  type: row.notification_type,
  title: row.title,
  body: row.body,
  referenceType: row.reference_type,
  referenceId: row.reference_id,
  isRead: row.read_at !== null,
  readAt: row.read_at,
  createdAt: row.created_at,
});

export const notificationsRouter = Router();
notificationsRouter.use(authenticate, requireAccountType("business_user"));

/**
 * NOT permission-gated, deliberately — and this is the one module where that is
 * the right answer.
 *
 * A notification is addressed to whoever is working: "stock has run out" is for
 * the person on the floor, and gating it behind `inventory.view` would silence
 * it for the salesperson who is about to promise that stock to a customer. The
 * rows carry no figures beyond the event itself, they are scoped to the
 * business, and each one links to a record the reader still has to have
 * permission to open. There is no write endpoint: notifications are RAISED by
 * the events that cause them (see triggers.js), never posted by a client.
 */
notificationsRouter.get("/", validate(listQuerySchema, "query"), async (req, res, next) => {
  try {
    const pagination = parsePagination(req.query);
    const { rows, total } = await repo.listNotifications({
      businessId: tenant(req),
      userId: req.auth.userId,
      query: req.query,
      pagination,
      unreadOnly: req.query.unread === "true",
    });
    res.json(paginated(rows.map(view), paginationMeta(pagination, total)));
  } catch (err) {
    next(err);
  }
});

/** The badge. Its own endpoint because a header asks for it on every screen. */
notificationsRouter.get("/unread-count", async (req, res, next) => {
  try {
    res.json(
      ok({
        unread: await repo.unreadCount({ businessId: tenant(req), userId: req.auth.userId }),
      })
    );
  } catch (err) {
    next(err);
  }
});

notificationsRouter.patch("/read-all", async (req, res, next) => {
  try {
    const marked = await repo.markAllRead({ businessId: tenant(req), userId: req.auth.userId });
    res.json(ok({ marked }));
  } catch (err) {
    next(err);
  }
});

notificationsRouter.patch("/:id/read", validate(idParamsSchema, "params"), async (req, res, next) => {
  try {
    const businessId = tenant(req);
    const marked = await repo.markRead({ businessId, userId: req.auth.userId, id: req.params.id });

    // Zero rows means either "already read" or "not yours". Only the second is a
    // 404, so the two are told apart rather than both answered the same way.
    if (marked === 0 && !(await repo.notificationExists({ businessId, id: req.params.id }))) {
      throw errors.notFound("notification");
    }
    res.json(ok({ id: Number(req.params.id), isRead: true }));
  } catch (err) {
    next(err);
  }
});
