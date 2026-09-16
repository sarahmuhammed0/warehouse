// Authentication middleware foundation (architecture §7/§8).
//
// NOT mounted on any route yet — there is no /api/auth/login to issue a
// token in Phase 0, so wiring this in now would only ever reject requests.
// It exists so Phase 1 adds one line (`app.use('/api', authenticate, ...)`
// or per-route) instead of writing this from scratch, and so the shape of
// `req.context` is decided once, here, not reinvented per module.
//
// Sets req.context = { userId, businessId, isSystemAdmin, permissions }
// from a verified JWT — businessId is what §7's tenant isolation reads on
// every request; it is never taken from a route param or request body.

import { verifyAccessToken } from "../utils/token.js";
import { AppError } from "../utils/AppError.js";

export function authenticate(req, res, next) {
  const header = req.headers.authorization || "";
  const [scheme, token] = header.split(" ");

  if (scheme !== "Bearer" || !token) {
    return next(new AppError("UNAUTHENTICATED", "Authentication required.", 401));
  }

  const payload = verifyAccessToken(token);
  req.context = {
    userId: payload.userId,
    businessId: payload.businessId ?? null,
    isSystemAdmin: Boolean(payload.isSystemAdmin),
    permissions: payload.permissions ?? [],
  };
  next();
}
