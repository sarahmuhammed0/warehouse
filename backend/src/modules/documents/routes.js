import { Router } from "express";
import { z } from "zod";

import { authenticate } from "../../middleware/authenticate.js";
import { requireAccountType } from "../../middleware/requireAccountType.js";
import { authorize, loadPermissions } from "../../middleware/authorize.js";
import { auditTrail } from "../../middleware/auditTrail.js";
import { validate, validateRequest } from "../../middleware/validate.js";
import { idParamsSchema, requiredString, optionalString } from "../../validation/common.js";
import { ok } from "../../utils/responseEnvelope.js";
import { errors } from "../../utils/AppError.js";
import { pool, runInTransaction } from "../../db/pool.js";
import { findOrder, orderItems, orderPayments } from "../orders/repository.js";
import { defaultTemplate, saveDefaultTemplate, templateView, TEMPLATE_FIELDS } from "./templates.js";
import { writeInvoicePdf } from "./invoicePdf.js";

const tenant = (req) => req.auth.businessId;
const num = (v) => (v === null || v === undefined ? null : Number(v));

const templateSchema = z
  .object({
    name: optionalString(100),
    invoiceTitle: requiredString(100, "The title").optional(),
    logoUrl: optionalString(500),
    headerText: optionalString(500),
    footerText: optionalString(500),
    thankYouMessage: optionalString(255),
    returnPolicy: optionalString(5000),
    paymentTerms: optionalString(5000),
    signatureText: optionalString(150),
    currency: z.string().trim().length(3).transform((v) => v.toUpperCase()).optional(),
    dateFormat: z.enum(["YYYY-MM-DD", "DD/MM/YYYY", "MM/DD/YYYY"]).optional(),
    /**
     * The blocks that can be switched off, each optional so a screen may save
     * one toggle without restating the rest — `saveDefaultTemplate` merges what
     * it is given onto what is stored.
     *
     * Built from the template's own field list and `.strict()`, so a key this
     * build does not know about is a 422 rather than a silent no-op. NOT
     * `z.record(z.enum(...))`: in zod 4 a record keyed by an enum is exhaustive,
     * which made every partial save fail with "expected boolean, received
     * undefined" for the keys it did not mention.
     */
    fields: z
      .object(Object.fromEntries(Object.keys(TEMPLATE_FIELDS).map((key) => [key, z.boolean().optional()])))
      .strict()
      .optional(),
  })
  .refine((value) => Object.values(value).some((v) => v !== undefined), {
    message: "Provide at least one field to update.",
  });

export const documentsRouter = Router();
documentsRouter.use(authenticate, requireAccountType("business_user"), auditTrail("settings"));

/**
 * §28's template. Gated on `settings.*` — it is what every document the business
 * issues will say, which is an administrative decision rather than a clerk's.
 */
documentsRouter.get("/pdf-template", authorize("settings.view"), async (req, res, next) => {
  try {
    const row = await defaultTemplate({ businessId: tenant(req) });
    res.json(ok({ ...templateView(row), availableFields: Object.keys(TEMPLATE_FIELDS) }));
  } catch (err) {
    next(err);
  }
});

documentsRouter.put(
  "/pdf-template",
  authorize("settings.edit"),
  validate(templateSchema),
  async (req, res, next) => {
    try {
      const businessId = tenant(req);
      await runInTransaction((conn) => saveDefaultTemplate(conn, { businessId, data: req.body }));
      const row = await defaultTemplate({ businessId });
      res.json(ok({ ...templateView(row), availableFields: Object.keys(TEMPLATE_FIELDS) }));
    } catch (err) {
      next(err);
    }
  }
);

/**
 * An order's invoice as a real PDF (§28).
 *
 * Lives on its own router mounted at /orders so it reads as what it is — a
 * representation of the order — and is gated on `orders.view`: anyone who may
 * read the order may print it.
 *
 * The money on the page is the order's own stored figures, and the item names are
 * §55's snapshot, so an invoice reprinted in a year says what it said today.
 */
export const orderPdfRouter = Router();
orderPdfRouter.use(authenticate, requireAccountType("business_user"));

orderPdfRouter.get(
  "/:id/pdf",
  authorize("orders.view"),
  validate(idParamsSchema, "params"),
  async (req, res, next) => {
    try {
      const businessId = tenant(req);
      const row = await findOrder({ businessId, id: req.params.id });
      if (!row) throw errors.notFound("order");

      const grandTotal = num(row.grand_total) ?? 0;
      const paidAmount = num(row.paid_amount) ?? 0;
      const order = {
        orderNumber: row.order_number,
        status: row.status,
        // Whether it is settled, which is the question asked of an invoice
        // second only to what it is for. There is no `payment_method` on an
        // order — a method belongs to each payment, not to the order — so this
        // is the honest field to print.
        paymentStatus: row.payment_status,
        orderDate: row.order_date,
        createdAt: row.created_at,
        customerName: row.customer_name,
        customerPhone: row.customer_phone,
        subtotal: num(row.subtotal),
        discountAmount: num(row.discount_amount),
        taxAmount: num(row.tax_amount),
        extraCharges: num(row.extra_charges),
        grandTotal,
        paidAmount,
        remainingAmount: grandTotal - paidAmount,
      };

      const items = (await orderItems({ businessId, orderId: row.id })).map((item) => ({
        productName: item.product_name,
        sku: item.sku,
        quantity: num(item.quantity),
        unitPrice: num(item.unit_price),
        taxAmount: num(item.tax_amount),
        lineTotal: num(item.line_total),
      }));

      // §24's financial visibility decides whether the payment history is
      // printed, the same as it decides whether the API returns it.
      const permissions = await loadPermissions(req);
      const payments = permissions.includes("financial.view")
        ? (await orderPayments({ businessId, orderId: row.id })).map((p) => ({
            amount: num(p.amount),
            method: p.method,
            reference: p.reference,
            paidAt: p.paid_at,
          }))
        : [];

      const [[business]] = await pool.query(`SELECT * FROM businesses WHERE id = ? LIMIT 1`, [businessId]);
      const template = templateView(await defaultTemplate({ businessId }));

      // Streamed, so nothing buffers the whole file to measure it first. The
      // headers go out before the first byte of PDF, which means an error after
      // this point can no longer be turned into a JSON error response — hence
      // every lookup above happens first.
      res.setHeader("Content-Type", "application/pdf");
      res.setHeader(
        "Content-Disposition",
        `inline; filename="${row.order_number.replace(/[^A-Za-z0-9._-]/g, "_")}.pdf"`
      );

      writeInvoicePdf({ stream: res, business, template, order, items, payments });
    } catch (err) {
      next(err);
    }
  }
);
