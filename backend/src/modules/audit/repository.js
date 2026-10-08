import { defineListSpec, buildWhere, buildOrderBy } from "../../db/listQuery.js";
import { pool, queryAll, queryCount } from "../../db/pool.js";

/**
 * §30's activity log, read back.
 *
 * The rows are written by `middleware/auditTrail.js` (every module's writes) and
 * by the auth module (logins, password changes). Nothing here writes: an audit
 * trail a client can edit is not one.
 */
const listSpec = defineListSpec({
  filters: {
    module: {
      column: "a.module",
      type: "enum",
      // The modules that actually file events, plus `auth` and `businesses`,
      // which predate the trail middleware and write their own.
      values: [
        "auth",
        "businesses",
        "products",
        "categories",
        "inventory",
        "orders",
        "customers",
        "suppliers",
        "purchases",
        "returns",
        "production",
        "users",
        "settings",
      ],
    },
    actorType: { column: "a.actor_type", type: "enum", values: ["business_user", "system_admin", "system"] },
    actorId: { column: "a.actor_id", type: "int" },
    referenceType: { column: "a.reference_type", type: "string" },
    referenceId: { column: "a.reference_id", type: "int" },
  },
  search: { columns: ["a.action", "a.description", "u.name"] },
  sort: {
    allowed: { createdAt: "a.created_at", module: "a.module", action: "a.action" },
    // Newest first: §30's question is almost always "what just happened".
    default: { key: "createdAt", direction: "DESC" },
  },
  dateRange: { column: "a.created_at" },
});

const JOINS = `LEFT JOIN users u ON u.id = a.actor_id AND a.actor_type = 'business_user'`;

export async function listAuditLogs({ businessId, query, pagination }) {
  // Scoped to the tenant, like every other business read (§36). A System Admin
  // reading across businesses would need its own endpoint; this one is a
  // business looking at its own history.
  const where = buildWhere(listSpec, query, { "a.business_id": businessId });
  const orderBy = buildOrderBy(listSpec, query, "a.id");

  const rows = await queryAll(
    `SELECT a.id, a.actor_type, a.actor_id, u.name AS actor_name,
            a.module, a.action, a.description, a.ip_address,
            a.reference_type, a.reference_id, a.created_at
       FROM audit_logs a ${JOINS} ${where.sql} ${orderBy} LIMIT ? OFFSET ?`,
    [...where.params, pagination.pageSize, pagination.offset]
  );

  const total = await queryCount(
    `SELECT COUNT(*) AS total FROM audit_logs a ${JOINS} ${where.sql}`,
    where.params
  );

  return { rows, total };
}

/** The distinct actions a business has actually recorded — for a filter list. */
/**
 * One entry, scoped to the business that owns it (§36).
 *
 * The id alone is not enough: audit ids are sequential across every tenant, so
 * fetching by id without the business check would hand one business another's
 * trail — which is exactly the record you least want leaking.
 */
export async function findAuditLog({ businessId, id }) {
  const [rows] = await pool.query(
    `SELECT a.*, u.name AS actor_name
       FROM audit_logs a ${JOINS}
      WHERE a.id = ? AND a.business_id = ? LIMIT 1`,
    [id, businessId]
  );
  return rows[0] ?? null;
}

export async function listAuditActions({ businessId }) {
  return queryAll(
    `SELECT a.module, a.action, COUNT(*) AS total
       FROM audit_logs a
      WHERE a.business_id = ?
      GROUP BY a.module, a.action
      ORDER BY a.module, a.action`,
    [businessId]
  );
}
