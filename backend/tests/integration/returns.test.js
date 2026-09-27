// §16 (returns), and the approved policy §16 itself leaves open.
//
// The specification says only "inventory updates per the configured return
// process", so the project resolved it (docs/architecture.md's decision table)
// as TWO-STAGE and CONDITION-GATED: nothing moves on approval, sellable goods
// go back to the shelf they were sold from on completion, damaged goods never
// re-enter stock, and the refund is money leaving. Every one of those is a
// decision a future change could quietly reverse, so every one has a test.

import { test, after } from "node:test";
import assert from "node:assert/strict";
import request from "supertest";

import { app } from "../../src/app.js";
import { pool, closePool, runInTransaction } from "../../src/db/pool.js";
import { createDefaultRoles, findOwnerRoleId } from "../../src/modules/rbac/repository.js";
import { adjustStock } from "../../src/modules/inventory/service.js";
import { signAccessToken } from "../../src/utils/token.js";
import { requireDatabase, testPhone, cleanupTestData } from "./helpers.js";

async function fixture({ stock = 20, onShelf = false } = {}) {
  const f = await runInTransaction(async (conn) => {
    const [b] = await conn.query(
      `INSERT INTO businesses (name, business_type, phone, status) VALUES (?, 'warehouse', ?, 'active')`,
      [`Ret ${Date.now()}-${Math.random().toString(36).slice(2, 6)}`, testPhone()]
    );
    const businessId = b.insertId;
    await createDefaultRoles(conn, businessId);
    const roleId = await findOwnerRoleId(conn, businessId);

    const [u] = await conn.query(
      `INSERT INTO users (business_id, name, phone, password_hash, is_owner, role_id, status)
       VALUES (?, 'Clerk', ?, 'x', TRUE, ?, 'active')`,
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
      `INSERT INTO products (business_id, name, sku, selling_price, status)
       VALUES (?, 'Chair', ?, 100, 'active')`,
      [businessId, `RET-${Date.now()}-${Math.random().toString(36).slice(2, 6)}`]
    );
    const [c] = await conn.query(
      `INSERT INTO customers (business_id, name, phone, status) VALUES (?, 'Buyer', ?, 'active')`,
      [businessId, testPhone()]
    );
    return {
      businessId,
      userId: u.insertId,
      warehouseId: w.insertId,
      locationId: l.insertId,
      productId: p.insertId,
      customerId: c.insertId,
    };
  });

  if (stock > 0) {
    await adjustStock({
      businessId: f.businessId,
      userId: f.userId,
      productId: f.productId,
      warehouseId: f.warehouseId,
      locationId: onShelf ? f.locationId : null,
      delta: stock,
      movementType: "manual_increase",
    });
  }

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
    `DELETE FROM return_items WHERE business_id = ?`,
    `DELETE FROM returns WHERE business_id = ?`,
    `DELETE FROM payments WHERE business_id = ?`,
    `DELETE FROM order_edits WHERE business_id = ?`,
    `DELETE FROM order_items WHERE business_id = ?`,
    `DELETE FROM orders WHERE business_id = ?`,
    `DELETE FROM inventory_movements WHERE business_id = ?`,
    `DELETE FROM inventory WHERE business_id = ?`,
    `DELETE FROM document_sequences WHERE business_id = ?`,
    `DELETE FROM audit_logs WHERE business_id = ?`,
    `DELETE FROM customers WHERE business_id = ?`,
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
    `SELECT location_id, quantity FROM inventory WHERE business_id = ? AND product_id = ? ORDER BY id`,
    [businessId, productId]
  );
  return rows.map((r) => ({ locationId: r.location_id, quantity: Number(r.quantity) }));
};

/** A completed sale of `quantity`, fully paid, ready to be returned against. */
async function sell(f, { quantity = 4, unitPrice = 100, pay = true } = {}) {
  const order = await auth(request(app).post("/api/orders"), f.token).send({
    orderType: "standard",
    customerId: f.customerId,
    status: "confirmed",
    items: [{ productId: f.productId, quantity, unitPrice }],
  });
  assert.equal(order.status, 201, JSON.stringify(order.body));

  if (pay) {
    const paid = await auth(
      request(app).post(`/api/orders/${order.body.data.id}/payments`),
      f.token
    ).send({ amount: order.body.data.grandTotal, method: "cash" });
    assert.equal(paid.status, 201, JSON.stringify(paid.body));
  }

  const detail = await auth(request(app).get(`/api/orders/${order.body.data.id}`), f.token).send();
  return { id: order.body.data.id, order: detail.body.data, lineId: detail.body.data.items[0].id };
}

const raise = (f, sold, body = {}) =>
  auth(request(app).post("/api/returns"), f.token).send({
    orderId: sold.id,
    reason: "Wrong colour",
    items: [{ orderItemId: sold.lineId, quantity: 2 }],
    ...body,
  });

const setStatus = (f, returnId, status) =>
  auth(request(app).patch(`/api/returns/${returnId}/status`), f.token).send({ status });

// ---- raising a return ---------------------------------------------------

test("§16: a return is raised against an order's line, priced from what was paid", async (t) => {
  if (!(await requireDatabase(t))) return;
  const f = await fixture();
  t.after(() => cleanup(f.businessId));
  const sold = await sell(f, { quantity: 4, unitPrice: 100 });

  const res = await raise(f, sold);

  assert.equal(res.status, 201, JSON.stringify(res.body));
  const returned = res.body.data;
  assert.equal(returned.status, "requested", "§16's first stage is a request");
  assert.match(returned.returnNumber, /^RET-/, "§29's numbering, with the return prefix");
  assert.equal(returned.refundAmount, 200, "2 of 4 at 100 each");
  assert.equal(returned.orderNumber, sold.order.orderNumber);
  assert.equal(returned.items.length, 1);
  assert.equal(returned.items[0].condition, "sellable", "the default condition");
  assert.equal(returned.items[0].productName, "Chair", "§55: the name as it was sold");
  assert.equal(await stockOf(f.businessId, f.productId), 16, "a request moves no stock");
});

test("§16: a part-return of a discounted line refunds the discounted price", async (t) => {
  if (!(await requireDatabase(t))) return;
  const f = await fixture();
  t.after(() => cleanup(f.businessId));

  // 4 at 100, less a 100 line discount = 300 for the line, so 75 each.
  const order = await auth(request(app).post("/api/orders"), f.token).send({
    orderType: "standard",
    customerId: f.customerId,
    status: "confirmed",
    items: [{ productId: f.productId, quantity: 4, unitPrice: 100, discountAmount: 100 }],
  });
  const detail = await auth(request(app).get(`/api/orders/${order.body.data.id}`), f.token).send();
  const sold = { id: order.body.data.id, lineId: detail.body.data.items[0].id, order: detail.body.data };

  const res = await raise(f, sold, { items: [{ orderItemId: sold.lineId, quantity: 2 }] });
  assert.equal(res.status, 201, JSON.stringify(res.body));
  assert.equal(res.body.data.refundAmount, 150, "half the line's own total, not half the list price");
});

test("a refund larger than what was paid for those items is refused", async (t) => {
  if (!(await requireDatabase(t))) return;
  const f = await fixture();
  t.after(() => cleanup(f.businessId));
  const sold = await sell(f, { quantity: 4, unitPrice: 100 });

  const res = await raise(f, sold, { refundAmount: 5000 });
  assert.equal(res.status, 422, JSON.stringify(res.body));
  assert.match(res.body.error.message, /exceeds/i);

  const [[left]] = await pool.query(`SELECT COUNT(*) AS n FROM returns WHERE business_id = ?`, [
    f.businessId,
  ]);
  assert.equal(Number(left.n), 0, "and nothing is recorded");
});

test("a return cannot claim more than the line sold, across requests", async (t) => {
  if (!(await requireDatabase(t))) return;
  const f = await fixture();
  t.after(() => cleanup(f.businessId));
  const sold = await sell(f, { quantity: 4, unitPrice: 100 });

  const tooMany = await raise(f, sold, { items: [{ orderItemId: sold.lineId, quantity: 5 }] });
  assert.equal(tooMany.status, 422, JSON.stringify(tooMany.body));

  assert.equal((await raise(f, sold, { items: [{ orderItemId: sold.lineId, quantity: 3 }] })).status, 201);

  // 3 of 4 already claimed, so only 1 is left — even though the first return
  // has not been approved yet. Goods claimed twice get refunded twice.
  const second = await raise(f, sold, { items: [{ orderItemId: sold.lineId, quantity: 2 }] });
  assert.equal(second.status, 422, JSON.stringify(second.body));
  assert.match(second.body.error.message, /Only 1/);

  assert.equal((await raise(f, sold, { items: [{ orderItemId: sold.lineId, quantity: 1 }] })).status, 201);
  const exhausted = await raise(f, sold, { items: [{ orderItemId: sold.lineId, quantity: 1 }] });
  assert.equal(exhausted.status, 422);
  assert.match(exhausted.body.error.message, /already been returned in full/);
});

test("a rejected return releases what it had claimed", async (t) => {
  if (!(await requireDatabase(t))) return;
  const f = await fixture();
  t.after(() => cleanup(f.businessId));
  const sold = await sell(f, { quantity: 4, unitPrice: 100 });

  const first = await raise(f, sold, { items: [{ orderItemId: sold.lineId, quantity: 4 }] });
  assert.equal((await raise(f, sold, { items: [{ orderItemId: sold.lineId, quantity: 1 }] })).status, 422);

  assert.equal((await setStatus(f, first.body.data.id, "rejected")).status, 200);

  const again = await raise(f, sold, { items: [{ orderItemId: sold.lineId, quantity: 4 }] });
  assert.equal(again.status, 201, "a refused return must not lock the goods away forever");
});

test("a return must name a line of its own order", async (t) => {
  if (!(await requireDatabase(t))) return;
  const f = await fixture();
  t.after(() => cleanup(f.businessId));
  const a = await sell(f, { quantity: 2 });
  const b = await sell(f, { quantity: 2 });

  const crossed = await auth(request(app).post("/api/returns"), f.token).send({
    orderId: a.id,
    reason: "Wrong colour",
    items: [{ orderItemId: b.lineId, quantity: 1 }],
  });
  assert.equal(crossed.status, 422, JSON.stringify(crossed.body));
  assert.match(crossed.body.error.message, /not part of that order/);
});

test("§16: only an order whose goods have left can be returned", async (t) => {
  if (!(await requireDatabase(t))) return;
  const f = await fixture();
  t.after(() => cleanup(f.businessId));

  const draft = await auth(request(app).post("/api/orders"), f.token).send({
    orderType: "standard",
    items: [{ productId: f.productId, quantity: 1, unitPrice: 100 }],
  });
  const detail = await auth(request(app).get(`/api/orders/${draft.body.data.id}`), f.token).send();

  const res = await auth(request(app).post("/api/returns"), f.token).send({
    orderId: draft.body.data.id,
    reason: "Changed mind",
    items: [{ orderItemId: detail.body.data.items[0].id, quantity: 1 }],
  });
  assert.equal(res.status, 422, JSON.stringify(res.body));
  assert.match(res.body.error.message, /nothing to return/);

  const missing = await auth(request(app).post("/api/returns"), f.token).send({
    orderId: 99999999,
    reason: "Nope",
    items: [{ orderItemId: 1, quantity: 1 }],
  });
  assert.equal(missing.status, 422);
});

// ---- the two-stage policy ----------------------------------------------

test("§16: approving moves NOTHING — the goods are still in the customer's car", async (t) => {
  if (!(await requireDatabase(t))) return;
  const f = await fixture();
  t.after(() => cleanup(f.businessId));
  const sold = await sell(f, { quantity: 4, unitPrice: 100 });
  const returned = await raise(f, sold);

  const approved = await setStatus(f, returned.body.data.id, "approved");
  assert.equal(approved.status, 200, JSON.stringify(approved.body));
  assert.equal(approved.body.data.status, "approved");
  assert.equal(approved.body.data.approvedBy, f.userId, "§16: who approved it");

  assert.equal(await stockOf(f.businessId, f.productId), 16, "approval is a decision, not a delivery");
  const [[payments]] = await pool.query(`SELECT COUNT(*) AS n FROM payments WHERE business_id = ? AND direction = 'outgoing'`, [
    f.businessId,
  ]);
  assert.equal(Number(payments.n), 0, "and no money has moved either");
});

test("§16: completing restocks the SELLABLE items and refunds the customer", async (t) => {
  if (!(await requireDatabase(t))) return;
  const f = await fixture();
  t.after(() => cleanup(f.businessId));
  const sold = await sell(f, { quantity: 4, unitPrice: 100 });
  assert.equal(sold.order.paidAmount, 400);

  const returned = await raise(f, sold);
  await setStatus(f, returned.body.data.id, "approved");
  const completed = await setStatus(f, returned.body.data.id, "completed");

  assert.equal(completed.status, 200, JSON.stringify(completed.body));
  assert.equal(completed.body.data.status, "completed");
  assert.ok(completed.body.data.completedAt);
  assert.equal(await stockOf(f.businessId, f.productId), 18, "the two chairs are back");

  const [[movement]] = await pool.query(
    `SELECT movement_type, quantity, reference_type, reference_number
       FROM inventory_movements WHERE business_id = ? ORDER BY id DESC LIMIT 1`,
    [f.businessId]
  );
  assert.equal(movement.movement_type, "return", "§12: the ledger says why");
  assert.equal(Number(movement.quantity), 2);
  assert.equal(movement.reference_type, "return");
  assert.equal(movement.reference_number, completed.body.data.returnNumber);

  // The refund leaves, so the order stops reading as paid in full.
  const order = await auth(request(app).get(`/api/orders/${sold.id}`), f.token).send();
  assert.equal(order.body.data.paidAmount, 200, "400 in, 200 back out");
  assert.equal(order.body.data.paymentStatus, "partially_paid");
  assert.equal(order.body.data.status, "partially_returned", "§16: 2 of 4 came back");
});

test("§16: DAMAGED items are not restocked, but are on the record", async (t) => {
  if (!(await requireDatabase(t))) return;
  const f = await fixture();
  t.after(() => cleanup(f.businessId));
  const sold = await sell(f, { quantity: 4, unitPrice: 100 });

  const returned = await raise(f, sold, {
    items: [{ orderItemId: sold.lineId, quantity: 2, condition: "damaged" }],
  });
  await setStatus(f, returned.body.data.id, "approved");
  const completed = await setStatus(f, returned.body.data.id, "completed");

  assert.equal(completed.status, 200, JSON.stringify(completed.body));
  assert.equal(
    await stockOf(f.businessId, f.productId),
    16,
    "a broken chair must not go back on the shelf to be sold again"
  );
  assert.equal(completed.body.data.items[0].condition, "damaged", "but the document says it came back");

  // The customer is still refunded — the goods were faulty.
  const order = await auth(request(app).get(`/api/orders/${sold.id}`), f.token).send();
  assert.equal(order.body.data.paidAmount, 200);
});

test("§16: a mixed return restocks only the sellable half", async (t) => {
  if (!(await requireDatabase(t))) return;
  const f = await fixture();
  t.after(() => cleanup(f.businessId));
  const sold = await sell(f, { quantity: 4, unitPrice: 100 });

  const returned = await auth(request(app).post("/api/returns"), f.token).send({
    orderId: sold.id,
    reason: "One broken in transit",
    items: [
      { orderItemId: sold.lineId, quantity: 1, condition: "sellable" },
      { orderItemId: sold.lineId, quantity: 1, condition: "damaged" },
    ],
  });
  assert.equal(returned.status, 201, JSON.stringify(returned.body));
  assert.equal(returned.body.data.refundAmount, 200, "both are refunded");

  await setStatus(f, returned.body.data.id, "approved");
  await setStatus(f, returned.body.data.id, "completed");

  assert.equal(await stockOf(f.businessId, f.productId), 17, "one back on the shelf, one written off");
});

test("§16: returned goods go back to the shelf they were sold from (§11)", async (t) => {
  if (!(await requireDatabase(t))) return;
  const f = await fixture({ stock: 20, onShelf: true });
  t.after(() => cleanup(f.businessId));
  const sold = await sell(f, { quantity: 4, unitPrice: 100 });

  assert.deepEqual(await slotsOf(f.businessId, f.productId), [
    { locationId: f.locationId, quantity: 16 },
  ]);

  const returned = await raise(f, sold);
  await setStatus(f, returned.body.data.id, "approved");
  await setStatus(f, returned.body.data.id, "completed");

  assert.deepEqual(
    await slotsOf(f.businessId, f.productId),
    [{ locationId: f.locationId, quantity: 18 }],
    "back on A-1, not dumped in the warehouse's location-less slot"
  );
});

test("§16: returning everything marks the order returned, not partially", async (t) => {
  if (!(await requireDatabase(t))) return;
  const f = await fixture();
  t.after(() => cleanup(f.businessId));
  const sold = await sell(f, { quantity: 4, unitPrice: 100 });

  const returned = await raise(f, sold, { items: [{ orderItemId: sold.lineId, quantity: 4 }] });
  await setStatus(f, returned.body.data.id, "approved");
  await setStatus(f, returned.body.data.id, "completed");

  const order = await auth(request(app).get(`/api/orders/${sold.id}`), f.token).send();
  assert.equal(order.body.data.status, "returned");
  assert.equal(order.body.data.paidAmount, 0, "the whole sale is refunded");
  assert.equal(order.body.data.paymentStatus, "unpaid");
  assert.equal(await stockOf(f.businessId, f.productId), 20, "and all the stock is back");
});

test("a rejected return neither restocks nor refunds", async (t) => {
  if (!(await requireDatabase(t))) return;
  const f = await fixture();
  t.after(() => cleanup(f.businessId));
  const sold = await sell(f, { quantity: 4, unitPrice: 100 });
  const returned = await raise(f, sold);

  const rejected = await setStatus(f, returned.body.data.id, "rejected");
  assert.equal(rejected.status, 200);
  assert.equal(await stockOf(f.businessId, f.productId), 16);

  const order = await auth(request(app).get(`/api/orders/${sold.id}`), f.token).send();
  assert.equal(order.body.data.paidAmount, 400, "the customer keeps nothing back");
  assert.equal(order.body.data.status, "confirmed", "and the order is untouched");
});

test("§16: an impossible transition is refused, and completion happens once", async (t) => {
  if (!(await requireDatabase(t))) return;
  const f = await fixture();
  t.after(() => cleanup(f.businessId));
  const sold = await sell(f, { quantity: 4, unitPrice: 100 });
  const returned = await raise(f, sold);
  const id = returned.body.data.id;

  // Straight from requested to completed skips the approval §16 requires.
  assert.equal((await setStatus(f, id, "completed")).status, 409);
  assert.equal(await stockOf(f.businessId, f.productId), 16);

  await setStatus(f, id, "approved");
  assert.equal((await setStatus(f, id, "completed")).status, 200);
  assert.equal((await setStatus(f, id, "completed")).status, 409, "a completed return is closed");
  assert.equal(await stockOf(f.businessId, f.productId), 18, "and the goods came back once");
});

test("two simultaneous completions restock the goods once", async (t) => {
  if (!(await requireDatabase(t))) return;
  const f = await fixture();
  t.after(() => cleanup(f.businessId));
  const sold = await sell(f, { quantity: 4, unitPrice: 100 });
  const returned = await raise(f, sold);
  await setStatus(f, returned.body.data.id, "approved");

  const [a, b] = await Promise.all([
    setStatus(f, returned.body.data.id, "completed"),
    setStatus(f, returned.body.data.id, "completed"),
  ]);
  const statuses = [a.status, b.status].sort();
  assert.equal(statuses[0], 200, "one completion should succeed");
  assert.ok(statuses[1] >= 400, `the other must not, got ${statuses[1]}`);
  assert.equal(await stockOf(f.businessId, f.productId), 18, "16 + 2, once");

  const [[refunds]] = await pool.query(
    `SELECT COUNT(*) AS n FROM payments WHERE business_id = ? AND direction = 'outgoing'`,
    [f.businessId]
  );
  assert.equal(Number(refunds.n), 1, "and the customer is refunded once");
});

// ---- what the form needs -----------------------------------------------

test("an order says what it still has left to return", async (t) => {
  if (!(await requireDatabase(t))) return;
  const f = await fixture();
  t.after(() => cleanup(f.businessId));
  const sold = await sell(f, { quantity: 4, unitPrice: 100 });

  const before = await auth(request(app).get(`/api/orders/${sold.id}/returnable`), f.token).send();
  assert.equal(before.status, 200, JSON.stringify(before.body));
  assert.equal(before.body.data.returnable, true);
  assert.equal(before.body.data.lines.length, 1);
  assert.equal(before.body.data.lines[0].quantity, 4);
  assert.equal(before.body.data.lines[0].returned, 0);
  assert.equal(before.body.data.lines[0].remaining, 4);

  await raise(f, sold, { items: [{ orderItemId: sold.lineId, quantity: 3 }] });

  const after_ = await auth(request(app).get(`/api/orders/${sold.id}/returnable`), f.token).send();
  assert.equal(after_.body.data.lines[0].returned, 3);
  assert.equal(after_.body.data.lines[0].remaining, 1);
});

// ---- listing and tenancy -----------------------------------------------

test("returns list, filter and search", async (t) => {
  if (!(await requireDatabase(t))) return;
  const f = await fixture();
  t.after(() => cleanup(f.businessId));
  const sold = await sell(f, { quantity: 4, unitPrice: 100 });

  const first = await raise(f, sold, { items: [{ orderItemId: sold.lineId, quantity: 1 }] });
  await raise(f, sold, { items: [{ orderItemId: sold.lineId, quantity: 1 }] });
  await setStatus(f, first.body.data.id, "approved");

  const all = await auth(request(app).get("/api/returns?page=1&pageSize=10"), f.token).send();
  assert.equal(all.status, 200);
  assert.equal(all.body.data.length, 2);
  assert.equal(all.body.meta.pagination.total, 2);

  const approved = await auth(request(app).get("/api/returns?status=approved"), f.token).send();
  assert.equal(approved.body.data.length, 1);

  const byOrder = await auth(request(app).get(`/api/returns?orderId=${sold.id}`), f.token).send();
  assert.equal(byOrder.body.data.length, 2);

  const found = await auth(
    request(app).get(`/api/returns?search=${sold.order.orderNumber}`),
    f.token
  ).send();
  assert.equal(found.body.data.length, 2, "the order's number is searchable");
});

test("returns are tenant-scoped — one business never sees another's", async (t) => {
  if (!(await requireDatabase(t))) return;
  const a = await fixture();
  const b = await fixture();
  t.after(() => Promise.all([cleanup(a.businessId), cleanup(b.businessId)]));

  const sold = await sell(a, { quantity: 4 });
  const returned = await raise(a, sold);
  const id = returned.body.data.id;

  assert.equal((await auth(request(app).get(`/api/returns/${id}`), b.token).send()).status, 404);
  assert.equal((await setStatus(b, id, "approved")).status, 404);
  assert.equal(
    (await auth(request(app).get(`/api/orders/${sold.id}/returnable`), b.token).send()).status,
    404
  );
  assert.equal((await auth(request(app).get("/api/returns"), b.token).send()).body.data.length, 0);

  // A return against the other tenant's order is not a return at all.
  const crossed = await auth(request(app).post("/api/returns"), b.token).send({
    orderId: sold.id,
    reason: "Not mine",
    items: [{ orderItemId: sold.lineId, quantity: 1 }],
  });
  assert.equal(crossed.status, 422);
  assert.equal(await stockOf(a.businessId, a.productId), 16, "and moves nothing");
});

test("§30: raising and completing a return are both in the activity trail", async (t) => {
  if (!(await requireDatabase(t))) return;
  const f = await fixture();
  t.after(() => cleanup(f.businessId));
  const sold = await sell(f, { quantity: 4, unitPrice: 100 });
  const returned = await raise(f, sold);
  await setStatus(f, returned.body.data.id, "approved");

  let rows = [];
  for (let i = 0; i < 60; i += 1) {
    const [found] = await pool.query(
      `SELECT action, actor_id FROM audit_logs WHERE business_id = ? AND module = 'returns' ORDER BY id`,
      [f.businessId]
    );
    rows = found;
    if (rows.length >= 2) break;
    await new Promise((resolve) => setTimeout(resolve, 25));
  }

  const actions = rows.map((r) => r.action);
  assert.ok(actions.includes("returns.create"), actions.join(", "));
  assert.ok(actions.includes("returns.update"), actions.join(", "));
  assert.ok(rows.every((r) => Number(r.actor_id) === f.userId), "who approved it is on the record");
});

after(() => closePool());
