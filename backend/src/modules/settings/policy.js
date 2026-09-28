// The settings that other modules have to OBEY, as named checks.
//
// Each function here is the one place a stored setting turns into a decision, so
// the catalogue's claim that a key is honoured can be verified by following the
// `honouredBy` note to exactly one function — rather than hunting for a query
// against a JSON column in whichever module happened to need it.

import { errors } from "../../utils/AppError.js";
import { readSetting } from "./repository.js";

/** The floor no business may go below, whatever it sets (§3). */
export const ABSOLUTE_MIN_PASSWORD_LENGTH = 8;

/**
 * §43: a payment method the business has switched off is refused here rather
 * than merely hidden by the client. A form that still offers cards after cards
 * were turned off is a UI bug; a card payment RECORDED after that is a wrong
 * ledger, and only the server can prevent the second.
 */
const METHOD_SETTINGS = {
  cash: "payments.cash_enabled",
  bank_transfer: "payments.bank_transfer_enabled",
  card: "payments.card_enabled",
  // `other` has no switch: it is the escape hatch for a method the business
  // records in a note, and turning it off would leave no way to record a
  // payment that really happened.
};

export async function assertPaymentMethodAllowed({ businessId, method, conn }) {
  const key = METHOD_SETTINGS[method];
  if (!key) return;

  const enabled = await readSetting({ businessId, key, conn });
  if (!enabled) {
    throw errors.validation(
      `${labelFor(method)} payments are switched off in settings. Turn them on, or record this another way.`
    );
  }
}

const labelFor = (method) =>
  ({ cash: "Cash", bank_transfer: "Bank transfer", card: "Card" })[method] ?? method;

/**
 * §3's password policy: the business's own minimum, but never below the
 * system's. A setting that could weaken the floor would make the policy a
 * suggestion.
 */
export async function assertPasswordMeetsPolicy({ businessId, password, conn }) {
  const configured = Number(await readSetting({ businessId, key: "security.min_password_length", conn }));
  const minimum = Math.max(ABSOLUTE_MIN_PASSWORD_LENGTH, Number.isFinite(configured) ? configured : 0);

  if (String(password).length < minimum) {
    throw errors.validation(`A password must be at least ${minimum} characters.`);
  }
  return minimum;
}

/** §44's default low-stock threshold, for products with none of their own. */
export async function lowStockDefault({ businessId, conn }) {
  const configured = Number(
    await readSetting({ businessId, key: "inventory.low_stock_threshold_default", conn })
  );
  return Number.isFinite(configured) && configured >= 0 ? configured : 0;
}
