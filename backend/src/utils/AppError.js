// The one kind of error a route/service is expected to throw on purpose.
// The central error handler (middleware/errorHandler.js) knows how to turn
// this into the API's standard error envelope; anything that isn't an
// AppError is treated as unexpected and never shown to the client verbatim
// (see §31/§53 of the architecture blueprint).

export class AppError extends Error {
  constructor(code, message, statusCode = 400) {
    super(message);
    this.name = "AppError";
    this.code = code;
    this.statusCode = statusCode;
  }
}
