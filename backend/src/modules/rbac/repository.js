import { pool } from "../../db/pool.js";
import { DEFAULT_ROLES, OWNER_ROLE_NAME } from "./catalog.js";

/**
 * Creates §23's default roles for a business and grants each one its
 * permissions.
 *
 * Takes a connection so it can run INSIDE the transaction that creates the
 * business. A business that exists without roles is a business whose users
 * can do nothing, and a crash between the two would produce exactly that —
 * so it is one atomic operation with the business itself (§46).
 *
 * Idempotent per business: `uq_roles_business_name` makes a second call a
 * no-op rather than a duplicate-key error, which is what lets the same
 * function serve both business creation and the backfill.
 *
 * Returns the created roles by name, so the caller can assign one to the
 * owner without a second query.
 */
export async function createDefaultRoles(conn, businessId) {
  const roleIds = new Map();

  for (const role of DEFAULT_ROLES) {
    await conn.query(
      `INSERT INTO roles (business_id, name, description, is_system)
       VALUES (?, ?, ?, TRUE)
       ON DUPLICATE KEY UPDATE description = VALUES(description)`,
      [businessId, role.name, role.description]
    );

    // LAST_INSERT_ID() is unreliable here: ON DUPLICATE KEY UPDATE leaves it
    // unchanged when nothing was inserted, so the id is read back instead.
    const [[row]] = await conn.query(
      `SELECT id FROM roles WHERE business_id = ? AND name = ? LIMIT 1`,
      [businessId, role.name]
    );
    roleIds.set(role.name, row.id);

    if (role.permissions.length === 0) continue;

    // One statement for the whole role. The join to `permissions` is what
    // makes an unknown key impossible to grant: a permission name that is
    // not in the catalogue simply matches no row, rather than being written
    // and silently never checked.
    await conn.query(
      `INSERT IGNORE INTO role_permissions (role_id, permission_id)
       SELECT ?, p.id FROM permissions p WHERE p.permission_key IN (?)`,
      [row.id, role.permissions]
    );
  }

  return roleIds;
}

/** The role a business's initial administrator gets (§3). */
export async function findOwnerRoleId(conn, businessId) {
  const [[row]] = await conn.query(
    `SELECT id FROM roles WHERE business_id = ? AND name = ? AND deleted_at IS NULL LIMIT 1`,
    [businessId, OWNER_ROLE_NAME]
  );
  return row?.id ?? null;
}

/**
 * Every permission key a user holds, via their role.
 *
 * Resolved from the database on each request rather than baked into the
 * access token: a permission change must take effect immediately, and a
 * token that carried its grants would keep them until it expired — up to
 * fifteen minutes of access after it was revoked.
 *
 * A user with no role gets an empty list, which denies everything. That is
 * the right default: Phase 2's users predate roles, and the safe reading of
 * "no role assigned" is "no permissions", never "all of them".
 */
export async function permissionsForUser(userId) {
  const [rows] = await pool.query(
    `SELECT p.permission_key
       FROM users u
       JOIN roles r            ON r.id = u.role_id AND r.deleted_at IS NULL
       JOIN role_permissions rp ON rp.role_id = r.id
       JOIN permissions p       ON p.id = rp.permission_id
      WHERE u.id = ? AND u.deleted_at IS NULL`,
    [userId]
  );
  return rows.map((row) => row.permission_key);
}

/** Businesses that have no roles yet — the backfill's work list. */
export async function businessesWithoutRoles() {
  const [rows] = await pool.query(
    `SELECT b.id, b.name
       FROM businesses b
       LEFT JOIN roles r ON r.business_id = b.id
      WHERE b.deleted_at IS NULL AND r.id IS NULL`
  );
  return rows;
}
