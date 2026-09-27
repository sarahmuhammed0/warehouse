// Centralized error-handling foundation (architecture §31, spec §53).
//
// This is the ONLY place an exception becomes an HTTP response. Three cases,
// in order:
//
//   1. A deliberately-thrown AppError → its own code/message/status. The
//      module that threw it chose wording a user can act on.
//   2. A MySQL driver error that corresponds to something the client can
//      fix (a duplicate, a dangling reference, a CHECK violation) → mapped
//      by utils/databaseError.js to an AppError, again with safe wording.
//   3. Anything else — a bug, a syntax error, a library's internal failure
//      → logged in full server-side, and answered with one generic message.
//
// Case 3 is the rule §53 spells out: the client must never see the SQL, the
// stack, a table or column name, a file path, or a driver's own string.
// Case 2 exists so that rule does not cost the user the one piece of
// information they actually needed.

import { fail } from "../utils/responseEnvelope.js";
import { logger } from "../utils/logger.js";
import { AppError } from "../utils/AppError.js";
import { toAppError } from "../utils/databaseError.js";

// eslint-disable-next-line no-unused-vars
export function errorHandler(err, req, res, next) {
  const appError = err instanceof AppError ? err : toAppError(err);

  if (appError) {
    // 4xx is the client's business and routine — not worth an error log.
    // 5xx we caused, so it is logged with the original error attached even
    // though the client is told something generic.
    if (appError.statusCode >= 500) {
      logger.error({ err, code: appError.code }, "Request failed (5xx)");
    } else if (appError.code === "CONCURRENT_UPDATE") {
      // The one 4xx worth more than a debug line. It is not the client's
      // mistake — it is a deadlock or a lock timeout, i.e. contention in our
      // own transactions — and it looks identical to an ordinary business-rule
      // 409 from the outside. An intermittent 409 that nobody can explain is
      // exactly what this turns into a log entry naming the query that lost.
      logger.warn({ err, code: appError.code }, "Request hit lock contention (409)");
    } else {
      logger.debug({ code: appError.code, statusCode: appError.statusCode }, "Request rejected");
    }
    return res
      .status(appError.statusCode)
      .json(fail(appError.code, appError.message, appError.details));
  }

  // Unexpected. The full error — message, stack, and for a driver error its
  // `code`/`errno`/`sqlMessage` — goes to the log, which is the one place
  // §53 says technical detail belongs.
  logger.error({ err }, "Unhandled error");
  return res
    .status(500)
    .json(fail("INTERNAL_ERROR", "Something went wrong. Please try again."));
}
