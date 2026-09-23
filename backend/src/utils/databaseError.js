// Turns a MySQL driver error into an AppError the client may see.
//
// §53 is unambiguous: never expose SQL errors, and show something a person
// can act on instead. But mapping every driver error to a generic 500 loses
// real information — a duplicate SKU is the user's problem and they can fix
// it, while a broken connection is ours and they cannot. So the handful of
// driver codes that correspond to a *user-correctable* situation are
// translated, and everything else is deliberately not: it returns null, and
// the central error handler logs it in full and answers with the generic
// message.
//
// What is never included in the returned message: the SQL, the table or
// column names, the constraint name, the driver's own text, or any value
// from the row. A constraint name like `uq_products_sku` leaks the schema;
// worse, echoing the conflicting value back can confirm the existence of
// another tenant's record. Callers that want to name the field pass a
// `fieldLabels` map, written in code.

import { AppError } from "./AppError.js";

/**
 * @param {unknown} error       anything thrown by mysql2
 * @param {object} [options]
 * @param {Record<string, string>} [options.constraintMessages]
 *   Maps a constraint/index name to the message the user should see, e.g.
 *   `{ uq_products_sku: "A product with this SKU already exists." }`.
 *   Written in code by the module that owns the table.
 * @param {string} [options.conflictMessage] fallback for a duplicate.
 * @returns {AppError | null} null when the error is not client-correctable.
 */
export function toAppError(error, options = {}) {
  const code = error?.code;
  if (typeof code !== "string") return null;

  switch (code) {
    // Unique constraint. §54's "duplicate SKUs / duplicate document
    // numbers" arriving here rather than being pre-checked is the *correct*
    // outcome under concurrency: a check-then-insert has a race, the unique
    // index does not.
    case "ER_DUP_ENTRY":
    case "ER_DUP_KEY": {
      const constraint = constraintNameOf(error);
      const mapped = constraint ? options.constraintMessages?.[constraint] : undefined;
      return new AppError(
        "CONFLICT",
        mapped ?? options.conflictMessage ?? "That record already exists.",
        409
      );
    }

    // Foreign key: the request referenced something that does not exist
    // (or tried to remove something still referenced). Both are the
    // client's to fix, and both are 422 rather than 500.
    case "ER_NO_REFERENCED_ROW":
    case "ER_NO_REFERENCED_ROW_2":
      return new AppError(
        "VALIDATION_ERROR",
        "One of the selected records no longer exists. Refresh and try again.",
        422
      );

    case "ER_ROW_IS_REFERENCED":
    case "ER_ROW_IS_REFERENCED_2":
      return new AppError(
        "CONFLICT",
        "This record is still in use elsewhere and cannot be removed.",
        409
      );

    // A CHECK constraint refused the row — a negative quantity, a payment
    // attached to both an order and a purchase. The schema's constraints
    // are the last line of §54's validation, so reaching one means the
    // request was invalid.
    case "ER_CHECK_CONSTRAINT_VIOLATED":
      return new AppError("VALIDATION_ERROR", "Those values are not valid for this record.", 422);

    case "ER_DATA_TOO_LONG":
      return new AppError("VALIDATION_ERROR", "One of the values is too long.", 422);

    case "ER_BAD_NULL_ERROR":
      return new AppError("VALIDATION_ERROR", "A required value is missing.", 422);

    case "ER_WARN_DATA_OUT_OF_RANGE":
    case "ER_TRUNCATED_WRONG_VALUE":
    case "ER_TRUNCATED_WRONG_VALUE_FOR_FIELD":
      return new AppError("VALIDATION_ERROR", "One of the values is not in a valid format.", 422);

    // Deadlock / lock timeout. Transient and genuinely retryable — worth
    // its own code so a client can retry instead of surfacing a failure,
    // and worth 409 rather than 500 because nothing is broken.
    case "ER_LOCK_DEADLOCK":
    case "ER_LOCK_WAIT_TIMEOUT":
      return new AppError(
        "CONCURRENT_UPDATE",
        "Another change was being saved at the same time. Please try again.",
        409
      );

    // Infrastructure. Not the client's fault and not their business, but a
    // 503 tells them it is worth retrying, which a 500 does not.
    case "ECONNREFUSED":
    case "PROTOCOL_CONNECTION_LOST":
    case "ER_CON_COUNT_ERROR":
    case "ETIMEDOUT":
      return new AppError("SERVICE_UNAVAILABLE", "The service is temporarily unavailable.", 503);

    default:
      // Everything else — including every syntax error and every access
      // denial, which are bugs or misconfiguration, never something to
      // describe to a user.
      return null;
  }
}

/**
 * Pulls the index name out of a duplicate-key error so the caller's
 * `constraintMessages` map can be consulted. MySQL's message is
 * "Duplicate entry 'x' for key 'products.uq_products_sku'"; the schema
 * qualifier is dropped. Used only as a lookup key — never echoed.
 */
function constraintNameOf(error) {
  const match = /for key '(?:[^'.]+\.)?([^']+)'/.exec(error?.sqlMessage ?? error?.message ?? "");
  return match?.[1];
}
