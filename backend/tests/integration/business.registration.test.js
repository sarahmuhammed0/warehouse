// Business self-registration with System Admin approval, end to end against
// the real database.
//
// The requirement this proves: a business can ask for an account, and it
// cannot get into the system until an administrator approves it. §2 keeps
// the System Admin in control of who has an account — self-registration
// changes who initiates, not who decides.

import { test, after } from "node:test";
import assert from "node:assert/strict";
import request from "supertest";

import { app } from "../../src/app.js";
import { pool, closePool } from "../../src/db/pool.js";
import { requireDatabase, testPhone, createTestSystemAdmin, cleanupTestData } from "./helpers.js";

const OWNER_PASSWORD = "ApplicantPass12345";

/** A valid registration payload with unique phones. */
function registrationPayload(overrides = {}) {
  return {
    name: `Applicant Co ${Date.now()}-${Math.random().toString(36).slice(2, 6)}`,
    businessType: "warehouse",
    phone: testPhone(),
    currency: "IQD",
    language: "en",
    timezone: "Asia/Baghdad",
    owner: { name: "Applicant Owner", phone: testPhone(), password: OWNER_PASSWORD },
    ...overrides,
  };
}

/** Logs in a throwaway System Admin and returns its access token. */
async function adminToken(t) {
  const phone = testPhone();
  const admin = await createTestSystemAdmin({ phone });
  t.after(() => cleanupTestData({ adminIds: [admin.id] }));
  const res = await request(app)
    .post("/api/admin/auth/login")
    .send({ phone, password: admin.password });
  assert.equal(res.status, 200, "the test admin should be able to log in");
  return res.body.data.accessToken;
}

/** Deletes a business and its users, in FK-safe order. */
async function dropBusiness(businessId) {
  if (!businessId) return;
  const [users] = await pool.query(`SELECT id FROM users WHERE business_id = ?`, [businessId]);
  await cleanupTestData({
    businessIds: [businessId],
    userIds: users.map((u) => u.id),
  });
}

test("a self-registration is accepted but created pending, not active", async (t) => {
  if (!(await requireDatabase(t))) return;

  const payload = registrationPayload();
  const res = await request(app).post("/api/registration").send(payload);

  // 202, not 201: the account exists but is not usable yet.
  assert.equal(res.status, 202, JSON.stringify(res.body));
  assert.equal(res.body.success, true);
  assert.equal(res.body.data.status, "pending");

  const businessId = res.body.data.businessId;
  t.after(() => dropBusiness(businessId));

  const [rows] = await pool.query(`SELECT status, approved_at, rejected_at FROM businesses WHERE id = ?`, [
    businessId,
  ]);
  assert.equal(rows[0].status, "pending", "a self-registration must never create an active business");
  assert.equal(rows[0].approved_at, null);
  assert.equal(rows[0].rejected_at, null);
});

test("a pending business CANNOT log in, even with the correct password", async (t) => {
  if (!(await requireDatabase(t))) return;

  // The whole point of the feature. The password is right; the answer is
  // still no, because no administrator has approved it.
  const payload = registrationPayload();
  const res = await request(app).post("/api/registration").send(payload);
  const businessId = res.body.data.businessId;
  t.after(() => dropBusiness(businessId));

  const login = await request(app)
    .post("/api/auth/login")
    .send({ phone: payload.owner.phone, password: OWNER_PASSWORD });

  assert.equal(login.status, 403, JSON.stringify(login.body));
  assert.equal(login.body.success, false);
  assert.equal(login.body.error.code, "BUSINESS_PENDING_APPROVAL");
  assert.ok(!login.body.data, "no session may be issued");
});

test("approval lets the same credentials in, and records who decided", async (t) => {
  if (!(await requireDatabase(t))) return;

  const token = await adminToken(t);
  const payload = registrationPayload();
  const submitted = await request(app).post("/api/registration").send(payload);
  const businessId = submitted.body.data.businessId;
  t.after(() => dropBusiness(businessId));

  // Refused before the decision...
  const before = await request(app)
    .post("/api/auth/login")
    .send({ phone: payload.owner.phone, password: OWNER_PASSWORD });
  assert.equal(before.status, 403);

  const approved = await request(app)
    .post(`/api/admin/businesses/${businessId}/approve`)
    .set("Authorization", `Bearer ${token}`)
    .send();
  assert.equal(approved.status, 200, JSON.stringify(approved.body));
  assert.equal(approved.body.data.status, "active");

  // ...and admitted after it, with no change to the credentials.
  const after_ = await request(app)
    .post("/api/auth/login")
    .send({ phone: payload.owner.phone, password: OWNER_PASSWORD });
  assert.equal(after_.status, 200, JSON.stringify(after_.body));
  assert.equal(after_.body.data.business.id, businessId);
  assert.ok(after_.body.data.accessToken, "an approved business gets a real session");

  const [rows] = await pool.query(`SELECT status, approved_at, approved_by FROM businesses WHERE id = ?`, [
    businessId,
  ]);
  assert.equal(rows[0].status, "active");
  assert.ok(rows[0].approved_at, "the decision must be dated");
  assert.ok(rows[0].approved_by, "the decision must name the administrator who made it");
});

test("rejection keeps them out and tells them why", async (t) => {
  if (!(await requireDatabase(t))) return;

  const token = await adminToken(t);
  const payload = registrationPayload();
  const submitted = await request(app).post("/api/registration").send(payload);
  const businessId = submitted.body.data.businessId;
  t.after(() => dropBusiness(businessId));

  const reason = "Business licence could not be verified.";
  const rejected = await request(app)
    .post(`/api/admin/businesses/${businessId}/reject`)
    .set("Authorization", `Bearer ${token}`)
    .send({ reason });
  assert.equal(rejected.status, 200, JSON.stringify(rejected.body));
  assert.equal(rejected.body.data.status, "rejected");
  assert.equal(rejected.body.data.rejectionReason, reason);

  const login = await request(app)
    .post("/api/auth/login")
    .send({ phone: payload.owner.phone, password: OWNER_PASSWORD });
  assert.equal(login.status, 403);
  assert.equal(login.body.error.code, "BUSINESS_REJECTED");
  assert.match(login.body.error.message, /licence/i, "the applicant should be told the reason");
});

test("a rejection requires a reason", async (t) => {
  if (!(await requireDatabase(t))) return;

  const token = await adminToken(t);
  const payload = registrationPayload();
  const submitted = await request(app).post("/api/registration").send(payload);
  const businessId = submitted.body.data.businessId;
  t.after(() => dropBusiness(businessId));

  const res = await request(app)
    .post(`/api/admin/businesses/${businessId}/reject`)
    .set("Authorization", `Bearer ${token}`)
    .send({});
  assert.equal(res.status, 422, JSON.stringify(res.body));
  assert.ok(res.body.error.details?.fields, "the failing field should be named");

  const [rows] = await pool.query(`SELECT status FROM businesses WHERE id = ?`, [businessId]);
  assert.equal(rows[0].status, "pending", "a refused-but-unreasoned rejection must change nothing");
});

test("a decision cannot be made twice", async (t) => {
  if (!(await requireDatabase(t))) return;

  // Two administrators working the same queue, or one double-click. The
  // second attempt must not silently overwrite the first decision.
  const token = await adminToken(t);
  const payload = registrationPayload();
  const submitted = await request(app).post("/api/registration").send(payload);
  const businessId = submitted.body.data.businessId;
  t.after(() => dropBusiness(businessId));

  const first = await request(app)
    .post(`/api/admin/businesses/${businessId}/approve`)
    .set("Authorization", `Bearer ${token}`)
    .send();
  assert.equal(first.status, 200);

  const second = await request(app)
    .post(`/api/admin/businesses/${businessId}/reject`)
    .set("Authorization", `Bearer ${token}`)
    .send({ reason: "Changed my mind." });
  assert.equal(second.status, 409, JSON.stringify(second.body));
  assert.equal(second.body.error.code, "ALREADY_DECIDED");

  const [rows] = await pool.query(`SELECT status FROM businesses WHERE id = ?`, [businessId]);
  assert.equal(rows[0].status, "active", "the first decision stands");
});

test("the approval queue lists pending registrations, and is paged", async (t) => {
  if (!(await requireDatabase(t))) return;

  const token = await adminToken(t);
  const payload = registrationPayload();
  const submitted = await request(app).post("/api/registration").send(payload);
  const businessId = submitted.body.data.businessId;
  t.after(() => dropBusiness(businessId));

  const res = await request(app)
    .get("/api/admin/businesses?status=pending&pageSize=100")
    .set("Authorization", `Bearer ${token}`);

  assert.equal(res.status, 200, JSON.stringify(res.body));
  assert.ok(Array.isArray(res.body.data));
  assert.ok(res.body.meta.pagination, "a list must report how it was paged");

  const mine = res.body.data.find((b) => b.id === businessId);
  assert.ok(mine, "the new registration should appear in the pending queue");
  assert.equal(mine.status, "pending");
  assert.equal(mine.owner.phone, payload.owner.phone, "the admin needs the applicant's contact details");

  // The filter must actually filter.
  assert.ok(
    res.body.data.every((b) => b.status === "pending"),
    "status=pending must not return businesses in other states"
  );
});

test("a business user's token cannot reach the approval queue or decide", async (t) => {
  if (!(await requireDatabase(t))) return;

  // Approving your own registration would defeat the entire feature.
  const adminTok = await adminToken(t);
  const payload = registrationPayload();
  const submitted = await request(app).post("/api/registration").send(payload);
  const businessId = submitted.body.data.businessId;
  t.after(() => dropBusiness(businessId));

  // Approve so the applicant can obtain a real business-user session.
  await request(app)
    .post(`/api/admin/businesses/${businessId}/approve`)
    .set("Authorization", `Bearer ${adminTok}`)
    .send();

  const login = await request(app)
    .post("/api/auth/login")
    .send({ phone: payload.owner.phone, password: OWNER_PASSWORD });
  assert.equal(login.status, 200);
  const businessTok = login.body.data.accessToken;

  for (const call of [
    request(app).get("/api/admin/businesses").set("Authorization", `Bearer ${businessTok}`),
    request(app).post(`/api/admin/businesses/${businessId}/approve`).set("Authorization", `Bearer ${businessTok}`),
    request(app)
      .post(`/api/admin/businesses/${businessId}/reject`)
      .set("Authorization", `Bearer ${businessTok}`)
      .send({ reason: "self-serve" }),
  ]) {
    const res = await call;
    assert.equal(res.status, 403, `a business user reached an admin route: ${JSON.stringify(res.body)}`);
  }
});

test("registration is anonymous, so a duplicate phone must not be revealed", async (t) => {
  if (!(await requireDatabase(t))) return;

  // §58's rule applies to any public endpoint that can be probed: the
  // response must be identical whether or not the number already has an
  // account, or this becomes a way to enumerate users.
  const first = registrationPayload();
  const submitted = await request(app).post("/api/registration").send(first);
  const businessId = submitted.body.data.businessId;
  t.after(() => dropBusiness(businessId));

  const second = await request(app)
    .post("/api/registration")
    .send(registrationPayload({ owner: { ...first.owner } }));

  assert.equal(second.status, submitted.status, "status must not differ for a known phone");
  assert.equal(second.body.data.status, "pending");
  assert.equal(second.body.data.message, submitted.body.data.message, "the message must not differ either");
  assert.ok(!second.body.data.businessId, "and no second business may be created");

  const [rows] = await pool.query(`SELECT COUNT(*) AS n FROM users WHERE phone = ?`, [first.owner.phone]);
  assert.equal(Number(rows[0].n), 1, "the duplicate owner must not exist");
});

test("a registration cannot smuggle its own approved status", async (t) => {
  if (!(await requireDatabase(t))) return;

  // Mass-assignment: the validator strips unknown keys, so `status` sent by
  // a client is dropped rather than honoured. If it were honoured, anyone
  // could self-approve and the approval step would be decorative.
  const payload = { ...registrationPayload(), status: "active" };
  const res = await request(app).post("/api/registration").send(payload);
  const businessId = res.body.data.businessId;
  t.after(() => dropBusiness(businessId));

  const [rows] = await pool.query(`SELECT status FROM businesses WHERE id = ?`, [businessId]);
  assert.equal(rows[0].status, "pending", "a client-supplied status must be ignored");
});

test("an administrator creating a business directly gets an active one", async (t) => {
  if (!(await requireDatabase(t))) return;

  // §2's original path, which must keep working: the administrator IS the
  // approval, so no pending step and no approval metadata.
  const token = await adminToken(t);
  const payload = registrationPayload();

  const res = await request(app)
    .post("/api/admin/businesses")
    .set("Authorization", `Bearer ${token}`)
    .send(payload);
  assert.equal(res.status, 201, JSON.stringify(res.body));
  const businessId = res.body.data.businessId;
  t.after(() => dropBusiness(businessId));

  const [rows] = await pool.query(`SELECT status, approved_at FROM businesses WHERE id = ?`, [businessId]);
  assert.equal(rows[0].status, "active");
  assert.equal(rows[0].approved_at, null, "it was never pending, so it was never approved");

  const login = await request(app)
    .post("/api/auth/login")
    .send({ phone: payload.owner.phone, password: OWNER_PASSWORD });
  assert.equal(login.status, 200, "an admin-created business can sign in immediately");
});

after(async () => {
  await closePool();
});
