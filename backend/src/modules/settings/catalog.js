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

/**
 * EVERY KEY HERE IS HONOURED SOMEWHERE. A setting the API stores and no code
 * reads is worse than a missing one: the business believes it has configured
 * something. The `honouredBy` note on each says where, so that claim can be
 * checked rather than trusted.
 *
 * @type {Record<string, SettingSpec>}
 */
export const SETTINGS = {
  // §47, verbatim: negative inventory is permitted "only through an explicit
  // business setting". This is that setting — the one `allowsNegativeStock`
  // reads before it refuses a movement that would go below zero. Default
  // false, which is the safe answer for a business that has never chosen.
  "inventory.allow_negative_stock": {
    type: "boolean",
    default: false,
    description: "Allow stock levels to go below zero (§47).",
    honouredBy: "inventory/service.js adjustStock, inventory/allocation.js planOutbound",
  },

  // §44's low-stock alert needs a threshold, and most products never get one of
  // their own. This is the figure used when a product's `reorder_level` is NULL,
  // so a business can set the rule once instead of per product.
  "inventory.low_stock_threshold_default": {
    type: "number",
    default: 5,
    description: "The low-stock threshold for products that have none of their own (§44).",
    honouredBy: "inventory/repository.js lowStockProducts",
  },

  // §43's payment methods. A business that never takes cards should not be
  // offered one on a payment form, and more to the point should not be able to
  // record one by accident — so the server refuses a method that is switched
  // off rather than trusting the client to hide the option.
  "payments.cash_enabled": {
    type: "boolean",
    default: true,
    description: "Accept cash payments (§43).",
    honouredBy: "settings/paymentMethods.js, checked by orders and purchases",
  },
  "payments.bank_transfer_enabled": {
    type: "boolean",
    default: true,
    description: "Accept bank transfers (§43).",
    honouredBy: "settings/paymentMethods.js, checked by orders and purchases",
  },
  "payments.card_enabled": {
    type: "boolean",
    default: false,
    description: "Accept card payments (§43).",
    honouredBy: "settings/paymentMethods.js, checked by orders and purchases",
  },

  // §3's password policy. The floor is 8 either way: a business may demand more
  // than the system's minimum, never less, which is why the check takes the
  // larger of the two rather than this value alone.
  "security.min_password_length": {
    type: "number",
    default: 8,
    description: "Shortest password a user may choose — never below 8 (§3).",
    honouredBy: "settings/securityPolicy.js, checked when a password is set or changed",
  },

  /**
   * DELIBERATELY ABSENT: the login lockout threshold (§4).
   *
   * It looks like a natural per-business setting, and the Settings screen offers
   * one. It cannot be honoured without weakening §7. The lockout is checked
   * BEFORE the phone is resolved to an account, precisely so that a locked-out
   * response is identical whether or not the phone belongs to anyone — reading a
   * per-business threshold would mean looking the account up first, and a
   * business that locks out after three attempts would then behave observably
   * differently from an unknown number, which is an account-enumeration
   * side-channel.
   *
   * The uniformity of the lockout is itself the security property, so it stays a
   * system-wide constant in `auth/authService.js`. A setting stored here that
   * nothing read would be worse: the business would believe it had configured
   * something.
   */
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
