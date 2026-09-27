// Filtering, searching and sorting foundation (spec §25's per-report
// filters, §32's search, §59's server-side filtering and sorting).
//
// THE RULE THIS FILE EXISTS TO ENFORCE: a column name never comes from the
// client. §35 requires SQL-injection protection, and parameterised values
// alone do not provide it for a list endpoint — `ORDER BY ?` is not valid
// SQL, so the naive way to support `?sort=name` is to interpolate the
// client's string into the query, which is an injection point that no
// amount of value-parameterisation closes.
//
// So every module declares a *spec*: the exact filters, search columns and
// sort keys it permits, written in code, reviewed in code. A client sends
// keys; this module looks them up in the spec and emits the column name the
// developer wrote. An unknown key is ignored, never passed through. Values
// are always bound as parameters.
//
// Usage (a Phase 6+ module):
//
//   const productListSpec = defineListSpec({
//     filters: {
//       status:     { column: "p.status", type: "enum", values: ["active", "inactive"] },
//       categoryId: { column: "p.category_id", type: "int" },
//       lowStock:   { column: "p.reorder_level", type: "flag", operator: ">=" },
//     },
//     search: { columns: ["p.name", "p.sku", "p.barcode", "p.product_code"] },
//     sort: {
//       allowed: { name: "p.name", sku: "p.sku", createdAt: "p.created_at" },
//       default: { key: "createdAt", direction: "DESC" },
//     },
//   });
//
//   const where = buildWhere(productListSpec, req.query, {
//     "p.business_id": req.auth.businessId,   // tenant scope, always applied
//     "p.deleted_at": null,
//   });
//   const sql = `SELECT ... FROM products p ${where.sql} ${buildOrderBy(productListSpec, req.query)} LIMIT ? OFFSET ?`;
//   const rows = (await pool.query(sql, [...where.params, limit, offset]))[0];

import { AppError } from "../utils/AppError.js";

/** Only these two, and only upper-case, ever reach the SQL string. */
const DIRECTIONS = { asc: "ASC", desc: "DESC" };

/**
 * A column reference the developer wrote. Validated anyway — cheap, and it
 * turns a typo or a future refactor that threads user input into a spec
 * into a startup-time error instead of an injection.
 */
function assertSafeColumn(column) {
  if (typeof column !== "string" || !/^[A-Za-z_][A-Za-z0-9_]*(\.[A-Za-z_][A-Za-z0-9_]*)?$/.test(column)) {
    throw new Error(
      `Unsafe column reference in a list spec: ${JSON.stringify(column)}. ` +
        "Expected `column` or `alias.column`, written in code — never derived from a request."
    );
  }
  return column;
}

/**
 * Validates a spec once, at module load, so a malformed spec fails when the
 * server starts rather than when a customer first filters a list.
 *
 * @param {{
 *   filters?: Record<string, {column: string, type: 'string'|'int'|'decimal'|'bool'|'enum'|'flag', values?: string[], operator?: string}>,
 *   search?: {columns: string[]},
 *   sort?: {allowed: Record<string, string>, default?: {key: string, direction?: 'ASC'|'DESC'}},
 *   dateRange?: {column: string},
 * }} spec
 */
export function defineListSpec(spec) {
  const filters = spec.filters ?? {};
  for (const [key, filter] of Object.entries(filters)) {
    assertSafeColumn(filter.column);
    if (filter.type === "enum" && !Array.isArray(filter.values)) {
      throw new Error(`Filter "${key}" is type "enum" but declares no \`values\`.`);
    }
    if (filter.operator && !["=", "!=", ">", ">=", "<", "<="].includes(filter.operator)) {
      throw new Error(`Filter "${key}" declares an unsupported operator: ${filter.operator}`);
    }
  }
  if (spec.search) {
    if (!Array.isArray(spec.search.columns) || spec.search.columns.length === 0) {
      throw new Error("`search` declares no columns.");
    }
    spec.search.columns.forEach(assertSafeColumn);
  }
  if (spec.sort) {
    for (const column of Object.values(spec.sort.allowed ?? {})) assertSafeColumn(column);
    const fallback = spec.sort.default?.key;
    if (fallback && !(fallback in (spec.sort.allowed ?? {}))) {
      throw new Error(`Default sort key "${fallback}" is not in \`sort.allowed\`.`);
    }
  }
  if (spec.dateRange) assertSafeColumn(spec.dateRange.column);

  return Object.freeze({ ...spec, filters });
}

/**
 * Builds the WHERE clause for a list request.
 *
 * @param {ReturnType<typeof defineListSpec>} spec
 * @param {Record<string, unknown>} query   the request's query string
 * @param {Record<string, unknown>} [scope] conditions the caller always
 *   applies — above all the tenant predicate (§36). Keys are column
 *   references written in code; a `null` value becomes `IS NULL`.
 * @returns {{sql: string, params: unknown[]}}
 */
export function buildWhere(spec, query = {}, scope = {}) {
  const clauses = [];
  const params = [];

  // Scope first, so a reader of the generated SQL sees the tenant predicate
  // at the front of the WHERE rather than buried among optional filters.
  for (const [column, value] of Object.entries(scope)) {
    assertSafeColumn(column);
    if (value === null) {
      clauses.push(`${column} IS NULL`);
    } else if (value !== undefined) {
      clauses.push(`${column} = ?`);
      params.push(value);
    }
  }

  for (const [key, filter] of Object.entries(spec.filters)) {
    const raw = query[key];
    if (raw === undefined || raw === null || raw === "") continue;

    // A flag filter is present/absent rather than a value comparison —
    // "?lowStock=true" means "apply this predicate", not "= true".
    if (filter.type === "flag") {
      if (isTruthy(raw)) clauses.push(`${filter.column} ${filter.operator ?? "="} ?`);
      if (isTruthy(raw)) params.push(filter.value ?? 1);
      continue;
    }

    // Repeated query params ("?status=a&status=b") arrive as an array and
    // mean "any of these" — an IN list, still fully parameterised.
    if (Array.isArray(raw)) {
      const values = raw.map((value) => coerce(value, filter, key)).filter((v) => v !== undefined);
      if (values.length === 0) continue;
      clauses.push(`${filter.column} IN (${values.map(() => "?").join(", ")})`);
      params.push(...values);
      continue;
    }

    const value = coerce(raw, filter, key);
    if (value === undefined) continue;
    clauses.push(`${filter.column} ${filter.operator ?? "="} ?`);
    params.push(value);
  }

  // §25's date filter, present on every report.
  if (spec.dateRange) {
    const from = parseDate(query.dateFrom);
    const to = parseDate(query.dateTo);
    if (from) {
      clauses.push(`${spec.dateRange.column} >= ?`);
      params.push(from);
    }
    if (to) {
      // Inclusive of the whole end day: a user asking for 1–3 March means
      // through the end of the 3rd, not up to its first second.
      clauses.push(`${spec.dateRange.column} < ?`);
      params.push(addOneDay(to));
    }
  }

  // §32's search. One LIKE per declared column, OR'd — the columns are from
  // the spec, only the term is bound.
  const term = typeof query.search === "string" ? query.search.trim() : "";
  if (spec.search && term.length > 0) {
    const group = spec.search.columns.map((column) => `${column} LIKE ?`).join(" OR ");
    clauses.push(`(${group})`);
    // Escaped so a term containing % or _ is matched literally rather than
    // silently becoming a wildcard.
    const pattern = `%${escapeLike(term)}%`;
    spec.search.columns.forEach(() => params.push(pattern));
  }

  return {
    sql: clauses.length ? `WHERE ${clauses.join(" AND ")}` : "",
    params,
  };
}

/**
 * Builds the ORDER BY clause. Falls back to the spec's default, and appends
 * a unique tiebreaker so paging is stable: two rows with the same sort value
 * have no defined order in SQL, which means a row can appear on page 1 and
 * again on page 2 (or on neither) as the client walks a list.
 *
 * @param {ReturnType<typeof defineListSpec>} spec
 * @param {Record<string, unknown>} query
 * @param {string} [tiebreaker] column reference, written in code
 */
export function buildOrderBy(spec, query = {}, tiebreaker) {
  if (!spec.sort) return "";

  const requestedKey = typeof query.sort === "string" ? query.sort : undefined;
  // `Object.hasOwn`, never `in`: `in` walks the prototype chain, so
  // `?sort=constructor` passes the allowlist and `allowed["constructor"]`
  // yields the Object function, which is then interpolated into ORDER BY —
  // a guaranteed 500 on every list endpoint from a one-word query string.
  const key =
    requestedKey && Object.hasOwn(spec.sort.allowed, requestedKey)
      ? requestedKey
      : spec.sort.default?.key;
  if (!key) return "";

  const column = spec.sort.allowed[key];
  const requestedDirection = typeof query.direction === "string" ? query.direction.toLowerCase() : "";
  const direction =
    DIRECTIONS[requestedDirection] ?? spec.sort.default?.direction ?? "ASC";

  const parts = [`${column} ${direction}`];
  if (tiebreaker) parts.push(`${assertSafeColumn(tiebreaker)} ${direction}`);
  return `ORDER BY ${parts.join(", ")}`;
}

function coerce(raw, filter, key) {
  switch (filter.type) {
    case "int": {
      const parsed = Number.parseInt(String(raw), 10);
      if (!Number.isFinite(parsed)) return undefined;
      return parsed;
    }
    case "decimal": {
      const parsed = Number.parseFloat(String(raw));
      if (!Number.isFinite(parsed)) return undefined;
      return parsed;
    }
    case "bool":
      return isTruthy(raw) ? 1 : 0;
    case "enum": {
      const value = String(raw);
      // An unrecognised enum value is a client error worth reporting: it
      // usually means a stale UI sending a status the backend no longer
      // has, and silently ignoring it would return an unfiltered list that
      // looks like the filter did nothing.
      if (!filter.values.includes(value)) {
        throw new AppError(
          "VALIDATION_ERROR",
          `${key}: must be one of ${filter.values.join(", ")}.`,
          422
        );
      }
      return value;
    }
    default:
      return String(raw);
  }
}

function isTruthy(value) {
  return value === true || value === 1 || ["1", "true", "yes", "on"].includes(String(value).toLowerCase());
}

/** Accepts YYYY-MM-DD (what a date filter sends); rejects anything else. */
function parseDate(value) {
  if (typeof value !== "string" || !/^\d{4}-\d{2}-\d{2}$/.test(value)) return undefined;
  const date = new Date(`${value}T00:00:00Z`);
  return Number.isNaN(date.getTime()) ? undefined : value;
}

function addOneDay(isoDate) {
  const date = new Date(`${isoDate}T00:00:00Z`);
  date.setUTCDate(date.getUTCDate() + 1);
  return date.toISOString().slice(0, 10);
}

/** `%`, `_` and `\` are LIKE metacharacters; a search term must not be one. */
function escapeLike(term) {
  return term.replace(/[\\%_]/g, (char) => `\\${char}`);
}
