import { defineListSpec, buildWhere, buildOrderBy } from "../../db/listQuery.js";
import { queryAll, queryCount, pool } from "../../db/pool.js";

/** A business's own staff (§23). */
const listSpec = defineListSpec({
  filters: {
    status: { column: "u.status", type: "enum", values: ["active", "disabled"] },
    roleId: { column: "u.role_id", type: "int" },
  },
  search: { columns: ["u.name", "u.phone", "u.email"] },
  sort: {
    allowed: { name: "u.name", createdAt: "u.created_at", lastLoginAt: "u.last_login_at" },
    default: { key: "name", direction: "ASC" },
  },
  dateRange: { column: "u.created_at" },
});

const JOINS = `LEFT JOIN roles r ON r.id = u.role_id AND r.business_id = u.business_id`;

const SELECT_COLUMNS = `
  u.id, u.business_id, u.name, u.phone, u.email, u.status, u.is_owner,
  u.role_id, r.name AS role_name, u.last_login_at, u.created_at, u.updated_at`;

export async function listUsers({ businessId, query, pagination }) {
  const where = buildWhere(listSpec, query, { "u.business_id": businessId, "u.deleted_at": null });
  const orderBy = buildOrderBy(listSpec, query, "u.id");

  const rows = await queryAll(
    `SELECT ${SELECT_COLUMNS} FROM users u ${JOINS} ${where.sql} ${orderBy} LIMIT ? OFFSET ?`,
    [...where.params, pagination.pageSize, pagination.offset]
  );
  const total = await queryCount(
    `SELECT COUNT(*) AS total FROM users u ${JOINS} ${where.sql}`,
    where.params
  );
  return { rows, total };
}

export async function findUser({ businessId, id, conn = pool }) {
  const [rows] = await conn.query(
    `SELECT ${SELECT_COLUMNS} FROM users u ${JOINS}
      WHERE u.id = ? AND u.business_id = ? AND u.deleted_at IS NULL LIMIT 1`,
    [id, businessId]
  );
  return rows[0] ?? null;
}

/**
 * A role of THIS business, by id.
 *
 * The tenant check is the point (§36): a role id arrives as a bare number, and
 * without it a user could be given another business's role — and with it,
 * whatever that role's permissions happen to be.
 */
export async function roleBelongsToBusiness({ businessId, roleId, conn = pool }) {
  const [rows] = await conn.query(
    `SELECT 1 AS ok FROM roles WHERE id = ? AND business_id = ? AND deleted_at IS NULL LIMIT 1`,
    [roleId, businessId]
  );
  return rows.length > 0;
}

export async function createUser(conn, { businessId, name, phone, email, passwordHash, roleId, status }) {
  const [result] = await conn.query(
    `INSERT INTO users (business_id, name, phone, email, password_hash, is_owner, role_id, status)
     VALUES (?, ?, ?, ?, ?, FALSE, ?, ?)`,
    [businessId, name, phone, email ?? null, passwordHash, roleId, status ?? "active"]
  );
  return result.insertId;
}

/**
 * Applies only the fields that were sent (§54's partial update).
 *
 * `affectedRows` counts rows MATCHED rather than changed (see db/pool.js), so a
 * save that re-sends the values a user already has still reports 1 and does not
 * turn into a 404.
 */
export async function updateUser(conn, { businessId, id, fields }) {
  const columns = {
    name: "name",
    email: "email",
    roleId: "role_id",
    status: "status",
    passwordHash: "password_hash",
  };

  const sets = [];
  const params = [];
  for (const [key, column] of Object.entries(columns)) {
    if (fields[key] === undefined) continue;
    sets.push(`${column} = ?`);
    params.push(fields[key]);
  }
  if (sets.length === 0) return 1; // nothing to change is not a failure

  const [result] = await conn.query(
    `UPDATE users SET ${sets.join(", ")}, updated_at = NOW()
      WHERE id = ? AND business_id = ? AND deleted_at IS NULL`,
    [...params, id, businessId]
  );
  return result.affectedRows;
}

/**
 * §45's soft delete. The row stays, because every document it created still
 * points at it — a purchase's `created_by`, a movement's `user_id`, an audit
 * row's `actor_id`. A hard delete would either fail on those references or,
 * worse, take the history with it.
 *
 * The phone is left exactly as it was. It stops blocking a new account by
 * itself: uniqueness is enforced on the generated `active_phone` column, which
 * is NULL for an archived row (see the migration), so the number is free again
 * for a re-hire while the record still says who this was.
 */
export async function softDeleteUser(conn, { businessId, id }) {
  const [result] = await conn.query(
    `UPDATE users
        SET deleted_at = NOW(), status = 'disabled', updated_at = NOW()
      WHERE id = ? AND business_id = ? AND deleted_at IS NULL`,
    [id, businessId]
  );
  return result.affectedRows;
}

/** Whether this business has any other active owner besides `exceptId`. */
export async function hasAnotherActiveOwner({ businessId, exceptId, conn = pool }) {
  const [rows] = await conn.query(
    `SELECT 1 AS ok FROM users
      WHERE business_id = ? AND id <> ? AND is_owner = TRUE
        AND status = 'active' AND deleted_at IS NULL LIMIT 1`,
    [businessId, exceptId]
  );
  return rows.length > 0;
}

/** Every session this user holds — revoked when they are disabled or removed. */
export async function revokeRefreshTokens(conn, { userId }) {
  await conn.query(`DELETE FROM refresh_tokens WHERE user_id = ?`, [userId]);
}
