// Shared integration-test helpers. These tests are the ones instruction
// §30/§32 calls "integration tests requiring MySQL" — every file in this
// directory calls `requireDatabase(t)` first and skips (never fakes a
// pass) if the isolated MySQL 8.x instance (port 3307, see
// docs/environment.md) isn't reachable. They reuse the same dev database
// (`warehouse_os_dev`) rather than a dedicated test database — acceptable
// for this phase's scope, and documented as a known simplification in
// docs/phase2-traceability.md; every row a test creates is deleted in its
// own cleanup, identifiable by a `test-` phone prefix reserved for this
// purpose (never used by real seed/dev data).

import { pool, checkDatabaseConnection } from "../../src/db/pool.js";
import { hashPassword } from "../../src/utils/password.js";

export async function requireDatabase(t) {
  const status = await checkDatabaseConnection();
  if (!status.reachable) {
    t.skip(`MySQL not reachable at the configured host/port — see docs/environment.md. (${status.error})`);
    return false;
  }
  return true;
}

let counter = 0;
/** Unique-per-run phone numbers within the test's reserved namespace. */
export function testPhone() {
  counter += 1;
  return `+1555000${String(Date.now() % 10000).padStart(4, "0")}${counter}`;
}

export async function createTestBusiness({ status = "active" } = {}) {
  const [result] = await pool.query(
    `INSERT INTO businesses (name, business_type, phone, status) VALUES (?, 'custom', ?, ?)`,
    [`Test Business ${Date.now()}-${Math.random().toString(36).slice(2, 7)}`, testPhone(), status]
  );
  return result.insertId;
}

export async function createTestUser({ businessId, phone, password = "TestPassword123", status = "active", isOwner = false }) {
  const passwordHash = await hashPassword(password);
  const [result] = await pool.query(
    `INSERT INTO users (business_id, name, phone, password_hash, is_owner, status) VALUES (?, 'Test User', ?, ?, ?, ?)`,
    [businessId, phone, passwordHash, isOwner, status]
  );
  return { id: result.insertId, phone, password };
}

export async function createTestSystemAdmin({ phone, password = "AdminPassword123", status = "active" }) {
  const passwordHash = await hashPassword(password);
  const [result] = await pool.query(
    `INSERT INTO system_admins (name, phone, password_hash, status) VALUES ('Test Admin', ?, ?, ?)`,
    [phone, passwordHash, status]
  );
  return { id: result.insertId, phone, password };
}

/** Deletes everything a test created, in FK-safe order. Call in a `finally`. */
export async function cleanupTestData({ businessIds = [], userIds = [], adminIds = [] } = {}) {
  if (userIds.length) {
    await pool.query(`DELETE FROM refresh_tokens WHERE user_id IN (?)`, [userIds]);
    await pool.query(`DELETE FROM login_attempts WHERE phone IN (SELECT phone FROM users WHERE id IN (?))`, [
      userIds,
    ]);
    await pool.query(`DELETE FROM audit_logs WHERE actor_id IN (?) AND actor_type = 'business_user'`, [userIds]);
    await pool.query(`DELETE FROM users WHERE id IN (?)`, [userIds]);
  }
  if (adminIds.length) {
    await pool.query(`DELETE FROM system_admin_refresh_tokens WHERE system_admin_id IN (?)`, [adminIds]);
    await pool.query(`DELETE FROM audit_logs WHERE actor_id IN (?) AND actor_type = 'system_admin'`, [adminIds]);
    await pool.query(`DELETE FROM system_admins WHERE id IN (?)`, [adminIds]);
  }
  if (businessIds.length) {
    await pool.query(`DELETE FROM audit_logs WHERE business_id IN (?)`, [businessIds]);
    // Roles must go before the business: `roles.business_id` is RESTRICT,
    // deliberately, because production soft-deletes businesses and never
    // hard-deletes them. Only these tests remove one for real, so only
    // these tests have to unpick it. `role_permissions` cascades from
    // `roles`, and users (which reference a role) are already gone above.
    await pool.query(
      `DELETE rp FROM role_permissions rp
         JOIN roles r ON r.id = rp.role_id
        WHERE r.business_id IN (?)`,
      [businessIds]
    );
    await pool.query(`DELETE FROM roles WHERE business_id IN (?)`, [businessIds]);
    await pool.query(`DELETE FROM businesses WHERE id IN (?)`, [businessIds]);
  }
}
