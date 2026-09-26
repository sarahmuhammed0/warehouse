import { z } from "zod";

import {
  requiredString,
  optionalString,
  idSchema,
  enumSchema,
  moneySchema,
  quantitySchema,
  percentSchema,
  optionalDateSchema,
} from "../../validation/common.js";

/**
 * §45's vocabulary, verbatim: "active / archived / deleted_at". `inactive`
 * is the documented addition for a product temporarily not offered but
 * still in the catalogue — see the migration's own comment.
 */
const statusSchema = enumSchema(["active", "inactive", "archived"], "Status");

/** §21's two terms. Raw materials ARE products; this is what tells them apart. */
const productTypeSchema = enumSchema(["finished_good", "raw_material"], "Product type");

/**
 * §8's optional block. Every field here is nullable because §8 says outright
 * "do not force unnecessary fields" — an electronics warehouse fills almost
 * none of these and a furniture factory fills most.
 */
const optionalDetails = {
  brand: optionalString(150),
  imageUrl: optionalString(500),
  description: optionalString(5000),
  shortDescription: optionalString(500),
  size: optionalString(100),
  length: quantitySchema.optional(),
  width: quantitySchema.optional(),
  height: quantitySchema.optional(),
  weight: quantitySchema.optional(),
  color: optionalString(50),
  material: optionalString(100),
  model: optionalString(100),
  manufacturer: optionalString(150),
  serialNumber: optionalString(100),
  batchNumber: optionalString(100),
  expiryDate: optionalDateSchema,
  warrantyPeriod: optionalString(50),
};

/** §8's financial block. Prices are money, never floats — see moneySchema. */
const financial = {
  purchaseCost: moneySchema.optional(),
  sellingPrice: moneySchema.optional(),
  wholesalePrice: moneySchema.optional(),
  discountPrice: moneySchema.optional(),
  taxRate: percentSchema.optional(),
};

/**
 * §8's stock policy. These are thresholds, not quantities: the amount on
 * hand lives in `inventory` and is never accepted here, because a product's
 * stock is the sum of what is in its locations and cannot be set by editing
 * the product.
 */
const stockPolicy = {
  minStock: quantitySchema.optional(),
  maxStock: quantitySchema.optional(),
  reorderLevel: quantitySchema.optional(),
};

export const createProductSchema = z.object({
  name: requiredString(200),
  productCode: optionalString(100),
  sku: optionalString(100),
  barcode: optionalString(100),
  categoryId: idSchema.nullable().optional(),
  unitId: idSchema.nullable().optional(),
  defaultLocationId: idSchema.nullable().optional(),
  status: statusSchema.optional(),
  productType: productTypeSchema.optional(),
  ...stockPolicy,
  ...financial,
  ...optionalDetails,
});

export const updateProductSchema = z
  .object({
    name: optionalString(200),
    productCode: optionalString(100),
    sku: optionalString(100),
    barcode: optionalString(100),
    categoryId: idSchema.nullable().optional(),
    unitId: idSchema.nullable().optional(),
    defaultLocationId: idSchema.nullable().optional(),
    status: statusSchema.optional(),
    productType: productTypeSchema.optional(),
    ...stockPolicy,
    ...financial,
    ...optionalDetails,
  })
  .refine((value) => Object.values(value).some((v) => v !== undefined), {
    message: "Provide at least one field to update.",
  });
