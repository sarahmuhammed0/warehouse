import { Router } from "express";
import { z } from "zod";

import { authenticate } from "../../middleware/authenticate.js";
import { requireAccountType } from "../../middleware/requireAccountType.js";
import { authorize } from "../../middleware/authorize.js";
import { auditTrail } from "../../middleware/auditTrail.js";
import { validate, validateRequest } from "../../middleware/validate.js";
import {
  idParamsSchema,
  idSchema,
  listQuerySchema,
  optionalString,
  enumSchema,
  moneySchema,
  positiveQuantitySchema,
  optionalDateSchema,
} from "../../validation/common.js";
import { list, get, create, updateStatus, getBom, putBom } from "./controller.js";

const materialSchema = z.object({
  materialProductId: idSchema,
  variantId: idSchema.nullable().optional(),
  // The TOTAL this run needs, not the per-unit figure — the per-unit figure
  // lives in the bill of materials and is multiplied out when the run is
  // created from it.
  quantityRequired: positiveQuantitySchema,
  unitCost: moneySchema.optional(),
});

const createSchema = z.object({
  productId: idSchema,
  variantId: idSchema.nullable().optional(),
  warehouseId: idSchema.nullable().optional(),
  quantityPlanned: positiveQuantitySchema,
  batchNumber: optionalString(100),
  // Left out, the materials come from the product's bill of materials (§21).
  materials: z.array(materialSchema).optional(),
  assignedUserId: idSchema.nullable().optional(),
  productionDate: optionalDateSchema,
  note: optionalString(5000),
  status: enumSchema(["planned", "in_progress"], "Status").optional(),
});

const statusSchema = z.object({
  status: enumSchema(["planned", "in_progress", "completed", "cancelled"], "Status"),
  // §22 keeps planned and produced quantities apart because a batch yields what
  // it yields. Left out on completion, the run is taken to have made what it
  // planned.
  quantityProduced: positiveQuantitySchema.optional(),
});

const bomSchema = z.object({
  // An empty list is a real edit: it clears the recipe. `min(1)` would leave a
  // product that should no longer be made from anything stuck with its old one.
  lines: z.array(
    z.object({
      materialProductId: idSchema,
      quantityPerUnit: positiveQuantitySchema,
      unitId: idSchema.nullable().optional(),
      note: optionalString(2000),
    })
  ),
});

export const productionRouter = Router();
productionRouter.use(authenticate, requireAccountType("business_user"), auditTrail("production"));

productionRouter.get("/", authorize("production.view"), validate(listQuerySchema, "query"), list);
productionRouter.get("/:id", authorize("production.view"), validate(idParamsSchema, "params"), get);
productionRouter.post("/", authorize("production.create"), validate(createSchema), create);

productionRouter.patch(
  "/:id/status",
  authorize("production.edit"),
  validateRequest({ params: idParamsSchema, body: statusSchema }),
  updateStatus
);

/**
 * §21's bill of materials, hung off the product it belongs to.
 *
 * Gated on `production.*` rather than `products.*`: a BOM is a manufacturing
 * recipe, and §24 gives Production its own permissions. A shop that does not
 * manufacture never grants them and never sees this.
 */
export const productBomRouter = Router();
productBomRouter.use(authenticate, requireAccountType("business_user"), auditTrail("production"));

productBomRouter.get(
  "/:id/bom",
  authorize("production.view"),
  validate(idParamsSchema, "params"),
  getBom
);

productBomRouter.put(
  "/:id/bom",
  authorize("production.edit"),
  validateRequest({ params: idParamsSchema, body: bomSchema }),
  putBom
);
