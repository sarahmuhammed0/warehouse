// Pagination foundation (spec §59: "do NOT load thousands of products into
// the browser unnecessarily"; §26's requirement that every list be paged).
//
// Two halves that must agree: `parsePagination` turns whatever the client
// sent into a safe LIMIT/OFFSET, and `paginationMeta` describes the page it
// produced. Both live here so a module cannot page one way and report
// another.
//
// The cap is the point. An unbounded `pageSize` is a denial-of-service the
// client gets to choose — one request for 10,000,000 rows and the server
// spends its memory serialising them. `PAGE_SIZE_MAX` is therefore a hard
// ceiling applied by clamping rather than by rejecting: a client asking for
// too much gets the maximum and is told so in the metadata, which is kinder
// than a 422 and just as safe.

/** What a list returns when the client says nothing. */
export const PAGE_SIZE_DEFAULT = 25;

/** The most rows any single request can obtain, whatever it asks for. */
export const PAGE_SIZE_MAX = 100;

/**
 * @typedef {object} Pagination
 * @property {number} page      1-based, at least 1
 * @property {number} pageSize  1..PAGE_SIZE_MAX
 * @property {number} limit     for SQL — equals pageSize
 * @property {number} offset    for SQL
 * @property {boolean} pageSizeClamped  true when the request asked for more
 *                                      than PAGE_SIZE_MAX
 */

/**
 * Normalises `page`/`pageSize` from a query string.
 *
 * Tolerant by design: a missing, empty, non-numeric, zero or negative value
 * becomes the default rather than an error. These arrive from URLs that
 * humans and bookmarks edit, and there is no useful difference between
 * "?page=abc" and no page at all.
 *
 * @param {{page?: unknown, pageSize?: unknown}} [source]
 * @returns {Pagination}
 */
export function parsePagination(source = {}) {
  const page = positiveInt(source.page, 1);
  const requested = positiveInt(source.pageSize, PAGE_SIZE_DEFAULT);
  const pageSize = Math.min(requested, PAGE_SIZE_MAX);

  return {
    page,
    pageSize,
    limit: pageSize,
    offset: (page - 1) * pageSize,
    pageSizeClamped: requested > PAGE_SIZE_MAX,
  };
}

/**
 * The `meta.pagination` block that accompanies a page of rows.
 *
 * `totalPages` is at least 1 even when `total` is 0, so a client rendering
 * "Page 1 of 0" for an empty list never has to special-case it.
 *
 * @param {{page: number, pageSize: number}} pagination
 * @param {number} total  the unfiltered-by-page row count
 */
export function paginationMeta(pagination, total) {
  const safeTotal = Number.isFinite(total) && total > 0 ? Math.floor(total) : 0;
  const totalPages = Math.max(1, Math.ceil(safeTotal / pagination.pageSize));

  return {
    page: pagination.page,
    pageSize: pagination.pageSize,
    total: safeTotal,
    totalPages,
    hasPreviousPage: pagination.page > 1,
    hasNextPage: pagination.page < totalPages,
  };
}

function positiveInt(value, fallback) {
  const parsed = Number.parseInt(String(value ?? ""), 10);
  if (!Number.isFinite(parsed) || parsed < 1) return fallback;
  return parsed;
}
