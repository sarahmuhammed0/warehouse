import { z } from "zod";

import { requiredString, optionalString } from "../../validation/common.js";

/**
 * Units of measurement (§8's "Unit of measurement", §34's Units setting).
 *
 * `decimalPlaces` is what makes fractional stock meaningful: a unit of
 * Piece has 0 and cannot hold 2.5, while Kilogram has 3 and can. The
 * database stores every quantity as DECIMAL(14,3), so this is the business's
 * statement about how much of that precision a given unit actually uses —
 * §21's own example weighs "Paint: 1 liter" and "Wood: 5 pieces" in the same
 * bill of materials.
 */
export const createUnitSchema = z.object({
  name: requiredString(50),
  // The short form shown in tables and on documents: "kg", "pcs".
  code: requiredString(20),
  decimalPlaces: z.coerce.number().int().min(0).max(3).optional(),
});

/**
 * Every field optional, but at least one required — a PATCH that changes
 * nothing is almost always a client bug, and answering 200 to it hides that.
 */
export const updateUnitSchema = z
  .object({
    name: optionalString(50),
    code: optionalString(20),
    decimalPlaces: z.coerce.number().int().min(0).max(3).optional(),
  })
  .refine((value) => Object.values(value).some((v) => v !== undefined), {
    message: "Provide at least one field to update.",
  });
