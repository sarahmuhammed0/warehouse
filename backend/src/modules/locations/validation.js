import { z } from "zod";

import { requiredString, optionalString, idSchema, enumSchema } from "../../validation/common.js";

const statusSchema = enumSchema(["active", "inactive"], "Status");

/** §11's location types. */
const locationTypeSchema = enumSchema(
  ["warehouse", "showroom", "production_area", "storage_room", "outdoor", "other"],
  "Location type"
);

export const createWarehouseSchema = z.object({
  name: requiredString(150),
  code: optionalString(50),
  address: optionalString(255),
  locationType: locationTypeSchema.optional(),
  isDefault: z.coerce.boolean().optional(),
  status: statusSchema.optional(),
});

export const updateWarehouseSchema = z
  .object({
    name: optionalString(150),
    code: optionalString(50),
    address: optionalString(255),
    locationType: locationTypeSchema.optional(),
    isDefault: z.coerce.boolean().optional(),
    status: statusSchema.optional(),
  })
  .refine((value) => Object.values(value).some((v) => v !== undefined), {
    message: "Provide at least one field to update.",
  });

/**
 * §11's "Shelf/rack/bin". Every positional field is optional because they
 * differ per business: a small store labels a shelf, a distribution centre
 * uses aisle + rack + shelf + bin.
 */
export const createStorageLocationSchema = z.object({
  warehouseId: idSchema,
  name: requiredString(150),
  code: optionalString(50),
  aisle: optionalString(30),
  rack: optionalString(30),
  shelf: optionalString(30),
  bin: optionalString(30),
  status: statusSchema.optional(),
});

export const updateStorageLocationSchema = z
  .object({
    warehouseId: idSchema.optional(),
    name: optionalString(150),
    code: optionalString(50),
    aisle: optionalString(30),
    rack: optionalString(30),
    shelf: optionalString(30),
    bin: optionalString(30),
    status: statusSchema.optional(),
  })
  .refine((value) => Object.values(value).some((v) => v !== undefined), {
    message: "Provide at least one field to update.",
  });
