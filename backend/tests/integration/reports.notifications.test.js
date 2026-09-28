// §25 (reports) and §31 (notifications).
//
// Reports are where invented numbers do the most damage, because somebody makes
// a decision on them. So these build a known set of documents and assert the
// exact figures — not merely that a report returns rows. The two rules worth
// pinning: a draft order is not revenue, and a cancelled one never happened.
//
// Notifications are the opposite risk: a screen that is always empty because
// nothing ever writes to the table. Each trigger is therefore driven through the
// action that causes it.

import { test, after } from "node:test";
import assert from "node:assert/strict";
import request from "supertest";

import { app } from "../../src/app.js";
import { pool, closePool, runInTransaction } from "../../src/db/pool.js";
import { createDefaultRoles, findOwnerRoleId } from "../../src/modules/rbac/repository.js";
import { adjustStock } from "../../src/modules/inventory/service.js";
import { signAccessToken } from "../../src/utils/token.js";
import { requireDatabase, testPhone, cleanupTestData } from "./helpers.js";

async function fixture() {
  const f = await runInTransaction(async (conn) => {
    const [b] = await conn.query(
      `INSERT INTO businesses (name, business_type, phone, status) VALUES (?, 'warehouse', ?, 'active')`,
      [`Rep ${Date.now()}-${Math.random().toString(36).slice(2, 6)}`, testPhone()]
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
      `INSERT INTO products (business_id, name, sku, purchase_cost, selling_price, reorder_level, status)
       VALUES (?, 'Widget', ?, 4, 10, 3, 'active')`,
      [businessId, `REP-${Date.now()}-${Math.random().toString(36).slice(2, 6)}`]
    );
    const [c] = await conn.query(
      `INSERT INTO customers (business_id, name, phone, status) VALUES (?, 'Buyer', ?, 'active')`,
      [businessId, testPhone()]
    );
    const [s] = await conn.query(
      `INSERT INTO suppliers (business_id, name, phone, status) VALUES (?, 'Seller', ?, 'active')`,
      [businessId, testPhone()]
    );
    return {
      businessId,
      userId: u.insertId,
      warehouseId: w.insertId,
      productId: p.insertId,
      customerId: c.insertId,
      supplierId: s.insertId,
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
    "notifications",
    "payments",
    "return_items",
    "returns",
    "order_edits",
    "order_items",
    "orders",
    "purchase_items",
    "purchases",
    "stock_transfer_items",
    "stock_transfers",
    "production_items",
    "production_orders",
    "bill_of_materials",
    "inventory_movements",
    "inventory",
    "product_variants",
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

const stock = (f, delta) =>
  adjustStock({
    businessId: f.businessId,
    userId: f.userId,
    productId: f.productId,
    warehouseId: f.warehouseId,
    delta,
    movementType: delta > 0 ? "manual_increase" : "manual_decrease",
  });

const sell = (f, { quantity = 2, unitPrice = 10, status = "confirmed" } = {}) =>
  auth(request(app).post("/api/orders"), f.token).send({
    orderType: "standard",
    customerId: f.customerId,
    status,
    items: [{ productId: f.productId, quantity, unitPrice }],
  });

const buy = (f, { quantity = 10, unitCost = 4, status = "completed" } = {}) =>
  auth(request(app).post("/api/purchases"), f.token).send({
    supplierId: f.supplierId,
    items: [{ productId: f.productId, quantity, unitCost }],
    status,
  });

// ---- §25: what the reports say ------------------------------------------

test("§25: the index says which reports exist and which this user may open", async (t) => {
  if (!(await requireDatabase(t))) return;
  const f = await fixture();
  t.after(() => cleanup(f.businessId));

  const res = await auth(request(app).get("/api/reports"), f.token).send();
  assert.equal(res.status, 200, JSON.stringify(res.body));
  assert.ok(res.body.data.length >= 10);

  const inventory = res.body.data.find((r) => r.key === "inventory");
  assert.equal(inventory.financial, false);
  assert.equal(inventory.available, true);

  const sales = res.body.data.find((r) => r.key === "sales");
  assert.equal(sales.financial, true);
  // The owner holds financial.view, so it is available to them.
  assert.equal(sales.available, true);
  assert.equal(sales.path, "/api/reports/sales");
});

test("§25: the stock report values what is on hand at what it cost", async (t) => {
  if (!(await requireDatabase(t))) return;
  const f = await fixture();
  t.after(() => cleanup(f.businessId));
  await stock(f, 25);

  const res = await auth(request(app).get("/api/reports/inventory"), f.token).send();
  assert.equal(res.status, 200, JSON.stringify(res.body));

  const row = res.body.data.rows.find((r) => r.productId === f.productId);
  assert.equal(row.quantity, 25);
  assert.equal(row.purchaseCost, 4);
  // 25 at cost 4 = 100. Cost, not the 250 it might sell for — an unsold item
  // has not earned its margin.
  assert.equal(row.stockValue, 100);
  assert.equal(res.body.data.totals.quantity, 25);
  assert.equal(res.body.data.totals.stockValue, 100);
});

test("§25: a draft order is not revenue, and a cancelled one never happened", async (t) => {
  if (!(await requireDatabase(t))) return;
  const f = await fixture();
  t.after(() => cleanup(f.businessId));
  await stock(f, 100);

  // 2 × 10 = 20, counted.
  const counted = await sell(f, { quantity: 2, unitPrice: 10 });
  assert.equal(counted.status, 201, JSON.stringify(counted.body));

  // A draft: a conversation, not a sale.
  await sell(f, { quantity: 5, unitPrice: 10, status: "draft" });

  // Confirmed and then cancelled: it never happened.
  const cancelled = await sell(f, { quantity: 3, unitPrice: 10 });
  await auth(request(app).patch(`/api/orders/${cancelled.body.data.id}/status`), f.token).send({
    status: "cancelled",
    reason: "Customer changed their mind",
  });

  const res = await auth(request(app).get("/api/reports/sales"), f.token).send();
  assert.equal(res.status, 200, JSON.stringify(res.body));
  assert.equal(res.body.data.totals.orders, 1, "only the confirmed order counts");
  assert.equal(res.body.data.totals.total, 20);
  assert.equal(res.body.data.totals.outstanding, 20, "nothing paid yet");
});

test("§25: sales, purchases and profit agree with the documents", async (t) => {
  if (!(await requireDatabase(t))) return;
  const f = await fixture();
  t.after(() => cleanup(f.businessId));
  await stock(f, 100);

  await sell(f, { quantity: 5, unitPrice: 10 }); // revenue 50
  const purchase = await buy(f, { quantity: 10, unitCost: 4 }); // cost 40
  assert.equal(purchase.status, 201, JSON.stringify(purchase.body));

  const sales = await auth(request(app).get("/api/reports/sales"), f.token).send();
  assert.equal(sales.body.data.totals.total, 50);

  const purchases = await auth(request(app).get("/api/reports/purchases"), f.token).send();
  assert.equal(purchases.body.data.totals.total, 40);

  const profit = await auth(request(app).get("/api/reports/profit"), f.token).send();
  assert.equal(profit.status, 200, JSON.stringify(profit.body));
  assert.equal(profit.body.data.totals.revenue, 50);
  assert.equal(profit.body.data.totals.cost, 40);
  assert.equal(profit.body.data.totals.profit, 10);
  // The report must say what kind of profit figure it is, so a screen cannot
  // present a cash-basis number as cost-of-goods-sold.
  assert.equal(profit.body.data.basis, "cash");
  assert.match(profit.body.data.basisNote, /not cost-of-goods-sold/i);
});

test("§25: the product, customer and outstanding reports add up", async (t) => {
  if (!(await requireDatabase(t))) return;
  const f = await fixture();
  t.after(() => cleanup(f.businessId));
  await stock(f, 100);

  const order = await sell(f, { quantity: 4, unitPrice: 25 }); // 100
  await auth(request(app).post(`/api/orders/${order.body.data.id}/payments`), f.token).send({
    amount: 30,
    method: "cash",
  });

  const products = await auth(request(app).get("/api/reports/products"), f.token).send();
  const line = products.body.data.rows.find((r) => r.productId === f.productId);
  assert.equal(line.quantitySold, 4);
  assert.equal(line.revenue, 100);
  assert.equal(line.orders, 1);

  const customers = await auth(request(app).get("/api/reports/customers"), f.token).send();
  const customer = customers.body.data.rows.find((r) => r.customerId === f.customerId);
  assert.equal(customer.orders, 1);
  assert.equal(customer.total, 100);
  assert.equal(customer.paid, 30);
  assert.equal(customer.outstanding, 70);

  const outstanding = await auth(request(app).get("/api/reports/outstanding"), f.token).send();
  assert.equal(outstanding.body.data.totals.receivable, 70, "what the customer still owes");
  assert.equal(outstanding.body.data.totals.payable, 0, "nothing owed to suppliers yet");
  assert.equal(outstanding.body.data.receivable[0].orderNumber, order.body.data.orderNumber);

  // And a purchase with an unpaid balance shows on the other side.
  await buy(f, { quantity: 5, unitCost: 4 });
  const both = await auth(request(app).get("/api/reports/outstanding"), f.token).send();
  assert.equal(both.body.data.totals.payable, 20);
});

test("§25: a date range applies to the document's own date", async (t) => {
  if (!(await requireDatabase(t))) return;
  const f = await fixture();
  t.after(() => cleanup(f.businessId));
  await stock(f, 100);

  const sold = await sell(f, { quantity: 1, unitPrice: 10 });
  // Backdate the ORDER, leaving created_at as today: a business entering last
  // month's paperwork means it to count as last month.
  await pool.query(`UPDATE orders SET order_date = '2026-01-15 10:00:00' WHERE id = ?`, [
    sold.body.data.id,
  ]);

  const january = await auth(
    request(app).get("/api/reports/sales?from=2026-01-01&to=2026-01-31"),
    f.token
  ).send();
  assert.equal(january.body.data.totals.orders, 1);
  assert.equal(january.body.data.rows[0].period, "2026-01");

  const february = await auth(
    request(app).get("/api/reports/sales?from=2026-02-01&to=2026-02-28"),
    f.token
  ).send();
  assert.equal(february.body.data.totals.orders, 0, "not in this range");

  const backwards = await auth(
    request(app).get("/api/reports/sales?from=2026-03-01&to=2026-01-01"),
    f.token
  ).send();
  assert.equal(backwards.status, 422, "a range that ends before it starts is a mistake");
});

test("§25: the operational reports report what happened", async (t) => {
  if (!(await requireDatabase(t))) return;
  const f = await fixture();
  t.after(() => cleanup(f.businessId));
  await stock(f, 50);

  const movements = await auth(request(app).get("/api/reports/stock-movements"), f.token).send();
  assert.equal(movements.status, 200);
  const increase = movements.body.data.rows.find((r) => r.movementType === "manual_increase");
  assert.equal(increase.movements, 1);
  assert.equal(increase.totalQuantity, 50);

  // A return, so the returns report has something to say.
  const order = await sell(f, { quantity: 2, unitPrice: 10 });
  const detail = await auth(request(app).get(`/api/orders/${order.body.data.id}`), f.token).send();
  await auth(request(app).post("/api/returns"), f.token).send({
    orderId: order.body.data.id,
    reason: "Wrong size",
    items: [{ orderItemId: detail.body.data.items[0].id, quantity: 1 }],
  });

  const returns = await auth(request(app).get("/api/reports/returns"), f.token).send();
  const requested = returns.body.data.rows.find((r) => r.status === "requested");
  assert.equal(requested.returns, 1);
  assert.equal(requested.quantity, 1);

  for (const key of ["transfers", "production"]) {
    const res = await auth(request(app).get(`/api/reports/${key}`), f.token).send();
    assert.equal(res.status, 200, `${key} should answer even with nothing to report`);
    assert.deepEqual(res.body.data.rows, [], "and say so with an empty list, not an error");
  }
});

test("§24: a report of money needs financial.view, and says so up front", async (t) => {
  if (!(await requireDatabase(t))) return;
  const f = await fixture();
  t.after(() => cleanup(f.businessId));

  // §23's Manager reads reports but holds no financial visibility — which is
  // precisely the case this rule exists for. (A Warehouse Manager holds no
  // `reports.view` at all, so it would prove the wrong thing.)
  const [[role]] = await pool.query(`SELECT id FROM roles WHERE business_id = ? AND name = 'Manager'`, [
    f.businessId,
  ]);
  const phone = testPhone();
  const staff = await auth(request(app).post("/api/users"), f.token).send({
    name: "Ops Manager",
    phone,
    roleId: role.id,
  });
  const login = await request(app)
    .post("/api/auth/login")
    .send({ phone, password: staff.body.data.temporaryPassword });
  const theirToken = login.body.data.accessToken;

  // Operational reports: theirs to read.
  assert.equal((await auth(request(app).get("/api/reports/inventory"), theirToken).send()).status, 200);
  assert.equal(
    (await auth(request(app).get("/api/reports/stock-movements"), theirToken).send()).status,
    200
  );

  // Financial ones: refused outright rather than returned with blanks, which
  // would leave a reader unsure whether zero meant zero.
  for (const key of ["sales", "purchases", "profit", "customers", "outstanding", "products"]) {
    const res = await auth(request(app).get(`/api/reports/${key}`), theirToken).send();
    assert.equal(res.status, 403, `${key} shows money and must be refused`);
  }

  // And the index tells them in advance, so nothing appears that then 403s.
  const index = await auth(request(app).get("/api/reports"), theirToken).send();
  assert.equal(index.body.data.find((r) => r.key === "sales").available, false);
  assert.equal(index.body.data.find((r) => r.key === "inventory").available, true);
});

test("§36: reports never cross a tenant boundary", async (t) => {
  if (!(await requireDatabase(t))) return;
  const a = await fixture();
  const b = await fixture();
  t.after(() => Promise.all([cleanup(a.businessId), cleanup(b.businessId)]));

  await stock(a, 50);
  await sell(a, { quantity: 5, unitPrice: 10 });

  const mine = await auth(request(app).get("/api/reports/sales"), b.token).send();
  assert.equal(mine.body.data.totals.total, 0, "one business's sales are not another's");

  const stockReport = await auth(request(app).get("/api/reports/inventory"), b.token).send();
  assert.equal(
    stockReport.body.data.rows.some((r) => r.productId === a.productId),
    false
  );
});

// ---- §31: notifications --------------------------------------------------

async function waitForNotifications(f, count, type = null) {
  for (let i = 0; i < 60; i += 1) {
    const [rows] = await pool.query(
      `SELECT notification_type, title, body, reference_type, reference_id, read_at
         FROM notifications WHERE business_id = ? ${type ? "AND notification_type = ?" : ""} ORDER BY id`,
      type ? [f.businessId, type] : [f.businessId]
    );
    if (rows.length >= count) return rows;
    await new Promise((resolve) => setTimeout(resolve, 20));
  }
  const [rows] = await pool.query(`SELECT * FROM notifications WHERE business_id = ? ORDER BY id`, [
    f.businessId,
  ]);
  return rows;
}

test("§44: stock crossing its threshold raises a notification", async (t) => {
  if (!(await requireDatabase(t))) return;
  const f = await fixture();
  t.after(() => cleanup(f.businessId));

  // The product's reorder level is 3. Ten in stock is not low.
  await stock(f, 10);
  const [quiet] = await pool.query(
    `SELECT COUNT(*) AS n FROM notifications WHERE business_id = ? AND notification_type = 'low_stock'`,
    [f.businessId]
  );
  assert.equal(Number(quiet[0].n), 0, "a healthy level is not news");

  // Down to 3: at the threshold.
  await stock(f, -7);
  const low = await waitForNotifications(f, 1, "low_stock");
  assert.equal(low.length, 1, "crossing the threshold is news");
  assert.match(low[0].title, /Low stock: Widget/);
  assert.match(low[0].body, /threshold of 3/);
  assert.equal(low[0].reference_type, "products");
  assert.equal(Number(low[0].reference_id), f.productId);

  // Down further, still low: one unread alert, not one per pick.
  await stock(f, -1);
  await stock(f, -1);
  const [after_] = await pool.query(
    `SELECT COUNT(*) AS n FROM notifications WHERE business_id = ? AND notification_type = 'low_stock' AND read_at IS NULL`,
    [f.businessId]
  );
  assert.equal(Number(after_[0].n), 1, "an afternoon of picking must not bury the list");
});

test("§44: running out raises its own, more urgent notification", async (t) => {
  if (!(await requireDatabase(t))) return;
  const f = await fixture();
  t.after(() => cleanup(f.businessId));

  await stock(f, 5);
  await stock(f, -5);

  const out = await waitForNotifications(f, 1, "out_of_stock");
  assert.equal(out.length, 1);
  assert.match(out[0].title, /Out of stock: Widget/);
  assert.match(out[0].body, /has run out/);
});

test("§31: an order, a return and a production run each announce themselves", async (t) => {
  if (!(await requireDatabase(t))) return;
  const f = await fixture();
  t.after(() => cleanup(f.businessId));
  await stock(f, 100);

  const order = await sell(f, { quantity: 2, unitPrice: 10 });
  const newOrder = await waitForNotifications(f, 1, "new_order");
  assert.equal(newOrder.length, 1);
  assert.match(newOrder[0].title, new RegExp(`New order ${order.body.data.orderNumber}`));
  assert.match(newOrder[0].body, /Buyer/, "and says who it is for");

  const detail = await auth(request(app).get(`/api/orders/${order.body.data.id}`), f.token).send();
  await auth(request(app).post("/api/returns"), f.token).send({
    orderId: order.body.data.id,
    reason: "Damaged in transit",
    items: [{ orderItemId: detail.body.data.items[0].id, quantity: 1 }],
  });
  const returned = await waitForNotifications(f, 1, "return_request");
  assert.equal(returned.length, 1);
  assert.match(returned[0].body, /Damaged in transit/, "the reason is what a decision needs");

  // A production run, completed.
  const material = await auth(request(app).post("/api/products"), f.token).send({
    name: "Raw",
    sku: `RAW-${Math.random().toString(36).slice(2, 7)}`,
    purchaseCost: 1,
  });
  await adjustStock({
    businessId: f.businessId,
    userId: f.userId,
    productId: material.body.data.id,
    warehouseId: f.warehouseId,
    delta: 100,
    movementType: "manual_increase",
  });
  await auth(request(app).put(`/api/products/${f.productId}/bom`), f.token).send({
    lines: [{ materialProductId: material.body.data.id, quantityPerUnit: 2 }],
  });
  const run = await auth(request(app).post("/api/production-orders"), f.token).send({
    productId: f.productId,
    quantityPlanned: 3,
  });
  await auth(request(app).patch(`/api/production-orders/${run.body.data.id}/status`), f.token).send({
    status: "completed",
  });

  const produced = await waitForNotifications(f, 1, "production_completed");
  assert.equal(produced.length, 1);
  assert.match(produced[0].body, /3 × Widget are ready/);
});

test("§11: an arriving transfer tells the destination", async (t) => {
  if (!(await requireDatabase(t))) return;
  const f = await fixture();
  t.after(() => cleanup(f.businessId));
  await stock(f, 50);

  const [south] = await pool.query(
    `INSERT INTO warehouses (business_id, name, location_type, is_default, status)
     VALUES (?, 'South', 'warehouse', FALSE, 'active')`,
    [f.businessId]
  );

  await auth(request(app).post("/api/stock-transfers"), f.token).send({
    fromWarehouseId: f.warehouseId,
    toWarehouseId: south.insertId,
    items: [{ productId: f.productId, quantity: 5 }],
    status: "completed",
  });

  const arrived = await waitForNotifications(f, 1, "transfer_received");
  assert.equal(arrived.length, 1);
  assert.match(arrived[0].body, /Received at South/);
});

test("§31: notifications can be listed, counted and marked read", async (t) => {
  if (!(await requireDatabase(t))) return;
  const f = await fixture();
  t.after(() => cleanup(f.businessId));
  await stock(f, 100);
  await sell(f, { quantity: 1, unitPrice: 10 });
  await waitForNotifications(f, 1, "new_order");

  const list = await auth(request(app).get("/api/notifications"), f.token).send();
  assert.equal(list.status, 200, JSON.stringify(list.body));
  assert.ok(list.body.data.length >= 1);
  assert.equal(list.body.data[0].isRead, false);
  assert.ok(Number.isInteger(list.body.meta.pagination.total));

  const count = await auth(request(app).get("/api/notifications/unread-count"), f.token).send();
  assert.equal(count.status, 200);
  assert.ok(count.body.data.unread >= 1);

  const id = list.body.data[0].id;
  const read = await auth(request(app).patch(`/api/notifications/${id}/read`), f.token).send();
  assert.equal(read.status, 200, JSON.stringify(read.body));
  assert.equal(read.body.data.isRead, true);

  // Reading it twice is not an error: the caller wanted it read, and it is.
  assert.equal((await auth(request(app).patch(`/api/notifications/${id}/read`), f.token).send()).status, 200);

  const unread = await auth(request(app).get("/api/notifications?unread=true"), f.token).send();
  assert.equal(
    unread.body.data.some((n) => n.id === id),
    false,
    "a read notification is not unread"
  );

  const all = await auth(request(app).patch("/api/notifications/read-all"), f.token).send();
  assert.equal(all.status, 200);
  const after_ = await auth(request(app).get("/api/notifications/unread-count"), f.token).send();
  assert.equal(after_.body.data.unread, 0);
});

test("§31: notifications cannot be posted by a client, and never cross tenants", async (t) => {
  if (!(await requireDatabase(t))) return;
  const a = await fixture();
  const b = await fixture();
  t.after(() => Promise.all([cleanup(a.businessId), cleanup(b.businessId)]));
  await stock(a, 100);
  await sell(a, { quantity: 1, unitPrice: 10 });
  const raised = await waitForNotifications(a, 1, "new_order");
  assert.equal(raised.length, 1);

  // Raised by events, never posted — there is no write endpoint at all.
  assert.equal(
    (await auth(request(app).post("/api/notifications"), a.token).send({
      type: "system_alert",
      title: "Fake",
      body: "Injected",
    })).status,
    404
  );

  const other = await auth(request(app).get("/api/notifications"), b.token).send();
  assert.equal(other.body.data.length, 0, "§36: one business's events are not another's");

  const [[mine]] = await pool.query(`SELECT id FROM notifications WHERE business_id = ? LIMIT 1`, [
    a.businessId,
  ]);
  assert.equal(
    (await auth(request(app).patch(`/api/notifications/${mine.id}/read`), b.token).send()).status,
    404,
    "nor can it mark them read"
  );
});

after(() => closePool());
