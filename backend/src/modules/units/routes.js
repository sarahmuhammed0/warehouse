import { Router } from "express";

import { authenticate } from "../../middleware/authenticate.js";
import { requireAccountType } from "../../middleware/requireAccountType.js";
import { authorize } from "../../middleware/authorize.js";
import { auditTrail } from "../../middleware/auditTrail.js";
import { validate, validateRequest } from "../../middleware/validate.js";
import { idParamsSchema, listQuerySchema } from "../../validation/common.js";
import { createUnitSchema, updateUnitSchema } from "./validation.js";
import { listUnits, getUnit, createUnit, updateUnit, deleteUnit } from "./controller.js";

export const unitsRouter = Router();

// Business users only, and always authenticated. A System Admin has no
// business context, so a tenant-scoped route would have nothing to scope to
// — see docs/multi-tenancy.md.
unitsRouter.use(authenticate, requireAccountType("business_user"), auditTrail("products"));

/**
 * GATED ON `products.*`, NOT `settings.*`, and that is a judgement call
 * worth recording. §34 lists Units under Settings, which would suggest
 * `settings.edit` — but only the owner role holds `settings.*` by default,
 * so that reading would stop a Warehouse Manager ("Inventory, products,
 * transfers, stock", §23) from adding a unit like "Pallet". §8 lists Unit of
 * measurement as a product field, and the people who manage products are
 * the people who need units, so the product permissions are the honest fit.
 */
unitsRouter.get("/", authorize("products.view"), validate(listQuerySchema, "query"), listUnits);
unitsRouter.get("/:id", authorize("products.view"), validate(idParamsSchema, "params"), getUnit);

unitsRouter.post("/", authorize("products.create"), validate(createUnitSchema), createUnit);

unitsRouter.patch(
  "/:id",
  authorize("products.edit"),
  validateRequest({ params: idParamsSchema, body: updateUnitSchema }),
  updateUnit
);

unitsRouter.delete(
  "/:id",
  authorize("products.delete"),
  validate(idParamsSchema, "params"),
  deleteUnit
);
