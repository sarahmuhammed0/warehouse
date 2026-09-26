import { z } from "zod";

import { requiredString, optionalString, idSchema, enumSchema } from "../../validation/common.js";

const statusSchema = enumSchema(["active", "inactive"], "Status");

/** §7's category fields. */
export const createCategorySchema = z.object({
  name: requiredString(150),
  code: optionalString(50),
  // Nullable rather than merely optional: clearing a parent (making a
  // subcategory top-level) is a real edit, and `null` is how it is said.
  parentId: idSchema.nullable().optional(),
  imageUrl: optionalString(500),
  description: optionalString(2000),
  sortOrder: z.coerce.number().int().min(0).max(100000).optional(),
  status: statusSchema.optional(),
});

export const updateCategorySchema = z
  .object({
    name: optionalString(150),
    code: optionalString(50),
    parentId: idSchema.nullable().optional(),
    imageUrl: optionalString(500),
    description: optionalString(2000),
    sortOrder: z.coerce.number().int().min(0).max(100000).optional(),
    status: statusSchema.optional(),
  })
  .refine((value) => Object.values(value).some((v) => v !== undefined), {
    message: "Provide at least one field to update.",
  });
