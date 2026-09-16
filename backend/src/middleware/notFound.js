import { AppError } from "../utils/AppError.js";

// Catches any request that matched no route. Placed after all routers,
// before the error handler, so an unknown path becomes a normal AppError
// instead of Express's default HTML 404 page.
export function notFound(req, res, next) {
  next(new AppError("NOT_FOUND", `Route not found: ${req.method} ${req.originalUrl}`, 404));
}
