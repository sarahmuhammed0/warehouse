// §10/§11/§12/§47 against the real database.
//
// These are the rules that make stock trustworthy, so each is proven by
// making the system actually do the wrong thing and watching it refuse —
// not by asserting that a function was called.

import { test, after } from "node:test";
import assert from "node:assert/strict";

import { pool, closePool, runInTransaction } from "../../src/db/pool.js";
import { adjustStock, transferStock } from "../../src/modules/inventory/service.js";
import { createDefaultRoles } from "../../src/modules/rbac/repository.js";
import { requireDatabase, testPhone, cleanupTestData } from "./helpers.js";

/** A business with one product, two warehouses and a user, ready to move stock. */
async function fixture() {
  return runInTransaction(async (conn) => {
    const [b] = await conn.query(
      `INSERT INTO businesses (name, business_type, phone, status) VALUES (?, 'warehouse', ?, 'active')`,
      [`Inv ${Date.now()}-${Math.random().toString(36).slice(2, 6)}`, testPhone()]
    );
    const businessId = b.insertId;
    await createDefaultRoles(conn, businessId);

    const [u] = await conn.query(
      `INSERT INTO users (business_id, name, phone, password_hash, is_owner, status)
       VALUES (?, 'Stock User', ?, 'x', TRUE, 'active')`,
      [businessId, testPhone()]
    );
    const [p] = await conn.query(
      `INSERT INTO products (business_id, name, sku, reorder_level, status)
       VALUES (?, 'Test Product', ?, 5, 'active')`,
      [businessId, `SKU-${Date.now()}-${Math.random().toString(36).slice(2, 6)}`]
    );
    const [w1] = await conn.query(
      `INSERT INTO warehouses (business_id, name, location_type, status) VALUES (?, 'W1', 'warehouse', 'active')`,
      [businessId]
    );
    const [w2] = await conn.query(
      `INSERT INTO warehouses (business_id, name, location_type, status) VALUES (?, 'W2', 'warehouse', 'active')`,
      [businessId]
    );
    return {
      businessId,
      userId: u.insertId,
      productId: p.insertId,
      warehouseA: w1.insertId,
      warehouseB: w2.insertId,
    };
  });
}

async function cleanup(businessId) {
  if (!businessId) return;
  await pool.query(`DELETE FROM inventory_movements WHERE business_id = ?`, [businessId]);
  await pool.query(`DELETE FROM inventory WHERE business_id = ?`, [businessId]);
  await pool.query(`DELETE FROM products WHERE business_id = ?`, [businessId]);
  await pool.query(`DELETE FROM storage_locations WHERE business_id = ?`, [businessId]);
  await pool.query(`DELETE FROM warehouses WHERE business_id = ?`, [businessId]);
  const [users] = await pool.query(`SELECT id FROM users WHERE business_id = ?`, [businessId]);
  await cleanupTestData({ businessIds: [businessId], userIds: users.map((u) => u.id) });
}

const levelOf = async (businessId, productId, warehouseId) => {
  const [[row]] = await pool.query(
    `SELECT quantity FROM inventory WHERE business_id = ? AND product_id = ? AND warehouse_id = ?`,
    [businessId, productId, warehouseId]
  );
  return row ? Number(row.quantity) : 0;
};

const movementCount = async (businessId) =>
  Number((await pool.query(`SELECT COUNT(*) AS n FROM inventory_movements WHERE business_id = ?`, [businessId]))[0][0].n);

test("a stock change writes the level AND the ledger, together", async (t) => {
  if (!(await requireDatabase(t))) return;
  const f = await fixture();
  t.after(() => cleanup(f.businessId));

  await adjustStock({
    businessId: f.businessId,
    userId: f.userId,
    productId: f.productId,
    warehouseId: f.warehouseA,
    delta: 10,
    movementType: "manual_increase",
  });

  assert.equal(await levelOf(f.businessId, f.productId, f.warehouseA), 10);
  assert.equal(await movementCount(f.businessId), 1, "§12: every change is recorded");

  const [[m]] = await pool.query(
    `SELECT movement_type, quantity, quantity_before, quantity_after, user_id
       FROM inventory_movements WHERE business_id = ? ORDER BY id DESC LIMIT 1`,
    [f.businessId]
  );
  assert.equal(m.movement_type, "manual_increase");
  assert.equal(Number(m.quantity), 10, "the ledger stores a magnitude");
  assert.equal(Number(m.quantity_before), 0);
  assert.equal(Number(m.quantity_after), 10);
  assert.equal(m.user_id, f.userId, "§12 requires the user who moved it");
});

test("§47: stock cannot go negative unless the business enables it", async (t) => {
  if (!(await requireDatabase(t))) return;
  const f = await fixture();
  t.after(() => cleanup(f.businessId));

  await adjustStock({
    businessId: f.businessId,
    userId: f.userId,
    productId: f.productId,
    warehouseId: f.warehouseA,
    delta: 5,
    movementType: "manual_increase",
  });

  await assert.rejects(
    () =>
      adjustStock({
        businessId: f.businessId,
        userId: f.userId,
        productId: f.productId,
        warehouseId: f.warehouseA,
        delta: -8,
        movementType: "manual_decrease",
      }),
    (error) => error.statusCode === 409 && /Available quantity: 5/.test(error.message),
    "§47's own wording names what is actually available"
  );

  // And the refusal must change nothing at all — not the level, not the
  // ledger. A rejected movement that still wrote history would be worse
  // than one that silently succeeded.
  assert.equal(await levelOf(f.businessId, f.productId, f.warehouseA), 5);
  assert.equal(await movementCount(f.businessId), 1, "the refused movement must leave no trace");
});

test("§47: with the business setting enabled, negative stock is allowed", async (t) => {
  if (!(await requireDatabase(t))) return;
  const f = await fixture();
  t.after(() => cleanup(f.businessId));

  // The setting is the ONLY thing that changes here. If this passed without
  // it, the rule would be decorative; if it failed with it, §47's explicit
  // opt-in would be impossible.
  await pool.query(
    `INSERT INTO business_settings (business_id, setting_key, setting_value)
     VALUES (?, 'inventory.allow_negative_stock', CAST('true' AS JSON))`,
    [f.businessId]
  );

  await adjustStock({
    businessId: f.businessId,
    userId: f.userId,
    productId: f.productId,
    warehouseId: f.warehouseA,
    delta: -4,
    movementType: "manual_decrease",
  });

  assert.equal(await levelOf(f.businessId, f.productId, f.warehouseA), -4);
  await pool.query(`DELETE FROM business_settings WHERE business_id = ?`, [f.businessId]);
});

test("a transfer moves both legs, or neither", async (t) => {
  if (!(await requireDatabase(t))) return;
  const f = await fixture();
  t.after(() => cleanup(f.businessId));

  await adjustStock({
    businessId: f.businessId,
    userId: f.userId,
    productId: f.productId,
    warehouseId: f.warehouseA,
    delta: 10,
    movementType: "manual_increase",
  });

  await transferStock({
    businessId: f.businessId,
    userId: f.userId,
    productId: f.productId,
    fromWarehouseId: f.warehouseA,
    toWarehouseId: f.warehouseB,
    quantity: 4,
  });

  assert.equal(await levelOf(f.businessId, f.productId, f.warehouseA), 6);
  assert.equal(await levelOf(f.businessId, f.productId, f.warehouseB), 4);
  assert.equal(await movementCount(f.businessId), 3, "one in, one out, plus the opening increase");
});

test("a transfer that cannot complete leaves the source untouched", async (t) => {
  if (!(await requireDatabase(t))) return;
  const f = await fixture();
  t.after(() => cleanup(f.businessId));

  await adjustStock({
    businessId: f.businessId,
    userId: f.userId,
    productId: f.productId,
    warehouseId: f.warehouseA,
    delta: 3,
    movementType: "manual_increase",
  });

  // More than exists: the outbound leg must fail, and because both legs are
  // one transaction, nothing may be left half-moved.
  await assert.rejects(() =>
    transferStock({
      businessId: f.businessId,
      userId: f.userId,
      productId: f.productId,
      fromWarehouseId: f.warehouseA,
      toWarehouseId: f.warehouseB,
      quantity: 9,
    })
  );

  assert.equal(await levelOf(f.businessId, f.productId, f.warehouseA), 3, "source must be unchanged");
  assert.equal(await levelOf(f.businessId, f.productId, f.warehouseB), 0, "destination must be unchanged");
  assert.equal(await movementCount(f.businessId), 1, "no half-transfer may be recorded");
});

test("a transfer to the same place is refused", async (t) => {
  if (!(await requireDatabase(t))) return;
  const f = await fixture();
  t.after(() => cleanup(f.businessId));

  await assert.rejects(
    () =>
      transferStock({
        businessId: f.businessId,
        userId: f.userId,
        productId: f.productId,
        fromWarehouseId: f.warehouseA,
        toWarehouseId: f.warehouseA,
        quantity: 1,
      }),
    (error) => error.statusCode === 422
  );
});

test("movements are append-only — nothing deletes them", async (t) => {
  if (!(await requireDatabase(t))) return;
  const f = await fixture();
  t.after(() => cleanup(f.businessId));

  await adjustStock({
    businessId: f.businessId,
    userId: f.userId,
    productId: f.productId,
    warehouseId: f.warehouseA,
    delta: 7,
    movementType: "purchase",
  });
  await adjustStock({
    businessId: f.businessId,
    userId: f.userId,
    productId: f.productId,
    warehouseId: f.warehouseA,
    delta: -2,
    movementType: "sale",
  });

  // §12: "records should never silently disappear". The schema has no
  // deleted_at on this table, so the history cannot even be hidden.
  const [cols] = await pool.query(
    `SELECT COLUMN_NAME FROM information_schema.COLUMNS
      WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'inventory_movements' AND COLUMN_NAME = 'deleted_at'`
  );
  assert.equal(cols.length, 0, "the stock ledger must not be soft-deletable");
  assert.equal(await movementCount(f.businessId), 2);
});

test("a zero-quantity movement is refused", async (t) => {
  if (!(await requireDatabase(t))) return;
  const f = await fixture();
  t.after(() => cleanup(f.businessId));

  await assert.rejects(
    () =>
      adjustStock({
        businessId: f.businessId,
        userId: f.userId,
        productId: f.productId,
        warehouseId: f.warehouseA,
        delta: 0,
        movementType: "adjustment",
      }),
    (error) => error.statusCode === 422
  );
  assert.equal(await movementCount(f.businessId), 0);
});

test("stock is tracked per slot, not per product", async (t) => {
  if (!(await requireDatabase(t))) return;
  const f = await fixture();
  t.after(() => cleanup(f.businessId));

  // Ten in A and none in B does not mean ten are available in B. The whole
  // point of per-location stock is that "where" is part of the answer.
  await adjustStock({
    businessId: f.businessId,
    userId: f.userId,
    productId: f.productId,
    warehouseId: f.warehouseA,
    delta: 10,
    movementType: "manual_increase",
  });

  await assert.rejects(
    () =>
      adjustStock({
        businessId: f.businessId,
        userId: f.userId,
        productId: f.productId,
        warehouseId: f.warehouseB,
        delta: -1,
        movementType: "manual_decrease",
      }),
    (error) => error.statusCode === 409
  );
});

after(async () => {
  await closePool();
});
