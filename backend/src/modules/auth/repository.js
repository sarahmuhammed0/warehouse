// Auth data access — parameterized SQL only, explicit per-table functions
// (never a dynamically-interpolated table name) so there is zero SQL-
// injection surface here regardless of caller input (architecture §25).
//
// This file covers BOTH identity tables (`users` and `system_admins`),
// kept in one file because the two are exact structural mirrors of each
// other and a caller (accountAdapters.js) picks the right function pair —
// splitting this into two files would just be the same code twice.

import { pool } from "../../db/pool.js";

// ---- business users ----------------------------------------------------

export async function findUserByPhone(phone) {
  const [rows] = await pool.query(
    `SELECT id, business_id, name, phone, password_hash, is_owner, status
       FROM users WHERE phone = ? AND deleted_at IS NULL LIMIT 1`,
    [phone]
  );
  return rows[0] ?? null;
}

export async function findUserById(id) {
  const [rows] = await pool.query(
    `SELECT id, business_id, name, phone, is_owner, status
       FROM users WHERE id = ? AND deleted_at IS NULL LIMIT 1`,
    [id]
  );
  return rows[0] ?? null;
}

export async function updateUserLastLogin(id) {
  await pool.query(`UPDATE users SET last_login_at = NOW() WHERE id = ?`, [id]);
}

export async function updateUserPasswordHash(id, passwordHash) {
  await pool.query(`UPDATE users SET password_hash = ? WHERE id = ?`, [passwordHash, id]);
}

export async function findUserPasswordHash(id) {
  const [rows] = await pool.query(`SELECT password_hash FROM users WHERE id = ?`, [id]);
  return rows[0]?.password_hash ?? null;
}

// ---- system admins -------------------------------------------------------

export async function findSystemAdminByPhone(phone) {
  const [rows] = await pool.query(
    `SELECT id, name, phone, password_hash, status
       FROM system_admins WHERE phone = ? AND deleted_at IS NULL LIMIT 1`,
    [phone]
  );
  return rows[0] ?? null;
}

export async function findSystemAdminById(id) {
  const [rows] = await pool.query(
    `SELECT id, name, phone, status FROM system_admins WHERE id = ? AND deleted_at IS NULL LIMIT 1`,
    [id]
  );
  return rows[0] ?? null;
}

export async function updateSystemAdminLastLogin(id) {
  await pool.query(`UPDATE system_admins SET last_login_at = NOW() WHERE id = ?`, [id]);
}

export async function updateSystemAdminPasswordHash(id, passwordHash) {
  await pool.query(`UPDATE system_admins SET password_hash = ? WHERE id = ?`, [passwordHash, id]);
}

export async function findSystemAdminPasswordHash(id) {
  const [rows] = await pool.query(`SELECT password_hash FROM system_admins WHERE id = ?`, [id]);
  return rows[0]?.password_hash ?? null;
}

// ---- business (read-only here — creation lives in modules/businesses) ----

export async function findBusinessById(id) {
  const [rows] = await pool.query(
    // `rejection_reason` is read so a refused registration's owner can be
    // told why at login. It never reaches a response body: `safeBusiness` in
    // authService is an allowlist and does not include it.
    `SELECT id, name, business_type, logo_url, currency, language, timezone, status, rejection_reason
       FROM businesses WHERE id = ? AND deleted_at IS NULL LIMIT 1`,
    [id]
  );
  return rows[0] ?? null;
}

// ---- refresh tokens (business users) --------------------------------------

export async function createUserRefreshToken({ userId, tokenHash, expiresAt, ip, userAgent }) {
  const [result] = await pool.query(
    `INSERT INTO refresh_tokens (user_id, token_hash, expires_at, ip_address, user_agent)
     VALUES (?, ?, ?, ?, ?)`,
    [userId, tokenHash, expiresAt, ip ?? null, userAgent ?? null]
  );
  return result.insertId;
}

export async function findUserRefreshTokenByHash(tokenHash) {
  const [rows] = await pool.query(
    `SELECT id, user_id, expires_at, revoked_at FROM refresh_tokens WHERE token_hash = ? LIMIT 1`,
    [tokenHash]
  );
  return rows[0] ?? null;
}

export async function revokeUserRefreshToken(id, replacedById = null) {
  await pool.query(`UPDATE refresh_tokens SET revoked_at = NOW(), replaced_by_id = ? WHERE id = ?`, [
    replacedById,
    id,
  ]);
}

export async function revokeAllUserRefreshTokens(userId) {
  await pool.query(
    `UPDATE refresh_tokens SET revoked_at = NOW() WHERE user_id = ? AND revoked_at IS NULL`,
    [userId]
  );
}

// ---- refresh tokens (system admins) ---------------------------------------

export async function createAdminRefreshToken({ adminId, tokenHash, expiresAt, ip, userAgent }) {
  const [result] = await pool.query(
    `INSERT INTO system_admin_refresh_tokens (system_admin_id, token_hash, expires_at, ip_address, user_agent)
     VALUES (?, ?, ?, ?, ?)`,
    [adminId, tokenHash, expiresAt, ip ?? null, userAgent ?? null]
  );
  return result.insertId;
}

export async function findAdminRefreshTokenByHash(tokenHash) {
  const [rows] = await pool.query(
    `SELECT id, system_admin_id, expires_at, revoked_at
       FROM system_admin_refresh_tokens WHERE token_hash = ? LIMIT 1`,
    [tokenHash]
  );
  return rows[0] ?? null;
}

export async function revokeAdminRefreshToken(id, replacedById = null) {
  await pool.query(
    `UPDATE system_admin_refresh_tokens SET revoked_at = NOW(), replaced_by_id = ? WHERE id = ?`,
    [replacedById, id]
  );
}

export async function revokeAllAdminRefreshTokens(adminId) {
  await pool.query(
    `UPDATE system_admin_refresh_tokens SET revoked_at = NOW() WHERE system_admin_id = ? AND revoked_at IS NULL`,
    [adminId]
  );
}

// ---- login attempts / lockout ----------------------------------------------

export async function recordLoginAttempt({ accountType, phone, success, ip }) {
  await pool.query(
    `INSERT INTO login_attempts (account_type, phone, success, ip_address) VALUES (?, ?, ?, ?)`,
    [accountType, phone, success, ip ?? null]
  );
}

/** Consecutive-failure lockout check — see docs/authentication.md "Login protection". */
export async function countRecentFailedAttempts({ accountType, phone, sinceMinutesAgo }) {
  const [rows] = await pool.query(
    `SELECT COUNT(*) AS count FROM login_attempts
      WHERE account_type = ? AND phone = ? AND success = 0
        AND created_at > (NOW() - INTERVAL ? MINUTE)`,
    [accountType, phone, sinceMinutesAgo]
  );
  return rows[0]?.count ?? 0;
}

// ---- audit -----------------------------------------------------------------

export async function writeAuditLog({
  businessId = null,
  actorType,
  actorId = null,
  // §30 requires every audit record to name the module it came from, and
  // requires filtering by it, so the column is NOT NULL. It defaults to
  // "auth" because that is where every caller in this repository lives;
  // any other module must pass its own name, or its events all file
  // themselves under authentication.
  module = "auth",
  action,
  description,
  ip = null,
  referenceType = null,
  referenceId = null,
}) {
  await pool.query(
    `INSERT INTO audit_logs
       (business_id, actor_type, actor_id, module, action, description, ip_address, reference_type, reference_id)
     VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)`,
    [businessId, actorType, actorId, module, action, description, ip, referenceType, referenceId]
  );
}
