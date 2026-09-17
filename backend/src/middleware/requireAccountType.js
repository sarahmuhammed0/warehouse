// Authorization foundation, account-type layer (§10/§12). Must run after
// `authenticate`. This is the boundary that stops a business user from
// ever reaching a System Admin route (or vice versa) — independent of,
// and prior to, whatever fine-grained permission system a later phase
// adds. `requireAccountType('business_user')` on every business-app route,
// `requireAccountType('system_admin')` on every admin route.

import { AppError } from "../utils/AppError.js";

export function requireAccountType(accountType) {
  return (req, res, next) => {
    if (!req.auth) {
      return next(new AppError("UNAUTHENTICATED", "Authentication required.", 401));
    }
    if (req.auth.accountType !== accountType) {
      return next(
        new AppError("FORBIDDEN", "You do not have permission to perform this action.", 403)
      );
    }
    next();
  };
}
