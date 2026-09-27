// The order defects that only appear under concurrency, plus the two that
// only appear when the warehouse setup changes underneath an order.
//
// Every test here failed before the fix it describes. They are separate from
// orders.test.js because they drive the HTTP layer — the races live in the
// controller, between reading a row and writing it, so testing the service
// alone cannot reach them.

import { test, after } from "node:test";
import assert from "node:assert/strict";
import request from "supertest";

import { app } from "../../src/app.js";
import { pool, closePool, runInTransaction } from "../../src/db/pool.js";
import { createDefaultRoles, findOwnerRoleId } from "../../src/modules/rbac/repository.js";
import { adjustStock } from "../../src/modules/inventory/service.js";
import { signAccessToken } from "../../src/utils/token.js";
import { requireDatabase, testPhone, cleanupTestData } from "./helpers.js";

/** A business with two warehouses (the second is not the default), stock and a product. */
async function fixture({ stock = 10 } = {}) {
  const f = await runInTransaction(async (conn) => {
    const [b] = await conn.query(
      `INSERT INTO businesses (name, business_type, phone, status) VALUES (?, 'warehouse', ?, 'active')`,
      [`Conc ${Math.random().toString(36).slice(2, 8)}`, testPhone()]
    );
    const businessId = b.insertId;
    await createDefaultRoles(conn, businessId);
    // Permissions come from the role, not from is_owner — a user with no role
    // holds nothing and every route answers 403.
    const roleId = await findOwnerRoleId(conn, businessId);

    const [u] = await conn.query(
      `INSERT INTO users (business_id, name, phone, password_hash, is_owner, role_id, status)
       VALUES (?, 'Seller', ?, 'x', TRUE, ?, 'active')`,
      [businessId, testPhone(), roleId]
    );
    const [w1] = await conn.query(
      `INSERT INTO warehouses (business_id, name, location_type, is_default, status)
       VALUES (?, 'North', 'warehouse', TRUE, 'active')`,
      [businessId]
    );
    const [w2] = await conn.query(
      `INSERT INTO warehouses (business_id, name, location_type, is_default, status)
       VALUES (?, 'South', 'warehouse', FALSE, 'active')`,
      [businessId]
    );
    const [p] = await conn.query(
      `INSERT INTO products (business_id, name, sku, selling_price, status)
       VALUES (?, 'Widget', ?, 100, 'active')`,
      [businessId, `SKU-${Math.random().toString(36).slice(2, 8)}`]
    );
    return {
      businessId,
      userId: u.insertId,
      warehouseId: w1.insertId,
      otherWarehouseId: w2.insertId,
      productId: p.insertId,
    };
  });

  // The owner role holds every permission, so the token can drive any route.
  f.token = signAccessToken({
    accountType: "business_user",
    userId: f.userId,
    businessId: f.businessId,
  });

  if (stock > 0) {
    await adjustStock({
      businessId: f.businessId,
      userId: f.userId,
      productId: f.productId,
      warehouseId: f.warehouseId,
      delta: stock,
      movementType: "manual_increase",
    });
  }
  return f;
}

async function cleanup(businessId) {
  if (!businessId) return;
  for (const sql of [
    `DELETE FROM audit_logs WHERE business_id = ?`,
    `DELETE FROM order_edits WHERE business_id = ?`,
    `DELETE FROM payments WHERE business_id = ?`,
    `DELETE FROM order_items WHERE business_id = ?`,
    `DELETE FROM orders WHERE business_id = ?`,
    `DELETE FROM inventory_movements WHERE business_id = ?`,
    `DELETE FROM inventory WHERE business_id = ?`,
    `DELETE FROM document_sequences WHERE business_id = ?`,
    `DELETE FROM business_settings WHERE business_id = ?`,
    `DELETE FROM product_variants WHERE business_id = ?`,
    `DELETE FROM products WHERE business_id = ?`,
    `DELETE FROM storage_locations WHERE warehouse_id IN (SELECT id FROM warehouses WHERE business_id = ?)`,
    `DELETE FROM warehouses WHERE business_id = ?`,
  ]) {
    await pool.query(sql, [businessId]);
  }
  const [users] = await pool.query(`SELECT id FROM users WHERE business_id = ?`, [businessId]);
  await cleanupTestData({ businessIds: [businessId], userIds: users.map((u) => u.id) });
}

const auth = (req, token) => req.set("Authorization", `Bearer ${token}`);

const slotsOf = async (businessId, productId) => {
  const [rows] = await pool.query(
    `SELECT warehouse_id, quantity FROM inventory
      WHERE business_id = ? AND product_id = ? ORDER BY warehouse_id`,
    [businessId, productId]
  );
  return rows.map((r) => ({ warehouseId: r.warehouse_id, quantity: Number(r.quantity) }));
};

async function createDraft(f, { quantity = 2 } = {}) {
  const res = await auth(request(app).post("/api/orders"), f.token).send({
    orderType: "standard",
    items: [{ productId: f.productId, quantity, unitPrice: 100 }],
  });
  assert.equal(res.status, 201, JSON.stringify(res.body));
  return res.body.data.id;
}

// -------------------------------------------------------------------------
// The status race: stock must leave exactly once.
// -------------------------------------------------------------------------

test("two simultaneous confirmations ship the stock once, not twice", async (t) => {
  if (!(await requireDatabase(t))) return;
  const f = await fixture({ stock: 10 });
  t.after(() => cleanup(f.businessId));

  const orderId = await createDraft(f, { quantity: 2 });

  // Both requests read the order, both see "draft". Before the fix each then
  // moved stock, taking 4 units off the shelf for a 2-unit order.
  const confirm = () =>
    auth(request(app).patch(`/api/orders/${orderId}/status`), f.token).send({ status: "confirmed" });
  const [a, b] = await Promise.all([confirm(), confirm()]);

  const statuses = [a.status, b.status].sort();
  assert.equal(statuses[0], 200, "one confirmation should succeed");
  assert.ok(statuses[1] >= 400, `the second should be refused, got ${statuses[1]}`);

  const [{ quantity }] = await slotsOf(f.businessId, f.productId);
  assert.equal(quantity, 8, "10 - 2, once");

  const [movements] = await pool.query(
    `SELECT COUNT(*) AS n FROM inventory_movements
      WHERE business_id = ? AND reference_type = 'order' AND reference_id = ?`,
    [f.businessId, orderId]
  );
  assert.equal(Number(movements[0].n), 1, "exactly one ledger entry for the order");
});

test("two simultaneous payments cannot together exceed the balance", async (t) => {
  if (!(await requireDatabase(t))) return;
  const f = await fixture({ stock: 10 });
  t.after(() => cleanup(f.businessId));

  const orderId = await createDraft(f, { quantity: 2 }); // grand total 200

  const pay = (amount) =>
    auth(request(app).post(`/api/orders/${orderId}/payments`), f.token).send({
      amount,
      method: "cash",
    });
  const results = await Promise.all([pay(150), pay(150)]);

  const accepted = results.filter((r) => r.status === 201);
  assert.equal(accepted.length, 1, "only one 150 payment fits under a 200 total");

  const [rows] = await pool.query(
    `SELECT o.paid_amount,
            (SELECT COALESCE(SUM(amount), 0) FROM payments p WHERE p.order_id = o.id) AS ledger
       FROM orders o WHERE o.id = ?`,
    [orderId]
  );
  assert.equal(
    Number(rows[0].paid_amount),
    Number(rows[0].ledger),
    "the order's running total must equal the payments it summarises"
  );
});

// -------------------------------------------------------------------------
// Returning stock to where it came from.
// -------------------------------------------------------------------------

test("cancelling returns stock to the warehouse it left, not today's default", async (t) => {
  if (!(await requireDatabase(t))) return;
  const f = await fixture({ stock: 0 });
  t.after(() => cleanup(f.businessId));

  // The stock is in North, which is the default when the order is confirmed.
  await adjustStock({
    businessId: f.businessId,
    userId: f.userId,
    productId: f.productId,
    warehouseId: f.warehouseId,
    delta: 10,
    movementType: "manual_increase",
  });

  const orderId = await createDraft(f, { quantity: 3 });
  const confirmed = await auth(
    request(app).patch(`/api/orders/${orderId}/status`),
    f.token
  ).send({ status: "confirmed" });
  assert.equal(confirmed.status, 200, JSON.stringify(confirmed.body));

  // Now the business makes South its default — a perfectly ordinary change.
  await pool.query(`UPDATE warehouses SET is_default = FALSE WHERE id = ?`, [f.warehouseId]);
  await pool.query(`UPDATE warehouses SET is_default = TRUE WHERE id = ?`, [f.otherWarehouseId]);

  const cancelled = await auth(
    request(app).patch(`/api/orders/${orderId}/status`),
    f.token
  ).send({ status: "cancelled", reason: "Customer changed their mind" });
  assert.equal(cancelled.status, 200, JSON.stringify(cancelled.body));

  const slots = await slotsOf(f.businessId, f.productId);
  const north = slots.find((s) => s.warehouseId === f.warehouseId);
  const south = slots.find((s) => s.warehouseId === f.otherWarehouseId);

  assert.equal(north.quantity, 10, "the goods go back where they came from");
  assert.equal(south?.quantity ?? 0, 0, "and must not appear in a warehouse they never entered");
});

// -------------------------------------------------------------------------
// Validation the API was missing.
// -------------------------------------------------------------------------

test("an order line cannot reference another product's variant", async (t) => {
  if (!(await requireDatabase(t))) return;
  const f = await fixture({ stock: 10 });
  t.after(() => cleanup(f.businessId));

  // A second product, with a variant of its own.
  const [other] = await pool.query(
    `INSERT INTO products (business_id, name, sku, selling_price, status)
     VALUES (?, 'Other', ?, 50, 'active')`,
    [f.businessId, `SKU-${Math.random().toString(36).slice(2, 8)}`]
  );
  const [variant] = await pool.query(
    `INSERT INTO product_variants (business_id, product_id, name, sku) VALUES (?, ?, 'Red', ?)`,
    [f.businessId, other.insertId, `VAR-${Math.random().toString(36).slice(2, 8)}`]
  );

  const res = await auth(request(app).post("/api/orders"), f.token).send({
    orderType: "standard",
    items: [{ productId: f.productId, quantity: 1, unitPrice: 100, variantId: variant.insertId }],
  });

  assert.equal(res.status, 422, JSON.stringify(res.body));
  assert.match(res.body.error.message, /variant/i);
});

test("a line discount larger than the line itself is refused", async (t) => {
  if (!(await requireDatabase(t))) return;
  const f = await fixture({ stock: 10 });
  t.after(() => cleanup(f.businessId));

  // 1 x 100 with 150 off would make the line pay the customer 50. A second,
  // positive line hides it from any order-level total check.
  const res = await auth(request(app).post("/api/orders"), f.token).send({
    orderType: "standard",
    items: [
      { productId: f.productId, quantity: 1, unitPrice: 100, discountAmount: 150 },
      { productId: f.productId, quantity: 5, unitPrice: 100 },
    ],
  });

  assert.equal(res.status, 422, JSON.stringify(res.body));
});

test("?sort= cannot reach an inherited property", async (t) => {
  if (!(await requireDatabase(t))) return;
  const f = await fixture({ stock: 0 });
  t.after(() => cleanup(f.businessId));

  // `"constructor" in allowed` is true for every object, so the Object
  // function itself was interpolated into ORDER BY — a 500 from one word.
  // Either answer is fine (the sort-key regex rejects the underscored ones
  // outright); what must never happen is the query reaching MySQL.
  for (const key of ["constructor", "__proto__", "toString", "valueOf"]) {
    const res = await auth(request(app).get(`/api/orders?sort=${key}`), f.token).send();
    assert.ok(
      res.status === 200 || res.status === 422,
      `?sort=${key} must be ignored or refused, not a ${res.status}`
    );
  }
});

// -------------------------------------------------------------------------
// The single-order response, and repeated saves.
// -------------------------------------------------------------------------

test("GET one order reports its real item count", async (t) => {
  if (!(await requireDatabase(t))) return;
  const f = await fixture({ stock: 10 });
  t.after(() => cleanup(f.businessId));

  const orderId = await createDraft(f, { quantity: 2 });
  const res = await auth(request(app).get(`/api/orders/${orderId}`), f.token).send();

  assert.equal(res.status, 200);
  assert.equal(res.body.data.itemCount, 1, "one line — not the 0 the missing column produced");
});

test("saving a product twice with the same values is not a 404", async (t) => {
  if (!(await requireDatabase(t))) return;
  const f = await fixture({ stock: 0 });
  t.after(() => cleanup(f.businessId));

  // The repositories read `affectedRows === 1` as "that row exists" and turn 0
  // into a 404, which only holds while affectedRows counts rows MATCHED. It
  // does (see the FOUND_ROWS flag in db/pool.js), and this test is what would
  // notice if that ever stopped being true.
  const patch = () =>
    auth(request(app).patch(`/api/products/${f.productId}`), f.token).send({ name: "Widget Two" });

  assert.equal((await patch()).status, 200);
  assert.equal((await patch()).status, 200, "the second identical save must also succeed");
});

/**
 * Two DIFFERENT orders racing for the same stock.
 *
 * This is the invariant that justifies reading the shelves without a range
 * lock (see `stockedSlots`): the plan may be stale, but every leg is applied
 * under its own slot lock, so the shortfall is refused rather than oversold.
 * The earlier `FOR UPDATE` version was safe here too — and deadlocked instead.
 */
test("two orders racing for the last of the stock never oversell it", async (t) => {
  if (!(await requireDatabase(t))) return;
  const f = await fixture({ stock: 10 });
  t.after(() => cleanup(f.businessId));

  // 8 + 8 against 10 on hand: one can be filled, the other cannot.
  const first = await createDraft(f, { quantity: 8 });
  const second = await createDraft(f, { quantity: 8 });

  const confirm = (id) =>
    auth(request(app).patch(`/api/orders/${id}/status`), f.token).send({ status: "confirmed" });
  const results = await Promise.all([confirm(first), confirm(second)]);

  const filled = results.filter((r) => r.status === 200);
  assert.equal(filled.length, 1, `exactly one order can be filled: ${results.map((r) => r.status)}`);
  assert.ok(results.some((r) => r.status === 409), "and the other is told the stock is not there");

  const [{ quantity }] = await slotsOf(f.businessId, f.productId);
  assert.equal(quantity, 2, "10 - 8, once");
  assert.ok(quantity >= 0, "and stock is never negative while §47 forbids it");
});

/**
 * Reopening a cancelled order — the approved scope in docs/architecture.md's
 * decision table ("Cancelled → Pending only, permission-gated"), which the
 * transition map did not implement.
 *
 * The stock is the point. Cancelling gave the goods back, so a reopened order
 * must not silently re-own them: it lands in `pending`, where nothing is
 * committed, and the goods leave again only when someone confirms it.
 */
test("a cancelled order can be reopened to pending — and only to pending", async (t) => {
  if (!(await requireDatabase(t))) return;
  const f = await fixture({ stock: 10 });
  t.after(() => cleanup(f.businessId));

  const orderId = await createDraft(f, { quantity: 4 });
  const patch = (body) =>
    auth(request(app).patch(`/api/orders/${orderId}/status`), f.token).send(body);
  const onHand = async () => (await slotsOf(f.businessId, f.productId))[0].quantity;

  const firstConfirm = await patch({ status: "confirmed" });
  assert.equal(firstConfirm.status, 200, JSON.stringify(firstConfirm.body));
  assert.equal(await onHand(), 6, "4 shipped");

  const cancelStep = await patch({ status: "cancelled", reason: "Customer error" });
  assert.equal(cancelStep.status, 200, JSON.stringify(cancelStep.body));
  assert.equal(await onHand(), 10, "and returned");

  const straightBack = await patch({ status: "confirmed" });
  assert.equal(straightBack.status, 409, "it cannot re-acquire the stock it gave back");

  const reopened = await patch({ status: "pending" });
  assert.equal(reopened.status, 200, JSON.stringify(reopened.body));
  assert.equal(reopened.body.data.status, "pending");
  assert.equal(await onHand(), 10, "reopening alone moves nothing");

  const [[row]] = await pool.query(
    `SELECT cancelled_at, cancelled_by, cancel_reason, status_before_cancel FROM orders WHERE id = ?`,
    [orderId]
  );
  assert.equal(row.cancelled_at, null, "an order that is pending was not cancelled by anyone");
  assert.equal(row.cancelled_by, null);
  assert.equal(row.cancel_reason, null);
  assert.equal(row.status_before_cancel, null);

  // §15: but the history still says what happened.
  const [edits] = await pool.query(
    `SELECT previous_value, new_value FROM order_edits WHERE order_id = ? ORDER BY id`,
    [orderId]
  );
  assert.ok(
    edits.some((e) => e.previous_value === "cancelled" && e.new_value === "pending"),
    `the reopening must be in the trail: ${JSON.stringify(edits)}`
  );

  // And confirming it again ships the goods — once.
  const reconfirm = await patch({ status: "confirmed" });
  assert.equal(reconfirm.status, 200, JSON.stringify(reconfirm.body));
  assert.equal(await onHand(), 6, "the goods leave again on confirmation");
});

after(() => closePool());
