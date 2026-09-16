// Validation middleware foundation (architecture §30). zod was chosen for
// request-schema validation: it's a single small dependency (no code
// generation step), gives typed, composable schemas, and its error format
// is easy to map into the API's standard error envelope — a module's
// validation.js file (backend/src/modules/<name>/validation.js, once
// Phase 1 creates them) exports a zod schema per endpoint and passes it to
// this factory.
//
// Not used by any route yet — Phase 0 has no request bodies to validate.

import { AppError } from "../utils/AppError.js";

/**
 * @param {import('zod').ZodType} schema
 * @param {'body' | 'query' | 'params'} source
 */
export function validate(schema, source = "body") {
  return (req, res, next) => {
    const result = schema.safeParse(req[source]);

    if (!result.success) {
      const firstIssue = result.error.issues[0];
      const field = firstIssue?.path?.join(".") || source;
      return next(
        new AppError(
          "VALIDATION_ERROR",
          `${field}: ${firstIssue?.message || "Invalid value."}`,
          422
        )
      );
    }

    req[source] = result.data;
    next();
  };
}
