// The one kind of error a route/service is expected to throw on purpose.
// The central error handler (middleware/errorHandler.js) knows how to turn
// this into the API's standard error envelope; anything that isn't an
// AppError is treated as unexpected and never shown to the client verbatim
// (see §31/§53 of the architecture blueprint).
//
// Every message passed here is written for a user to read: §53's rule is
// that the client sees understandable language and the server keeps the
// technical detail. If a message would only make sense to whoever wrote the
// query, it belongs in a log line, not in an AppError.

export class AppError extends Error {
  /**
   * @param {string} code    stable machine-readable code, e.g. "NOT_FOUND"
   * @param {string} message plain language, safe to show a user
   * @param {number} [statusCode]
   * @param {Record<string, unknown>} [details] optional field-level detail,
   *   used by validation so a form can highlight the offending inputs.
   *   Must contain nothing internal — it is returned to the client.
   */
  constructor(code, message, statusCode = 400, details) {
    super(message);
    this.name = "AppError";
    this.code = code;
    this.statusCode = statusCode;
    if (details) this.details = details;
  }
}

/** The small set of errors that come up in every module. */
export const errors = {
  notFound: (what = "record") =>
    new AppError("NOT_FOUND", `That ${what} could not be found.`, 404),
  validation: (message, details) => new AppError("VALIDATION_ERROR", message, 422, details),
  conflict: (message) => new AppError("CONFLICT", message, 409),
  forbidden: (message = "You do not have permission to do that.") =>
    new AppError("FORBIDDEN", message, 403),
  unauthorized: (message = "Please sign in again.") =>
    new AppError("UNAUTHORIZED", message, 401),
};
