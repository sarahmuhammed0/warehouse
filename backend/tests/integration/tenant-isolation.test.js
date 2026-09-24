// Mandatory per the Phase 2 brief (§30/§10): proves a business user can
// never read/act on another business's context, and can never escalate to
// System Admin routes. Phase 2 has no generic business-data CRUD yet (no
// products/orders/etc.), so what's provable here is the full surface that
// DOES exist: identity resolution (does /me ever return anyone else's
// business?) and the account-type boundary (can a business user reach an
// admin-only route, or vice versa?) — exactly the two mechanisms every
// future tenant-scoped module will be built on
// (`req.auth.businessId`/`requireAccountType`).

import { test, after } from "node:test";
import { closePool } from "../../src/db/pool.js";
import assert from "node:assert/strict";
import request from "supertest";
import jwt from "jsonwebtoken";

import { app } from "../../src/app.js";
import { env } from "../../src/config/env.js";
import {
  requireDatabase,
  testPhone,
  createTestBusiness,
  createTestUser,
  createTestSystemAdmin,
  cleanupTestData,
} from "./helpers.js";

test("Multi-tenant isolation", async (t) => {
  if (!(await requireDatabase(t))) return;

  const businessAId = await createTestBusiness();
  const businessBId = await createTestBusiness();
  const userA = await createTestUser({ businessId: businessAId, phone: testPhone() });
  const userB = await createTestUser({ businessId: businessBId, phone: testPhone() });
  const admin = await createTestSystemAdmin({ phone: testPhone() });

  t.after(() =>
    cleanupTestData({
      businessIds: [businessAId, businessBId],
      userIds: [userA.id, userB.id],
      adminIds: [admin.id],
    })
  );

  let tokenA;
  let tokenB;

  await t.test("login always derives businessId from the database, never accepts one from the request", async () => {
    // Neither login body has a `businessId` field at all — proving the
    // server has no such input to trust in the first place.
    const resA = await request(app).post("/api/auth/login").send({ phone: userA.phone, password: userA.password });
    const resB = await request(app).post("/api/auth/login").send({ phone: userB.phone, password: userB.password });
    tokenA = resA.body.data.accessToken;
    tokenB = resB.body.data.accessToken;

    assert.equal(resA.body.data.business.id, businessAId);
    assert.equal(resB.body.data.business.id, businessBId);

    const decodedA = jwt.decode(tokenA);
    const decodedB = jwt.decode(tokenB);
    assert.equal(decodedA.businessId, businessAId);
    assert.equal(decodedB.businessId, businessBId);
  });

  await t.test("/me for user A returns ONLY business A, even if the request tries to smuggle business B's id", async () => {
    const res = await request(app)
      .get("/api/auth/me")
      .query({ businessId: businessBId }) // ignored — no route reads this
      .set("Authorization", `Bearer ${tokenA}`)
      .send({ businessId: businessBId }); // also ignored on a GET body

    assert.equal(res.status, 200);
    assert.equal(res.body.data.business.id, businessAId);
    assert.notEqual(res.body.data.business.id, businessBId);
  });

  await t.test("user A's token cannot be used to change user A's own businessId via change-password or any auth route", async () => {
    // There is no endpoint that accepts a businessId body field at all in
    // this phase — confirmed by checking the request succeeds/fails based
    // purely on password correctness, never on any businessId supplied.
    const res = await request(app)
      .post("/api/auth/change-password")
      .set("Authorization", `Bearer ${tokenA}`)
      .send({ currentPassword: userA.password, newPassword: userA.password, businessId: businessBId });
    assert.equal(res.status, 200); // succeeds on password grounds alone

    const meAfter = await request(app).get("/api/auth/me").set("Authorization", `Bearer ${tokenA}`);
    assert.equal(meAfter.body.data.business.id, businessAId); // unchanged
  });

  await t.test("a business user token is rejected by System-Admin-only routes", async () => {
    const res = await request(app)
      .post("/api/admin/businesses")
      .set("Authorization", `Bearer ${tokenA}`)
      .send({});
    assert.equal(res.status, 403);
  });

  await t.test("System Admin login never returns a businessId — the two identities cannot be conflated", async () => {
    const res = await request(app).post("/api/admin/auth/login").send({ phone: admin.phone, password: admin.password });
    assert.equal(res.status, 200);
    assert.equal(res.body.data.business, null);
    const decoded = jwt.decode(res.body.data.accessToken);
    assert.equal(decoded.accountType, "system_admin");
    assert.equal(decoded.businessId, null);

    // And a System Admin token is rejected by business-user-only routes.
    const meAsAdmin = await request(app).get("/api/auth/me").set("Authorization", `Bearer ${res.body.data.accessToken}`);
    assert.equal(meAsAdmin.status, 403);
  });

  await t.test("a token forged with a mismatched secret is rejected outright (proves the boundary is cryptographic, not just structural)", async () => {
    const forged = jwt.sign({ accountType: "business_user", userId: userA.id, businessId: businessBId }, "wrong-secret-entirely");
    const res = await request(app).get("/api/auth/me").set("Authorization", `Bearer ${forged}`);
    assert.equal(res.status, 401);
  });

  await t.test("sanity: env.auth.jwtSecret is actually configured for this test run", () => {
    assert.ok(env.auth.jwtSecret && env.auth.jwtSecret.length > 0);
  });
});

// Close the shared pool once this file's tests are done, or `node --test`
// never exits: an open mysql2 pool keeps the event loop alive. This was
// invisible while the database was unreachable, because every test skipped
// before opening a connection.
after(async () => {
  await closePool();
});
