// §34's Settings sections, §29's numbering, and the claim the catalogue makes.
//
// The catalogue says every key it declares is HONOURED somewhere. That is the
// claim worth testing: for each setting, change it and show that behaviour
// elsewhere changes with it. A setting that stores cleanly and does nothing is
// the failure mode these tests exist to catch, and it is invisible otherwise —
// the PATCH returns 200 either way.

import { test, after } from "node:test";
import assert from "node:assert/strict";
import request from "supertest";

import { app } from "../../src/app.js";
import { pool, closePool, runInTransaction } from "../../src/db/pool.js";
import { createDefaultRoles, findOwnerRoleId } from "../../src/modules/rbac/repository.js";
import { adjustStock } from "../../src/modules/inventory/service.js";
import { signAccessToken } from "../../src/utils/token.js";
import { SETTINGS } from "../../src/modules/settings/catalog.js";
import { requireDatabase, testPhone, cleanupTestData } from "./helpers.js";

async function fixture() {
  const f = await runInTransaction(async (conn) => {
    const [b] = await conn.query(
      `INSERT INTO businesses (name, business_type, phone, status, currency)
       VALUES (?, 'warehouse', ?, 'active', 'USD')`,
      [`Cfg ${Date.now()}-${Math.random().toString(36).slice(2, 6)}`, testPhone()]
    );
    const businessId = b.insertId;
    await createDefaultRoles(conn, businessId);
    const roleId = await findOwnerRoleId(conn, businessId);

    const [u] = await conn.query(
      `INSERT INTO users (business_id, name, phone, password_hash, is_owner, role_id, status)
       VALUES (?, 'Owner', ?, 'x', TRUE, ?, 'active')`,
      [businessId, testPhone(), roleId]
    );
    const [w] = await conn.query(
      `INSERT INTO warehouses (business_id, name, location_type, is_default, status)
       VALUES (?, 'Main', 'warehouse', TRUE, 'active')`,
      [businessId]
    );
    const [p] = await conn.query(
      `INSERT INTO products (business_id, name, sku, selling_price, status)
       VALUES (?, 'Widget', ?, 10, 'active')`,
      [businessId, `CFG-${Date.now()}-${Math.random().toString(36).slice(2, 6)}`]
    );
    const [c] = await conn.query(
      `INSERT INTO customers (business_id, name, phone, status) VALUES (?, 'Buyer', ?, 'active')`,
      [businessId, testPhone()]
    );
    return {
      businessId,
      userId: u.insertId,
      warehouseId: w.insertId,
      productId: p.insertId,
      customerId: c.insertId,
      ownerRoleId: roleId,
    };
  });

  f.token = signAccessToken({
    accountType: "business_user",
    userId: f.userId,
    businessId: f.businessId,
  });
  return f;
}

async function cleanup(businessId) {
  if (!businessId) return;
  for (const table of [
    "payments",
    "order_edits",
    "order_items",
    "orders",
    "purchase_items",
    "purchases",
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
const setSetting = (f, body) => auth(request(app).patch("/api/settings"), f.token).send(body);

// ---- the catalogue's own promise -----------------------------------------

test("every declared setting says where it is honoured", () => {
  // Not a database test: it checks the catalogue against its own rule, which is
  // what stops the next setting being added without anything reading it.
  for (const [key, spec] of Object.entries(SETTINGS)) {
    assert.ok(spec.honouredBy, `${key} declares no honouredBy — nothing may read it`);
    assert.ok(spec.description, `${key} has no description`);
    assert.ok(["boolean", "string", "number"].includes(spec.type), `${key} has an odd type`);
    assert.notEqual(spec.default, undefined, `${key} has no default`);
  }
});

test("settings read back with every declared key and its default", async (t) => {
  if (!(await requireDatabase(t))) return;
  const f = await fixture();
  t.after(() => cleanup(f.businessId));

  const res = await auth(request(app).get("/api/settings"), f.token).send();
  assert.equal(res.status, 200, JSON.stringify(res.body));

  for (const [key, spec] of Object.entries(SETTINGS)) {
    assert.equal(
      res.body.data.values[key],
      spec.default,
      `${key} should read back as its declared default`
    );
    assert.equal(res.body.data.definitions[key].type, spec.type);
  }
});

// ---- §44: the low-stock default -----------------------------------------

test("§44: a product with no threshold of its own uses the business setting", async (t) => {
  if (!(await requireDatabase(t))) return;
  const f = await fixture();
  t.after(() => cleanup(f.businessId));

  // 4 in stock, no reorder_level on the product at all.
  await adjustStock({
    businessId: f.businessId,
    userId: f.userId,
    productId: f.productId,
    warehouseId: f.warehouseId,
    delta: 4,
    movementType: "manual_increase",
  });

  // Default is 5, so 4 is low — and before the setting existed this product
  // could run to zero without ever appearing, because NULL <= NULL is not true.
  const byDefault = await auth(request(app).get("/api/inventory/low-stock"), f.token).send();
  assert.equal(byDefault.status, 200, JSON.stringify(byDefault.body));
  assert.equal(byDefault.body.data.length, 1);
  assert.equal(byDefault.body.data[0].reorderLevel, null, "the product has none of its own");
  assert.equal(byDefault.body.data[0].effectiveReorderLevel, 5, "so the business's default applied");

  // Lower the threshold below what is on hand and it stops being low.
  assert.equal((await setSetting(f, { "inventory.low_stock_threshold_default": 2 })).status, 200);
  const stricter = await auth(request(app).get("/api/inventory/low-stock"), f.token).send();
  assert.equal(stricter.body.data.length, 0, "4 on hand is no longer low when the rule says 2");

  // Raise it and it is low again — the setting is being read per request.
  await setSetting(f, { "inventory.low_stock_threshold_default": 10 });
  const looser = await auth(request(app).get("/api/inventory/low-stock"), f.token).send();
  assert.equal(looser.body.data.length, 1);
  assert.equal(looser.body.data[0].effectiveReorderLevel, 10);
});

test("§44: a product's own threshold still wins over the default", async (t) => {
  if (!(await requireDatabase(t))) return;
  const f = await fixture();
  t.after(() => cleanup(f.businessId));

  await pool.query(`UPDATE products SET reorder_level = 1 WHERE id = ?`, [f.productId]);
  await adjustStock({
    businessId: f.businessId,
    userId: f.userId,
    productId: f.productId,
    warehouseId: f.warehouseId,
    delta: 4,
    movementType: "manual_increase",
  });

  await setSetting(f, { "inventory.low_stock_threshold_default": 10 });
  const res = await auth(request(app).get("/api/inventory/low-stock"), f.token).send();
  assert.equal(res.body.data.length, 0, "the product said 1, and 4 is not below 1");
});

test("§54: a threshold can be cleared with null, and 0 still means 'only when empty'", async (t) => {
  if (!(await requireDatabase(t))) return;
  const f = await fixture();
  t.after(() => cleanup(f.businessId));

  await adjustStock({
    businessId: f.businessId,
    userId: f.userId,
    productId: f.productId,
    warehouseId: f.warehouseId,
    delta: 4,
    movementType: "manual_increase",
  });

  // Explicitly zero: alert me only when it is actually empty. The column used to
  // be NOT NULL DEFAULT 0, so this was the only thing it could say.
  const zeroed = await auth(request(app).patch(`/api/products/${f.productId}`), f.token).send({
    reorderLevel: 0,
  });
  assert.equal(zeroed.status, 200, JSON.stringify(zeroed.body));
  const atZero = await auth(request(app).get("/api/inventory/low-stock"), f.token).send();
  assert.equal(atZero.body.data.length, 0, "4 on hand is not empty");

  // And null means "no threshold of my own — use the business default", which
  // the column previously could not hold: the request failed on a NOT NULL
  // constraint with a message about a missing value.
  const cleared = await auth(request(app).patch(`/api/products/${f.productId}`), f.token).send({
    reorderLevel: null,
  });
  assert.equal(cleared.status, 200, JSON.stringify(cleared.body));
  assert.equal(cleared.body.data.reorderLevel, null);

  const byDefault = await auth(request(app).get("/api/inventory/low-stock"), f.token).send();
  assert.equal(byDefault.body.data.length, 1, "the default of 5 now applies");
  assert.equal(byDefault.body.data[0].effectiveReorderLevel, 5);
});

// ---- §43: payment methods -----------------------------------------------

async function confirmedOrder(f) {
  const res = await auth(request(app).post("/api/orders"), f.token).send({
    orderType: "standard",
    customerId: f.customerId,
    status: "confirmed",
    items: [{ productId: f.productId, quantity: 1, unitPrice: 100 }],
  });
  assert.equal(res.status, 201, JSON.stringify(res.body));
  return res.body.data.id;
}

test("§43: a payment method that is switched off is refused, not merely hidden", async (t) => {
  if (!(await requireDatabase(t))) return;
  const f = await fixture();
  t.after(() => cleanup(f.businessId));
  await adjustStock({
    businessId: f.businessId,
    userId: f.userId,
    productId: f.productId,
    warehouseId: f.warehouseId,
    delta: 10,
    movementType: "manual_increase",
  });

  const orderId = await confirmedOrder(f);

  // Cards are off by default (§43's own default), so this must be refused even
  // though the request is otherwise perfectly valid.
  const card = await auth(request(app).post(`/api/orders/${orderId}/payments`), f.token).send({
    amount: 10,
    method: "card",
  });
  assert.equal(card.status, 422, JSON.stringify(card.body));
  assert.match(card.body.error.message, /switched off/i);

  const [[none]] = await pool.query(`SELECT COUNT(*) AS n FROM payments WHERE business_id = ?`, [
    f.businessId,
  ]);
  assert.equal(Number(none.n), 0, "a refused method must not leave a payment behind");

  // Turn cards on and the same request works.
  assert.equal((await setSetting(f, { "payments.card_enabled": true })).status, 200);
  const allowed = await auth(request(app).post(`/api/orders/${orderId}/payments`), f.token).send({
    amount: 10,
    method: "card",
  });
  assert.equal(allowed.status, 201, JSON.stringify(allowed.body));

  // And turning cash OFF refuses cash, which is the same rule in reverse.
  await setSetting(f, { "payments.cash_enabled": false });
  const cash = await auth(request(app).post(`/api/orders/${orderId}/payments`), f.token).send({
    amount: 10,
    method: "cash",
  });
  assert.equal(cash.status, 422, JSON.stringify(cash.body));
});

test("§43: the same rule applies to paying a supplier, including on creation", async (t) => {
  if (!(await requireDatabase(t))) return;
  const f = await fixture();
  t.after(() => cleanup(f.businessId));

  const supplier = await auth(request(app).post("/api/suppliers"), f.token).send({
    name: "Timber Co",
    phone: testPhone(),
  });

  // A purchase created with an initial payment by a disabled method must be
  // refused as a whole — this is the path that does not go through the payments
  // endpoint at all.
  const onCreate = await auth(request(app).post("/api/purchases"), f.token).send({
    supplierId: supplier.body.data.id,
    items: [{ productId: f.productId, quantity: 1, unitCost: 5 }],
    paidAmount: 5,
    paymentMethod: "card",
  });
  assert.equal(onCreate.status, 422, JSON.stringify(onCreate.body));

  const [[left]] = await pool.query(`SELECT COUNT(*) AS n FROM purchases WHERE business_id = ?`, [
    f.businessId,
  ]);
  assert.equal(Number(left.n), 0, "§46: the whole purchase rolls back, not just the payment");

  await setSetting(f, { "payments.card_enabled": true });
  const retry = await auth(request(app).post("/api/purchases"), f.token).send({
    supplierId: supplier.body.data.id,
    items: [{ productId: f.productId, quantity: 1, unitCost: 5 }],
    paidAmount: 5,
    paymentMethod: "card",
  });
  assert.equal(retry.status, 201, JSON.stringify(retry.body));
});

test("§43: `other` has no switch, so a real payment can always be recorded", async (t) => {
  if (!(await requireDatabase(t))) return;
  const f = await fixture();
  t.after(() => cleanup(f.businessId));
  await adjustStock({
    businessId: f.businessId,
    userId: f.userId,
    productId: f.productId,
    warehouseId: f.warehouseId,
    delta: 10,
    movementType: "manual_increase",
  });

  const orderId = await confirmedOrder(f);
  await setSetting(f, {
    "payments.cash_enabled": false,
    "payments.bank_transfer_enabled": false,
    "payments.card_enabled": false,
  });

  const res = await auth(request(app).post(`/api/orders/${orderId}/payments`), f.token).send({
    amount: 10,
    method: "other",
    note: "Cheque, banked Monday",
  });
  assert.equal(res.status, 201, JSON.stringify(res.body));
});

// ---- §3: the password policy --------------------------------------------

test("§3: a business can demand a longer password, but never a shorter one", async (t) => {
  if (!(await requireDatabase(t))) return;
  const f = await fixture();
  t.after(() => cleanup(f.businessId));

  // 8 is the system floor, so a 9-character password is fine by default.
  const ok9 = await auth(request(app).post("/api/users"), f.token).send({
    name: "Nine",
    phone: testPhone(),
    roleId: f.ownerRoleId,
    password: "123456789",
  });
  assert.equal(ok9.status, 201, JSON.stringify(ok9.body));

  await setSetting(f, { "security.min_password_length": 12 });

  const tooShort = await auth(request(app).post("/api/users"), f.token).send({
    name: "Still Nine",
    phone: testPhone(),
    roleId: f.ownerRoleId,
    password: "123456789",
  });
  assert.equal(tooShort.status, 422, JSON.stringify(tooShort.body));
  assert.match(tooShort.body.error.message, /at least 12/);

  const longEnough = await auth(request(app).post("/api/users"), f.token).send({
    name: "Twelve",
    phone: testPhone(),
    roleId: f.ownerRoleId,
    password: "123456789012",
  });
  assert.equal(longEnough.status, 201, JSON.stringify(longEnough.body));

  // A setting BELOW the system floor cannot weaken it.
  await setSetting(f, { "security.min_password_length": 3 });
  const stillRefused = await auth(request(app).post("/api/users"), f.token).send({
    name: "Four",
    phone: testPhone(),
    roleId: f.ownerRoleId,
    password: "abcd",
  });
  assert.equal(stillRefused.status, 422, "the floor is the floor, whatever the setting says");
});

test("§3: the policy also governs a reset and a self-service change", async (t) => {
  if (!(await requireDatabase(t))) return;
  const f = await fixture();
  t.after(() => cleanup(f.businessId));

  const phone = testPhone();
  const created = await auth(request(app).post("/api/users"), f.token).send({
    name: "Staff",
    phone,
    roleId: f.ownerRoleId,
  });
  const id = created.body.data.id;
  await setSetting(f, { "security.min_password_length": 14 });

  const shortReset = await auth(request(app).post(`/api/users/${id}/password`), f.token).send({
    password: "shortpassword",
  });
  assert.equal(shortReset.status, 422, JSON.stringify(shortReset.body));
  assert.match(shortReset.body.error.message, /at least 14/);

  const goodReset = await auth(request(app).post(`/api/users/${id}/password`), f.token).send({
    password: "quitealongpassword",
  });
  assert.equal(goodReset.status, 200, JSON.stringify(goodReset.body));

  // And the employee changing their own password obeys the same minimum.
  const login = await request(app).post("/api/auth/login").send({ phone, password: "quitealongpassword" });
  assert.equal(login.status, 200, JSON.stringify(login.body));
  const theirToken = login.body.data.accessToken;

  const theirChange = await auth(request(app).post("/api/auth/change-password"), theirToken).send({
    currentPassword: "quitealongpassword",
    newPassword: "shortpassword",
  });
  assert.equal(theirChange.status, 422, JSON.stringify(theirChange.body));
});

// ---- §34's business profile ---------------------------------------------

test("§34: a business can read and edit its own profile", async (t) => {
  if (!(await requireDatabase(t))) return;
  const f = await fixture();
  t.after(() => cleanup(f.businessId));

  const read = await auth(request(app).get("/api/business"), f.token).send();
  assert.equal(read.status, 200, JSON.stringify(read.body));
  assert.equal(read.body.data.id, f.businessId);
  assert.equal(read.body.data.currency, "USD");
  assert.equal(read.body.data.status, "active");

  const patched = await auth(request(app).patch("/api/business"), f.token).send({
    name: "Karwan Furniture",
    currency: "iqd",
    city: "Erbil",
    taxNumber: "TX-100",
    businessType: "furniture_factory",
  });
  assert.equal(patched.status, 200, JSON.stringify(patched.body));
  assert.equal(patched.body.data.name, "Karwan Furniture");
  assert.equal(patched.body.data.currency, "IQD", "a currency code is normalised, not stored as typed");
  assert.equal(patched.body.data.city, "Erbil");
  assert.equal(patched.body.data.businessType, "furniture_factory");

  assert.equal((await auth(request(app).patch("/api/business"), f.token).send({})).status, 422);
  assert.equal(
    (await auth(request(app).patch("/api/business"), f.token).send({ currency: "DOLLARS" })).status,
    422
  );
  assert.equal(
    (await auth(request(app).patch("/api/business"), f.token).send({ businessType: "bakery" })).status,
    422
  );

  // The phone is the business's identity in the approval queue, so it is not
  // self-service — an unknown field is refused outright.
  assert.equal(
    (await auth(request(app).patch("/api/business"), f.token).send({ phone: testPhone() })).status,
    422
  );
});

test("§34: the profile is the business's own, and not an employee's to read", async (t) => {
  if (!(await requireDatabase(t))) return;
  const a = await fixture();
  const b = await fixture();
  t.after(() => Promise.all([cleanup(a.businessId), cleanup(b.businessId)]));

  const mine = await auth(request(app).get("/api/business"), b.token).send();
  assert.equal(Number(mine.body.data.id), b.businessId, "each session sees its own business");
  assert.notEqual(Number(mine.body.data.id), a.businessId);

  // §24: only the owner holds settings.* by default.
  const phone = testPhone();
  const [[clerkRole]] = await pool.query(
    `SELECT id FROM roles WHERE business_id = ? AND name = 'Sales Staff'`,
    [a.businessId]
  );
  const clerk = await auth(request(app).post("/api/users"), a.token).send({
    name: "Clerk",
    phone,
    roleId: clerkRole.id,
  });
  const login = await request(app)
    .post("/api/auth/login")
    .send({ phone, password: clerk.body.data.temporaryPassword });

  assert.equal(
    (await auth(request(app).get("/api/business"), login.body.data.accessToken).send()).status,
    403
  );
  assert.equal(
    (await auth(request(app).patch("/api/business"), login.body.data.accessToken).send({ city: "X" })).status,
    403
  );
});

// ---- §29's document numbering -------------------------------------------

test("§29: numbering is listed for every type, including ones never used yet", async (t) => {
  if (!(await requireDatabase(t))) return;
  const f = await fixture();
  t.after(() => cleanup(f.businessId));

  const res = await auth(request(app).get("/api/documents/numbering"), f.token).send();
  assert.equal(res.status, 200, JSON.stringify(res.body));

  const types = res.body.data.map((r) => r.documentType);
  for (const expected of ["sale", "order", "purchase", "return", "transfer", "production"]) {
    assert.ok(types.includes(expected), `${expected} should be configurable`);
  }
  assert.equal(
    types.includes("invoice"),
    false,
    "nothing allocates `invoice` — a sale is the invoice — so it must not be offered"
  );

  const order = res.body.data.find((r) => r.documentType === "order");
  assert.equal(order.prefix, "ORD");
  assert.equal(order.nextNumber, 1, "a type with no row yet still reports what it would start at");
  assert.match(order.example, /^ORD-\d{4}-000001$/, "and shows what the next document will be called");
});

test("§29: a business can choose its own prefix and padding, and documents use them", async (t) => {
  if (!(await requireDatabase(t))) return;
  const f = await fixture();
  t.after(() => cleanup(f.businessId));

  const changed = await auth(request(app).patch("/api/documents/numbering/order"), f.token).send({
    prefix: "KRW",
    numberPadding: 4,
    includeYear: false,
  });
  assert.equal(changed.status, 200, JSON.stringify(changed.body));
  assert.equal(changed.body.data.prefix, "KRW");
  assert.equal(changed.body.data.example, "KRW-0001");

  // The real test: the next document actually gets that number.
  const order = await auth(request(app).post("/api/orders"), f.token).send({
    orderType: "standard",
    items: [{ productId: f.productId, quantity: 1, unitPrice: 10 }],
  });
  assert.equal(order.status, 201, JSON.stringify(order.body));
  assert.equal(order.body.data.orderNumber, "KRW-0001", "§29: the business's own numbering, applied");

  const second = await auth(request(app).post("/api/orders"), f.token).send({
    orderType: "standard",
    items: [{ productId: f.productId, quantity: 1, unitPrice: 10 }],
  });
  assert.equal(second.body.data.orderNumber, "KRW-0002");
});

test("§29: the counter can be moved forward for a migration, never backward", async (t) => {
  if (!(await requireDatabase(t))) return;
  const f = await fixture();
  t.after(() => cleanup(f.businessId));

  // A business arriving from another system continues its own numbering.
  const forward = await auth(request(app).patch("/api/documents/numbering/order"), f.token).send({
    nextNumber: 5000,
  });
  assert.equal(forward.status, 200, JSON.stringify(forward.body));
  assert.equal(forward.body.data.nextNumber, 5000);

  const order = await auth(request(app).post("/api/orders"), f.token).send({
    orderType: "standard",
    items: [{ productId: f.productId, quantity: 1, unitPrice: 10 }],
  });
  assert.match(order.body.data.orderNumber, /-005000$/);

  // Backward would hand out a number that already exists on a document.
  const backward = await auth(request(app).patch("/api/documents/numbering/order"), f.token).send({
    nextNumber: 10,
  });
  assert.equal(backward.status, 422, JSON.stringify(backward.body));
  assert.match(backward.body.error.message, /only be moved forward/);

  const [[row]] = await pool.query(
    `SELECT next_number FROM document_sequences WHERE business_id = ? AND document_type = 'order'`,
    [f.businessId]
  );
  assert.equal(Number(row.next_number), 5001, "the counter is where the issued document left it");
});

test("§29: numbering is per business, and an unknown type is a 404", async (t) => {
  if (!(await requireDatabase(t))) return;
  const a = await fixture();
  const b = await fixture();
  t.after(() => Promise.all([cleanup(a.businessId), cleanup(b.businessId)]));

  await auth(request(app).patch("/api/documents/numbering/order"), a.token).send({ prefix: "AAA" });

  const other = await auth(request(app).get("/api/documents/numbering"), b.token).send();
  const order = other.body.data.find((r) => r.documentType === "order");
  assert.equal(order.prefix, "ORD", "one business's choice is not another's");

  assert.equal(
    (await auth(request(app).patch("/api/documents/numbering/carrier-pigeon"), a.token).send({ prefix: "X" }))
      .status,
    404
  );
  assert.equal(
    (await auth(request(app).patch("/api/documents/numbering/order"), a.token).send({})).status,
    422
  );
});

after(() => closePool());
