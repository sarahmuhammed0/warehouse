// Authorization middleware — the permission layer (§24).
//
// This is the ONLY place a fine-grained permission check happens. The
// Flutter client also knows the permission catalogue, but that is UX: it
// hides buttons the user cannot use. It is never a substitute for this,
// because a client can be modified and the server cannot.

import { AppError } from "../utils/AppError.js";
import { permissionsForUser } from "../modules/rbac/repository.js";

/**
 * Permissions are read from the database, not from the access token.
 *
 * A token that carried its grants would keep them until it expired — up to
 * fifteen minutes of access after an administrator revoked them. Resolving
 * per request means a permission change takes effect on the next request.
 *
 * Loaded lazily and cached on the request: most endpoints check one
 * permission, some check none, and an eager load in `authenticate` would
 * add a query to every authenticated call including refresh and /me.
 */
async function permissionsFor(req) {
  if (req.auth.permissions) return req.auth.permissions;
  const permissions = await permissionsForUser(req.auth.userId);
  req.auth.permissions = permissions;
  return permissions;
}

/**
 * @param {string} permission - `{module}.{action}`, e.g. "products.create".
 *   Must be a key that exists in the catalogue
 *   (`src/modules/rbac/catalog.js`) — a typo here would be a permission
 *   nobody can ever hold, which fails closed but silently.
 */
export function authorize(permission) {
  return async function authorizeRequest(req, res, next) {
    try {
      if (!req.auth) {
        return next(new AppError("UNAUTHENTICATED", "Authentication required.", 401));
      }

      // A System Admin is a platform operator, not a member of any business,
      // so business-scoped permissions do not apply to them. What keeps them
      // out of a tenant's data is `requireAccountType` on those routes, not
      // this check — see docs/multi-tenancy.md.
      if (req.auth.accountType === "system_admin") return next();

      const permissions = await permissionsFor(req);
      if (!permissions.includes(permission)) {
        // Deliberately does not name the permission. Telling a caller
        // exactly which grant they lack maps out the authorization model for
        // anyone probing it, and the user cannot act on it anyway — only an
        // administrator can change their role.
        return next(
          new AppError("FORBIDDEN", "You do not have permission to perform this action.", 403)
        );
      }

      next();
    } catch (err) {
      next(err);
    }
  };
}

/**
 * For a handler that needs the caller's permissions without gating on one —
 * a list endpoint that hides monetary columns unless `financial.view` is
 * held, for example. Returns an array, never throws for "no role".
 */
export async function loadPermissions(req) {
  if (!req.auth || req.auth.accountType !== "business_user") return [];
  return permissionsFor(req);
}
