import { queryAll, pool } from "../../db/pool.js";

/**
 * A business's roles, each with the permission keys it grants (§23/§24).
 *
 * Not paginated: §23's list is eight roles, and a permission editor needs all
 * of them at once to show which role holds what.
 */
export async function listRoles({ businessId }) {
  const roles = await queryAll(
    `SELECT r.id, r.name, r.description, r.is_system, r.created_at, r.updated_at,
            (SELECT COUNT(*) FROM users u
              WHERE u.role_id = r.id AND u.deleted_at IS NULL) AS user_count
       FROM roles r
      WHERE r.business_id = ? AND r.deleted_at IS NULL
      ORDER BY r.id`,
    [businessId]
  );

  const grants = await queryAll(
    `SELECT rp.role_id, p.permission_key
       FROM role_permissions rp
       JOIN roles r       ON r.id = rp.role_id
       JOIN permissions p ON p.id = rp.permission_id
      WHERE r.business_id = ? AND r.deleted_at IS NULL
      ORDER BY p.permission_key`,
    [businessId]
  );

  const byRole = new Map();
  for (const grant of grants) {
    const key = String(grant.role_id);
    if (!byRole.has(key)) byRole.set(key, []);
    byRole.get(key).push(grant.permission_key);
  }

  return roles.map((role) => ({ ...role, permissions: byRole.get(String(role.id)) ?? [] }));
}

export async function findRole({ businessId, id, conn = pool }) {
  const [rows] = await conn.query(
    `SELECT id, name, description, is_system FROM roles
      WHERE id = ? AND business_id = ? AND deleted_at IS NULL LIMIT 1`,
    [id, businessId]
  );
  return rows[0] ?? null;
}

/** The whole catalogue, for the permission editor's grid (§24). */
export async function listPermissions() {
  return queryAll(
    `SELECT permission_key, module, action, description FROM permissions
      ORDER BY module, action`
  );
}

export async function createRole(conn, { businessId, name, description }) {
  const [result] = await conn.query(
    `INSERT INTO roles (business_id, name, description, is_system) VALUES (?, ?, ?, FALSE)`,
    [businessId, name, description ?? null]
  );
  return result.insertId;
}

export async function renameRole(conn, { businessId, id, name, description }) {
  const sets = [];
  const params = [];
  if (name !== undefined) {
    sets.push("name = ?");
    params.push(name);
  }
  if (description !== undefined) {
    sets.push("description = ?");
    params.push(description);
  }
  if (sets.length === 0) return 1;

  const [result] = await conn.query(
    `UPDATE roles SET ${sets.join(", ")}, updated_at = NOW()
      WHERE id = ? AND business_id = ? AND deleted_at IS NULL`,
    [...params, id, businessId]
  );
  return result.affectedRows;
}

/**
 * Replaces a role's grants with exactly `keys`.
 *
 * The INSERT joins `permissions`, which is what makes an unknown key
 * impossible to grant: a key that is not in the catalogue matches no row and is
 * silently absent rather than being stored and never checked. The controller
 * still rejects unknown keys outright, so the caller is told — this is the
 * second line of that defence, not the only one.
 *
 * Whole-set replacement rather than add/remove calls: a permission editor saves
 * a grid, and two calls that must both succeed to leave a coherent role is how
 * a role ends up half-granted.
 */
export async function replacePermissions(conn, { roleId, keys }) {
  await conn.query(`DELETE FROM role_permissions WHERE role_id = ?`, [roleId]);
  if (keys.length === 0) return;

  await conn.query(
    `INSERT IGNORE INTO role_permissions (role_id, permission_id)
     SELECT ?, p.id FROM permissions p WHERE p.permission_key IN (?)`,
    [roleId, keys]
  );
}

/** Which of `keys` are not in the catalogue. */
export async function unknownPermissionKeys(keys) {
  if (keys.length === 0) return [];
  const rows = await queryAll(`SELECT permission_key FROM permissions WHERE permission_key IN (?)`, [
    keys,
  ]);
  const known = new Set(rows.map((row) => row.permission_key));
  return keys.filter((key) => !known.has(key));
}

export async function usersInRole({ businessId, roleId }) {
  const rows = await queryAll(
    `SELECT COUNT(*) AS total FROM users
      WHERE business_id = ? AND role_id = ? AND deleted_at IS NULL`,
    [businessId, roleId]
  );
  return Number(rows[0]?.total ?? 0);
}

export async function softDeleteRole(conn, { businessId, id }) {
  const [result] = await conn.query(
    `UPDATE roles SET deleted_at = NOW(), updated_at = NOW()
      WHERE id = ? AND business_id = ? AND deleted_at IS NULL`,
    [id, businessId]
  );
  return result.affectedRows;
}
