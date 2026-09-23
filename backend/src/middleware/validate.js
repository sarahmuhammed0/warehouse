// Validation middleware foundation (architecture §30, spec §54).
//
// zod was chosen for request-schema validation: a single small dependency
// with no code-generation step, typed composable schemas, and an error
// format that maps cleanly onto the API's envelope. A module keeps its
// schemas in `src/modules/<name>/validation.js` and passes them here.
//
// §54 requires validating on the backend as well as the frontend, and is
// explicit that required fields be clearly marked — which on the API side
// means the response has to say *which* field was wrong, not just that
// something was. So every failing field is reported, in `error.details`,
// rather than only the first: a form with three empty required inputs
// should light up all three on one round trip, not one per submit.
//
// On success the parsed (coerced, stripped) value REPLACES `req[source]`.
// That is deliberate: downstream code then reads validated data only, and
// cannot accidentally use the raw string where the schema produced a
// number. It also means unknown keys a schema does not declare are dropped
// rather than forwarded — mass-assignment protection for free.

import { AppError } from "../utils/AppError.js";

/**
 * @param {import('zod').ZodType} schema
 * @param {'body' | 'query' | 'params'} [source]
 */
export function validate(schema, source = "body") {
  return (req, res, next) => {
    const result = schema.safeParse(req[source]);

    if (!result.success) {
      return next(validationError(result.error, source));
    }

    // `req.query` is a getter on newer Express; assigning to it throws, so
    // the parsed value is written through `Object.defineProperty` when a
    // plain assignment is not possible.
    assign(req, source, result.data);
    next();
  };
}

/**
 * Validates several parts of one request together, so a request with a bad
 * path parameter *and* a bad body reports both.
 *
 * @param {Partial<Record<'body'|'query'|'params', import('zod').ZodType>>} schemas
 */
export function validateRequest(schemas) {
  const entries = Object.entries(schemas);
  return (req, res, next) => {
    /** @type {Record<string, string[]>} */
    const details = {};
    const parsed = [];

    for (const [source, schema] of entries) {
      const result = schema.safeParse(req[source]);
      if (result.success) {
        parsed.push([source, result.data]);
      } else {
        for (const [field, messages] of Object.entries(fieldErrors(result.error, source))) {
          details[field] = [...(details[field] ?? []), ...messages];
        }
      }
    }

    if (Object.keys(details).length > 0) {
      return next(
        new AppError("VALIDATION_ERROR", firstMessage(details), 422, { fields: details })
      );
    }

    for (const [source, data] of parsed) assign(req, source, data);
    next();
  };
}

function validationError(zodError, source) {
  const details = fieldErrors(zodError, source);
  return new AppError("VALIDATION_ERROR", firstMessage(details), 422, { fields: details });
}

/** `{ "owner.password": ["Must be at least 8 characters."] }` */
function fieldErrors(zodError, source) {
  /** @type {Record<string, string[]>} */
  const fields = {};
  for (const issue of zodError.issues) {
    // An issue with no path is about the object as a whole; attribute it to
    // the source ("body") so it still has a key.
    const key = issue.path.length > 0 ? issue.path.join(".") : source;
    fields[key] = [...(fields[key] ?? []), issue.message || "Invalid value."];
  }
  return fields;
}

/**
 * The `message` a client shows if it renders only one. Kept in the same
 * "field: problem" shape the previous implementation used, so existing
 * callers and tests see no change in wording.
 */
function firstMessage(fields) {
  const [field, messages] = Object.entries(fields)[0];
  return `${field}: ${messages[0]}`;
}

function assign(req, source, value) {
  try {
    req[source] = value;
  } catch {
    Object.defineProperty(req, source, { value, writable: true, configurable: true });
  }
}
