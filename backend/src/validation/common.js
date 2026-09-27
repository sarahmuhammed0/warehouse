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
  .number({ error: "Must be a number." })
  .int("Must be a whole number.")
  .positive("Must be greater than zero.");

/** `/:id` path parameters. */
export const idParamsSchema = z.object({ id: idSchema });

/** A required, trimmed, non-empty string with a maximum length. */
export const requiredString = (max, label = "This field") =>
  z
    .string({ error: `${label} is required.` })
    .trim()
    .min(1, `${label} is required.`)
    .max(max, `${label} must be ${max} characters or fewer.`);

/**
 * An optional string, where ABSENT and NULL mean different things.
 *
 *   absent  -> leave the column alone (a PATCH only writes what it is sent)
 *   null/"" -> clear the column
 *
 * The earlier version folded null into undefined, which made a set field
 * impossible to empty again: a user who cleared a product's description and
 * saved got a successful response and the old description still there.
 */
export const optionalString = (max) =>
  z.preprocess(
    (value) => (value === "" ? null : value),
    z
      .string()
      .trim()
      .max(max, `Must be ${max} characters or fewer.`)
      .nullable()
      .optional()
  );

/**
 * Wraps a numeric schema so that null means "clear it", not zero.
 *
 * `z.coerce.number()` runs Number() on whatever arrives, and `Number(null)` is
 * 0 — so an explicit JSON null (what a form sends for "no value") was stored
 * as zero. On a product that meant max_stock 0, which makes every product with
 * any stock at all look overstocked.
 *
 * Passing null THROUGH as null, rather than folding it to undefined, is what
 * lets a value be removed: undefined means "not in this request" and the
 * column keeps what it had. A real 0 the user typed is still a real 0.
 */
const clearable = (schema) =>
  z.preprocess((value) => (value === "" ? null : value), schema.nullable().optional());

/**
 * A money amount. Two decimal places, never negative, and bounded to what
 * DECIMAL(14,2) can hold — so a value the database would silently refuse is
 * rejected here with a message instead.
 */
export const moneySchema = z.coerce
  .number({ error: "Must be an amount." })
  .nonnegative("Cannot be negative.")
  .max(999_999_999_999.99, "That amount is too large.");

/** Same bounds; an explicit null clears the column. */
export const optionalMoneySchema = clearable(moneySchema);

/**
 * A quantity. Three decimal places (see the `units.decimal_places` column
 * for why fractional quantities exist) and never negative — §54's "prevent
 * negative quantities". Whether a *specific* product may be fractional
 * depends on its unit and is checked by the module that knows the unit.
 */
export const quantitySchema = z.coerce
  .number({ error: "Must be a quantity." })
  .nonnegative("Cannot be negative.")
  .max(999_999_999.999, "That quantity is too large.");

/** Same bounds; an explicit null clears the column. */
export const optionalQuantitySchema = clearable(quantitySchema);

/** A quantity that must actually be some — for order/purchase lines. */
export const positiveQuantitySchema = quantitySchema.refine(
  (value) => value > 0,
  "Must be greater than zero."
);

/** A percentage rate, e.g. tax. */
export const percentSchema = z.coerce
  .number({ error: "Must be a percentage." })
  .min(0, "Cannot be negative.")
  .max(100, "Cannot be more than 100.");

/** Same bounds; an explicit null clears the column. */
export const optionalPercentSchema = clearable(percentSchema);

/**
 * A boolean as a form or query string actually sends it.
 *
 * NOT `z.coerce.boolean()`, which runs `Boolean(value)` — and `Boolean("false")`
 * is `true`, so every "false" a client sent was read as "true". For a field
 * like `isDefault` that silently promotes the wrong warehouse.
 */
export const booleanSchema = z.preprocess((value) => {
  if (typeof value === "boolean") return value;
  if (typeof value === "number") return value === 1;
  if (typeof value === "string") {
    const text = value.trim().toLowerCase();
    if (["true", "1", "yes", "on"].includes(text)) return true;
    if (["false", "0", "no", "off", ""].includes(text)) return false;
  }
  return value; // anything else falls through and fails as a non-boolean
}, z.boolean({ error: "Must be true or false." }));

/** A calendar date with no time, as a date input sends it. */
export const dateSchema = z
  .string()
  .regex(/^\d{4}-\d{2}-\d{2}$/, "Must be a date (YYYY-MM-DD).")
  .refine((value) => !Number.isNaN(new Date(`${value}T00:00:00Z`).getTime()), "Not a real date.");

/** Same rule as optionalString: null clears the date, absent leaves it. */
export const optionalDateSchema = z.preprocess(
  (value) => (value === "" ? null : value),
  dateSchema.nullable().optional()
);

/**
 * One of a fixed set — the schema counterpart of the database's ENUMs.
 * The message lists the options, because a client sending the wrong one
 * usually cannot guess the right one.
 */
export const enumSchema = (values, label = "Value") =>
  z.enum(values, { error: `${label} must be one of: ${values.join(", ")}.` });

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
