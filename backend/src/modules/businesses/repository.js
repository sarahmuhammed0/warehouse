import { pool, runInTransaction, queryAll, queryCount } from "../../db/pool.js";
import { defineListSpec, buildWhere, buildOrderBy } from "../../db/listQuery.js";
import { createDefaultRoles, findOwnerRoleId } from "../rbac/repository.js";

/**
 * The admin's business list, including the registration queue. Column names
 * come from here and never from the request — see src/db/listQuery.js for
 * why that is the whole design rather than a detail.
 */
const businessListSpec = defineListSpec({
  filters: {
    status: { column: "b.status", type: "enum", values: ["pending", "active", "disabled", "rejected"] },
    businessType: { column: "b.business_type", type: "string" },
  },
  search: { columns: ["b.name", "b.phone"] },
  sort: {
    allowed: { name: "b.name", createdAt: "b.created_at", status: "b.status" },
    default: { key: "createdAt", direction: "DESC" },
  },
  dateRange: { column: "b.created_at" },
});

/**
 * Platform-wide by design: this is the System Admin's own view, the one
 * place in the application where crossing tenant boundaries is the point
 * (§2). Every other list is scoped to one business — see
 * docs/multi-tenancy.md.
 */
export async function listBusinesses(query, pagination) {
  // `deleted_at IS NULL` is passed as the scope so it is applied first and
  // cannot be overridden by anything the client sends.
  const where = buildWhere(businessListSpec, query, { "b.deleted_at": null });
  const orderBy = buildOrderBy(businessListSpec, query, "b.id");

  const rows = await queryAll(
    `SELECT b.id, b.name, b.business_type, b.phone, b.currency, b.status,
            b.rejection_reason, b.created_at, b.approved_at, b.rejected_at,
            u.id AS owner_id, u.name AS owner_name, u.phone AS owner_phone
       FROM businesses b
       LEFT JOIN users u ON u.business_id = b.id AND u.is_owner = TRUE AND u.deleted_at IS NULL
       ${where.sql}
       ${orderBy}
       LIMIT ? OFFSET ?`,
    [...where.params, pagination.pageSize, pagination.offset]
  );

  // Same WHERE and same parameters as the page query, so the total can never
  // describe a different filter than the rows.
  const total = await queryCount(
    `SELECT COUNT(*) AS total FROM businesses b ${where.sql}`,
    where.params
  );

  return { rows, total };
}

/**
 * Business + initial owner, created atomically (architecture §29) — a
 * business row without its owner (or vice versa) left behind by a crash
 * mid-way would be a real integrity problem, not just an inconvenience.
 */
export async function createBusinessWithOwner({ business, owner, status = "active" }) {
  return runInTransaction(async (conn) => {
    const [businessResult] = await conn.query(
      `INSERT INTO businesses (name, business_type, phone, currency, language, timezone, status)
       VALUES (?, ?, ?, ?, ?, ?, ?)`,
      [
        business.name,
        business.businessType,
        business.phone,
        business.currency,
        business.language,
        business.timezone,
        status,
      ]
    );
    const businessId = businessResult.insertId;

    // §23's default roles, in the SAME transaction as the business. A
    // business without roles is a business whose users can do nothing, and a
    // crash between the two would produce exactly that.
    await createDefaultRoles(conn, businessId);
    const ownerRoleId = await findOwnerRoleId(conn, businessId);

    // The owner account is created active even for a `pending` business: it
    // is the business that is awaiting a decision, not the person. Login
    // checks both, so a pending business cannot get in either way — and
    // keeping them separate means approving does not have to hunt down and
    // re-activate user rows.
    const [userResult] = await conn.query(
      `INSERT INTO users (business_id, name, phone, password_hash, is_owner, role_id, status)
       VALUES (?, ?, ?, ?, TRUE, ?, 'active')`,
      [businessId, owner.name, owner.phone, owner.passwordHash, ownerRoleId]
    );

    return { businessId, ownerId: userResult.insertId };
  });
}

/** One business, with its owner — what the admin needs to decide on it. */
export async function findBusinessForReview(businessId) {
  const [rows] = await pool.query(
    `SELECT b.id, b.name, b.business_type, b.phone, b.currency, b.language, b.timezone,
            b.status, b.rejection_reason, b.created_at, b.approved_at, b.rejected_at,
            u.id AS owner_id, u.name AS owner_name, u.phone AS owner_phone
       FROM businesses b
       LEFT JOIN users u ON u.business_id = b.id AND u.is_owner = TRUE AND u.deleted_at IS NULL
      WHERE b.id = ? AND b.deleted_at IS NULL
      LIMIT 1`,
    [businessId]
  );
  return rows[0] ?? null;
}

/**
 * Records an approve/reject decision. Guarded by `status = 'pending'` in the
 * UPDATE itself rather than by reading first and writing after: two
 * administrators opening the same queue would otherwise both see "pending"
 * and both write a decision, and the second would silently overwrite the
 * first. The affected-row count is the answer to "did I win the race".
 */
export async function decideRegistration({ businessId, decision, adminId, reason = null }) {
  const [result] =
    decision === "approve"
      ? await pool.query(
          `UPDATE businesses
              SET status = 'active', approved_at = NOW(), approved_by = ?,
                  rejected_at = NULL, rejected_by = NULL, rejection_reason = NULL
            WHERE id = ? AND status = 'pending' AND deleted_at IS NULL`,
          [adminId, businessId]
        )
      : await pool.query(
          `UPDATE businesses
              SET status = 'rejected', rejected_at = NOW(), rejected_by = ?, rejection_reason = ?
            WHERE id = ? AND status = 'pending' AND deleted_at IS NULL`,
          [adminId, reason, businessId]
        );
  return result.affectedRows === 1;
}

export async function findPhoneInUse(phone) {
  const [rows] = await pool.query(`SELECT id FROM users WHERE phone = ? LIMIT 1`, [phone]);
  return rows.length > 0;
}
