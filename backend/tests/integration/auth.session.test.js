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

test("Session lifecycle: /me, logout, refresh, change-password", async (t) => {
  if (!(await requireDatabase(t))) return;

  const businessId = await createTestBusiness();
  const user = await createTestUser({ businessId, phone: testPhone() });
  t.after(() => cleanupTestData({ businessIds: [businessId], userIds: [user.id] }));

  let accessToken;
  let refreshToken;

  await t.test("login issues both tokens", async () => {
    const res = await request(app).post("/api/auth/login").send({ phone: user.phone, password: user.password });
    accessToken = res.body.data.accessToken;
    refreshToken = res.body.data.refreshToken;
    assert.ok(accessToken);
    assert.ok(refreshToken);
  });

  await t.test("GET /api/auth/me with a valid token returns identity + business, never a password field", async () => {
    const res = await request(app).get("/api/auth/me").set("Authorization", `Bearer ${accessToken}`);
    assert.equal(res.status, 200);
    assert.equal(res.body.data.account.id, user.id);
    assert.equal(res.body.data.business.id, businessId);
    assert.equal(JSON.stringify(res.body).includes("password"), false);
  });

  await t.test("GET /api/auth/me with no token is 401", async () => {
    const res = await request(app).get("/api/auth/me");
    assert.equal(res.status, 401);
  });

  await t.test("GET /api/auth/me with an expired token is rejected", async () => {
    // Build an already-expired token directly via jsonwebtoken to avoid
    // waiting out the real 15m TTL in a test.
    const jwt = await import("jsonwebtoken");
    const { env } = await import("../../src/config/env.js");
    const expiredToken = jwt.default.sign(
      { accountType: "business_user", userId: user.id, businessId },
      env.auth.jwtSecret,
      { expiresIn: -10 }
    );
    const res = await request(app).get("/api/auth/me").set("Authorization", `Bearer ${expiredToken}`);
    assert.equal(res.status, 401);
  });

  await t.test("POST /api/auth/refresh rotates the refresh token and issues a new access token", async () => {
    const res = await request(app).post("/api/auth/refresh").send({ refreshToken });
    assert.equal(res.status, 200);
    assert.ok(res.body.data.accessToken);
    assert.ok(res.body.data.refreshToken);
    assert.notEqual(res.body.data.refreshToken, refreshToken);

    // The OLD refresh token must now be rejected (rotated, not reusable).
    const reuse = await request(app).post("/api/auth/refresh").send({ refreshToken });
    assert.equal(reuse.status, 401);

    refreshToken = res.body.data.refreshToken; // adopt the new one for subsequent steps
    accessToken = res.body.data.accessToken;
  });

  await t.test("POST /api/auth/change-password requires the correct current password", async () => {
    const res = await request(app)
      .post("/api/auth/change-password")
      .set("Authorization", `Bearer ${accessToken}`)
      .send({ currentPassword: "totally-wrong", newPassword: "NewPassword123" });
    assert.equal(res.status, 401);
  });

  await t.test("POST /api/auth/change-password succeeds with the correct current password, then old password stops working", async () => {
    const res = await request(app)
      .post("/api/auth/change-password")
      .set("Authorization", `Bearer ${accessToken}`)
      .send({ currentPassword: user.password, newPassword: "NewPassword123" });
    assert.equal(res.status, 200);

    const loginWithOld = await request(app)
      .post("/api/auth/login")
      .send({ phone: user.phone, password: user.password });
    assert.equal(loginWithOld.status, 401);

    const loginWithNew = await request(app)
      .post("/api/auth/login")
      .send({ phone: user.phone, password: "NewPassword123" });
    assert.equal(loginWithNew.status, 200);
  });

  await t.test("changing password revoked prior sessions — the pre-change refresh token no longer works", async () => {
    const res = await request(app).post("/api/auth/refresh").send({ refreshToken });
    assert.equal(res.status, 401);
  });

  await t.test("POST /api/auth/logout revokes the refresh token", async () => {
    const login = await request(app)
      .post("/api/auth/login")
      .send({ phone: user.phone, password: "NewPassword123" });
    const freshRefresh = login.body.data.refreshToken;

    const logoutRes = await request(app).post("/api/auth/logout").send({ refreshToken: freshRefresh });
    assert.equal(logoutRes.status, 200);

    const refreshAfterLogout = await request(app).post("/api/auth/refresh").send({ refreshToken: freshRefresh });
    assert.equal(refreshAfterLogout.status, 401);
  });
});

// Close the shared pool once this file's tests are done, or `node --test`
// never exits: an open mysql2 pool keeps the event loop alive. This was
// invisible while the database was unreachable, because every test skipped
// before opening a connection.
after(async () => {
  await closePool();
});
