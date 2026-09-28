import { Router } from "express";
import { z } from "zod";
import { randomBytes } from "node:crypto";

import { authenticate } from "../../middleware/authenticate.js";
import { requireAccountType } from "../../middleware/requireAccountType.js";
import { validate, validateRequest } from "../../middleware/validate.js";
import { idParamsSchema, optionalString, enumSchema } from "../../validation/common.js";
import { ok } from "../../utils/responseEnvelope.js";
import { errors } from "../../utils/AppError.js";
import { toAppError } from "../../utils/databaseError.js";
import { pool, runInTransaction, queryAll } from "../../db/pool.js";
import { hashPassword } from "../../utils/password.js";
import { getClientIp } from "../../utils/requestInfo.js";
import { writeAuditLog } from "../auth/repository.js";

/**
 * §57's System Admin actions that Phase 2 left out: editing a business, changing
 * its status, resetting an owner's password, and looking at one tenant's figures.
 *
 * The boundary this file has to hold is the one §36 exists for. A System Admin
 * has no `business_id` of their own, so every query here names the business
 * explicitly, and nothing in it is reachable by a business user — the router is
 * `system_admin` only, and the business-side routes remain scoped to the
 * caller's own session.
 */

const tenant = (req) => req.params.id;

const businessView = (row) => ({
  id: row.id,
  name: row.name,
  businessType: row.business_type,
  phone: row.phone,
  email: row.email,
  address: row.address,
  city: row.city,
  country: row.country,
  currency: row.currency,
  language: row.language,
  timezone: row.timezone,
  status: row.status,
  logoUrl: row.logo_url,
  taxNumber: row.tax_number,
  registrationNumber: row.registration_number,
  createdAt: row.created_at,
  updatedAt: row.updated_at,
  approvedAt: row.approved_at,
  rejectedAt: row.rejected_at,
  rejectionReason: row.rejection_reason,
});

const BUSINESS_TYPES = [
  "furniture_factory",
  "general_factory",
  "warehouse",
  "storage_store",
  "wholesale_store",
  "distribution_center",
  "custom",
];

const updateSchema = z
  .object({
    name: optionalString(150),
    businessType: enumSchema(BUSINESS_TYPES, "Business type").optional(),
    /**
     * Editable HERE and not on the business's own profile route.
     *
     * It is the number a System Admin rings about a registration, so correcting
     * it is an administrative act rather than self-service. It is deliberately
     * NOT unique — the migration that created the column says so outright, and
     * it is right: the credential is `users.phone`, which IS unique, and two
     * businesses run by the same family from the same landline are a real thing.
     */
    phone: optionalString(20),
    email: optionalString(255),
    address: optionalString(255),
    city: optionalString(100),
    country: optionalString(100),
    currency: z.string().trim().length(3).transform((v) => v.toUpperCase()).optional(),
    language: optionalString(10),
    timezone: optionalString(64),
    taxNumber: optionalString(100),
    registrationNumber: optionalString(100),
  })
  .refine((value) => Object.values(value).some((v) => v !== undefined), {
    message: "Provide at least one field to update.",
  });

const statusSchema = z.object({
  // `pending` and `rejected` are the registration queue's own states, set by
  // approving or rejecting — not by this route, which would skip the record of
  // who decided and why.
  status: enumSchema(["active", "disabled"], "Status"),
  reason: optionalString(500),
});

const COLUMNS = {
  name: "name",
  businessType: "business_type",
  phone: "phone",
  email: "email",
  address: "address",
  city: "city",
  country: "country",
  currency: "currency",
  language: "language",
  timezone: "timezone",
  taxNumber: "tax_number",
  registrationNumber: "registration_number",
};

export const adminBusinessRouter = Router();
adminBusinessRouter.use(authenticate, requireAccountType("system_admin"));

/** One business in full, with the owner and a few counts to orient by. */
adminBusinessRouter.get("/:id", validate(idParamsSchema, "params"), async (req, res, next) => {
  try {
    const [rows] = await pool.query(`SELECT * FROM businesses WHERE id = ? AND deleted_at IS NULL LIMIT 1`, [
      tenant(req),
    ]);
    if (rows.length === 0) throw errors.notFound("business");

    const [[counts]] = await pool.query(
      `SELECT
         (SELECT COUNT(*) FROM users u WHERE u.business_id = b.id AND u.deleted_at IS NULL) AS users,
         (SELECT COUNT(*) FROM products p WHERE p.business_id = b.id AND p.deleted_at IS NULL) AS products,
         (SELECT COUNT(*) FROM orders o WHERE o.business_id = b.id AND o.deleted_at IS NULL) AS orders
       FROM businesses b WHERE b.id = ?`,
      [tenant(req)]
    );

    const [owners] = await pool.query(
      `SELECT id, name, phone, status, last_login_at FROM users
        WHERE business_id = ? AND is_owner = TRUE AND deleted_at IS NULL ORDER BY id LIMIT 1`,
      [tenant(req)]
    );

    res.json(
      ok({
        ...businessView(rows[0]),
        counts: {
          users: Number(counts.users),
          products: Number(counts.products),
          orders: Number(counts.orders),
        },
        owner: owners[0]
          ? {
              id: owners[0].id,
              name: owners[0].name,
              phone: owners[0].phone,
              status: owners[0].status,
              lastLoginAt: owners[0].last_login_at,
            }
          : null,
      })
    );
  } catch (err) {
    next(err);
  }
});

/** §57's Edit. */
adminBusinessRouter.put(
  "/:id",
  validateRequest({ params: idParamsSchema, body: updateSchema }),
  async (req, res, next) => {
    try {
      const businessId = tenant(req);
      const sets = [];
      const params = [];
      for (const [key, column] of Object.entries(COLUMNS)) {
        if (req.body[key] === undefined) continue;
        sets.push(`${column} = ?`);
        params.push(req.body[key]);
      }

      await runInTransaction(async (conn) => {
        const [result] = await conn.query(
          `UPDATE businesses SET ${sets.join(", ")}, updated_at = NOW() WHERE id = ? AND deleted_at IS NULL`,
          [...params, businessId]
        );
        if (result.affectedRows === 0) throw errors.notFound("business");
      });

      await writeAuditLog({
        businessId,
        actorType: "system_admin",
        actorId: req.auth.userId,
        module: "businesses",
        action: "business.updated",
        description: `Business details edited by a System Admin: ${Object.keys(req.body).join(", ")}.`,
        ip: getClientIp(req),
        referenceType: "business",
        referenceId: businessId,
      });

      const [rows] = await pool.query(`SELECT * FROM businesses WHERE id = ? LIMIT 1`, [businessId]);
      res.json(ok(businessView(rows[0])));
    } catch (err) {
      next(toAppError(err, { constraintMessages }) ?? err);
    }
  }
);

/**
 * §57's enable/disable. "Delete" means this, per the approved decision — a
 * business is never truly removed in-app, because its documents, its stock
 * history and its staff records all still reference it.
 *
 * Disabling revokes every session the business's users hold. Without that, a
 * business switched off keeps working until its tokens expire, which is not what
 * anyone pressing the button expects.
 */
adminBusinessRouter.patch(
  "/:id/status",
  validateRequest({ params: idParamsSchema, body: statusSchema }),
  async (req, res, next) => {
    try {
      const businessId = tenant(req);
      const { status, reason } = req.body;

      const [existing] = await pool.query(
        `SELECT status FROM businesses WHERE id = ? AND deleted_at IS NULL LIMIT 1`,
        [businessId]
      );
      if (existing.length === 0) throw errors.notFound("business");

      await runInTransaction(async (conn) => {
        await conn.query(`UPDATE businesses SET status = ?, updated_at = NOW() WHERE id = ?`, [
          status,
          businessId,
        ]);

        if (status === "disabled") {
          await conn.query(
            `DELETE rt FROM refresh_tokens rt
               JOIN users u ON u.id = rt.user_id
              WHERE u.business_id = ?`,
            [businessId]
          );
        }
      });

      await writeAuditLog({
        businessId,
        actorType: "system_admin",
        actorId: req.auth.userId,
        module: "businesses",
        action: status === "disabled" ? "business.disabled" : "business.enabled",
        description: reason
          ? `Business ${status} by a System Admin: ${reason}`
          : `Business ${status} by a System Admin.`,
        ip: getClientIp(req),
        referenceType: "business",
        referenceId: businessId,
      });

      const [rows] = await pool.query(`SELECT * FROM businesses WHERE id = ? LIMIT 1`, [businessId]);
      res.json(ok(businessView(rows[0])));
    } catch (err) {
      next(toAppError(err) ?? err);
    }
  }
);

/**
 * §57's "Reset password", for the case the self-service endpoint cannot serve:
 * the owner cannot sign in to change a password they have forgotten.
 *
 * The new password is returned ONCE, for the administrator to pass on by
 * whatever channel they already use. It is not emailed — there is no mail
 * transport in this system, and inventing one silently would be worse than
 * handing the value back. It is stored only as a hash (§3), and every session
 * the owner held is revoked: if the reason for the reset is that someone else
 * had the old password, leaving their session alive defeats it.
 */
adminBusinessRouter.post(
  "/:id/reset-password",
  validateRequest({
    params: idParamsSchema,
    body: z.object({
      password: z.string().min(8, "A password must be at least 8 characters.").optional(),
      userId: z.coerce.number().int().positive().optional(),
    }),
  }),
  async (req, res, next) => {
    try {
      const businessId = tenant(req);

      // The owner by default; a named user if the administrator says so, so a
      // locked-out employee can be helped without touching the owner's account.
      const [targets] = await pool.query(
        req.body.userId
          ? `SELECT id, name, phone FROM users WHERE id = ? AND business_id = ? AND deleted_at IS NULL LIMIT 1`
          : `SELECT id, name, phone FROM users
              WHERE business_id = ? AND is_owner = TRUE AND deleted_at IS NULL ORDER BY id LIMIT 1`,
        req.body.userId ? [req.body.userId, businessId] : [businessId]
      );
      if (targets.length === 0) throw errors.notFound("user");
      const target = targets[0];

      const generated = req.body.password ? null : randomBytes(9).toString("base64url");
      const password = req.body.password ?? generated;
      const passwordHash = await hashPassword(password);

      await runInTransaction(async (conn) => {
        await conn.query(`UPDATE users SET password_hash = ?, updated_at = NOW() WHERE id = ?`, [
          passwordHash,
          target.id,
        ]);
        await conn.query(`DELETE FROM refresh_tokens WHERE user_id = ?`, [target.id]);
      });

      await writeAuditLog({
        businessId,
        actorType: "system_admin",
        actorId: req.auth.userId,
        module: "businesses",
        action: "business.password_reset",
        // The password itself is never written here, or anywhere else: a password
        // in a log is a password in every backup of that log.
        description: `Password reset for ${target.name} by a System Admin.`,
        ip: getClientIp(req),
        referenceType: "user",
        referenceId: target.id,
      });

      res.json(
        ok({
          userId: target.id,
          name: target.name,
          phone: target.phone,
          ...(generated ? { temporaryPassword: generated } : {}),
          sessionsRevoked: true,
        })
      );
    } catch (err) {
      next(toAppError(err) ?? err);
    }
  }
);

/**
 * §57's per-business figures, for a System Admin looking at one tenant.
 *
 * A deliberate, separate endpoint rather than letting an admin token through the
 * business routes: those resolve their tenant from the SESSION (§36), and making
 * them accept a business id would turn every one of them into a cross-tenant
 * read waiting for a bug. This one names the business in its path, returns
 * counts and totals only, and is the only place an admin sees inside a tenant.
 */
adminBusinessRouter.get("/:id/reports", validate(idParamsSchema, "params"), async (req, res, next) => {
  try {
    const businessId = tenant(req);
    const [exists] = await pool.query(`SELECT id FROM businesses WHERE id = ? AND deleted_at IS NULL`, [
      businessId,
    ]);
    if (exists.length === 0) throw errors.notFound("business");

    const [[summary]] = await pool.query(
      `SELECT
         (SELECT COUNT(*) FROM users WHERE business_id = ? AND deleted_at IS NULL) AS users,
         (SELECT COUNT(*) FROM products WHERE business_id = ? AND deleted_at IS NULL) AS products,
         (SELECT COUNT(*) FROM customers WHERE business_id = ? AND deleted_at IS NULL) AS customers,
         (SELECT COUNT(*) FROM suppliers WHERE business_id = ? AND deleted_at IS NULL) AS suppliers,
         (SELECT COUNT(*) FROM orders WHERE business_id = ? AND deleted_at IS NULL) AS orders,
         (SELECT COUNT(*) FROM purchases WHERE business_id = ? AND deleted_at IS NULL) AS purchases,
         (SELECT COALESCE(SUM(grand_total), 0) FROM orders
           WHERE business_id = ? AND deleted_at IS NULL
             AND status NOT IN ('draft','pending','cancelled')) AS sales_total,
         (SELECT COALESCE(SUM(quantity), 0) FROM inventory WHERE business_id = ?) AS stock_quantity`,
      Array(8).fill(businessId)
    );

    const recentOrders = await queryAll(
      `SELECT order_number, status, grand_total, order_date FROM orders
        WHERE business_id = ? AND deleted_at IS NULL ORDER BY id DESC LIMIT 5`,
      [businessId]
    );

    res.json(
      ok({
        businessId: Number(businessId),
        counts: {
          users: Number(summary.users),
          products: Number(summary.products),
          customers: Number(summary.customers),
          suppliers: Number(summary.suppliers),
          orders: Number(summary.orders),
          purchases: Number(summary.purchases),
        },
        totals: {
          salesTotal: Number(summary.sales_total),
          stockQuantity: Number(summary.stock_quantity),
        },
        recentOrders: recentOrders.map((row) => ({
          orderNumber: row.order_number,
          status: row.status,
          total: Number(row.grand_total),
          orderDate: row.order_date,
        })),
      })
    );
  } catch (err) {
    next(err);
  }
});

/**
 * Empty on purpose.
 *
 * There is no unique constraint on `businesses` that a client can trip: the
 * phone is not unique (see the schema note above), and the id is generated. An
 * entry here for a constraint that does not exist would be dead code claiming to
 * handle an error that can never arrive — which is how a message ends up being
 * trusted without ever having been produced.
 */
const constraintMessages = {};
