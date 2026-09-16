// Authorization middleware foundation (architecture §8/§9). NOT mounted
// anywhere yet — nothing to authorize until Phase 1 has real modules and a
// real permission catalog. `authorize()` must always run after
// `authenticate()`, which is what populates `req.context`.
//
// This is the ONLY place a permission check happens for a protected route —
// per §9, the frontend's own permission checks are UX-only and never a
// substitute for this running on the backend.

import { AppError } from "../utils/AppError.js";

/**
 * @param {string} permission - e.g. "products.create" (architecture §9's
 *   `{module}.{action}` shape)
 */
export function authorize(permission) {
  return (req, res, next) => {
    if (!req.context) {
      return next(new AppError("UNAUTHENTICATED", "Authentication required.", 401));
    }

    if (req.context.isSystemAdmin) return next();

    if (!req.context.permissions.includes(permission)) {
      return next(
        new AppError("FORBIDDEN", "You do not have permission to perform this action.", 403)
      );
    }

    next();
  };
}
