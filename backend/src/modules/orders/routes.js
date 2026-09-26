import { Router } from "express";
import { z } from "zod";

import { authenticate } from "../../middleware/authenticate.js";
import { requireAccountType } from "../../middleware/requireAccountType.js";
import { authorize } from "../../middleware/authorize.js";
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

const orderItemSchema = z.object({
  productId: idSchema,
  variantId: idSchema.nullable().optional(),
  quantity: positiveQuantitySchema,
  // §55: the price is the price AT THE TIME, so the client sends it rather
  // than the server silently using today's. The default comes from the
  // product in the UI; this is what gets frozen onto the line.
  unitPrice: moneySchema,
  discountAmount: moneySchema.optional(),
  taxRate: z.coerce.number().min(0).max(100).optional(),
});

const createOrderSchema = z.object({
  /**
   * The database's own two values, used verbatim rather than translated:
   *   `quick_sale` — §13's sale. The goods change hands now.
   *   `standard`   — §14's order. Promised, fulfilled later.
   * A friendlier pair ("sale" / "order") would have meant a third
   * vocabulary to keep in step with the schema and the client.
   */
  orderType: enumSchema(["standard", "quick_sale"], "Order type"),
  customerId: idSchema.nullable().optional(),
  // §18 allows an anonymous cash customer, so this stays optional.
  items: z.array(orderItemSchema).min(1, "An order needs at least one item."),
  discountAmount: moneySchema.optional(),
  extraCharges: moneySchema.optional(),
  notes: optionalString(5000),
  orderDate: optionalDateSchema,
  status: enumSchema(["draft", "pending", "confirmed"], "Status").optional(),
});

const statusSchema = z.object({
  status: enumSchema(
    ["draft", "pending", "confirmed", "processing", "ready", "completed", "cancelled"],
    "Status"
  ),
  // Required for a cancellation (§17); optional otherwise, but recorded in
  // the edit trail either way.
  reason: optionalString(255),
});

const paymentSchema = z.object({
  amount: moneySchema.refine((v) => v > 0, "A payment must be greater than zero."),
  method: enumSchema(["cash", "bank_transfer", "card", "other"], "Payment method"),
  reference: optionalString(100),
  note: optionalString(2000),
});

export const ordersRouter = Router();
ordersRouter.use(authenticate, requireAccountType("business_user"));

/**
 * Gated on `orders.*`. §24 lists Sales and Orders as separate modules and
 * this endpoint serves both — the permission follows the route rather than
 * the row's `order_type`, because a role granted "orders" but not "sales"
 * would otherwise see a list that silently omits half its contents.
 */
ordersRouter.get("/", authorize("orders.view"), validate(listQuerySchema, "query"), list);
ordersRouter.get("/:id", authorize("orders.view"), validate(idParamsSchema, "params"), get);
ordersRouter.post("/", authorize("orders.create"), validate(createOrderSchema), create);

ordersRouter.patch(
  "/:id/status",
  authorize("orders.edit"),
  validateRequest({ params: idParamsSchema, body: statusSchema }),
  updateStatus
);

ordersRouter.post(
  "/:id/payments",
  authorize("orders.edit"),
  validateRequest({ params: idParamsSchema, body: paymentSchema }),
  addPayment
);
