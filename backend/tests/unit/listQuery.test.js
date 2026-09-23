import { test } from "node:test";
import assert from "node:assert/strict";
import { defineListSpec, buildWhere, buildOrderBy } from "../../src/db/listQuery.js";
import { AppError } from "../../src/utils/AppError.js";

const spec = defineListSpec({
  filters: {
    status: { column: "p.status", type: "enum", values: ["active", "inactive"] },
    categoryId: { column: "p.category_id", type: "int" },
    minPrice: { column: "p.selling_price", type: "decimal", operator: ">=" },
  },
  search: { columns: ["p.name", "p.sku"] },
  sort: {
    allowed: { name: "p.name", createdAt: "p.created_at" },
    default: { key: "createdAt", direction: "DESC" },
  },
  dateRange: { column: "p.created_at" },
});

test("a spec rejects an unsafe column reference at definition time", () => {
  // The whole design rests on column names being developer-written. If one
  // ever came from a request, this is the guard that turns it into a
  // startup failure instead of an injection.
  assert.throws(
    () => defineListSpec({ filters: { x: { column: "p.name; DROP TABLE users--", type: "string" } } }),
    /Unsafe column reference/
  );
  assert.throws(() => defineListSpec({ sort: { allowed: { x: "1=1" } } }), /Unsafe column reference/);
});

test("a spec rejects a default sort key that is not allowed", () => {
  assert.throws(
    () => defineListSpec({ sort: { allowed: { name: "p.name" }, default: { key: "nope" } } }),
    /not in `sort.allowed`/
  );
});

test("the tenant scope is always applied, and comes first", () => {
  const where = buildWhere(spec, {}, { "p.business_id": 7, "p.deleted_at": null });
  assert.equal(where.sql, "WHERE p.business_id = ? AND p.deleted_at IS NULL");
  assert.deepEqual(where.params, [7]);
});

test("an unknown query key is ignored, never interpolated", () => {
  const where = buildWhere(
    spec,
    { nonsense: "1", "p.name; DROP TABLE users--": "x" },
    { "p.business_id": 1 }
  );
  assert.equal(where.sql, "WHERE p.business_id = ?");
  assert.deepEqual(where.params, [1]);
});

test("a declared filter becomes a parameterised comparison", () => {
  const where = buildWhere(spec, { status: "active", categoryId: "12" }, { "p.business_id": 1 });
  assert.equal(where.sql, "WHERE p.business_id = ? AND p.status = ? AND p.category_id = ?");
  assert.deepEqual(where.params, [1, "active", 12]);
});

test("a filter can declare its own comparison operator", () => {
  const where = buildWhere(spec, { minPrice: "9.99" });
  assert.equal(where.sql, "WHERE p.selling_price >= ?");
  assert.deepEqual(where.params, [9.99]);
});

test("repeated query parameters become an IN list", () => {
  const where = buildWhere(spec, { status: ["active", "inactive"] });
  assert.equal(where.sql, "WHERE p.status IN (?, ?)");
  assert.deepEqual(where.params, ["active", "inactive"]);
});

test("an unrecognised enum value is rejected rather than silently dropped", () => {
  // Silently ignoring it would return an unfiltered list that looks like
  // the filter did nothing — worse than an error.
  assert.throws(
    () => buildWhere(spec, { status: "deleted" }),
    (error) => error instanceof AppError && error.statusCode === 422
  );
});

test("a non-numeric value for a numeric filter is dropped, not passed through", () => {
  const where = buildWhere(spec, { categoryId: "abc" });
  assert.equal(where.sql, "");
  assert.deepEqual(where.params, []);
});

test("search produces one LIKE per declared column, with only the term bound", () => {
  const where = buildWhere(spec, { search: "sofa" });
  assert.equal(where.sql, "WHERE (p.name LIKE ? OR p.sku LIKE ?)");
  assert.deepEqual(where.params, ["%sofa%", "%sofa%"]);
});

test("LIKE metacharacters in a search term are escaped, not honoured", () => {
  // "100%" must find the literal text, not match everything.
  const where = buildWhere(spec, { search: "100%_x" });
  assert.deepEqual(where.params, ["%100\\%\\_x%", "%100\\%\\_x%"]);
});

test("an empty or whitespace-only search term adds no clause", () => {
  assert.equal(buildWhere(spec, { search: "   " }).sql, "");
  assert.equal(buildWhere(spec, { search: "" }).sql, "");
});

test("a date range is inclusive of the whole end day", () => {
  const where = buildWhere(spec, { dateFrom: "2026-03-01", dateTo: "2026-03-03" });
  assert.equal(where.sql, "WHERE p.created_at >= ? AND p.created_at < ?");
  // Exclusive upper bound of the 4th, so the 3rd is fully included.
  assert.deepEqual(where.params, ["2026-03-01", "2026-03-04"]);
});

test("a malformed date is ignored rather than reaching SQL", () => {
  assert.equal(buildWhere(spec, { dateFrom: "yesterday" }).sql, "");
  assert.equal(buildWhere(spec, { dateFrom: "2026-13-45" }).sql, "");
});

test("sorting falls back to the spec's default", () => {
  assert.equal(buildOrderBy(spec, {}), "ORDER BY p.created_at DESC");
});

test("a sort key not in the allowlist falls back to the default", () => {
  assert.equal(buildOrderBy(spec, { sort: "password_hash" }), "ORDER BY p.created_at DESC");
  assert.equal(buildOrderBy(spec, { sort: "name" }), "ORDER BY p.name DESC");
});

test("only ASC and DESC can reach the SQL", () => {
  assert.equal(buildOrderBy(spec, { sort: "name", direction: "asc" }), "ORDER BY p.name ASC");
  // Anything else falls back to the default direction.
  assert.equal(
    buildOrderBy(spec, { sort: "name", direction: "asc; DROP TABLE users--" }),
    "ORDER BY p.name DESC"
  );
});

test("a tiebreaker is appended so paging is stable", () => {
  // Rows sharing a sort value have no defined order in SQL, so without
  // this a row can appear on two pages, or none.
  assert.equal(buildOrderBy(spec, { sort: "name" }, "p.id"), "ORDER BY p.name DESC, p.id DESC");
});
