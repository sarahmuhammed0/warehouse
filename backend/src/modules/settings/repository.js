import { pool } from "../../db/pool.js";
import { SETTING_KEYS } from "./catalog.js";

/**
 * §24's Settings module, over `business_settings`.
 *
 * Reads are limited to the declared keys, so a row written by an older
 * release (or by hand) for a key this version no longer knows about is
 * ignored rather than surfaced as a setting the UI cannot render.
 */
export async function readSettings(businessId) {
  const [rows] = await pool.query(
    `SELECT setting_key, setting_value FROM business_settings
      WHERE business_id = ? AND setting_key IN (${SETTING_KEYS.map(() => "?").join(", ")})`,
    [businessId, ...SETTING_KEYS]
  );
  return rows;
}

/**
 * Writes one setting.
 *
 * `ON DUPLICATE KEY UPDATE` against `uq_business_settings_key`, so first write
 * and later change are the same statement — there is no "does it exist yet"
 * read to race against.
 */
export async function writeSetting({ businessId, key, value, conn = pool }) {
  await conn.query(
    `INSERT INTO business_settings (business_id, setting_key, setting_value)
     VALUES (?, ?, CAST(? AS JSON))
     ON DUPLICATE KEY UPDATE setting_value = VALUES(setting_value), updated_at = NOW()`,
    [businessId, key, JSON.stringify(value)]
  );
}
