import { test } from "node:test";
import assert from "node:assert/strict";
import { toAppError } from "../../src/utils/databaseError.js";
import { AppError } from "../../src/utils/AppError.js";

/** Shaped like a real mysql2 error. */
function dbError(code, sqlMessage) {
  const error = new Error(sqlMessage ?? code);
  error.code = code;
  error.sqlMessage = sqlMessage;
  return error;
}

test("a duplicate key becomes a 409 the client can act on", () => {
  const mapped = toAppError(dbError("ER_DUP_ENTRY", "Duplicate entry 'SKU-1' for key 'products.uq_products_sku'"));
  assert.ok(mapped instanceof AppError);
  assert.equal(mapped.statusCode, 409);
  assert.equal(mapped.code, "CONFLICT");
});

test("a duplicate key can be given a field-specific message by the caller", () => {
  const mapped = toAppError(
    dbError("ER_DUP_ENTRY", "Duplicate entry 'SKU-1' for key 'products.uq_products_sku'"),
    { constraintMessages: { uq_products_sku: "A product with this SKU already exists." } }
  );
  assert.equal(mapped.message, "A product with this SKU already exists.");
});

test("the message never contains the SQL, the constraint name or the conflicting value", () => {
  // §53: the client must not see internals. The conflicting value matters
  // too — echoing it back could confirm another tenant's record exists.
  const mapped = toAppError(
    dbError("ER_DUP_ENTRY", "Duplicate entry 'SKU-1' for key 'products.uq_products_sku'")
  );
  for (const leak of ["uq_products_sku", "SKU-1", "products", "Duplicate entry"]) {
    assert.ok(!mapped.message.includes(leak), `message leaked ${leak}: ${mapped.message}`);
  }
});

test("a missing referenced row is a 422, not a 500", () => {
  const mapped = toAppError(dbError("ER_NO_REFERENCED_ROW_2"));
  assert.equal(mapped.statusCode, 422);
  assert.equal(mapped.code, "VALIDATION_ERROR");
});

test("deleting a row that is still referenced is a 409", () => {
  const mapped = toAppError(dbError("ER_ROW_IS_REFERENCED_2"));
  assert.equal(mapped.statusCode, 409);
});

test("a CHECK violation is reported as invalid input", () => {
  const mapped = toAppError(dbError("ER_CHECK_CONSTRAINT_VIOLATED"));
  assert.equal(mapped.statusCode, 422);
});

test("a deadlock is a retryable 409 with its own code", () => {
  const mapped = toAppError(dbError("ER_LOCK_DEADLOCK"));
  assert.equal(mapped.statusCode, 409);
  assert.equal(mapped.code, "CONCURRENT_UPDATE");
});

test("an unreachable database is a 503, so the client knows to retry", () => {
  assert.equal(toAppError(dbError("ECONNREFUSED")).statusCode, 503);
  assert.equal(toAppError(dbError("PROTOCOL_CONNECTION_LOST")).statusCode, 503);
});

test("a syntax error is NOT mapped — it is our bug and must stay generic", () => {
  // Returning null sends it down the unexpected-error path, which logs the
  // detail server-side and answers with the generic message.
  assert.equal(toAppError(dbError("ER_PARSE_ERROR", "You have an error in your SQL syntax")), null);
  assert.equal(toAppError(dbError("ER_ACCESS_DENIED_ERROR")), null);
  assert.equal(toAppError(dbError("ER_NO_SUCH_TABLE")), null);
});

test("a non-database error is not mapped", () => {
  assert.equal(toAppError(new Error("something else")), null);
  assert.equal(toAppError(undefined), null);
  assert.equal(toAppError(null), null);
});
