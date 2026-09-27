// §20 (purchases from suppliers), §25's purchase cost, §43's supplier payment.
//
// A purchase is the mirror of an order, so these prove the places the mirror
// can crack: goods counted as stock before they arrive, a completion that
// receives them twice, a cancellation that cannot find them because the
// receiving clerk put them on a shelf, and a payment that drifts from the
// payments table.

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
      [`Pur ${Date.now()}-${Math.random().toString(36).slice(2, 6)}`, testPhone()]
    );
    const businessId = b.insertId;
    await createDefaultRoles(conn, businessId);
    const roleId = await findOwnerRoleId(conn, businessId);

    const [u] = await conn.query(
      `INSERT INTO users (business_id, name, phone, password_hash, is_owner, role_id, status)
       VALUES (?, 'Buyer', ?, 'x', TRUE, ?, 'active')`,
      [businessId, testPhone(), roleId]
    );
    const [w] = await conn.query(
      `INSERT INTO warehouses (business_id, name, location_type, is_default, status)
       VALUES (?, 'Main', 'warehouse', TRUE, 'active')`,
      [businessId]
    );
    const [l] = await conn.query(
      `INSERT INTO storage_locations (business_id, warehouse_id, name, status)
       VALUES (?, ?, 'A-1', 'active')`,
      [businessId, w.insertId]
    );
    const [p] = await conn.query(
      `INSERT INTO products (business_id, name, sku, purchase_cost, selling_price, status)
       VALUES (?, 'Timber', ?, 8, 20, 'active')`,
      [businessId, `PUR-${Date.now()}-${Math.random().toString(36).slice(2, 6)}`]
    );
    const [s] = await conn.query(
      `INSERT INTO suppliers (business_id, name, phone, status) VALUES (?, 'Timber Co', ?, 'active')`,
      [businessId, testPhone()]
    );
    return {
      businessId,
      userId: u.insertId,
      warehouseId: w.insertId,
      locationId: l.insertId,
      productId: p.insertId,
      supplierId: s.insertId,
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
  for (const sql of [
    `DELETE FROM payments WHERE business_id = ?`,
    `DELETE FROM purchase_items WHERE business_id = ?`,
    `DELETE FROM purchases WHERE business_id = ?`,
    `DELETE FROM order_edits WHERE business_id = ?`,
    `DELETE FROM order_items WHERE business_id = ?`,
    `DELETE FROM orders WHERE business_id = ?`,
    `DELETE FROM inventory_movements WHERE business_id = ?`,
    `DELETE FROM inventory WHERE business_id = ?`,
    `DELETE FROM document_sequences WHERE business_id = ?`,
    `DELETE FROM audit_logs WHERE business_id = ?`,
    `DELETE FROM suppliers WHERE business_id = ?`,
    `DELETE FROM products WHERE business_id = ?`,
    `DELETE FROM storage_locations WHERE business_id = ?`,
    `DELETE FROM warehouses WHERE business_id = ?`,
  ]) {
    await pool.query(sql, [businessId]);
  }
  const [users] = await pool.query(`SELECT id FROM users WHERE business_id = ?`, [businessId]);
  await cleanupTestData({ businessIds: [businessId], userIds: users.map((u) => u.id) });
}

const auth = (req, token) => req.set("Authorization", `Bearer ${token}`);

const stockOf = async (businessId, productId) =>
  Number(
    (
      await pool.query(
        `SELECT COALESCE(SUM(quantity),0) AS q FROM inventory WHERE business_id=? AND product_id=?`,
        [businessId, productId]
      )
    )[0][0].q
  );

const slotsOf = async (businessId, productId) => {
  const [rows] = await pool.query(
    `SELECT warehouse_id, location_id, quantity FROM inventory
      WHERE business_id = ? AND product_id = ? ORDER BY id`,
    [businessId, productId]
  );
  return rows.map((r) => ({
    warehouseId: r.warehouse_id,
    locationId: r.location_id,
    quantity: Number(r.quantity),
  }));
};

const newPurchase = (f, body = {}) =>
  auth(request(app).post("/api/purchases"), f.token).send({
    supplierId: f.supplierId,
    items: [{ productId: f.productId, quantity: 100, unitCost: 8 }],
    ...body,
  });

// ---- the document -------------------------------------------------------

test("§20: a purchase is recorded with server-computed totals and a document number", async (t) => {
  if (!(await requireDatabase(t))) return;
  const f = await fixture();
  t.after(() => cleanup(f.businessId));

  const res = await newPurchase(f, {
    items: [
      { productId: f.productId, quantity: 100, unitCost: 8, discountAmount: 50, taxAmount: 30 },
    ],
    extraCharges: 20,
    note: "First delivery",
  });

  assert.equal(res.status, 201, JSON.stringify(res.body));
  const purchase = res.body.data;
  // 100 x 8 = 800, less 50 = 750, plus 30 tax = 780, plus 20 carriage = 800.
  assert.equal(purchase.subtotal, 750);
  assert.equal(purchase.taxAmount, 30);
  assert.equal(purchase.total, 800);
  assert.equal(purchase.remainingAmount, 800, "nothing paid yet");
  assert.equal(purchase.paymentStatus, "unpaid");
  assert.match(purchase.purchaseNumber, /^PUR-/, "§29's numbering, with the purchase prefix");
  assert.equal(purchase.items.length, 1);
  assert.equal(purchase.items[0].lineTotal, 780);
  assert.equal(purchase.supplierName, "Timber Co");
});

test("§20: a totals figure sent by the client is ignored, not trusted", async (t) => {
  if (!(await requireDatabase(t))) return;
  const f = await fixture();
  t.after(() => cleanup(f.businessId));

  const res = await newPurchase(f, {
    items: [{ productId: f.productId, quantity: 10, unitCost: 5 }],
    total: 1,
    subtotal: 1,
  });

  assert.equal(res.status, 201);
  assert.equal(res.body.data.total, 50, "the server's own arithmetic wins");
});

test("§55: a purchase line keeps the product name it was bought under", async (t) => {
  if (!(await requireDatabase(t))) return;
  const f = await fixture();
  t.after(() => cleanup(f.businessId));

  const created = await newPurchase(f);
  const purchaseId = created.body.data.id;
  assert.equal(created.body.data.items[0].productName, "Timber");

  await pool.query(`UPDATE products SET name = 'Renamed Timber' WHERE id = ?`, [f.productId]);

  const again = await auth(request(app).get(`/api/purchases/${purchaseId}`), f.token).send();
  assert.equal(again.body.data.items[0].productName, "Timber", "a rename must not rewrite history");
});

test("a purchase needs at least one line, and a line needs a real product", async (t) => {
  if (!(await requireDatabase(t))) return;
  const f = await fixture();
  t.after(() => cleanup(f.businessId));

  assert.equal((await newPurchase(f, { items: [] })).status, 422);
  assert.equal(
    (await newPurchase(f, { items: [{ productId: 99999999, quantity: 1, unitCost: 1 }] })).status,
    422
  );
  assert.equal(
    (await newPurchase(f, { items: [{ productId: f.productId, quantity: 0, unitCost: 1 }] })).status,
    422
  );
  assert.equal((await newPurchase(f, { supplierId: 99999999 })).status, 422);

  const [[left]] = await pool.query(`SELECT COUNT(*) AS n FROM purchases WHERE business_id = ?`, [
    f.businessId,
  ]);
  assert.equal(Number(left.n), 0, "a refused purchase leaves nothing behind");
});

// ---- stock -------------------------------------------------------------

test("§20: a pending purchase is not stock; completing it is", async (t) => {
  if (!(await requireDatabase(t))) return;
  const f = await fixture();
  t.after(() => cleanup(f.businessId));

  const created = await newPurchase(f);
  assert.equal(created.body.data.status, "pending", "§20's flow: recorded first, received later");
  assert.equal(await stockOf(f.businessId, f.productId), 0, "goods on a lorry are not stock");

  const completed = await auth(
    request(app).patch(`/api/purchases/${created.body.data.id}/status`),
    f.token
  ).send({ status: "completed" });

  assert.equal(completed.status, 200, JSON.stringify(completed.body));
  assert.equal(await stockOf(f.businessId, f.productId), 100);
  assert.ok(completed.body.data.completedAt, "and the arrival is dated");

  const [[movement]] = await pool.query(
    `SELECT movement_type, quantity, reference_type, reference_number, user_id
       FROM inventory_movements WHERE business_id = ? ORDER BY id DESC LIMIT 1`,
    [f.businessId]
  );
  assert.equal(movement.movement_type, "purchase", "§12: the ledger says why the stock moved");
  assert.equal(Number(movement.quantity), 100);
  assert.equal(movement.reference_type, "purchase");
  assert.equal(movement.reference_number, created.body.data.purchaseNumber);
  assert.equal(movement.user_id, f.userId);
});

test("§20: a purchase entered as already received receives its stock once", async (t) => {
  if (!(await requireDatabase(t))) return;
  const f = await fixture();
  t.after(() => cleanup(f.businessId));

  const created = await newPurchase(f, { status: "completed" });
  assert.equal(created.status, 201);
  assert.equal(await stockOf(f.businessId, f.productId), 100);

  const [[movements]] = await pool.query(
    `SELECT COUNT(*) AS n FROM inventory_movements WHERE business_id = ?`,
    [f.businessId]
  );
  assert.equal(Number(movements.n), 1, "exactly one receipt, not one per read");
});

test("completing a purchase twice does not receive the goods twice", async (t) => {
  if (!(await requireDatabase(t))) return;
  const f = await fixture();
  t.after(() => cleanup(f.businessId));

  const created = await newPurchase(f);
  const complete = () =>
    auth(request(app).patch(`/api/purchases/${created.body.data.id}/status`), f.token).send({
      status: "completed",
    });

  assert.equal((await complete()).status, 200);
  const second = await complete();
  assert.ok(second.status >= 400, `the second completion must be refused, got ${second.status}`);
  assert.equal(await stockOf(f.businessId, f.productId), 100, "and the stock is received once");
});

test("two simultaneous completions receive the delivery once", async (t) => {
  if (!(await requireDatabase(t))) return;
  const f = await fixture();
  t.after(() => cleanup(f.businessId));

  const created = await newPurchase(f);
  const complete = () =>
    auth(request(app).patch(`/api/purchases/${created.body.data.id}/status`), f.token).send({
      status: "completed",
    });

  const [a, b] = await Promise.all([complete(), complete()]);
  const statuses = [a.status, b.status].sort();
  assert.equal(statuses[0], 200, "one completion should succeed");
  assert.ok(statuses[1] >= 400, `the other must not, got ${statuses[1]}`);
  assert.equal(await stockOf(f.businessId, f.productId), 100, "100 received, once");

  const [[movements]] = await pool.query(
    `SELECT COUNT(*) AS n FROM inventory_movements WHERE business_id = ?`,
    [f.businessId]
  );
  assert.equal(Number(movements.n), 1, "exactly one ledger entry for the delivery");
});

test("cancelling a completed purchase sends the goods back out", async (t) => {
  if (!(await requireDatabase(t))) return;
  const f = await fixture();
  t.after(() => cleanup(f.businessId));

  const created = await newPurchase(f, { status: "completed" });
  assert.equal(await stockOf(f.businessId, f.productId), 100);

  const cancelled = await auth(
    request(app).patch(`/api/purchases/${created.body.data.id}/status`),
    f.token
  ).send({ status: "cancelled" });

  assert.equal(cancelled.status, 200, JSON.stringify(cancelled.body));
  assert.equal(await stockOf(f.businessId, f.productId), 0, "goods that were refused are not stock");
});

test("cancelling a purchase whose goods were shelved still finds them (§11)", async (t) => {
  if (!(await requireDatabase(t))) return;
  const f = await fixture();
  t.after(() => cleanup(f.businessId));

  const created = await newPurchase(f, { status: "completed" });

  // The receiving clerk puts the delivery away on A-1, which is what a
  // warehouse does with a delivery. Taking it back out of the location-less
  // slot it arrived in would find nothing there.
  await auth(request(app).post("/api/inventory/transfer"), f.token).send({
    productId: f.productId,
    fromWarehouseId: f.warehouseId,
    toWarehouseId: f.warehouseId,
    toLocationId: f.locationId,
    quantity: 100,
  });
  assert.deepEqual(await slotsOf(f.businessId, f.productId), [
    { warehouseId: f.warehouseId, locationId: null, quantity: 0 },
    { warehouseId: f.warehouseId, locationId: f.locationId, quantity: 100 },
  ]);

  const cancelled = await auth(
    request(app).patch(`/api/purchases/${created.body.data.id}/status`),
    f.token
  ).send({ status: "cancelled" });

  assert.equal(cancelled.status, 200, JSON.stringify(cancelled.body));
  assert.equal(await stockOf(f.businessId, f.productId), 0, "and they come off the shelf");
});

test("a purchase cannot be cancelled after its goods have been sold on", async (t) => {
  if (!(await requireDatabase(t))) return;
  const f = await fixture();
  t.after(() => cleanup(f.businessId));

  const created = await newPurchase(f, {
    items: [{ productId: f.productId, quantity: 10, unitCost: 8 }],
    status: "completed",
  });

  // All ten sold. There is nothing left to send back to the supplier, and
  // §47's default is to refuse rather than to invent negative stock.
  const order = await auth(request(app).post("/api/orders"), f.token).send({
    orderType: "quick_sale",
    status: "confirmed",
    items: [{ productId: f.productId, quantity: 10, unitPrice: 20 }],
  });
  assert.equal(order.status, 201, JSON.stringify(order.body));
  assert.equal(await stockOf(f.businessId, f.productId), 0);

  const cancelled = await auth(
    request(app).patch(`/api/purchases/${created.body.data.id}/status`),
    f.token
  ).send({ status: "cancelled" });

  assert.equal(cancelled.status, 409, JSON.stringify(cancelled.body));
  assert.match(cancelled.body.error.message, /Insufficient stock/);

  const [[still]] = await pool.query(`SELECT status FROM purchases WHERE id = ?`, [
    created.body.data.id,
  ]);
  assert.equal(still.status, "completed", "a refused cancellation changes nothing");
});

test("§20: an impossible transition is refused", async (t) => {
  if (!(await requireDatabase(t))) return;
  const f = await fixture();
  t.after(() => cleanup(f.businessId));

  const created = await newPurchase(f, { status: "completed" });
  const id = created.body.data.id;

  const back = await auth(request(app).patch(`/api/purchases/${id}/status`), f.token).send({
    status: "pending",
  });
  assert.equal(back.status, 409, "a received delivery cannot un-arrive");
  assert.equal(await stockOf(f.businessId, f.productId), 100, "and the stock is untouched");

  await auth(request(app).patch(`/api/purchases/${id}/status`), f.token).send({ status: "cancelled" });
  const revive = await auth(request(app).patch(`/api/purchases/${id}/status`), f.token).send({
    status: "completed",
  });
  assert.equal(revive.status, 409, "a cancelled purchase is terminal");
});

// ---- money -------------------------------------------------------------

test("§43: paying a supplier moves the balance and writes a payment row", async (t) => {
  if (!(await requireDatabase(t))) return;
  const f = await fixture();
  t.after(() => cleanup(f.businessId));

  const created = await newPurchase(f, {
    items: [{ productId: f.productId, quantity: 10, unitCost: 10 }],
    paidAmount: 40,
    paymentMethod: "bank_transfer",
  });
  assert.equal(created.status, 201, JSON.stringify(created.body));
  assert.equal(created.body.data.paidAmount, 40);
  assert.equal(created.body.data.remainingAmount, 60);
  assert.equal(created.body.data.paymentStatus, "partially_paid");

  const id = created.body.data.id;
  const rest = await auth(request(app).post(`/api/purchases/${id}/payments`), f.token).send({
    amount: 60,
    method: "cash",
  });
  assert.equal(rest.status, 201, JSON.stringify(rest.body));
  assert.equal(rest.body.data.remainingAmount, 0);

  const detail = await auth(request(app).get(`/api/purchases/${id}`), f.token).send();
  assert.equal(detail.body.data.paymentStatus, "paid");

  // The stored figure must agree with the payments table, or the supplier
  // balance in one screen disagrees with the other.
  const [[sum]] = await pool.query(
    `SELECT COALESCE(SUM(CASE WHEN direction='outgoing' THEN amount ELSE -amount END),0) AS paid
       FROM payments WHERE business_id = ? AND purchase_id = ?`,
    [f.businessId, id]
  );
  assert.equal(Number(sum.paid), 100);
  assert.equal(detail.body.data.paidAmount, 100);
  assert.equal(detail.body.data.payments.length, 2, "§43: both payments are on the record");
  assert.equal(detail.body.data.payments[0].method, "cash");
});

test("a payment cannot exceed what is still owed, at creation or after", async (t) => {
  if (!(await requireDatabase(t))) return;
  const f = await fixture();
  t.after(() => cleanup(f.businessId));

  const tooMuchUpFront = await newPurchase(f, {
    items: [{ productId: f.productId, quantity: 1, unitCost: 10 }],
    paidAmount: 500,
  });
  assert.equal(tooMuchUpFront.status, 422, JSON.stringify(tooMuchUpFront.body));

  const created = await newPurchase(f, { items: [{ productId: f.productId, quantity: 1, unitCost: 10 }] });
  const over = await auth(
    request(app).post(`/api/purchases/${created.body.data.id}/payments`),
    f.token
  ).send({ amount: 11, method: "cash" });
  assert.equal(over.status, 422, JSON.stringify(over.body));

  const [[rows]] = await pool.query(`SELECT COUNT(*) AS n FROM payments WHERE business_id = ?`, [
    f.businessId,
  ]);
  assert.equal(Number(rows.n), 0, "a refused payment is not recorded");
});

test("two simultaneous payments cannot both fit under the same balance", async (t) => {
  if (!(await requireDatabase(t))) return;
  const f = await fixture();
  t.after(() => cleanup(f.businessId));

  const created = await newPurchase(f, { items: [{ productId: f.productId, quantity: 1, unitCost: 100 }] });
  const pay = () =>
    auth(request(app).post(`/api/purchases/${created.body.data.id}/payments`), f.token).send({
      amount: 80,
      method: "cash",
    });

  const results = await Promise.all([pay(), pay()]);
  const accepted = results.filter((r) => r.status === 201);
  assert.equal(accepted.length, 1, "only one 80 fits under a 100 total");

  const detail = await auth(
    request(app).get(`/api/purchases/${created.body.data.id}`),
    f.token
  ).send();
  assert.equal(detail.body.data.paidAmount, 80);
});

test("a cancelled purchase cannot be paid", async (t) => {
  if (!(await requireDatabase(t))) return;
  const f = await fixture();
  t.after(() => cleanup(f.businessId));

  const created = await newPurchase(f);
  await auth(request(app).patch(`/api/purchases/${created.body.data.id}/status`), f.token).send({
    status: "cancelled",
  });

  const pay = await auth(
    request(app).post(`/api/purchases/${created.body.data.id}/payments`),
    f.token
  ).send({ amount: 10, method: "cash" });
  assert.equal(pay.status, 409, JSON.stringify(pay.body));
});

// ---- listing and tenancy -----------------------------------------------

test("purchases list, filter and search", async (t) => {
  if (!(await requireDatabase(t))) return;
  const f = await fixture();
  t.after(() => cleanup(f.businessId));

  await newPurchase(f);
  await newPurchase(f, { status: "completed" });

  const all = await auth(request(app).get("/api/purchases?page=1&pageSize=10"), f.token).send();
  assert.equal(all.status, 200);
  assert.equal(all.body.data.length, 2);
  assert.equal(all.body.meta.pagination.total, 2);

  const completed = await auth(request(app).get("/api/purchases?status=completed"), f.token).send();
  assert.equal(completed.body.data.length, 1);
  assert.equal(completed.body.data[0].status, "completed");

  const bySupplier = await auth(
    request(app).get(`/api/purchases?supplierId=${f.supplierId}`),
    f.token
  ).send();
  assert.equal(bySupplier.body.data.length, 2);

  const found = await auth(request(app).get("/api/purchases?search=Timber"), f.token).send();
  assert.equal(found.body.data.length, 2, "the supplier's name is searchable");

  const nonsense = await auth(request(app).get("/api/purchases?status=not-a-status"), f.token).send();
  assert.ok(nonsense.status === 200 || nonsense.status === 422, "and junk never 500s");
});

test("purchases are tenant-scoped — one business never sees another's", async (t) => {
  if (!(await requireDatabase(t))) return;
  const a = await fixture();
  const b = await fixture();
  t.after(() => Promise.all([cleanup(a.businessId), cleanup(b.businessId)]));

  const created = await newPurchase(a);
  const id = created.body.data.id;

  assert.equal((await auth(request(app).get(`/api/purchases/${id}`), b.token).send()).status, 404);
  assert.equal(
    (await auth(request(app).patch(`/api/purchases/${id}/status`), b.token).send({ status: "completed" }))
      .status,
    404
  );
  assert.equal(
    (await auth(request(app).post(`/api/purchases/${id}/payments`), b.token).send({ amount: 1, method: "cash" }))
      .status,
    404
  );
  const list = await auth(request(app).get("/api/purchases"), b.token).send();
  assert.equal(list.body.data.length, 0);

  // A line naming the other tenant's product is refused (§36).
  const crossed = await auth(request(app).post("/api/purchases"), b.token).send({
    items: [{ productId: a.productId, quantity: 1, unitCost: 1 }],
  });
  assert.equal(crossed.status, 422);
  assert.equal(await stockOf(a.businessId, a.productId), 0, "and moves nothing");
});

test("a purchase needs a default warehouse before it can be received", async (t) => {
  if (!(await requireDatabase(t))) return;
  const f = await fixture();
  t.after(() => cleanup(f.businessId));

  await pool.query(`UPDATE warehouses SET is_default = FALSE WHERE business_id = ?`, [f.businessId]);

  const res = await newPurchase(f, { status: "completed" });
  assert.equal(res.status, 422, JSON.stringify(res.body));
  assert.match(res.body.error.message, /default warehouse/i);

  const [[left]] = await pool.query(`SELECT COUNT(*) AS n FROM purchases WHERE business_id = ?`, [
    f.businessId,
  ]);
  assert.equal(Number(left.n), 0, "and the whole purchase rolls back");
});

test("§30: a purchase and its completion are both in the activity trail", async (t) => {
  if (!(await requireDatabase(t))) return;
  const f = await fixture();
  t.after(() => cleanup(f.businessId));

  const created = await newPurchase(f);
  await auth(request(app).patch(`/api/purchases/${created.body.data.id}/status`), f.token).send({
    status: "completed",
  });

  let actions = [];
  for (let i = 0; i < 60; i += 1) {
    const [rows] = await pool.query(
      `SELECT action, actor_id FROM audit_logs WHERE business_id = ? AND module = 'purchases' ORDER BY id`,
      [f.businessId]
    );
    actions = rows;
    if (rows.length >= 2) break;
    await new Promise((resolve) => setTimeout(resolve, 25));
  }

  const names = actions.map((a) => a.action);
  assert.ok(names.includes("purchases.create"), names.join(", "));
  assert.ok(names.includes("purchases.update"), names.join(", "));
  assert.ok(
    actions.every((a) => Number(a.actor_id) === f.userId),
    "the trail must name who received the delivery"
  );
});

test("an adjustment already on the shelf is untouched by a purchase's arrival", async (t) => {
  if (!(await requireDatabase(t))) return;
  const f = await fixture();
  t.after(() => cleanup(f.businessId));

  // Opening stock on A-1, then a delivery. The delivery lands in the
  // location-less slot; the shelf keeps what it had.
  await adjustStock({
    businessId: f.businessId,
    userId: f.userId,
    productId: f.productId,
    warehouseId: f.warehouseId,
    locationId: f.locationId,
    delta: 5,
    movementType: "manual_increase",
  });

  await newPurchase(f, { items: [{ productId: f.productId, quantity: 20, unitCost: 8 }], status: "completed" });

  const slots = await slotsOf(f.businessId, f.productId);
  const at = (locationId) => slots.find((s) => s.locationId === locationId)?.quantity;
  assert.equal(at(f.locationId), 5);
  assert.equal(at(null), 20);
  assert.equal(await stockOf(f.businessId, f.productId), 25);
});

after(() => closePool());
