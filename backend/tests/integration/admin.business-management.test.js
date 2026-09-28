// §57's System Admin actions: edit a business, enable or disable it, reset an
// owner's password, and read one tenant's figures.
//
// The boundary is the point of most of these. A System Admin has no business of
// their own, so every route here names the business explicitly — and a business
// user must not be able to reach any of them, in either direction.

import { test, after } from "node:test";
import assert from "node:assert/strict";
import request from "supertest";

import { app } from "../../src/app.js";
import { pool, closePool, runInTransaction } from "../../src/db/pool.js";
import { createDefaultRoles, findOwnerRoleId } from "../../src/modules/rbac/repository.js";
import { adjustStock } from "../../src/modules/inventory/service.js";
import { signAccessToken } from "../../src/utils/token.js";
import { hashPassword, verifyPassword } from "../../src/utils/password.js";
import { requireDatabase, testPhone, cleanupTestData } from "./helpers.js";

async function business() {
  const f = await runInTransaction(async (conn) => {
    const [b] = await conn.query(
      `INSERT INTO businesses (name, business_type, phone, status, currency)
       VALUES (?, 'warehouse', ?, 'active', 'USD')`,
      [`Adm ${Date.now()}-${Math.random().toString(36).slice(2, 6)}`, testPhone()]
    );
    const businessId = b.insertId;
    await createDefaultRoles(conn, businessId);
    const roleId = await findOwnerRoleId(conn, businessId);

    const ownerPhone = testPhone();
    const [u] = await conn.query(
      `INSERT INTO users (business_id, name, phone, password_hash, is_owner, role_id, status)
       VALUES (?, 'Owner', ?, ?, TRUE, ?, 'active')`,
      [businessId, ownerPhone, await hashPassword("OwnerPassword123"), roleId]
    );
    const [w] = await conn.query(
      `INSERT INTO warehouses (business_id, name, location_type, is_default, status)
       VALUES (?, 'Main', 'warehouse', TRUE, 'active')`,
      [businessId]
    );
    const [p] = await conn.query(
      `INSERT INTO products (business_id, name, sku, selling_price, status)
       VALUES (?, 'Widget', ?, 10, 'active')`,
      [businessId, `ADM-${Date.now()}-${Math.random().toString(36).slice(2, 6)}`]
    );
    return { businessId, userId: u.insertId, ownerPhone, warehouseId: w.insertId, productId: p.insertId };
  });

  f.token = signAccessToken({
    accountType: "business_user",
    userId: f.userId,
    businessId: f.businessId,
  });
  return f;
}

async function admin() {
  const phone = testPhone();
  const password = `Admin-${Math.random().toString(36).slice(2, 10)}`;
  const [result] = await pool.query(
    `INSERT INTO system_admins (name, phone, password_hash, status) VALUES ('Platform Admin', ?, ?, 'active')`,
    [phone, await hashPassword(password)]
  );
  return {
    id: result.insertId,
    phone,
    password,
    token: signAccessToken({ accountType: "system_admin", userId: result.insertId }),
  };
}

async function cleanup(businessId) {
  if (!businessId) return;
  for (const table of [
    "notifications",
    "payments",
    "order_edits",
    "order_items",
    "orders",
    "inventory_movements",
    "inventory",
    "products",
    "customers",
    "suppliers",
    "document_sequences",
    "business_settings",
    "audit_logs",
    "warehouses",
  ]) {
    await pool.query(`DELETE FROM ${table} WHERE business_id = ?`, [businessId]);
  }
  const [users] = await pool.query(`SELECT id, phone FROM users WHERE business_id = ?`, [businessId]);
  if (users.length) {
    await pool.query(`DELETE FROM refresh_tokens WHERE user_id IN (?)`, [users.map((u) => u.id)]);
    await pool.query(`DELETE FROM login_attempts WHERE phone IN (?)`, [users.map((u) => u.phone)]);
    await pool.query(`DELETE FROM users WHERE business_id = ?`, [businessId]);
  }
  await pool.query(
    `DELETE rp FROM role_permissions rp JOIN roles r ON r.id = rp.role_id WHERE r.business_id = ?`,
    [businessId]
  );
  await pool.query(`DELETE FROM roles WHERE business_id = ?`, [businessId]);
  await cleanupTestData({ businessIds: [businessId] });
}

const auth = (req, token) => req.set("Authorization", `Bearer ${token}`);

test("§57: an admin reads one business in full, with its owner and counts", async (t) => {
  if (!(await requireDatabase(t))) return;
  const f = await business();
  const a = await admin();
  t.after(async () => {
    await cleanup(f.businessId);
    await cleanupTestData({ adminIds: [a.id], phones: [a.phone] });
  });

  const res = await auth(request(app).get(`/api/admin/businesses/${f.businessId}`), a.token).send();
  assert.equal(res.status, 200, JSON.stringify(res.body));
  assert.equal(res.body.data.id, f.businessId);
  assert.equal(res.body.data.status, "active");
  assert.equal(res.body.data.owner.phone, f.ownerPhone, "who to contact is the first thing needed");
  assert.equal(res.body.data.counts.products, 1);
  assert.equal(res.body.data.counts.users, 1);

  assert.equal((await auth(request(app).get("/api/admin/businesses/99999999"), a.token).send()).status, 404);
});

test("§57: an admin can edit a business, including the phone a business cannot", async (t) => {
  if (!(await requireDatabase(t))) return;
  const f = await business();
  const a = await admin();
  t.after(async () => {
    await cleanup(f.businessId);
    await cleanupTestData({ adminIds: [a.id], phones: [a.phone] });
  });

  const newPhone = testPhone();
  const res = await auth(request(app).put(`/api/admin/businesses/${f.businessId}`), a.token).send({
    name: "Karwan Furniture Factory",
    businessType: "furniture_factory",
    phone: newPhone,
    city: "Erbil",
    currency: "iqd",
  });

  assert.equal(res.status, 200, JSON.stringify(res.body));
  assert.equal(res.body.data.name, "Karwan Furniture Factory");
  assert.equal(res.body.data.phone, newPhone, "§57: the identity a business cannot change itself");
  assert.equal(res.body.data.currency, "IQD", "normalised, not stored as typed");
  assert.equal(res.body.data.businessType, "furniture_factory");

  // §30: an administrative edit is on the record, against the business it touched.
  let logged = [];
  for (let i = 0; i < 40; i += 1) {
    const [rows] = await pool.query(
      `SELECT action, actor_type, actor_id, description FROM audit_logs
        WHERE business_id = ? AND action = 'business.updated'`,
      [f.businessId]
    );
    logged = rows;
    if (rows.length) break;
    await new Promise((resolve) => setTimeout(resolve, 25));
  }
  assert.equal(logged.length, 1, "an admin editing someone's business must be traceable");
  assert.equal(logged[0].actor_type, "system_admin");
  assert.equal(Number(logged[0].actor_id), a.id);

  assert.equal((await auth(request(app).put(`/api/admin/businesses/${f.businessId}`), a.token).send({})).status, 422);

  // A business phone is deliberately NOT unique — the migration that created the
  // column says so, and it is right: the credential is `users.phone`, which is
  // unique, while two businesses run by one family from one landline are
  // ordinary. So sharing a number is allowed, and this asserts that rather than
  // the 409 it would be easy to assume.
  const other = await business();
  t.after(() => cleanup(other.businessId));
  const [[existing]] = await pool.query(`SELECT phone FROM businesses WHERE id = ?`, [other.businessId]);
  const shared = await auth(request(app).put(`/api/admin/businesses/${f.businessId}`), a.token).send({
    phone: existing.phone,
  });
  assert.equal(shared.status, 200, JSON.stringify(shared.body));
  assert.equal(shared.body.data.phone, existing.phone);

  // The OWNER's phone is the one that cannot be shared, and it still cannot be.
  const [[owner]] = await pool.query(`SELECT phone FROM users WHERE id = ?`, [other.userId]);
  const clash = await auth(request(app).post("/api/users"), f.token).send({
    name: "Impostor",
    phone: owner.phone,
    roleId: (await pool.query(`SELECT id FROM roles WHERE business_id = ? LIMIT 1`, [f.businessId]))[0][0].id,
  });
  assert.equal(clash.status, 409, JSON.stringify(clash.body));
});

test("§57: disabling a business ends its sessions, and enabling restores access", async (t) => {
  if (!(await requireDatabase(t))) return;
  const f = await business();
  const a = await admin();
  t.after(async () => {
    await cleanup(f.businessId);
    await cleanupTestData({ adminIds: [a.id], phones: [a.phone] });
  });

  // A live session, so there is something to end.
  const login = await request(app)
    .post("/api/auth/login")
    .send({ phone: f.ownerPhone, password: "OwnerPassword123" });
  assert.equal(login.status, 200, JSON.stringify(login.body));
  const refreshToken = login.body.data.refreshToken;

  const disabled = await auth(
    request(app).patch(`/api/admin/businesses/${f.businessId}/status`),
    a.token
  ).send({ status: "disabled", reason: "Non-payment" });
  assert.equal(disabled.status, 200, JSON.stringify(disabled.body));
  assert.equal(disabled.body.data.status, "disabled");

  const [[sessions]] = await pool.query(
    `SELECT COUNT(*) AS n FROM refresh_tokens rt JOIN users u ON u.id = rt.user_id WHERE u.business_id = ?`,
    [f.businessId]
  );
  assert.equal(Number(sessions.n), 0, "switching a business off must actually switch it off");
  assert.ok(
    (await request(app).post("/api/auth/refresh").send({ refreshToken })).status >= 400,
    "and its refresh token mints nothing further"
  );

  // A disabled business cannot sign in at all.
  const blocked = await request(app)
    .post("/api/auth/login")
    .send({ phone: f.ownerPhone, password: "OwnerPassword123" });
  assert.ok(blocked.status >= 400, `a disabled business must not log in, got ${blocked.status}`);

  const enabled = await auth(
    request(app).patch(`/api/admin/businesses/${f.businessId}/status`),
    a.token
  ).send({ status: "active" });
  assert.equal(enabled.status, 200);
  const back = await request(app)
    .post("/api/auth/login")
    .send({ phone: f.ownerPhone, password: "OwnerPassword123" });
  assert.equal(back.status, 200, "re-enabling restores access");

  // The queue's own states are not set here — approving and rejecting record who
  // decided and why, and this route would skip that.
  assert.equal(
    (await auth(request(app).patch(`/api/admin/businesses/${f.businessId}/status`), a.token).send({
      status: "pending",
    })).status,
    422
  );
});

test("§57: an admin can reset an owner's password, and it is returned once", async (t) => {
  if (!(await requireDatabase(t))) return;
  const f = await business();
  const a = await admin();
  t.after(async () => {
    await cleanup(f.businessId);
    await cleanupTestData({ adminIds: [a.id], phones: [a.phone] });
  });

  await request(app).post("/api/auth/login").send({ phone: f.ownerPhone, password: "OwnerPassword123" });

  const res = await auth(
    request(app).post(`/api/admin/businesses/${f.businessId}/reset-password`),
    a.token
  ).send({});

  assert.equal(res.status, 200, JSON.stringify(res.body));
  assert.equal(Number(res.body.data.userId), f.userId, "the owner, by default");
  assert.ok(res.body.data.temporaryPassword, "the admin needs something to pass on");
  assert.equal(res.body.data.sessionsRevoked, true);

  // §3: stored as a hash, and it really is the password that was handed over.
  const [[row]] = await pool.query(`SELECT password_hash FROM users WHERE id = ?`, [f.userId]);
  assert.notEqual(row.password_hash, res.body.data.temporaryPassword);
  assert.equal(await verifyPassword(res.body.data.temporaryPassword, row.password_hash), true);

  // The old password is gone and the new one works.
  assert.ok(
    (await request(app).post("/api/auth/login").send({ phone: f.ownerPhone, password: "OwnerPassword123" }))
      .status >= 400
  );
  const fresh = await request(app)
    .post("/api/auth/login")
    .send({ phone: f.ownerPhone, password: res.body.data.temporaryPassword });
  assert.equal(fresh.status, 200, JSON.stringify(fresh.body));

  // If someone else knew the old password, their session must die too.
  const [[sessions]] = await pool.query(`SELECT COUNT(*) AS n FROM refresh_tokens WHERE user_id = ?`, [
    f.userId,
  ]);
  assert.equal(Number(sessions.n), 1, "only the session just created by the fresh login");

  // The password never reaches the audit trail.
  const [logs] = await pool.query(
    `SELECT description FROM audit_logs WHERE business_id = ? AND action = 'business.password_reset'`,
    [f.businessId]
  );
  assert.ok(logs.length >= 1, "§30: who reset it is recorded");
  assert.equal(
    logs.some((l) => l.description.includes(res.body.data.temporaryPassword)),
    false,
    "a password in a log is a password in every backup of that log"
  );
});

test("§57: an admin can reset a named employee rather than the owner", async (t) => {
  if (!(await requireDatabase(t))) return;
  const f = await business();
  const a = await admin();
  t.after(async () => {
    await cleanup(f.businessId);
    await cleanupTestData({ adminIds: [a.id], phones: [a.phone] });
  });

  const [[role]] = await pool.query(`SELECT id FROM roles WHERE business_id = ? AND name = 'Viewer'`, [
    f.businessId,
  ]);
  const staffPhone = testPhone();
  const [staff] = await pool.query(
    `INSERT INTO users (business_id, name, phone, password_hash, is_owner, role_id, status)
     VALUES (?, 'Locked Out', ?, ?, FALSE, ?, 'active')`,
    [f.businessId, staffPhone, await hashPassword("ForgottenPassword1"), role.id]
  );

  const res = await auth(
    request(app).post(`/api/admin/businesses/${f.businessId}/reset-password`),
    a.token
  ).send({ userId: staff.insertId, password: "BrandNewPassword1" });

  assert.equal(res.status, 200, JSON.stringify(res.body));
  assert.equal(Number(res.body.data.userId), staff.insertId);
  assert.equal(res.body.data.temporaryPassword, undefined, "nothing generated, so nothing returned");

  const login = await request(app)
    .post("/api/auth/login")
    .send({ phone: staffPhone, password: "BrandNewPassword1" });
  assert.equal(login.status, 200, JSON.stringify(login.body));

  // A user of another business cannot be reached through this business's path.
  const other = await business();
  t.after(() => cleanup(other.businessId));
  assert.equal(
    (await auth(request(app).post(`/api/admin/businesses/${f.businessId}/reset-password`), a.token).send({
      userId: other.userId,
    })).status,
    404
  );
});

test("§57: per-business figures come from a deliberate admin endpoint", async (t) => {
  if (!(await requireDatabase(t))) return;
  const f = await business();
  const a = await admin();
  t.after(async () => {
    await cleanup(f.businessId);
    await cleanupTestData({ adminIds: [a.id], phones: [a.phone] });
  });

  await adjustStock({
    businessId: f.businessId,
    userId: f.userId,
    productId: f.productId,
    warehouseId: f.warehouseId,
    delta: 12,
    movementType: "manual_increase",
  });
  const order = await auth(request(app).post("/api/orders"), f.token).send({
    orderType: "quick_sale",
    status: "confirmed",
    items: [{ productId: f.productId, quantity: 2, unitPrice: 10 }],
  });
  assert.equal(order.status, 201, JSON.stringify(order.body));

  const res = await auth(request(app).get(`/api/admin/businesses/${f.businessId}/reports`), a.token).send();
  assert.equal(res.status, 200, JSON.stringify(res.body));
  assert.equal(res.body.data.counts.products, 1);
  assert.equal(res.body.data.counts.orders, 1);
  assert.equal(res.body.data.totals.salesTotal, 20);
  assert.equal(res.body.data.totals.stockQuantity, 10, "12 in, 2 sold");
  assert.equal(res.body.data.recentOrders[0].orderNumber, order.body.data.orderNumber);
});

test("§36: the admin routes are closed to businesses, and business routes to admins", async (t) => {
  if (!(await requireDatabase(t))) return;
  const f = await business();
  const other = await business();
  const a = await admin();
  t.after(async () => {
    await cleanup(f.businessId);
    await cleanup(other.businessId);
    await cleanupTestData({ adminIds: [a.id], phones: [a.phone] });
  });

  // A business user cannot reach any of it — not even for its own business.
  for (const call of [
    () => auth(request(app).get(`/api/admin/businesses/${f.businessId}`), f.token).send(),
    () => auth(request(app).put(`/api/admin/businesses/${f.businessId}`), f.token).send({ city: "X" }),
    () =>
      auth(request(app).patch(`/api/admin/businesses/${f.businessId}/status`), f.token).send({
        status: "disabled",
      }),
    () => auth(request(app).post(`/api/admin/businesses/${f.businessId}/reset-password`), f.token).send({}),
    () => auth(request(app).get(`/api/admin/businesses/${f.businessId}/reports`), f.token).send(),
  ]) {
    const res = await call();
    assert.equal(res.status, 403, `a business user must not reach an admin route, got ${res.status}`);
  }

  // And an admin token cannot walk into the business routes: they resolve their
  // tenant from the session, and an admin has no business of their own.
  for (const path of ["/api/products", "/api/orders", "/api/users", "/api/reports/sales", "/api/business"]) {
    const res = await auth(request(app).get(path), a.token).send();
    assert.equal(res.status, 403, `${path} must refuse an admin token, got ${res.status}`);
  }

  // Another business's owner cannot reach this business through the admin path
  // either — the account type is what is checked, not the id in the URL.
  assert.equal(
    (await auth(request(app).get(`/api/admin/businesses/${f.businessId}`), other.token).send()).status,
    403
  );
});

after(() => closePool());
