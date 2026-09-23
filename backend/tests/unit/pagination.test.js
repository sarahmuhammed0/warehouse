import { test } from "node:test";
import assert from "node:assert/strict";
import {
  parsePagination,
  paginationMeta,
  PAGE_SIZE_DEFAULT,
  PAGE_SIZE_MAX,
} from "../../src/db/pagination.js";

test("defaults to page 1 and the default page size when nothing is sent", () => {
  const result = parsePagination();
  assert.equal(result.page, 1);
  assert.equal(result.pageSize, PAGE_SIZE_DEFAULT);
  assert.equal(result.offset, 0);
  assert.equal(result.limit, PAGE_SIZE_DEFAULT);
});

test("computes the SQL offset from the page", () => {
  const result = parsePagination({ page: 4, pageSize: 10 });
  assert.equal(result.offset, 30);
  assert.equal(result.limit, 10);
});

test("clamps an oversized page size instead of honouring it", () => {
  // §59: the client must not be able to ask for the whole table.
  const result = parsePagination({ pageSize: 10_000 });
  assert.equal(result.pageSize, PAGE_SIZE_MAX);
  assert.equal(result.pageSizeClamped, true);
});

test("treats junk, zero and negative values as absent rather than failing", () => {
  for (const bad of ["abc", "", null, undefined, 0, -5, "-1"]) {
    const result = parsePagination({ page: bad, pageSize: bad });
    assert.equal(result.page, 1, `page for ${JSON.stringify(bad)}`);
    assert.equal(result.pageSize, PAGE_SIZE_DEFAULT, `pageSize for ${JSON.stringify(bad)}`);
  }
});

test("accepts numeric strings, which is how a query string arrives", () => {
  const result = parsePagination({ page: "3", pageSize: "20" });
  assert.equal(result.page, 3);
  assert.equal(result.pageSize, 20);
  assert.equal(result.offset, 40);
});

test("metadata reports total pages and both neighbours", () => {
  const meta = paginationMeta({ page: 2, pageSize: 10 }, 35);
  assert.deepEqual(meta, {
    page: 2,
    pageSize: 10,
    total: 35,
    totalPages: 4,
    hasPreviousPage: true,
    hasNextPage: true,
  });
});

test("an empty result is page 1 of 1, never page 1 of 0", () => {
  const meta = paginationMeta({ page: 1, pageSize: 25 }, 0);
  assert.equal(meta.totalPages, 1);
  assert.equal(meta.total, 0);
  assert.equal(meta.hasNextPage, false);
  assert.equal(meta.hasPreviousPage, false);
});

test("the last page reports no next page", () => {
  const meta = paginationMeta({ page: 4, pageSize: 10 }, 35);
  assert.equal(meta.hasNextPage, false);
  assert.equal(meta.hasPreviousPage, true);
});
