// The one shared response shape every endpoint returns (architecture §29,
// spec §38's "follow consistent API response formats"), so the frontend's
// http client only ever has to unwrap one envelope, no matter which module
// the data came from.
//
// The contract, in full:
//
//   success  { "success": true,  "data": <payload>, "meta": <optional> }
//   failure  { "success": false, "error": { "code": "...", "message": "..." } }
//   list     { "success": true,  "data": [...], "meta": { "pagination": {...} } }
//
// `success` is always present and always a boolean, so a client can branch
// on one field without inspecting shapes. An error always carries a stable
// machine-readable `code` (which clients may switch on) and a
// human-readable `message` (which they may show) — §53 requires the message
// to be understandable and to contain nothing internal.
//
// There is no third shape. An endpoint that returns nothing returns
// `data: null`, not an empty body, so the client's unwrap never has to
// handle a missing envelope.

/**
 * @param {unknown} data
 * @param {Record<string, unknown>} [meta]
 */
export function ok(data, meta) {
  const body = { success: true, data };
  if (meta) body.meta = meta;
  return body;
}

/**
 * @param {string} code    stable, SCREAMING_SNAKE_CASE, safe to expose
 * @param {string} message plain language, no internals (§53)
 * @param {Record<string, unknown>} [details] field-level validation detail
 */
export function fail(code, message, details) {
  const error = { code, message };
  if (details) error.details = details;
  return { success: false, error };
}

/**
 * A page of rows plus the metadata describing the page (§26/§59).
 *
 * Kept here rather than assembled per module so every list in the API
 * reports its paging identically — the frontend's `PaginationBar` reads one
 * shape.
 *
 * @param {unknown[]} rows
 * @param {ReturnType<typeof import('../db/pagination.js').paginationMeta>} pagination
 * @param {Record<string, unknown>} [extraMeta]
 */
export function paginated(rows, pagination, extraMeta) {
  return ok(rows, { pagination, ...extraMeta });
}
