// Authentication middleware (architecture §7/§8, wired up in Phase 2).
//
// Sets req.auth = { accountType, userId, businessId } from a verified
// access-token JWT — businessId is what §10's tenant isolation reads on
// every request; it is never taken from a route param, query string, or
// request body. `userId` is the authenticated subject's id in whichever
// table `accountType` names ('business_user' → users.id, 'system_admin' →
// system_admins.id) — the two id spaces are never conflated because every
// tenant-scoped query is additionally gated by `requireAccountType`
// (see routes) before it can run.

import { verifyAccessToken } from "../utils/token.js";
import { AppError } from "../utils/AppError.js";

export function authenticate(req, res, next) {
  const header = req.headers.authorization || "";
  const [scheme, token] = header.split(" ");

  if (scheme !== "Bearer" || !token) {
    return next(new AppError("UNAUTHENTICATED", "Authentication required.", 401));
  }

  const payload = verifyAccessToken(token);

  if (payload.accountType !== "business_user" && payload.accountType !== "system_admin") {
    return next(new AppError("INVALID_TOKEN", "Session is invalid or has expired.", 401));
  }

  req.auth = {
    accountType: payload.accountType,
    userId: payload.userId,
    businessId: payload.accountType === "business_user" ? (payload.businessId ?? null) : null,
  };
  next();
}
