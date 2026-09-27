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
import { list, get, create, updateStatus, addPayment } from "./controller.js";

const purchaseItemSchema = z.object({
  productId: idSchema,
  variantId: idSchema.nullable().optional(),
  quantity: positiveQuantitySchema,
  // §25 reports on purchase cost, so the cost is what the business actually
  // paid per unit on this delivery — not the product's standing cost, which
  // changes with the next negotiation.
  unitCost: moneySchema,
  discountAmount: moneySchema.optional(),
  taxAmount: moneySchema.optional(),
});

const createPurchaseSchema = z.object({
  supplierId: idSchema.nullable().optional(),
  items: z.array(purchaseItemSchema).min(1, "A purchase needs at least one item."),
  discountAmount: moneySchema.optional(),
  extraCharges: moneySchema.optional(),
  paidAmount: moneySchema.optional(),
  paymentMethod: enumSchema(["cash", "bank_transfer", "card", "other"], "Payment method").optional(),
  paymentReference: optionalString(100),
  note: optionalString(5000),
  purchaseDate: optionalDateSchema,
  // `completed` is allowed at creation for the common case of entering a
  // delivery that has already arrived; `draft` for one still being assembled.
  status: enumSchema(["draft", "pending", "completed"], "Status").optional(),
});

const statusSchema = z.object({
  status: enumSchema(["draft", "pending", "completed", "cancelled"], "Status"),
});

const paymentSchema = z.object({
  amount: moneySchema.refine((v) => v > 0, "A payment must be greater than zero."),
  method: enumSchema(["cash", "bank_transfer", "card", "other"], "Payment method"),
  reference: optionalString(100),
  note: optionalString(2000),
});

export const purchasesRouter = Router();
purchasesRouter.use(authenticate, requireAccountType("business_user"), auditTrail("purchases"));

purchasesRouter.get("/", authorize("purchases.view"), validate(listQuerySchema, "query"), list);
purchasesRouter.get("/:id", authorize("purchases.view"), validate(idParamsSchema, "params"), get);
purchasesRouter.post("/", authorize("purchases.create"), validate(createPurchaseSchema), create);

/**
 * Gated on `purchases.approve`, not `purchases.edit`.
 *
 * §24 gives Purchases an Approve action — which only exists because deciding a
 * delivery has arrived is the decision that moves stock and commits the
 * business to paying for it. Editing a purchase's note is not that decision, so
 * the two are not the same permission.
 */
purchasesRouter.patch(
  "/:id/status",
  authorize("purchases.approve"),
  validateRequest({ params: idParamsSchema, body: statusSchema }),
  updateStatus
);

purchasesRouter.post(
  "/:id/payments",
  authorize("purchases.edit"),
  validateRequest({ params: idParamsSchema, body: paymentSchema }),
  addPayment
);
