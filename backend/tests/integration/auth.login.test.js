// Requires a live MySQL 8.x instance (see helpers.js / docs/environment.md
// and docs/phase2-traceability.md's "MySQL verification" note). Every test
// below calls `requireDatabase(t)` first and skips — never fakes a pass —
// if it isn't reachable.

import { test, after } from "node:test";
import { closePool } from "../../src/db/pool.js";
import assert from "node:assert/strict";
import request from "supertest";

import { app } from "../../src/app.js";
import {
  requireDatabase,
  testPhone,
  createTestBusiness,
  createTestUser,
  cleanupTestData,
} from "./helpers.js";

test("POST /api/auth/login", async (t) => {
  if (!(await requireDatabase(t))) return;

  const businessId = await createTestBusiness();
  const user = await createTestUser({ businessId, phone: testPhone() });
  const disabledUser = await createTestUser({ businessId, phone: testPhone(), status: "disabled" });
  const disabledBusinessId = await createTestBusiness({ status: "disabled" });
  const userAtDisabledBusiness = await createTestUser({ businessId: disabledBusinessId, phone: testPhone() });

  t.after(() =>
    cleanupTestData({
      businessIds: [businessId, disabledBusinessId],
      userIds: [user.id, disabledUser.id, userAtDisabledBusiness.id],
    })
  );

  await t.test("valid credentials succeed and return account + business, never the password hash", async () => {
    const res = await request(app).post("/api/auth/login").send({ phone: user.phone, password: user.password });
    assert.equal(res.status, 200);
    assert.equal(res.body.success, true);
    assert.ok(res.body.data.accessToken);
    assert.ok(res.body.data.refreshToken);
    assert.equal(res.body.data.account.phone, user.phone);
    assert.equal(res.body.data.business.id, businessId);
    assert.equal(res.body.data.account.password_hash, undefined);
    assert.equal(JSON.stringify(res.body).includes("password"), false);
  });

  await t.test("wrong password is rejected with the generic message", async () => {
    const res = await request(app).post("/api/auth/login").send({ phone: user.phone, password: "wrong-password" });
    assert.equal(res.status, 401);
    assert.equal(res.body.error.message, "Invalid phone number or password.");
  });

  await t.test("unknown phone gets the SAME generic message (no enumeration)", async () => {
    const res = await request(app)
      .post("/api/auth/login")
      .send({ phone: "+15559998888", password: "whatever123" });
    assert.equal(res.status, 401);
    assert.equal(res.body.error.message, "Invalid phone number or password.");
  });

  await t.test("disabled user is rejected only after password is proven correct", async () => {
    const res = await request(app)
      .post("/api/auth/login")
      .send({ phone: disabledUser.phone, password: disabledUser.password });
    assert.equal(res.status, 403);
    assert.equal(res.body.error.code, "ACCOUNT_DISABLED");
  });

  await t.test("user at a disabled business is rejected", async () => {
    const res = await request(app)
      .post("/api/auth/login")
      .send({ phone: userAtDisabledBusiness.phone, password: userAtDisabledBusiness.password });
    assert.equal(res.status, 403);
    assert.equal(res.body.error.code, "BUSINESS_DISABLED");
  });

  await t.test("missing fields are rejected before any database lookup (422)", async () => {
    const res = await request(app).post("/api/auth/login").send({ phone: user.phone });
    assert.equal(res.status, 422);
  });

  await t.test("malformed phone gets the same generic invalid-credentials message", async () => {
    const res = await request(app).post("/api/auth/login").send({ phone: "not-a-phone", password: "x" });
    assert.equal(res.status, 401);
    assert.equal(res.body.error.message, "Invalid phone number or password.");
  });

  await t.test("repeated failures against the same phone eventually trigger lockout (429)", async () => {
    const lockoutPhone = testPhone();
    let lastStatus;
    for (let i = 0; i < 6; i += 1) {
      const res = await request(app)
        .post("/api/auth/login")
        .send({ phone: lockoutPhone, password: "wrong" });
      lastStatus = res.status;
    }
    assert.equal(lastStatus, 429);
  });
});

// Close the shared pool once this file's tests are done, or `node --test`
// never exits: an open mysql2 pool keeps the event loop alive. This was
// invisible while the database was unreachable, because every test skipped
// before opening a connection.
after(async () => {
  await closePool();
});
