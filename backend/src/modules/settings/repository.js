import { pool } from "../../db/pool.js";
import { SETTING_KEYS, SETTINGS, parseSetting } from "./catalog.js";

/**
 * One setting's value for one business, or its declared default.
 *
 * The single read every feature that HONOURS a setting goes through, so "what
 * is this business's low-stock threshold" has one answer and one place to look
 * — rather than each module writing its own query against a JSON column and
 * disagreeing about what an absent row means.
 *
 * Takes a connection so a check inside a transaction reads what that
 * transaction can see.
 */
export async function readSetting({ businessId, key, conn = pool }) {
  const spec = SETTINGS[key];
  if (!spec) throw new Error(`Unknown setting: ${key}`);

  const [rows] = await conn.query(
    `SELECT setting_value FROM business_settings
      WHERE business_id = ? AND setting_key = ? LIMIT 1`,
    [businessId, key]
  );
  if (rows.length === 0) return spec.default;

  const parsed = parseSetting(key, rows[0].setting_value);
  return parsed === undefined ? spec.default : parsed;
}

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
