import { test } from "node:test";
import assert from "node:assert/strict";
import { authenticate } from "../../src/middleware/authenticate.js";
import { requireAccountType } from "../../src/middleware/requireAccountType.js";
import { signAccessToken } from "../../src/utils/token.js";
import { AppError } from "../../src/utils/AppError.js";

function mockReq(headers = {}) {
  return { headers, auth: undefined };
}

function callNext() {
  const calls = [];
  const next = (err) => calls.push(err);
  return { next, calls };
}

test("authenticate rejects a request with no Authorization header", () => {
  const req = mockReq();
  const { next, calls } = callNext();
  authenticate(req, {}, next);
  assert.equal(calls.length, 1);
  assert.ok(calls[0] instanceof AppError);
  assert.equal(calls[0].statusCode, 401);
  assert.equal(req.auth, undefined);
});

test("authenticate rejects a non-Bearer scheme", () => {
  const req = mockReq({ authorization: "Basic dXNlcjpwYXNz" });
  const { next, calls } = callNext();
  authenticate(req, {}, next);
  assert.ok(calls[0] instanceof AppError);
  assert.equal(calls[0].statusCode, 401);
});

test("authenticate rejects an invalid token", () => {
  // verifyAccessToken throws synchronously rather than calling next(err)
  // for this case (see utils/token.js) — Express 4 catches a synchronous
  // throw from a non-async middleware automatically and routes it to the
  // error handler in real usage; calling the middleware directly (as this
  // unit test does, bypassing Express) surfaces that same throw here.
  const req = mockReq({ authorization: "Bearer garbage.token.here" });
  const { next } = callNext();
  assert.throws(() => authenticate(req, {}, next), (err) => {
    assert.ok(err instanceof AppError);
    assert.equal(err.statusCode, 401);
    return true;
  });
});

test("authenticate sets req.auth from a valid business-user token — never trusts a client-supplied businessId elsewhere", () => {
  const token = signAccessToken({ accountType: "business_user", userId: 5, businessId: 9 });
  const req = mockReq({ authorization: `Bearer ${token}` });
  const { next, calls } = callNext();
  authenticate(req, {}, next);
  assert.equal(calls[0], undefined); // next() called with no error
  assert.deepEqual(req.auth, { accountType: "business_user", userId: 5, businessId: 9 });
});

test("authenticate forces businessId to null for a system_admin token, even if the payload tried to smuggle one", () => {
  const token = signAccessToken({ accountType: "system_admin", userId: 1, businessId: 999 });
  const req = mockReq({ authorization: `Bearer ${token}` });
  const { next } = callNext();
  authenticate(req, {}, next);
  assert.equal(req.auth.businessId, null);
});

test("requireAccountType allows a matching account type through", () => {
  const req = { auth: { accountType: "business_user", userId: 1, businessId: 1 } };
  const { next, calls } = callNext();
  requireAccountType("business_user")(req, {}, next);
  assert.equal(calls[0], undefined);
});

test("requireAccountType blocks a business_user from a system_admin-only route", () => {
  const req = { auth: { accountType: "business_user", userId: 1, businessId: 1 } };
  const { next, calls } = callNext();
  requireAccountType("system_admin")(req, {}, next);
  assert.ok(calls[0] instanceof AppError);
  assert.equal(calls[0].statusCode, 403);
});

test("requireAccountType blocks a system_admin from a business_user-only route (no silent cross-privilege)", () => {
  const req = { auth: { accountType: "system_admin", userId: 1, businessId: null } };
  const { next, calls } = callNext();
  requireAccountType("business_user")(req, {}, next);
  assert.ok(calls[0] instanceof AppError);
  assert.equal(calls[0].statusCode, 403);
});

test("requireAccountType rejects when authenticate never ran (no req.auth)", () => {
  const req = {};
  const { next, calls } = callNext();
  requireAccountType("business_user")(req, {}, next);
  assert.ok(calls[0] instanceof AppError);
  assert.equal(calls[0].statusCode, 401);
});
