import { Router } from "express";
import { z } from "zod";

import { authenticate } from "../../middleware/authenticate.js";
import { requireAccountType } from "../../middleware/requireAccountType.js";
import { authorize } from "../../middleware/authorize.js";
import { validate } from "../../middleware/validate.js";
import { idSchema, optionalString, listQuerySchema, enumSchema } from "../../validation/common.js";
import { getLevels, getMovements, getLowStock, adjust, transfer } from "./controller.js";

/**
 * §12's manual movement types only. A sale or a purchase also moves stock,
 * but through its own module with its document attached — letting a client
 * post `movementType: "sale"` here would create sales history with no sale
 * behind it.
 */
const manualMovementType = enumSchema(
  ["adjustment", "damage", "manual_increase", "manual_decrease"],
  "Movement type"
);

const adjustSchema = z
  .object({
    productId: idSchema,
    warehouseId: idSchema,
    locationId: idSchema.nullable().optional(),
    // Signed: negative removes stock. Bounded so a typo cannot ask for a
    // quantity the DECIMAL(14,3) column could not hold anyway.
    quantity: z.coerce.number().refine((n) => n !== 0, "The quantity must not be zero.").refine(
      (n) => Math.abs(n) <= 99999999999,
      "That quantity is too large."
    ),
    movementType: manualMovementType,
    reason: optionalString(255),
    note: optionalString(2000),
  })
  .refine((v) => !(v.movementType === "manual_increase" && v.quantity < 0), {
    message: "A manual increase cannot have a negative quantity.",
    path: ["quantity"],
  })
  .refine((v) => !(v.movementType === "manual_decrease" && v.quantity > 0), {
    message: "A manual decrease cannot have a positive quantity.",
    path: ["quantity"],
  })
  .refine((v) => !(v.movementType === "damage" && v.quantity > 0), {
    message: "Damaged stock must be recorded as a negative quantity.",
    path: ["quantity"],
  });

const transferSchema = z.object({
  productId: idSchema,
  fromWarehouseId: idSchema,
  fromLocationId: idSchema.nullable().optional(),
  toWarehouseId: idSchema,
  toLocationId: idSchema.nullable().optional(),
  quantity: z.coerce.number().positive("The transfer quantity must be greater than zero."),
  note: optionalString(2000),
});

export const inventoryRouter = Router();

inventoryRouter.use(authenticate, requireAccountType("business_user"));

inventoryRouter.get("/", authorize("inventory.view"), validate(listQuerySchema, "query"), getLevels);
inventoryRouter.get("/movements", authorize("inventory.view"), validate(listQuerySchema, "query"), getMovements);
inventoryRouter.get("/low-stock", authorize("inventory.view"), getLowStock);

// Changing stock is `inventory.edit`, not `.create`: §24's actions are about
// the module, and adjusting a level is editing inventory rather than
// creating a new thing. It is also what Inventory Staff hold (§23).
inventoryRouter.post("/adjust", authorize("inventory.edit"), validate(adjustSchema), adjust);
inventoryRouter.post("/transfer", authorize("inventory.edit"), validate(transferSchema), transfer);
