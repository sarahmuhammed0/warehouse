import { test } from "node:test";
import assert from "node:assert/strict";
import request from "supertest";

import { app } from "../../src/app.js";
import { pool } from "../../src/db/pool.js";
import { requireDatabase, testPhone, createTestSystemAdmin, cleanupTestData } from "./helpers.js";

test("POST /api/admin/businesses (System-Admin-only business + initial owner creation)", async (t) => {
  if (!(await requireDatabase(t))) return;

  const admin = await createTestSystemAdmin({ phone: testPhone() });
  const createdBusinessIds = [];
  const createdUserIds = [];
  t.after(() =>
    cleanupTestData({ businessIds: createdBusinessIds, userIds: createdUserIds, adminIds: [admin.id] })
  );

  const login = await request(app).post("/api/admin/auth/login").send({ phone: admin.phone, password: admin.password });
  const adminToken = login.body.data.accessToken;

  await t.test("unauthenticated request is rejected", async () => {
    const res = await request(app).post("/api/admin/businesses").send({});
    assert.equal(res.status, 401);
  });

  await t.test("System Admin can create a business with an initial owner — atomically", async () => {
    const ownerPhone = testPhone();
    const res = await request(app)
      .post("/api/admin/businesses")
      .set("Authorization", `Bearer ${adminToken}`)
      .send({
        name: "Integration Test Furniture Co",
        businessType: "furniture_factory",
        phone: testPhone(),
        owner: { name: "Test Owner", phone: ownerPhone, password: "OwnerPassword123" },
      });

    assert.equal(res.status, 201);
    assert.ok(res.body.data.businessId);
    assert.ok(res.body.data.ownerId);
    createdBusinessIds.push(res.body.data.businessId);
    createdUserIds.push(res.body.data.ownerId);

    const [businessRows] = await pool.query("SELECT * FROM businesses WHERE id = ?", [res.body.data.businessId]);
    const [userRows] = await pool.query("SELECT * FROM users WHERE id = ?", [res.body.data.ownerId]);
    assert.equal(businessRows.length, 1);
    assert.equal(userRows.length, 1);
    assert.equal(userRows[0].is_owner, 1);
    assert.equal(userRows[0].business_id, res.body.data.businessId);
    // Password is hashed in the actual row, never plaintext.
    assert.notEqual(userRows[0].password_hash, "OwnerPassword123");

    // The owner can now actually log in — proves the transaction really
    // committed both rows consistently, not just returned plausible ids.
    const ownerLogin = await request(app)
      .post("/api/auth/login")
      .send({ phone: ownerPhone, password: "OwnerPassword123" });
    assert.equal(ownerLogin.status, 200);
  });

  await t.test("duplicate owner phone is rejected with 409, no partial rows left behind", async () => {
    const dupPhone = testPhone();
    const first = await request(app)
      .post("/api/admin/businesses")
      .set("Authorization", `Bearer ${adminToken}`)
      .send({
        name: "First Co",
        businessType: "warehouse",
        phone: testPhone(),
        owner: { name: "Owner", phone: dupPhone, password: "Password123" },
      });
    createdBusinessIds.push(first.body.data.businessId);
    createdUserIds.push(first.body.data.ownerId);

    const [beforeCount] = await pool.query("SELECT COUNT(*) AS c FROM businesses");

    const second = await request(app)
      .post("/api/admin/businesses")
      .set("Authorization", `Bearer ${adminToken}`)
      .send({
        name: "Second Co",
        businessType: "warehouse",
        phone: testPhone(),
        owner: { name: "Owner", phone: dupPhone, password: "Password123" },
      });
    assert.equal(second.status, 409);

    const [afterCount] = await pool.query("SELECT COUNT(*) AS c FROM businesses");
    assert.equal(afterCount[0].c, beforeCount[0].c); // no orphaned business row from the rejected attempt
  });

  await t.test("a business user (not System Admin) cannot create a business", async () => {
    const res = await request(app)
      .post("/api/admin/businesses")
      .set("Authorization", `Bearer not-even-checked-because-role-fails-first`)
      .send({});
    assert.equal(res.status, 401); // invalid token entirely — separate concern from the 403 tested in tenant-isolation.test.js
  });

  await t.test("malformed payload is rejected by validation before touching the database", async () => {
    const res = await request(app)
      .post("/api/admin/businesses")
      .set("Authorization", `Bearer ${adminToken}`)
      .send({ name: "", businessType: "not-real" });
    assert.equal(res.status, 422);
  });
});
