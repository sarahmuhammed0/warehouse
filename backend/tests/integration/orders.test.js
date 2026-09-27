// §13–§17, §43, §55, §61.12 against the real database.
//
// Orders is where stock, money and document numbers meet, so these prove the
// places those three can disagree: a failed confirmation that half-commits,
// a payment that drifts from the payments table, a cancellation that invents
// or loses inventory, and two documents sharing a number.

import { test, after } from "node:test";
import assert from "node:assert/strict";

import { pool, closePool, runInTransaction } from "../../src/db/pool.js";
import { createDefaultRoles } from "../../src/modules/rbac/repository.js";
import {
  createOrder,
  cancelOrder,
  calculateTotals,
  paymentStatusFor,
  assertTransition,
  productResolver,
} from "../../src/modules/orders/service.js";
import { orderItems, toStockLines } from "../../src/modules/orders/repository.js";
import { nextDocumentNumber } from "../../src/modules/documents/numbering.js";
import { adjustStock } from "../../src/modules/inventory/service.js";
import { requireDatabase, testPhone, cleanupTestData } from "./helpers.js";

/** A business with a warehouse, a stocked product and a customer. */
async function fixture({ stock = 10 } = {}) {
  const f = await runInTransaction(async (conn) => {
    const [b] = await conn.query(
      `INSERT INTO businesses (name, business_type, phone, status) VALUES (?, 'warehouse', ?, 'active')`,
      [`Ord ${Date.now()}-${Math.random().toString(36).slice(2, 6)}`, testPhone()]
    );
    const businessId = b.insertId;
    await createDefaultRoles(conn, businessId);

    const [u] = await conn.query(
      `INSERT INTO users (business_id, name, phone, password_hash, is_owner, status)
       VALUES (?, 'Seller', ?, 'x', TRUE, 'active')`,
      [businessId, testPhone()]
    );
    const [w] = await conn.query(
      `INSERT INTO warehouses (business_id, name, location_type, is_default, status)
       VALUES (?, 'Main', 'warehouse', TRUE, 'active')`,
      [businessId]
    );
    const [p] = await conn.query(
      `INSERT INTO products (business_id, name, sku, selling_price, status)
       VALUES (?, 'Widget', ?, 100, 'active')`,
      [businessId, `SKU-${Date.now()}-${Math.random().toString(36).slice(2, 6)}`]
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
    };
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
    `DELETE FROM order_edits WHERE business_id = ?`,
    `DELETE FROM payments WHERE business_id = ?`,
    `DELETE FROM order_items WHERE business_id = ?`,
    `DELETE FROM orders WHERE business_id = ?`,
    `DELETE FROM inventory_movements WHERE business_id = ?`,
    `DELETE FROM inventory WHERE business_id = ?`,
    `DELETE FROM document_sequences WHERE business_id = ?`,
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

const stockOf = async (businessId, productId) =>
  Number(
    (await pool.query(`SELECT COALESCE(SUM(quantity),0) AS q FROM inventory WHERE business_id=? AND product_id=?`, [
      businessId,
      productId,
    ]))[0][0].q
  );

// The real resolver, not a stand-in — see productResolver's own comment.
const resolve = (businessId) => productResolver(businessId);

// ---- pure logic, no database needed for the arithmetic itself ------------

test("totals are computed from the lines, and a discount cannot exceed them", () => {
  const totals = calculateTotals({
    items: [{ productId: 1, quantity: 2, unitPrice: 100, taxRate: 10 }],
    discountAmount: 20,
  });
  assert.equal(totals.subtotal, 200);
  assert.equal(totals.taxTotal, 20);
  assert.equal(totals.grandTotal, 200);

  assert.throws(
    () => calculateTotals({ items: [{ productId: 1, quantity: 1, unitPrice: 10 }], discountAmount: 999 }),
    (e) => e.statusCode === 422
  );
});

test("payment status follows the amounts, and an exact payment reads as paid", () => {
  assert.equal(paymentStatusFor({ grandTotal: 100, paidAmount: 0 }), "unpaid");
  assert.equal(paymentStatusFor({ grandTotal: 100, paidAmount: 40 }), "partially_paid");
  assert.equal(paymentStatusFor({ grandTotal: 100, paidAmount: 100 }), "paid");
  // Decimals: paying to the fill must not leave a cent outstanding.
  assert.equal(paymentStatusFor({ grandTotal: 99.99, paidAmount: 99.99 }), "paid");
});

test("§14: impossible status transitions are refused", () => {
  assert.throws(() => assertTransition("confirmed", "draft"), (e) => e.statusCode === 409);
  assert.throws(() => assertTransition("completed", "processing"), (e) => e.statusCode === 409);
  assert.throws(() => assertTransition("cancelled", "confirmed"), (e) => e.statusCode === 409);
  assertTransition("draft", "confirmed");
  assertTransition("confirmed", "completed");
});

// ---- against the database -------------------------------------------------

test("a confirmed order moves stock once and snapshots the line (§55)", async (t) => {
  if (!(await requireDatabase(t))) return;
  const f = await fixture({ stock: 10 });
  t.after(() => cleanup(f.businessId));

  const { orderId } = await createOrder({
    businessId: f.businessId,
    userId: f.userId,
    data: {
      orderType: "quick_sale",
      customerId: f.customerId,
      status: "confirmed",
      items: [{ productId: f.productId, quantity: 3, unitPrice: 100 }],
    },
    resolveProduct: resolve(f.businessId),
  });

  assert.equal(await stockOf(f.businessId, f.productId), 7);

  const [[line]] = await pool.query(`SELECT product_name, sku, unit_price FROM order_items WHERE order_id = ?`, [
    orderId,
  ]);
  assert.equal(line.product_name, "Widget", "§55: the line keeps the name as it was");
  assert.ok(line.sku, "§55: and the SKU");

  // Renaming the product must not rewrite the invoice.
  await pool.query(`UPDATE products SET name = 'Renamed' WHERE id = ?`, [f.productId]);
  const [[after_]] = await pool.query(`SELECT product_name FROM order_items WHERE order_id = ?`, [orderId]);
  assert.equal(after_.product_name, "Widget", "a rename must not rewrite history");
});

test("a draft order does not move stock", async (t) => {
  if (!(await requireDatabase(t))) return;
  const f = await fixture({ stock: 10 });
  t.after(() => cleanup(f.businessId));

  await createOrder({
    businessId: f.businessId,
    userId: f.userId,
    data: {
      orderType: "standard",
      customerId: f.customerId,
      status: "draft",
      items: [{ productId: f.productId, quantity: 4, unitPrice: 100 }],
    },
    resolveProduct: resolve(f.businessId),
  });

  // Nothing is promised yet, so nothing leaves.
  assert.equal(await stockOf(f.businessId, f.productId), 10);
});

test("an order that cannot be stocked leaves NOTHING behind", async (t) => {
  if (!(await requireDatabase(t))) return;
  const f = await fixture({ stock: 2 });
  t.after(() => cleanup(f.businessId));

  await assert.rejects(
    () =>
      createOrder({
        businessId: f.businessId,
        userId: f.userId,
        data: {
          orderType: "quick_sale",
          status: "confirmed",
          items: [{ productId: f.productId, quantity: 99, unitPrice: 100 }],
        },
        resolveProduct: resolve(f.businessId),
      }),
    (e) => e.statusCode === 409
  );

  // The order, its lines, its movement and its document number must all be
  // gone — a half-written order is worse than no order.
  const [[orders]] = await pool.query(`SELECT COUNT(*) AS n FROM orders WHERE business_id = ?`, [f.businessId]);
  const [[items]] = await pool.query(`SELECT COUNT(*) AS n FROM order_items WHERE business_id = ?`, [f.businessId]);
  assert.equal(Number(orders.n), 0, "no order row may survive");
  assert.equal(Number(items.n), 0, "no line may survive");
  assert.equal(await stockOf(f.businessId, f.productId), 2, "stock must be untouched");
});

test("§17: cancelling returns the stock and records who, when and why", async (t) => {
  if (!(await requireDatabase(t))) return;
  const f = await fixture({ stock: 10 });
  t.after(() => cleanup(f.businessId));

  const { orderId } = await createOrder({
    businessId: f.businessId,
    userId: f.userId,
    data: {
      orderType: "quick_sale",
      status: "confirmed",
      items: [{ productId: f.productId, quantity: 4, unitPrice: 100 }],
    },
    resolveProduct: resolve(f.businessId),
  });
  assert.equal(await stockOf(f.businessId, f.productId), 6);

  const [[order]] = await pool.query(`SELECT * FROM orders WHERE id = ?`, [orderId]);
  await cancelOrder({
    businessId: f.businessId,
    userId: f.userId,
    order,
    reason: "Customer cancelled",
    items: toStockLines(await orderItems({ businessId: f.businessId, orderId })),
  });

  assert.equal(await stockOf(f.businessId, f.productId), 10, "the stock must come back");

  const [[cancelled]] = await pool.query(
    `SELECT status, cancelled_by, cancel_reason, status_before_cancel, cancelled_at FROM orders WHERE id = ?`,
    [orderId]
  );
  assert.equal(cancelled.status, "cancelled");
  assert.equal(cancelled.cancelled_by, f.userId, "§17: who");
  assert.ok(cancelled.cancelled_at, "§17: when");
  assert.equal(cancelled.cancel_reason, "Customer cancelled", "§17: why");
  assert.equal(cancelled.status_before_cancel, "confirmed", "§17: what it was before");

  // §15: and it appears in the edit trail, which is where someone looks.
  const [[edits]] = await pool.query(`SELECT COUNT(*) AS n FROM order_edits WHERE order_id = ?`, [orderId]);
  assert.ok(Number(edits.n) >= 1, "the cancellation must be in the edit trail");
});

test("cancelling a DRAFT order does not invent stock", async (t) => {
  if (!(await requireDatabase(t))) return;
  const f = await fixture({ stock: 5 });
  t.after(() => cleanup(f.businessId));

  const { orderId } = await createOrder({
    businessId: f.businessId,
    userId: f.userId,
    data: {
      orderType: "standard",
      status: "draft",
      items: [{ productId: f.productId, quantity: 3, unitPrice: 100 }],
    },
    resolveProduct: resolve(f.businessId),
  });

  const [[order]] = await pool.query(`SELECT * FROM orders WHERE id = ?`, [orderId]);
  await cancelOrder({
    businessId: f.businessId,
    userId: f.userId,
    order,
    reason: "Never went ahead",
    items: toStockLines(await orderItems({ businessId: f.businessId, orderId })),
  });

  // Stock never left, so cancelling must not put any back.
  assert.equal(await stockOf(f.businessId, f.productId), 5, "a draft cancellation must not create stock");
});

test("§61.12: concurrent allocations never produce the same document number", async (t) => {
  if (!(await requireDatabase(t))) return;
  const f = await fixture({ stock: 0 });
  t.after(() => cleanup(f.businessId));

  // Ten at once. Without the row lock these collide; the unique index would
  // then reject a document the user did nothing wrong to create.
  const numbers = await Promise.all(
    Array.from({ length: 10 }, () =>
      runInTransaction((conn) => nextDocumentNumber(conn, { businessId: f.businessId, documentType: "sale" }))
    )
  );

  assert.equal(new Set(numbers).size, 10, `duplicate document numbers: ${numbers.join(", ")}`);
  assert.ok(numbers.every((n) => /^INV-\d{4}-\d{6}$/.test(n)), `unexpected format: ${numbers[0]}`);
});

test("orders are tenant-scoped — one business never sees another's", async (t) => {
  if (!(await requireDatabase(t))) return;
  const a = await fixture({ stock: 5 });
  const b = await fixture({ stock: 5 });
  t.after(async () => {
    await cleanup(a.businessId);
    await cleanup(b.businessId);
  });

  await createOrder({
    businessId: a.businessId,
    userId: a.userId,
    data: {
      orderType: "quick_sale",
      status: "confirmed",
      items: [{ productId: a.productId, quantity: 1, unitPrice: 100 }],
    },
    resolveProduct: resolve(a.businessId),
  });

  const { listOrders } = await import("../../src/modules/orders/repository.js");
  const seen = await listOrders({
    businessId: b.businessId,
    query: {},
    pagination: { page: 1, pageSize: 50, offset: 0 },
  });
  assert.equal(seen.rows.length, 0, "§36: business B must not see business A's orders");
  assert.equal(seen.total, 0, "and the count must agree");
});

test("a line referencing another tenant's product is refused", async (t) => {
  if (!(await requireDatabase(t))) return;
  const a = await fixture({ stock: 5 });
  const b = await fixture({ stock: 5 });
  t.after(async () => {
    await cleanup(a.businessId);
    await cleanup(b.businessId);
  });

  // The foreign key would happily accept this: it constrains the id, not
  // who owns the row.
  await assert.rejects(() =>
    createOrder({
      businessId: b.businessId,
      userId: b.userId,
      data: {
        orderType: "quick_sale",
        status: "draft",
        items: [{ productId: a.productId, quantity: 1, unitPrice: 100 }],
      },
      resolveProduct: resolve(b.businessId),
    })
  );

  const [[orders]] = await pool.query(`SELECT COUNT(*) AS n FROM orders WHERE business_id = ?`, [b.businessId]);
  assert.equal(Number(orders.n), 0, "nothing may be created from a refused line");
});

// ---- §11: selling stock that has been put away on a shelf ----------------
//
// Inventory is tracked per SLOT — a warehouse, and optionally a shelf, rack
// or bin inside it. A sale used to debit the warehouse's location-less slot
// and nothing else, so a business that had actually put its stock away could
// not sell it: every confirmation answered "Insufficient stock. Available
// quantity: 0" with the goods on A-1 in plain sight. These four tests are the
// ones that were failing, in the order they were found.

/** A shelf inside a warehouse. */
async function shelf(businessId, warehouseId, name) {
  const [row] = await pool.query(
    `INSERT INTO storage_locations (business_id, warehouse_id, name, status) VALUES (?, ?, ?, 'active')`,
    [businessId, warehouseId, name]
  );
  return row.insertId;
}

/** Stock per slot, so a test can say WHERE the goods are, not just how many. */
const slotsOf = async (businessId, productId) => {
  const [rows] = await pool.query(
    `SELECT location_id, quantity FROM inventory
      WHERE business_id = ? AND product_id = ? ORDER BY id`,
    [businessId, productId]
  );
  return rows.map((row) => ({ locationId: row.location_id, quantity: Number(row.quantity) }));
};

test("§11: stock put away on a shelf can be sold, and comes off that shelf", async (t) => {
  if (!(await requireDatabase(t))) return;
  const f = await fixture({ stock: 0 });
  t.after(() => cleanup(f.businessId));

  const a1 = await shelf(f.businessId, f.warehouseId, "A-1");
  await adjustStock({
    businessId: f.businessId,
    userId: f.userId,
    productId: f.productId,
    warehouseId: f.warehouseId,
    locationId: a1,
    delta: 10,
    movementType: "manual_increase",
  });

  await createOrder({
    businessId: f.businessId,
    userId: f.userId,
    data: {
      orderType: "quick_sale",
      status: "confirmed",
      items: [{ productId: f.productId, quantity: 3, unitPrice: 100 }],
    },
    resolveProduct: resolve(f.businessId),
  });

  assert.equal(await stockOf(f.businessId, f.productId), 7, "the sale must not be refused");
  assert.deepEqual(
    await slotsOf(f.businessId, f.productId),
    [{ locationId: a1, quantity: 7 }],
    "it must come off the shelf that held it, not a second slot with a negative balance"
  );
});

test("§11: a line bigger than one shelf comes off several, fullest first", async (t) => {
  if (!(await requireDatabase(t))) return;
  const f = await fixture({ stock: 0 });
  t.after(() => cleanup(f.businessId));

  const small = await shelf(f.businessId, f.warehouseId, "A-1");
  const large = await shelf(f.businessId, f.warehouseId, "B-2");
  for (const [locationId, delta] of [[small, 4], [large, 6]]) {
    await adjustStock({
      businessId: f.businessId,
      userId: f.userId,
      productId: f.productId,
      warehouseId: f.warehouseId,
      locationId,
      delta,
      movementType: "manual_increase",
    });
  }

  const { orderId } = await createOrder({
    businessId: f.businessId,
    userId: f.userId,
    data: {
      orderType: "quick_sale",
      status: "confirmed",
      items: [{ productId: f.productId, quantity: 8, unitPrice: 100 }],
    },
    resolveProduct: resolve(f.businessId),
  });

  assert.equal(await stockOf(f.businessId, f.productId), 2);
  const slots = await slotsOf(f.businessId, f.productId);
  const at = (id) => slots.find((s) => s.locationId === id)?.quantity;
  assert.equal(at(large), 0, "the fullest shelf is emptied first");
  assert.equal(at(small), 2, "and the remainder comes off the other");

  // Each leg is its own ledger row, so the trail says which shelf gave what.
  const [[legs]] = await pool.query(
    `SELECT COUNT(*) AS n FROM inventory_movements
      WHERE reference_type = 'order' AND reference_id = ? AND quantity_after < quantity_before`,
    [orderId]
  );
  assert.equal(Number(legs.n), 2, "two shelves gave stock, so the ledger shows two movements");
});

test("§11: cancelling puts the goods back on the shelves they came off", async (t) => {
  if (!(await requireDatabase(t))) return;
  const f = await fixture({ stock: 0 });
  t.after(() => cleanup(f.businessId));

  const small = await shelf(f.businessId, f.warehouseId, "A-1");
  const large = await shelf(f.businessId, f.warehouseId, "B-2");
  for (const [locationId, delta] of [[small, 4], [large, 6]]) {
    await adjustStock({
      businessId: f.businessId,
      userId: f.userId,
      productId: f.productId,
      warehouseId: f.warehouseId,
      locationId,
      delta,
      movementType: "manual_increase",
    });
  }

  const { orderId } = await createOrder({
    businessId: f.businessId,
    userId: f.userId,
    data: {
      orderType: "quick_sale",
      status: "confirmed",
      items: [{ productId: f.productId, quantity: 8, unitPrice: 100 }],
    },
    resolveProduct: resolve(f.businessId),
  });

  const [[order]] = await pool.query(`SELECT * FROM orders WHERE id = ?`, [orderId]);
  await cancelOrder({
    businessId: f.businessId,
    userId: f.userId,
    order,
    reason: "Customer cancelled",
    items: toStockLines(await orderItems({ businessId: f.businessId, orderId })),
  });

  const slots = await slotsOf(f.businessId, f.productId);
  const at = (id) => slots.find((s) => s.locationId === id)?.quantity;
  assert.equal(at(large), 6, "6 came off B-2, so 6 go back to B-2");
  assert.equal(at(small), 4, "and 2 go back to A-1, where 2 came from");
  assert.equal(
    slots.filter((s) => s.locationId === null).length,
    0,
    "nothing may be dumped in the warehouse's location-less slot"
  );
});

test("§11: a warehouse that is short reports its OWN total, not one shelf's", async (t) => {
  if (!(await requireDatabase(t))) return;
  const f = await fixture({ stock: 0 });
  t.after(() => cleanup(f.businessId));

  for (const [name, delta] of [["A-1", 4], ["B-2", 3]]) {
    await adjustStock({
      businessId: f.businessId,
      userId: f.userId,
      productId: f.productId,
      warehouseId: f.warehouseId,
      locationId: await shelf(f.businessId, f.warehouseId, name),
      delta,
      movementType: "manual_increase",
    });
  }

  // 7 on hand across two shelves, 10 asked for. The refusal has to name 7 —
  // quoting one shelf's 4, or the location-less slot's 0, tells the business
  // something untrue about what it owns.
  await assert.rejects(
    () =>
      createOrder({
        businessId: f.businessId,
        userId: f.userId,
        data: {
          orderType: "quick_sale",
          status: "confirmed",
          items: [{ productId: f.productId, quantity: 10, unitPrice: 100 }],
        },
        resolveProduct: resolve(f.businessId),
      }),
    /Available quantity: 7/
  );

  assert.equal(await stockOf(f.businessId, f.productId), 7, "a refused sale moves nothing");
  const [[orders]] = await pool.query(`SELECT COUNT(*) AS n FROM orders WHERE business_id = ?`, [
    f.businessId,
  ]);
  assert.equal(Number(orders.n), 0, "and leaves no order behind");
});

after(async () => {
  await closePool();
});
