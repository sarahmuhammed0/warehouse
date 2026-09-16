// Centralized error-handling foundation (architecture §31/§53).
//
// This is the ONLY place an exception becomes an HTTP response. A known,
// deliberately-thrown AppError maps straight to its public message. Anything
// else (a bug, a driver error, a typo) is logged with full detail server-side
// and shown to the client as one generic, safe message — never a stack trace,
// a SQL fragment, or a library's internal error string.

import { fail } from "../utils/responseEnvelope.js";
import { logger } from "../utils/logger.js";
import { AppError } from "../utils/AppError.js";

// eslint-disable-next-line no-unused-vars
export function errorHandler(err, req, res, next) {
  if (err instanceof AppError) {
    if (err.statusCode >= 500) {
      logger.error({ err }, "AppError (5xx)");
    }
    return res.status(err.statusCode).json(fail(err.code, err.message));
  }

  // Unexpected error — never leaked to the client (§53's exact example:
  // a raw ORM/driver error string must never reach the user).
  logger.error({ err }, "Unhandled error");
  return res
    .status(500)
    .json(fail("INTERNAL_ERROR", "Something went wrong. Please try again."));
}
