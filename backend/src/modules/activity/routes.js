// "What is new since I last looked" — the counts behind the navigation badges.
//
// One request answers the whole navigation. The alternative, asking each
// module's list endpoint and counting client-side, is a request per nav item on
// every page load, and the client would have to page through rows just to
// discard them. These are `COUNT(*)` with an index-friendly `created_at >`.
//
// EACH ENTITY CARRIES ITS OWN `since`, because each navigation item is marked
// read independently: opening Products must not clear the badge on Orders. So
// the caller sends `?products=<iso>&orders=<iso>` and gets back only what it
// asked for. An entity that is absent from the query is absent from the answer
// rather than being reported as zero — "nothing new" and "did not ask" are
// different facts, and the client distinguishes them.
//
// WHAT IS DELIBERATELY NOT HERE: pending registrations. That badge is a queue
// of decisions, not a record of what arrived — it must NOT clear because an
// administrator looked at the screen, only because the last application was
// decided. It stays in `navIndicatorsProvider`, read from the same provider the
// Registrations screen renders. See the note there.

import { Router } from "express";
import { z } from "zod";

import { authenticate } from "../../middleware/authenticate.js";
import { requireAccountType } from "../../middleware/requireAccountType.js";
import { ok } from "../../utils/responseEnvelope.js";
import { errors } from "../../utils/AppError.js";
import { pool } from "../../db/pool.js";
import { permissionsForUser } from "../rbac/repository.js";

/**
 * One countable thing: the table it lives in, the extra condition that narrows
 * it, and the permission a business user needs before the count is told to
 * them.
 *
 * `soft` marks the tables that carry `deleted_at`; `inventory_movements` is an
 * append-only ledger and has none, so counting `deleted_at IS NULL` there would
 * be a SQL error rather than a no-op.
 */
const BUSINESS_ENTITIES = {
  products: { table: "products", soft: true, permission: "products.view" },
  categories: { table: "categories", soft: true, permission: "categories.view" },
  inventory: { table: "inventory_movements", soft: false, permission: "inventory.view" },
  orders: { table: "orders", soft: true, permission: "orders.view", where: "order_type = 'standard'" },
  sales: { table: "orders", soft: true, permission: "sales.view", where: "order_type = 'quick_sale'" },
  customers: { table: "customers", soft: true, permission: "customers.view" },
  suppliers: { table: "suppliers", soft: true, permission: "suppliers.view" },
  purchases: { table: "purchases", soft: true, permission: "purchases.view" },
  returns: { table: "returns", soft: true, permission: "returns.view" },
  production: { table: "production_orders", soft: true, permission: "production.view" },
  // §24's module is `users`; the navigation calls the screen Employees.
  employees: { table: "users", soft: true, permission: "users.view" },
};

/** The System Admin's nav, counted across every tenant (§57). */
const ADMIN_ENTITIES = {
  businesses: { table: "businesses", soft: true, tenantColumn: null },
  employees: { table: "users", soft: true },
  products: { table: "products", soft: true },
  orders: { table: "orders", soft: true, where: "order_type = 'standard'" },
  sales: { table: "orders", soft: true, where: "order_type = 'quick_sale'" },
};

/**
 * An ISO instant per entity. Anything unparseable is rejected rather than
 * silently treated as "the beginning of time", which would badge every record
 * that has ever existed and look like a broken counter.
 */
function parseSince(query, entities) {
  const asked = {};
  const schema = z.coerce.date();
  for (const key of Object.keys(entities)) {
    const raw = query[key];
    if (raw === undefined) continue;
    const parsed = schema.safeParse(raw);
    if (!parsed.success) throw errors.validation(`"${key}" must be a date.`);
    asked[key] = parsed.data;
  }
  return asked;
}

async function countSince({ entity, since, businessId }) {
  const conditions = ["created_at > ?"];
  const params = [since];

  // A System Admin's `businesses` count has no `business_id` to scope by — the
  // table IS the tenant list. Everything else is scoped when a business asked,
  // and deliberately not when the platform operator did.
  if (businessId !== null && entity.tenantColumn !== null) {
    conditions.push("business_id = ?");
    params.push(businessId);
  }
  if (entity.soft) conditions.push("deleted_at IS NULL");
  if (entity.where) conditions.push(entity.where);

  const [[row]] = await pool.query(
    `SELECT COUNT(*) AS n FROM \`${entity.table}\` WHERE ${conditions.join(" AND ")}`,
    params
  );
  return Number(row.n);
}

export const activityRouter = Router();
activityRouter.use(authenticate, requireAccountType("business_user"));

/**
 * §36: scoped to the caller's own business, always, and never to a business
 * named in the request.
 *
 * Counts are also filtered by what the caller may see. The navigation already
 * hides items a role has no permission for, so a well-behaved client never asks
 * — but "the client would not ask" is not a reason for the server to answer. A
 * Sales Staff asking for `employees` gets no key back, the same as if they had
 * not asked.
 */
activityRouter.get("/counts", async (req, res, next) => {
  try {
    const asked = parseSince(req.query, BUSINESS_ENTITIES);
    const permissions = await permissionsForUser(req.auth.userId);
    const counts = {};

    for (const [key, since] of Object.entries(asked)) {
      const entity = BUSINESS_ENTITIES[key];
      if (!permissions.includes(entity.permission)) continue;
      counts[key] = await countSince({ entity, since, businessId: req.auth.businessId });
    }

    res.json(ok(counts));
  } catch (err) {
    next(err);
  }
});

export const adminActivityCountsRouter = Router();
adminActivityCountsRouter.use(authenticate, requireAccountType("system_admin"));

/** The same question across every tenant — §57's oversight, not operation. */
adminActivityCountsRouter.get("/counts", async (req, res, next) => {
  try {
    const asked = parseSince(req.query, ADMIN_ENTITIES);
    const counts = {};
    for (const [key, since] of Object.entries(asked)) {
      counts[key] = await countSince({ entity: ADMIN_ENTITIES[key], since, businessId: null });
    }
    res.json(ok(counts));
  } catch (err) {
    next(err);
  }
});
