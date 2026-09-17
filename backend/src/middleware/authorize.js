// Authorization middleware — permission layer (architecture §8/§9). Still
// NOT mounted anywhere in Phase 2: there is no permission catalog or
// role_permissions table yet (full RBAC is explicitly deferred — see
// docs/phase2-traceability.md). Updated to read `req.auth` (Phase 2's
// shape, set by middleware/authenticate.js) instead of Phase 0's
// placeholder `req.context`, so this is ready to mount in whichever phase
// adds real permissions, without another rename.
//
// This will be the ONLY place a fine-grained permission check happens —
// per §9, the frontend's own permission checks are UX-only and never a
// substitute for this running on the backend.

import { AppError } from "../utils/AppError.js";

/**
 * @param {string} permission - e.g. "products.create" (architecture §9's
 *   `{module}.{action}` shape)
 */
export function authorize(permission) {
  return (req, res, next) => {
    if (!req.auth) {
      return next(new AppError("UNAUTHENTICATED", "Authentication required.", 401));
    }

    if (req.auth.accountType === "system_admin") return next();

    if (!req.auth.permissions?.includes(permission)) {
      return next(
        new AppError("FORBIDDEN", "You do not have permission to perform this action.", 403)
      );
    }

    next();
  };
}
