import { pool, runInTransaction } from "../../db/pool.js";

/**
 * Business + initial owner, created atomically (architecture §29) — a
 * business row without its owner (or vice versa) left behind by a crash
 * mid-way would be a real integrity problem, not just an inconvenience.
 */
export async function createBusinessWithOwner({ business, owner }) {
  return runInTransaction(async (conn) => {
    const [businessResult] = await conn.query(
      `INSERT INTO businesses (name, business_type, phone, currency, language, timezone, status)
       VALUES (?, ?, ?, ?, ?, ?, 'active')`,
      [business.name, business.businessType, business.phone, business.currency, business.language, business.timezone]
    );
    const businessId = businessResult.insertId;

    const [userResult] = await conn.query(
      `INSERT INTO users (business_id, name, phone, password_hash, is_owner, status)
       VALUES (?, ?, ?, ?, TRUE, 'active')`,
      [businessId, owner.name, owner.phone, owner.passwordHash]
    );

    return { businessId, ownerId: userResult.insertId };
  });
}

export async function findPhoneInUse(phone) {
  const [rows] = await pool.query(`SELECT id FROM users WHERE phone = ? LIMIT 1`, [phone]);
  return rows.length > 0;
}
