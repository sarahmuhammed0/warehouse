// Reusable request schemas (spec §54).
//
// Every module's `validation.js` composes from these rather than restating
// them, so "what is a valid id" or "what is a valid page" has one answer
// across the API. The pieces here are the ones §54 names — required fields,
// numeric constraints, dates, enums — plus the list-query shape §26/§27
// need.
//
// Coercion is on purpose. Everything in a query string is a string, so a
// schema that demanded `z.number()` for `?page=2` would reject every real
// request; these coerce first and then constrain.

import { z } from "zod";
import { PAGE_SIZE_MAX } from "../db/pagination.js";

/** A database id as it arrives in a path or body: positive integer. */
export const idSchema = z.coerce
  .number({ invalid_type_error: "Must be a number." })
  .int("Must be a whole number.")
  .positive("Must be greater than zero.");

/** `/:id` path parameters. */
export const idParamsSchema = z.object({ id: idSchema });

/** A required, trimmed, non-empty string with a maximum length. */
export const requiredString = (max, label = "This field") =>
  z
    .string({ required_error: `${label} is required.`, invalid_type_error: `${label} is required.` })
    .trim()
    .min(1, `${label} is required.`)
    .max(max, `${label} must be ${max} characters or fewer.`);

/** An optional string: absent, null and "" all become undefined. */
export const optionalString = (max) =>
  z
    .string()
    .trim()
    .max(max, `Must be ${max} characters or fewer.`)
    .optional()
    .nullable()
    .transform((value) => (value === null || value === "" ? undefined : value));

/**
 * A money amount. Two decimal places, never negative, and bounded to what
 * DECIMAL(14,2) can hold — so a value the database would silently refuse is
 * rejected here with a message instead.
 */
export const moneySchema = z.coerce
  .number({ invalid_type_error: "Must be an amount." })
  .nonnegative("Cannot be negative.")
  .max(999_999_999_999.99, "That amount is too large.");

/**
 * A quantity. Three decimal places (see the `units.decimal_places` column
 * for why fractional quantities exist) and never negative — §54's "prevent
 * negative quantities". Whether a *specific* product may be fractional
 * depends on its unit and is checked by the module that knows the unit.
 */
export const quantitySchema = z.coerce
  .number({ invalid_type_error: "Must be a quantity." })
  .nonnegative("Cannot be negative.")
  .max(999_999_999.999, "That quantity is too large.");

/** A quantity that must actually be some — for order/purchase lines. */
export const positiveQuantitySchema = quantitySchema.refine(
  (value) => value > 0,
  "Must be greater than zero."
);

/** A percentage rate, e.g. tax. */
export const percentSchema = z.coerce
  .number({ invalid_type_error: "Must be a percentage." })
  .min(0, "Cannot be negative.")
  .max(100, "Cannot be more than 100.");

/** A calendar date with no time, as a date input sends it. */
export const dateSchema = z
  .string()
  .regex(/^\d{4}-\d{2}-\d{2}$/, "Must be a date (YYYY-MM-DD).")
  .refine((value) => !Number.isNaN(new Date(`${value}T00:00:00Z`).getTime()), "Not a real date.");

export const optionalDateSchema = dateSchema
  .optional()
  .nullable()
  .transform((value) => (value === null || value === "" ? undefined : value));

/**
 * One of a fixed set — the schema counterpart of the database's ENUMs.
 * The message lists the options, because a client sending the wrong one
 * usually cannot guess the right one.
 */
export const enumSchema = (values, label = "Value") =>
  z.enum(values, {
    errorMap: () => ({ message: `${label} must be one of: ${values.join(", ")}.` }),
  });

/**
 * The query shape every list endpoint accepts (§26 pagination, §27
 * filtering/sorting, §32 search).
 *
 * Deliberately `passthrough()`: each module adds its own filters, and this
 * schema validates the common part without rejecting the module-specific
 * keys that `listQuery.js` then interprets against that module's spec.
 * Anything not in a module's spec is ignored there, so passthrough is not a
 * hole — the spec, not this schema, is the allowlist for filters.
 */
export const listQuerySchema = z
  .object({
    page: z.coerce.number().int().positive().optional(),
    pageSize: z.coerce.number().int().positive().max(PAGE_SIZE_MAX).optional(),
    search: z.string().trim().max(200).optional(),
    sort: z
      .string()
      .regex(/^[A-Za-z][A-Za-z0-9_]*$/, "Not a sortable field.")
      .max(50)
      .optional(),
    direction: z.enum(["asc", "desc", "ASC", "DESC"]).optional(),
    dateFrom: optionalDateSchema,
    dateTo: optionalDateSchema,
  })
  .passthrough()
  .refine(
    (value) => !value.dateFrom || !value.dateTo || value.dateFrom <= value.dateTo,
    { message: "The start date must not be after the end date.", path: ["dateFrom"] }
  );
