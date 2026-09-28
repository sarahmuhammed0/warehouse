// §9 (product variants) and §11 (stock transfers as documents).
//
// Both are about stock being somewhere more specific than "this product, this
// business": a variant has its own level, and a transfer moves one slot's goods
// to another. The tests that matter are the ones where that specificity is easy
// to lose — a variant deleted with stock still against it, a transfer that moves
// its goods twice, or one that moves them when it was only written down.

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
      [`VarTr ${Date.now()}-${Math.random().toString(36).slice(2, 6)}`, testPhone()]
    );
    const businessId = b.insertId;
    await createDefaultRoles(conn, businessId);
    const roleId = await findOwnerRoleId(conn, businessId);

    const [u] = await conn.query(
      `INSERT INTO users (business_id, name, phone, password_hash, is_owner, role_id, status)
       VALUES (?, 'Owner', ?, 'x', TRUE, ?, 'active')`,
      [businessId, testPhone(), roleId]
    );
    const [north] = await conn.query(
      `INSERT INTO warehouses (business_id, name, location_type, is_default, status)
       VALUES (?, 'North', 'warehouse', TRUE, 'active')`,
      [businessId]
    );
    const [south] = await conn.query(
      `INSERT INTO warehouses (business_id, name, location_type, is_default, status)
       VALUES (?, 'South', 'warehouse', FALSE, 'active')`,
      [businessId]
    );
    const [shelf] = await conn.query(
      `INSERT INTO storage_locations (business_id, warehouse_id, name, status)
       VALUES (?, ?, 'A-1', 'active')`,
      [businessId, north.insertId]
    );
    const [p] = await conn.query(
      `INSERT INTO products (business_id, name, sku, selling_price, status)
       VALUES (?, 'T-Shirt', ?, 20, 'active')`,
      [businessId, `TS-${Date.now()}-${Math.random().toString(36).slice(2, 6)}`]
    );
    return {
      businessId,
      userId: u.insertId,
      north: north.insertId,
      south: south.insertId,
      shelf: shelf.insertId,
      productId: p.insertId,
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
    "stock_transfer_items",
    "stock_transfers",
    "inventory_movements",
    "inventory",
    "product_variants",
    "products",
    "document_sequences",
    "audit_logs",
    "business_settings",
    "storage_locations",
    "warehouses",
  ]) {
    await pool.query(`DELETE FROM ${table} WHERE business_id = ?`, [businessId]);
  }
  const [users] = await pool.query(`SELECT id FROM users WHERE business_id = ?`, [businessId]);
  await cleanupTestData({ businessIds: [businessId], userIds: users.map((u) => u.id) });
}

const auth = (req, token) => req.set("Authorization", `Bearer ${token}`);

const levelAt = async (f, { warehouseId, locationId = null, variantId = null }) => {
  const [rows] = await pool.query(
    `SELECT COALESCE(SUM(quantity), 0) AS q FROM inventory
      WHERE business_id = ? AND product_id = ? AND warehouse_id = ?
        AND COALESCE(location_id, 0) = COALESCE(?, 0)
        AND COALESCE(variant_id, 0) = COALESCE(?, 0)`,
    [f.businessId, f.productId, warehouseId, locationId, variantId]
  );
  return Number(rows[0].q);
};

// ---- §9: variants -------------------------------------------------------

const newVariant = (f, body = {}) =>
  auth(request(app).post(`/api/products/${f.productId}/variants`), f.token).send({
    name: "Large / Blue",
    sku: `TS-L-B-${Math.random().toString(36).slice(2, 7)}`,
    attributes: { size: "L", colour: "Blue" },
    sellingPrice: 22,
    ...body,
  });

test("§9: a product can have variants, each with its own price and attributes", async (t) => {
  if (!(await requireDatabase(t))) return;
  const f = await fixture();
  t.after(() => cleanup(f.businessId));

  const res = await newVariant(f);
  assert.equal(res.status, 201, JSON.stringify(res.body));
  const variant = res.body.data;
  assert.equal(variant.name, "Large / Blue");
  assert.equal(variant.sellingPrice, 22);
  assert.deepEqual(variant.attributes, { size: "L", colour: "Blue" }, "§9's size/colour/model");
  assert.equal(variant.status, "active");
  assert.equal(variant.quantity, 0, "a new variant holds no stock");

  await newVariant(f, { name: "Small / Red", attributes: { size: "S", colour: "Red" } });

  const list = await auth(request(app).get(`/api/products/${f.productId}/variants`), f.token).send();
  assert.equal(list.status, 200);
  assert.equal(list.body.data.length, 2);
  assert.deepEqual(
    list.body.data.map((v) => v.name).sort(),
    ["Large / Blue", "Small / Red"]
  );
});

test("§9: a variant holds its OWN stock, not the product's", async (t) => {
  if (!(await requireDatabase(t))) return;
  const f = await fixture();
  t.after(() => cleanup(f.businessId));

  const large = (await newVariant(f, { name: "Large" })).body.data;
  const small = (await newVariant(f, { name: "Small" })).body.data;

  // Stock into one variant only.
  await adjustStock({
    businessId: f.businessId,
    userId: f.userId,
    productId: f.productId,
    variantId: large.id,
    warehouseId: f.north,
    delta: 12,
    movementType: "manual_increase",
  });

  const list = await auth(request(app).get(`/api/products/${f.productId}/variants`), f.token).send();
  const byId = (id) => list.body.data.find((v) => String(v.id) === String(id));
  assert.equal(byId(large.id).quantity, 12);
  assert.equal(byId(small.id).quantity, 0, "the other size is a different shelf entirely");
});

test("a variant can be edited, including clearing its attributes", async (t) => {
  if (!(await requireDatabase(t))) return;
  const f = await fixture();
  t.after(() => cleanup(f.businessId));

  const created = (await newVariant(f)).body.data;
  const patched = await auth(
    request(app).patch(`/api/products/${f.productId}/variants/${created.id}`),
    f.token
  ).send({ name: "Extra Large / Blue", sellingPrice: 25, attributes: { size: "XL" } });

  assert.equal(patched.status, 200, JSON.stringify(patched.body));
  assert.equal(patched.body.data.name, "Extra Large / Blue");
  assert.equal(patched.body.data.sellingPrice, 25);
  assert.deepEqual(patched.body.data.attributes, { size: "XL" }, "replaced whole, not merged");

  const empty = await auth(request(app).patch(`/api/products/${f.productId}/variants/${created.id}`), f.token).send({});
  assert.equal(empty.status, 422, "a save with nothing in it is a client bug");
});

test("a variant still holding stock cannot be archived", async (t) => {
  if (!(await requireDatabase(t))) return;
  const f = await fixture();
  t.after(() => cleanup(f.businessId));

  const created = (await newVariant(f)).body.data;
  await adjustStock({
    businessId: f.businessId,
    userId: f.userId,
    productId: f.productId,
    variantId: created.id,
    warehouseId: f.north,
    delta: 4,
    movementType: "manual_increase",
  });

  const refused = await auth(
    request(app).delete(`/api/products/${f.productId}/variants/${created.id}`),
    f.token
  ).send();
  assert.equal(refused.status, 409, JSON.stringify(refused.body));
  assert.match(refused.body.error.message, /still holds 4 in stock/);

  // Write it off, and it can go.
  await adjustStock({
    businessId: f.businessId,
    userId: f.userId,
    productId: f.productId,
    variantId: created.id,
    warehouseId: f.north,
    delta: -4,
    movementType: "damage",
  });
  const removed = await auth(
    request(app).delete(`/api/products/${f.productId}/variants/${created.id}`),
    f.token
  ).send();
  assert.equal(removed.status, 200, JSON.stringify(removed.body));

  const [[row]] = await pool.query(`SELECT deleted_at, status FROM product_variants WHERE id = ?`, [
    created.id,
  ]);
  assert.ok(row.deleted_at, "§45: archived — movements still reference it");
  assert.equal(row.status, "inactive");

  const list = await auth(request(app).get(`/api/products/${f.productId}/variants`), f.token).send();
  assert.equal(list.body.data.length, 0);
});

test("variants are scoped to their product and their tenant", async (t) => {
  if (!(await requireDatabase(t))) return;
  const a = await fixture();
  const b = await fixture();
  t.after(() => Promise.all([cleanup(a.businessId), cleanup(b.businessId)]));

  const created = (await newVariant(a)).body.data;

  assert.equal(
    (await auth(request(app).get(`/api/products/${a.productId}/variants`), b.token).send()).status,
    404,
    "another tenant cannot even see the product"
  );
  assert.equal(
    (await auth(request(app).patch(`/api/products/${b.productId}/variants/${created.id}`), b.token).send({
      name: "Stolen",
    })).status,
    404,
    "nor reach the variant through its own product"
  );
  assert.equal(
    (await auth(request(app).post(`/api/products/99999999/variants`), a.token).send({ name: "X" })).status,
    404
  );
});

// ---- §11: transfers as documents ---------------------------------------

const newTransfer = (f, body = {}) =>
  auth(request(app).post("/api/stock-transfers"), f.token).send({
    fromWarehouseId: f.north,
    toWarehouseId: f.south,
    items: [{ productId: f.productId, quantity: 10 }],
    ...body,
  });

async function stockNorth(f, quantity = 50) {
  await adjustStock({
    businessId: f.businessId,
    userId: f.userId,
    productId: f.productId,
    warehouseId: f.north,
    delta: quantity,
    movementType: "manual_increase",
  });
}

test("§11: a transfer is raised without moving anything, and moves on arrival", async (t) => {
  if (!(await requireDatabase(t))) return;
  const f = await fixture();
  t.after(() => cleanup(f.businessId));
  await stockNorth(f);

  const created = await newTransfer(f);
  assert.equal(created.status, 201, JSON.stringify(created.body));
  const transfer = created.body.data;
  assert.match(transfer.transferNumber, /^TRF-/, "§29's numbering, with the transfer prefix");
  assert.equal(transfer.status, "pending", "written down, not yet moved");
  assert.equal(transfer.fromWarehouseName, "North");
  assert.equal(transfer.toWarehouseName, "South");
  assert.equal(transfer.itemCount, 1);

  assert.equal(await levelAt(f, { warehouseId: f.north }), 50, "raising a transfer moves nothing");
  assert.equal(await levelAt(f, { warehouseId: f.south }), 0);

  const travelling = await auth(
    request(app).patch(`/api/stock-transfers/${transfer.id}/status`),
    f.token
  ).send({ status: "in_transit" });
  assert.equal(travelling.status, 200, JSON.stringify(travelling.body));
  assert.equal(
    await levelAt(f, { warehouseId: f.north }),
    50,
    "in transit is a document state, not a stock state — the goods are still the source's"
  );

  const arrived = await auth(
    request(app).patch(`/api/stock-transfers/${transfer.id}/status`),
    f.token
  ).send({ status: "completed" });
  assert.equal(arrived.status, 200, JSON.stringify(arrived.body));
  assert.ok(arrived.body.data.completedAt);

  assert.equal(await levelAt(f, { warehouseId: f.north }), 40);
  assert.equal(await levelAt(f, { warehouseId: f.south }), 10);

  // §12: both legs are in the ledger, and name the document.
  const [movements] = await pool.query(
    `SELECT warehouse_id, movement_type, quantity, reference_type, reference_number
       FROM inventory_movements
      WHERE business_id = ? AND reference_type = 'transfer' ORDER BY id`,
    [f.businessId]
  );
  assert.equal(movements.length, 2, "one out, one in");
  assert.ok(movements.every((m) => m.movement_type === "transfer"));
  assert.ok(movements.every((m) => m.reference_number === transfer.transferNumber));
});

test("§11: a transfer can be recorded as already done, moving stock at once", async (t) => {
  if (!(await requireDatabase(t))) return;
  const f = await fixture();
  t.after(() => cleanup(f.businessId));
  await stockNorth(f);

  const created = await newTransfer(f, { status: "completed" });
  assert.equal(created.status, 201, JSON.stringify(created.body));
  assert.equal(created.body.data.status, "completed");
  assert.equal(await levelAt(f, { warehouseId: f.north }), 40);
  assert.equal(await levelAt(f, { warehouseId: f.south }), 10);
});

test("§11: a transfer can move stock onto a shelf inside the same warehouse", async (t) => {
  if (!(await requireDatabase(t))) return;
  const f = await fixture();
  t.after(() => cleanup(f.businessId));
  await stockNorth(f, 20);

  const created = await newTransfer(f, {
    toWarehouseId: f.north,
    toLocationId: f.shelf,
    items: [{ productId: f.productId, quantity: 8 }],
    status: "completed",
  });
  assert.equal(created.status, 201, JSON.stringify(created.body));
  assert.equal(created.body.data.toLocationName, "A-1");

  assert.equal(await levelAt(f, { warehouseId: f.north, locationId: null }), 12);
  assert.equal(await levelAt(f, { warehouseId: f.north, locationId: f.shelf }), 8);
});

test("completing a transfer twice does not move the goods twice", async (t) => {
  if (!(await requireDatabase(t))) return;
  const f = await fixture();
  t.after(() => cleanup(f.businessId));
  await stockNorth(f);

  const created = await newTransfer(f);
  const complete = () =>
    auth(request(app).patch(`/api/stock-transfers/${created.body.data.id}/status`), f.token).send({
      status: "completed",
    });

  assert.equal((await complete()).status, 200);
  assert.ok((await complete()).status >= 400, "the second completion must be refused");
  assert.equal(await levelAt(f, { warehouseId: f.south }), 10, "10 moved, once");
});

test("two simultaneous completions move the goods once", async (t) => {
  if (!(await requireDatabase(t))) return;
  const f = await fixture();
  t.after(() => cleanup(f.businessId));
  await stockNorth(f);

  const created = await newTransfer(f);
  const complete = () =>
    auth(request(app).patch(`/api/stock-transfers/${created.body.data.id}/status`), f.token).send({
      status: "completed",
    });

  const [a, b] = await Promise.all([complete(), complete()]);
  const statuses = [a.status, b.status].sort();
  assert.equal(statuses[0], 200, "one should succeed");
  assert.ok(statuses[1] >= 400, `the other must not, got ${statuses[1]}`);
  assert.equal(await levelAt(f, { warehouseId: f.south }), 10);
  assert.equal(await levelAt(f, { warehouseId: f.north }), 40);
});

test("§47: a transfer of stock the source does not have is refused, and moves nothing", async (t) => {
  if (!(await requireDatabase(t))) return;
  const f = await fixture();
  t.after(() => cleanup(f.businessId));
  await stockNorth(f, 5);

  const created = await newTransfer(f, { items: [{ productId: f.productId, quantity: 10 }] });
  const arrived = await auth(
    request(app).patch(`/api/stock-transfers/${created.body.data.id}/status`),
    f.token
  ).send({ status: "completed" });

  assert.equal(arrived.status, 409, JSON.stringify(arrived.body));
  assert.match(arrived.body.error.message, /Insufficient stock/);
  assert.equal(await levelAt(f, { warehouseId: f.north }), 5, "the source is untouched");
  assert.equal(await levelAt(f, { warehouseId: f.south }), 0, "and nothing arrived");

  const [[still]] = await pool.query(`SELECT status FROM stock_transfers WHERE id = ?`, [
    created.body.data.id,
  ]);
  assert.equal(still.status, "pending", "a refused arrival leaves the document where it was");
});

test("a cancelled transfer moves nothing, and is terminal", async (t) => {
  if (!(await requireDatabase(t))) return;
  const f = await fixture();
  t.after(() => cleanup(f.businessId));
  await stockNorth(f);

  const created = await newTransfer(f);
  const id = created.body.data.id;

  const cancelled = await auth(request(app).patch(`/api/stock-transfers/${id}/status`), f.token).send({
    status: "cancelled",
  });
  assert.equal(cancelled.status, 200, JSON.stringify(cancelled.body));
  assert.equal(await levelAt(f, { warehouseId: f.north }), 50);

  const revive = await auth(request(app).patch(`/api/stock-transfers/${id}/status`), f.token).send({
    status: "completed",
  });
  assert.equal(revive.status, 409, "a cancelled transfer stays cancelled");
  assert.equal(await levelAt(f, { warehouseId: f.south }), 0);
});

test("a completed transfer cannot be un-completed", async (t) => {
  if (!(await requireDatabase(t))) return;
  const f = await fixture();
  t.after(() => cleanup(f.businessId));
  await stockNorth(f);

  const created = await newTransfer(f, { status: "completed" });
  const back = await auth(
    request(app).patch(`/api/stock-transfers/${created.body.data.id}/status`),
    f.token
  ).send({ status: "pending" });

  assert.equal(back.status, 409, "the goods are on the destination shelf — undo is a new transfer");
  assert.equal(await levelAt(f, { warehouseId: f.south }), 10);
});

test("a transfer to the same slot, with no items, or naming a stranger is refused", async (t) => {
  if (!(await requireDatabase(t))) return;
  const a = await fixture();
  const b = await fixture();
  t.after(() => Promise.all([cleanup(a.businessId), cleanup(b.businessId)]));
  await stockNorth(a);

  const same = await newTransfer(a, { toWarehouseId: a.north });
  assert.equal(same.status, 422, JSON.stringify(same.body));
  assert.match(same.body.error.message, /same location/i);

  assert.equal((await newTransfer(a, { items: [] })).status, 422);
  assert.equal((await newTransfer(a, { items: [{ productId: a.productId, quantity: 0 }] })).status, 422);
  assert.equal((await newTransfer(a, { toWarehouseId: 99999999 })).status, 422);

  // §36: another tenant's warehouse and product are both refused.
  assert.equal((await newTransfer(a, { toWarehouseId: b.south })).status, 422);
  assert.equal(
    (await newTransfer(a, { items: [{ productId: b.productId, quantity: 1 }] })).status,
    422
  );

  const [[left]] = await pool.query(`SELECT COUNT(*) AS n FROM stock_transfers WHERE business_id = ?`, [
    a.businessId,
  ]);
  assert.equal(Number(left.n), 0, "nothing refused is half-written");
});

test("transfers list, filter and tenant scope", async (t) => {
  if (!(await requireDatabase(t))) return;
  const a = await fixture();
  const b = await fixture();
  t.after(() => Promise.all([cleanup(a.businessId), cleanup(b.businessId)]));
  await stockNorth(a);

  await newTransfer(a);
  await newTransfer(a, { status: "completed", items: [{ productId: a.productId, quantity: 1 }] });

  const all = await auth(request(app).get("/api/stock-transfers?pageSize=10"), a.token).send();
  assert.equal(all.status, 200);
  assert.equal(all.body.data.length, 2);
  assert.ok(Number.isInteger(all.body.meta.pagination.total));

  const completed = await auth(request(app).get("/api/stock-transfers?status=completed"), a.token).send();
  assert.equal(completed.body.data.length, 1);

  const fromNorth = await auth(
    request(app).get(`/api/stock-transfers?fromWarehouseId=${a.north}`),
    a.token
  ).send();
  assert.equal(fromNorth.body.data.length, 2);

  // §36
  const other = await auth(request(app).get("/api/stock-transfers"), b.token).send();
  assert.equal(other.body.data.length, 0);
  assert.equal(
    (await auth(request(app).get(`/api/stock-transfers/${all.body.data[0].id}`), b.token).send()).status,
    404
  );
  assert.equal(
    (await auth(request(app).patch(`/api/stock-transfers/${all.body.data[0].id}/status`), b.token).send({
      status: "completed",
    })).status,
    404
  );
});

test("§30: a transfer and its arrival are both in the activity trail", async (t) => {
  if (!(await requireDatabase(t))) return;
  const f = await fixture();
  t.after(() => cleanup(f.businessId));
  await stockNorth(f);

  const created = await newTransfer(f);
  await auth(request(app).patch(`/api/stock-transfers/${created.body.data.id}/status`), f.token).send({
    status: "completed",
  });

  let rows = [];
  for (let i = 0; i < 60; i += 1) {
    const [found] = await pool.query(
      `SELECT action, actor_id FROM audit_logs WHERE business_id = ? AND module = 'inventory' ORDER BY id`,
      [f.businessId]
    );
    rows = found;
    if (rows.length >= 2) break;
    await new Promise((resolve) => setTimeout(resolve, 25));
  }

  const actions = rows.map((r) => r.action);
  assert.ok(actions.includes("inventory.create"), actions.join(", "));
  assert.ok(actions.includes("inventory.update"), actions.join(", "));
  assert.ok(rows.every((r) => Number(r.actor_id) === f.userId));
});

after(() => closePool());
