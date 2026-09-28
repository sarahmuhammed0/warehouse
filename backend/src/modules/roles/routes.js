import { Router } from "express";
import { z } from "zod";

import { authenticate } from "../../middleware/authenticate.js";
import { requireAccountType } from "../../middleware/requireAccountType.js";
import { authorize } from "../../middleware/authorize.js";
import { auditTrail } from "../../middleware/auditTrail.js";
import { validate, validateRequest } from "../../middleware/validate.js";
import { idParamsSchema, requiredString, optionalString } from "../../validation/common.js";
import { list, catalogue, create, rename, setPermissions, remove } from "./controller.js";

/** A `{module}.{action}` key, as §24 spells them. */
const permissionKeySchema = z
  .string()
  .regex(/^[a-z_]+\.[a-z_]+$/, "A permission looks like products.view.")
  .max(100);

const createRoleSchema = z.object({
  name: requiredString(100, "A role name"),
  description: optionalString(255),
  permissions: z.array(permissionKeySchema).max(200).optional(),
});

const renameRoleSchema = z
  .object({ name: optionalString(100), description: optionalString(255) })
  .refine((value) => Object.values(value).some((v) => v !== undefined), {
    message: "Provide at least one field to update.",
  });

const permissionsSchema = z.object({
  // An empty array is a real edit — a role that may do nothing yet. `min(1)`
  // would make "untick everything and save" impossible to express.
  permissions: z.array(permissionKeySchema).max(200),
});

export const rolesRouter = Router();
rolesRouter.use(authenticate, requireAccountType("business_user"), auditTrail("users"));

/**
 * Gated on `users.*`, and filed in the activity trail under `users`.
 *
 * §24 gives no "roles" module of its own, and role management IS user
 * management: what a role may do decides what its holders may do. Anyone who
 * can edit roles can grant themselves anything, which is exactly the authority
 * `users.edit` already represents — inventing a separate, narrower permission
 * would only make that authority look smaller than it is.
 */
rolesRouter.get("/", authorize("users.view"), list);

/**
 * The permission catalogue. Gated on `users.view` rather than left open:
 * it is the map of everything this system can authorize, which is not
 * information an ordinary employee's screen needs.
 */
rolesRouter.get("/permissions", authorize("users.view"), catalogue);

rolesRouter.post("/", authorize("users.create"), validate(createRoleSchema), create);

rolesRouter.patch(
  "/:id",
  authorize("users.edit"),
  validateRequest({ params: idParamsSchema, body: renameRoleSchema }),
  rename
);

rolesRouter.put(
  "/:id/permissions",
  authorize("users.edit"),
  validateRequest({ params: idParamsSchema, body: permissionsSchema }),
  setPermissions
);

rolesRouter.delete("/:id", authorize("users.delete"), validate(idParamsSchema, "params"), remove);
