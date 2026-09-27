// The business settings this API recognises (§24's Settings module).
//
// AN ALLOWLIST, NOT FREE-FORM KEY/VALUE. `business_settings` is a key/value
// table, and exposing it directly would let a client write any key it liked —
// including one a future release means to use for something else, and one that
// merely LOOKS like a real setting ("inventory.allow_negative_stocks") and so
// silently does nothing. Declaring the keys here means an unknown key is a
// validation error the caller can see, and every setting has exactly one
// documented type and default in one place.

/**
 * @typedef {{ type: "boolean" | "string" | "number", default: unknown, description: string }} SettingSpec
 */

/** @type {Record<string, SettingSpec>} */
export const SETTINGS = {
  // §47, verbatim: negative inventory is permitted "only through an explicit
  // business setting". This is that setting — the one `allowsNegativeStock`
  // reads before it refuses a movement that would go below zero. Default
  // false, which is the safe answer for a business that has never chosen.
  "inventory.allow_negative_stock": {
    type: "boolean",
    default: false,
    description: "Allow stock levels to go below zero (§47).",
  },
};

export const SETTING_KEYS = Object.keys(SETTINGS);

/**
 * Reads a stored value back into its declared type.
 *
 * The column is JSON, and MySQL hands it back as a parsed value on some
 * drivers and as a string on others, so both are handled rather than assumed.
 */
export function parseSetting(key, raw) {
  const spec = SETTINGS[key];
  if (!spec) return undefined;

  let value = raw;
  if (typeof raw === "string") {
    try {
      value = JSON.parse(raw);
    } catch {
      value = raw;
    }
  }

  switch (spec.type) {
    case "boolean":
      return value === true || value === "true" || value === 1 || value === "1";
    case "number":
      return Number(value);
    default:
      return value === null || value === undefined ? spec.default : String(value);
  }
}

/** Every setting, with stored values where they exist and defaults elsewhere. */
export function withDefaults(rows) {
  const stored = new Map(rows.map((row) => [row.setting_key, row.setting_value]));
  const result = {};
  for (const key of SETTING_KEYS) {
    result[key] = stored.has(key) ? parseSetting(key, stored.get(key)) : SETTINGS[key].default;
  }
  return result;
}
