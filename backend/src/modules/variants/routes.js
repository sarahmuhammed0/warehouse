import { Router } from "express";
import { z } from "zod";

import { authenticate } from "../../middleware/authenticate.js";
import { requireAccountType } from "../../middleware/requireAccountType.js";
import { authorize } from "../../middleware/authorize.js";
import { auditTrail } from "../../middleware/auditTrail.js";
import { validateRequest } from "../../middleware/validate.js";
import {
  idSchema,
  optionalString,
  enumSchema,
  optionalMoneySchema,
} from "../../validation/common.js";
import { ok } from "../../utils/responseEnvelope.js";
import { errors } from "../../utils/AppError.js";
import { toAppError } from "../../utils/databaseError.js";
import { runInTransaction } from "../../db/pool.js";
import * as repo from "./repository.js";

const tenant = (req) => req.auth.businessId;
const num = (v) => (v === null || v === undefined ? null : Number(v));

const view = (row) => ({
  id: row.id,
  productId: row.product_id,
  name: row.name,
  sku: row.sku,
  barcode: row.barcode,
  purchaseCost: num(row.purchase_cost),
  sellingPrice: num(row.selling_price),
  // §9's "size, color, model" — stored as JSON because which attributes matter
  // differs per business, and a column per attribute would need a migration
  // every time a factory started tracking one more.
  attributes: typeof row.attributes === "string" ? safeJson(row.attributes) : (row.attributes ?? {}),
  imageUrl: row.image_url,
  status: row.status,
  quantity: row.quantity === undefined ? undefined : num(row.quantity),
  createdAt: row.created_at,
  updatedAt: row.updated_at,
});

function safeJson(raw) {
  try {
    return JSON.parse(raw) ?? {};
  } catch {
    return {};
  }
}

const params = z.object({ id: idSchema, variantId: idSchema });
const productParams = z.object({ id: idSchema });

const attributesSchema = z.record(z.string().max(60), z.string().max(200)).optional();

const createSchema = z.object({
  // Nullable in the schema, because a business may distinguish variants purely
  // by attributes ({size: "XL"}) without naming each one.
  name: optionalString(200),
  sku: optionalString(100),
  barcode: optionalString(100),
  purchaseCost: optionalMoneySchema,
  sellingPrice: optionalMoneySchema,
  attributes: attributesSchema,
  imageUrl: optionalString(500),
  status: enumSchema(["active", "inactive"], "Status").optional(),
});

const updateSchema = createSchema.refine(
  (value) => Object.values(value).some((v) => v !== undefined),
  { message: "Provide at least one field to update." }
);

/**
 * §9's variants, hung off the product they belong to.
 *
 * Gated on `products.*`: a variant is part of a product's definition, and
 * anyone who may edit the product may edit its forms. Its STOCK is still the
 * inventory module's business, and is only reported here.
 */
export const variantsRouter = Router();
variantsRouter.use(authenticate, requireAccountType("business_user"), auditTrail("products"));

variantsRouter.get(
  "/:id/variants",
  authorize("products.view"),
  validateRequest({ params: productParams }),
  async (req, res, next) => {
    try {
      const businessId = tenant(req);
      if (!(await repo.productExists({ businessId, productId: req.params.id }))) {
        throw errors.notFound("product");
      }
      const rows = await repo.listVariants({ businessId, productId: req.params.id });
      res.json(ok(rows.map(view)));
    } catch (err) {
      next(err);
    }
  }
);

variantsRouter.post(
  "/:id/variants",
  authorize("products.create"),
  validateRequest({ params: productParams, body: createSchema }),
  async (req, res, next) => {
    try {
      const businessId = tenant(req);
      const productId = req.params.id;
      if (!(await repo.productExists({ businessId, productId }))) throw errors.notFound("product");

      const id = await runInTransaction((conn) =>
        repo.createVariant(conn, { businessId, productId, data: req.body })
      );
      const rows = await repo.listVariants({ businessId, productId });
      res.status(201).json(ok(view(rows.find((r) => String(r.id) === String(id)))));
    } catch (err) {
      next(toAppError(err, { constraintMessages }) ?? err);
    }
  }
);

variantsRouter.patch(
  "/:id/variants/:variantId",
  authorize("products.edit"),
  validateRequest({ params, body: updateSchema }),
  async (req, res, next) => {
    try {
      const businessId = tenant(req);
      const { id: productId, variantId } = req.params;

      const affected = await runInTransaction((conn) =>
        repo.updateVariant(conn, { businessId, productId, id: variantId, data: req.body })
      );
      if (affected === 0) throw errors.notFound("variant");

      const rows = await repo.listVariants({ businessId, productId });
      res.json(ok(view(rows.find((r) => String(r.id) === String(variantId)))));
    } catch (err) {
      next(toAppError(err, { constraintMessages }) ?? err);
    }
  }
);

variantsRouter.delete(
  "/:id/variants/:variantId",
  authorize("products.delete"),
  validateRequest({ params }),
  async (req, res, next) => {
    try {
      const businessId = tenant(req);
      const { id: productId, variantId } = req.params;

      const variant = await repo.findVariant({ businessId, productId, id: variantId });
      if (!variant) throw errors.notFound("variant");

      // Stock standing against a variant is stock the business owns. Archiving
      // the variant would leave it in a slot nothing can now be sold from, so
      // it has to be moved or written off first — said plainly rather than
      // discovered later by a stock count that will not balance.
      const quantity = await repo.variantStock({ businessId, id: variantId });
      if (quantity !== 0) {
        throw errors.conflict(
          `This variant still holds ${quantity} in stock — move or write it off first.`
        );
      }

      const affected = await runInTransaction((conn) =>
        repo.softDeleteVariant(conn, { businessId, productId, id: variantId })
      );
      if (affected === 0) throw errors.notFound("variant");
      res.json(ok({ id: Number(variantId), deleted: true }));
    } catch (err) {
      next(toAppError(err) ?? err);
    }
  }
);

const constraintMessages = {
  uq_product_variants_sku: "A variant with that SKU already exists.",
  uq_product_variants_barcode: "A variant with that barcode already exists.",
};
