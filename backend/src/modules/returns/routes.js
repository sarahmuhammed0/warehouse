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
  requiredString,
  optionalString,
  enumSchema,
  moneySchema,
  positiveQuantitySchema,
  optionalDateSchema,
} from "../../validation/common.js";
import { list, get, create, updateStatus, returnable } from "./controller.js";

const returnItemSchema = z.object({
  // A return names the ORDER LINE, not just the product: the same product can
  // appear twice on one order at two prices, and a refund has to know which.
  orderItemId: idSchema,
  quantity: positiveQuantitySchema,
  // §16's per-item condition, which is what decides whether it goes back into
  // stock on completion.
  condition: enumSchema(["sellable", "damaged"], "Condition").optional(),
});

const createReturnSchema = z.object({
  orderId: idSchema,
  items: z.array(returnItemSchema).min(1, "A return needs at least one item."),
  reason: requiredString(500, "A reason"),
  // Optional: left out, the refund is everything the customer paid for the
  // returned quantities. Sent, it is capped at that same figure.
  refundAmount: moneySchema.optional(),
  note: optionalString(5000),
  returnDate: optionalDateSchema,
});

const statusSchema = z.object({
  status: enumSchema(["approved", "rejected", "completed"], "Status"),
});

export const returnsRouter = Router();
returnsRouter.use(authenticate, requireAccountType("business_user"), auditTrail("returns"));

returnsRouter.get("/", authorize("returns.view"), validate(listQuerySchema, "query"), list);
returnsRouter.get("/:id", authorize("returns.view"), validate(idParamsSchema, "params"), get);
returnsRouter.post("/", authorize("returns.create"), validate(createReturnSchema), create);

/**
 * Gated on `returns.approve` — the one action §24 gives only to Returns and
 * Purchases. Approving a return refunds money and puts goods back on the
 * shelf, which is not the same decision as raising the request.
 */
returnsRouter.patch(
  "/:id/status",
  authorize("returns.approve"),
  validateRequest({ params: idParamsSchema, body: statusSchema }),
  updateStatus
);

/**
 * What an order still has left to return.
 *
 * Mounted under the returns router rather than orders because it answers a
 * returns question and is gated on `returns.create` — someone who may raise a
 * return needs it, and it tells them nothing about the order they could not
 * already see.
 */
export const orderReturnableRouter = Router();
orderReturnableRouter.use(authenticate, requireAccountType("business_user"));
orderReturnableRouter.get(
  "/:id/returnable",
  authorize("returns.create"),
  validate(idParamsSchema, "params"),
  returnable
);
