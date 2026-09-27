import { Router } from "express";
import { z } from "zod";

import { authenticate } from "../../middleware/authenticate.js";
import { requireAccountType } from "../../middleware/requireAccountType.js";
import { authorize } from "../../middleware/authorize.js";
import { auditTrail } from "../../middleware/auditTrail.js";
import { validate, validateRequest } from "../../middleware/validate.js";
import { idParamsSchema, listQuerySchema, idSchema } from "../../validation/common.js";
import {
  createWarehouseSchema,
  updateWarehouseSchema,
  createStorageLocationSchema,
  updateStorageLocationSchema,
} from "./validation.js";
import {
  listWarehouses,
  listWarehouseOptions,
  getWarehouse,
  createWarehouse,
  updateWarehouse,
  deleteWarehouse,
  listStorageLocations,
  listStorageLocationOptions,
  getStorageLocation,
  createStorageLocation,
  updateStorageLocation,
  deleteStorageLocation,
} from "./controller.js";

/**
 * `?warehouseId=` on the options route. Unvalidated it reached Number(), and
 * `?warehouseId=abc` became NaN — which MySQL rejects as a bound parameter, so
 * a typo in a query string was a 500 rather than a 422.
 */
const locationOptionsQuerySchema = z.object({ warehouseId: idSchema.optional() });

/**
 * Warehouses and storage locations are §11's Inventory module — where stock
 * lives — so they are gated on `inventory.*`, not on a permission of their
 * own. §24's catalogue has no "warehouses" module, and inventing one would
 * mean a permission the Flutter client cannot offer.
 */
export const warehousesRouter = Router();
warehousesRouter.use(authenticate, requireAccountType("business_user"), auditTrail("inventory"));

warehousesRouter.get("/", authorize("inventory.view"), validate(listQuerySchema, "query"), listWarehouses);
warehousesRouter.get("/options", authorize("inventory.view"), listWarehouseOptions);
warehousesRouter.get("/:id", authorize("inventory.view"), validate(idParamsSchema, "params"), getWarehouse);
warehousesRouter.post("/", authorize("inventory.create"), validate(createWarehouseSchema), createWarehouse);
warehousesRouter.patch(
  "/:id",
  authorize("inventory.edit"),
  validateRequest({ params: idParamsSchema, body: updateWarehouseSchema }),
  updateWarehouse
);
warehousesRouter.delete(
  "/:id",
  authorize("inventory.delete"),
  validate(idParamsSchema, "params"),
  deleteWarehouse
);

export const storageLocationsRouter = Router();
storageLocationsRouter.use(authenticate, requireAccountType("business_user"), auditTrail("inventory"));

storageLocationsRouter.get(
  "/",
  authorize("inventory.view"),
  validate(listQuerySchema, "query"),
  listStorageLocations
);
storageLocationsRouter.get(
  "/options",
  authorize("inventory.view"),
  validate(locationOptionsQuerySchema, "query"),
  listStorageLocationOptions
);
storageLocationsRouter.get(
  "/:id",
  authorize("inventory.view"),
  validate(idParamsSchema, "params"),
  getStorageLocation
);
storageLocationsRouter.post(
  "/",
  authorize("inventory.create"),
  validate(createStorageLocationSchema),
  createStorageLocation
);
storageLocationsRouter.patch(
  "/:id",
  authorize("inventory.edit"),
  validateRequest({ params: idParamsSchema, body: updateStorageLocationSchema }),
  updateStorageLocation
);
storageLocationsRouter.delete(
  "/:id",
  authorize("inventory.delete"),
  validate(idParamsSchema, "params"),
  deleteStorageLocation
);
