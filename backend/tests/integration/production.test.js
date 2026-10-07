// §21 (bill of materials, raw materials) and §22 (production orders, history).
//
// A production run is the only place stock moves in both directions at once, so
// these prove the two halves cannot come apart: materials consumed without goods
// produced, goods produced out of materials the factory did not have, a recipe
// edit that rewrites what a past run consumed, or a run that makes its output
// twice because two people pressed Complete.

import { test, after } from "node:test";
import assert from "node:assert/strict";
import request from "supertest";

import { app } from "../../src/app.js";
import { pool, closePool, runInTransaction } from "../../src/db/pool.js";
import { createDefaultRoles, findOwnerRoleId } from "../../src/modules/rbac/repository.js";
import { adjustStock } from "../../src/modules/inventory/service.js";
import { signAccessToken } from "../../src/utils/token.js";
import { requireDatabase, testPhone, cleanupTestData } from "./helpers.js";

/**
 * A furniture factory: a finished good (Table), two raw materials (Wood, Paint),
 * a warehouse and a shelf. §21's raw materials ARE products, so they are rows in
 * the same table — which is the decision these tests exercise.
 */
async function fixture({ wood = 100, paint = 50, onShelf = false } = {}) {
  const f = await runInTransaction(async (conn) => {
    const [b] = await conn.query(
      `INSERT INTO businesses (name, business_type, phone, status) VALUES (?, 'furniture_factory', ?, 'active')`,
      [`Prod ${Date.now()}-${Math.random().toString(36).slice(2, 6)}`, testPhone()]
    );
    const businessId = b.insertId;
    await createDefaultRoles(conn, businessId);
    const roleId = await findOwnerRoleId(conn, businessId);

    const [u] = await conn.query(
      `INSERT INTO users (business_id, name, phone, password_hash, is_owner, role_id, status)
       VALUES (?, 'Foreman', ?, 'x', TRUE, ?, 'active')`,
      [businessId, testPhone(), roleId]
    );
    const [unit] = await conn.query(
      `INSERT INTO units (business_id, name, code, decimal_places) VALUES (?, 'Piece', ?, 0)`,
      [businessId, `pc${Math.random().toString(36).slice(2, 6)}`]
    );
    const [w] = await conn.query(
      `INSERT INTO warehouses (business_id, name, location_type, is_default, status)
       VALUES (?, 'Factory', 'warehouse', TRUE, 'active')`,
      [businessId]
    );
    const [l] = await conn.query(
      `INSERT INTO storage_locations (business_id, warehouse_id, name, status)
       VALUES (?, ?, 'R-1', 'active')`,
      [businessId, w.insertId]
    );

    const product = async (name, type, cost) => {
      const [row] = await conn.query(
        `INSERT INTO products (business_id, name, sku, product_type, unit_id, purchase_cost, selling_price, status)
         VALUES (?, ?, ?, ?, ?, ?, ?, 'active')`,
        [
          businessId,
          name,
          `${name}-${Date.now()}-${Math.random().toString(36).slice(2, 6)}`,
          type,
          unit.insertId,
          cost,
          cost * 3,
        ]
      );
      return row.insertId;
    };

    return {
      businessId,
      userId: u.insertId,
      unitId: unit.insertId,
      warehouseId: w.insertId,
      locationId: l.insertId,
      tableId: await product("Table", "finished_good", 40),
      woodId: await product("Wood", "raw_material", 5),
      paintId: await product("Paint", "raw_material", 2),
    };
  });

  for (const [productId, delta] of [
    [f.woodId, wood],
    [f.paintId, paint],
  ]) {
    if (delta > 0) {
      await adjustStock({
        businessId: f.businessId,
        userId: f.userId,
        productId,
        warehouseId: f.warehouseId,
        locationId: onShelf ? f.locationId : null,
        delta,
        movementType: "manual_increase",
      });
    }
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
    `DELETE FROM production_items WHERE business_id = ?`,
    `DELETE FROM production_orders WHERE business_id = ?`,
    `DELETE FROM bill_of_materials WHERE business_id = ?`,
    `DELETE FROM order_items WHERE business_id = ?`,
    `DELETE FROM orders WHERE business_id = ?`,
    `DELETE FROM inventory_movements WHERE business_id = ?`,
    `DELETE FROM inventory WHERE business_id = ?`,
    `DELETE FROM document_sequences WHERE business_id = ?`,
    `DELETE FROM audit_logs WHERE business_id = ?`,
    `DELETE FROM products WHERE business_id = ?`,
    `DELETE FROM units WHERE business_id = ?`,
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

/** Table = 5 Wood + 2 Paint, per unit (§21's own kind of example). */
const putBom = (f, lines) =>
  auth(request(app).put(`/api/products/${f.tableId}/bom`), f.token).send({
    lines:
      lines ?? [
        { materialProductId: f.woodId, quantityPerUnit: 5 },
        { materialProductId: f.paintId, quantityPerUnit: 2 },
      ],
  });

const newRun = (f, body = {}) =>
  auth(request(app).post("/api/production-orders"), f.token).send({
    productId: f.tableId,
    quantityPlanned: 10,
    ...body,
  });

const setStatus = (f, id, body) =>
  auth(request(app).patch(`/api/production-orders/${id}/status`), f.token).send(body);

// ---- §21's bill of materials -------------------------------------------

test("§21: a product's bill of materials can be set and read back", async (t) => {
  if (!(await requireDatabase(t))) return;
  const f = await fixture();
  t.after(() => cleanup(f.businessId));

  const empty = await auth(request(app).get(`/api/products/${f.tableId}/bom`), f.token).send();
  assert.equal(empty.status, 200, JSON.stringify(empty.body));
  assert.deepEqual(empty.body.data.lines, [], "a product starts with no recipe");

  const saved = await putBom(f);
  assert.equal(saved.status, 200, JSON.stringify(saved.body));
  assert.equal(saved.body.data.lines.length, 2);

  const wood = saved.body.data.lines.find((l) => l.materialProductId === f.woodId);
  assert.equal(wood.quantityPerUnit, 5);
  assert.equal(wood.materialProductName, "Wood");
  assert.equal(wood.unitCode !== null, true, "§21's example weighs materials in their own units");

  const read = await auth(request(app).get(`/api/products/${f.tableId}/bom`), f.token).send();
  assert.equal(read.body.data.lines.length, 2);
});

test("§21: replacing a recipe replaces it whole, and can empty it", async (t) => {
  if (!(await requireDatabase(t))) return;
  const f = await fixture();
  t.after(() => cleanup(f.businessId));

  await putBom(f);
  const fewer = await putBom(f, [{ materialProductId: f.woodId, quantityPerUnit: 8 }]);
  assert.equal(fewer.body.data.lines.length, 1, "the paint is gone, not merged");
  assert.equal(fewer.body.data.lines[0].quantityPerUnit, 8);

  const cleared = await putBom(f, []);
  assert.equal(cleared.status, 200);
  assert.deepEqual(cleared.body.data.lines, [], "clearing a recipe is a real edit");
});

test("a recipe cannot contain the product itself, a duplicate, or a stranger", async (t) => {
  if (!(await requireDatabase(t))) return;
  const f = await fixture();
  t.after(() => cleanup(f.businessId));

  const itself = await putBom(f, [{ materialProductId: f.tableId, quantityPerUnit: 1 }]);
  assert.equal(itself.status, 422, JSON.stringify(itself.body));
  assert.match(itself.body.error.message, /out of itself/);

  const twice = await putBom(f, [
    { materialProductId: f.woodId, quantityPerUnit: 1 },
    { materialProductId: f.woodId, quantityPerUnit: 2 },
  ]);
  assert.equal(twice.status, 422, JSON.stringify(twice.body));

  const stranger = await putBom(f, [{ materialProductId: 99999999, quantityPerUnit: 1 }]);
  assert.equal(stranger.status, 422);

  const [[left]] = await pool.query(
    `SELECT COUNT(*) AS n FROM bill_of_materials WHERE business_id = ? AND deleted_at IS NULL`,
    [f.businessId]
  );
  assert.equal(Number(left.n), 0, "a refused recipe is not half-saved");
});

// ---- §22's production orders -------------------------------------------

test("§22: a run takes its materials from the recipe, scaled to the batch", async (t) => {
  if (!(await requireDatabase(t))) return;
  const f = await fixture();
  t.after(() => cleanup(f.businessId));
  await putBom(f);

  const res = await newRun(f, { quantityPlanned: 10, batchNumber: "B-1" });

  assert.equal(res.status, 201, JSON.stringify(res.body));
  const run = res.body.data;
  assert.equal(run.status, "planned");
  assert.match(run.productionNumber, /^PRD-/, "§29's numbering, with the production prefix");
  assert.equal(run.quantityPlanned, 10);
  assert.equal(run.quantityProduced, 0, "nothing made yet");
  assert.equal(run.batchNumber, "B-1");
  assert.equal(run.materials.length, 2);

  const wood = run.materials.find((m) => m.materialProductId === f.woodId);
  assert.equal(wood.quantityRequired, 50, "5 per table x 10 tables");
  assert.equal(wood.quantityConsumed, 0);
  assert.equal(wood.unitCost, 5, "§22's cost tracking snapshots what the material costs today");

  // 50 wood at 5 + 20 paint at 2 = 290.
  assert.equal(run.productionCost, 290, "the estimate before the run happens");
  assert.equal(await stockOf(f.businessId, f.woodId), 100, "planning consumes nothing");
});

test("§22: a run can carry its own materials, substituting the recipe", async (t) => {
  if (!(await requireDatabase(t))) return;
  const f = await fixture();
  t.after(() => cleanup(f.businessId));
  await putBom(f);

  const res = await newRun(f, {
    quantityPlanned: 2,
    materials: [{ materialProductId: f.woodId, quantityRequired: 7 }],
  });

  assert.equal(res.status, 201, JSON.stringify(res.body));
  assert.equal(res.body.data.materials.length, 1, "the operator's list wins over the recipe");
  assert.equal(res.body.data.materials[0].quantityRequired, 7);
});

test("§22: a run can be assigned to someone, and reads back who", async (t) => {
  // The client's Employee field used to be a free-typed name that
  // `ApiProductionRepository.create` left out of the request entirely, so every
  // run was created unassigned however carefully the box was filled in. It now
  // sends `assignedUserId`, which is what this proves the server takes and
  // gives back — the contract that change depends on.
  if (!(await requireDatabase(t))) return;
  const f = await fixture();
  t.after(() => cleanup(f.businessId));
  await putBom(f);

  const res = await newRun(f, { quantityPlanned: 1, assignedUserId: f.userId });

  assert.equal(res.status, 201, JSON.stringify(res.body));
  assert.equal(res.body.data.assignedUserId, f.userId);
  assert.equal(res.body.data.assignedUserName, "Foreman", "the name comes from the join, not the request");

  // And it survives a re-read, rather than only being echoed by the create.
  const again = await auth(request(app).get(`/api/production-orders/${res.body.data.id}`), f.token);
  assert.equal(again.status, 200);
  assert.equal(again.body.data.assignedUserName, "Foreman");
});

test("a run cannot be assigned to somebody from another factory", async (t) => {
  // `assignedUserId` is an id the client now chooses, so it is worth knowing it
  // is scoped (§36) rather than trusted.
  if (!(await requireDatabase(t))) return;
  const [a, b] = [await fixture(), await fixture()];
  t.after(() => cleanup(a.businessId));
  t.after(() => cleanup(b.businessId));
  await putBom(a);

  const res = await newRun(a, { quantityPlanned: 1, assignedUserId: b.userId });

  assert.ok(res.status >= 400, `a stranger's id must not be accepted (got ${res.status})`);
});

test("a run cannot draw from another factory's warehouse", async (t) => {
  // The same hole as `assignedUserId`, in the field next to it: every material
  // on a run is checked against the tenant, and `warehouseId` was taken raw.
  // Accepting it would have moved one factory's stock on another's instruction.
  if (!(await requireDatabase(t))) return;
  const [a, b] = [await fixture(), await fixture()];
  t.after(() => cleanup(a.businessId));
  t.after(() => cleanup(b.businessId));
  await putBom(a);

  const res = await newRun(a, { quantityPlanned: 1, warehouseId: b.warehouseId });

  assert.ok(res.status >= 400, `a stranger's warehouse must not be accepted (got ${res.status})`);
});

test("§21's recipe is optional — a product with no bill of materials can still be produced", async (t) => {
  // This used to be refused with "has no bill of materials ... Add one first".
  // That made the recipe a precondition of a run, which it is not, and it was a
  // dead end: nothing in the application writes a bill of materials, so a new
  // business could never produce anything.
  if (!(await requireDatabase(t))) return;
  const f = await fixture();
  t.after(() => cleanup(f.businessId));

  const res = await newRun(f, { quantityPlanned: 3 });

  assert.equal(res.status, 201, JSON.stringify(res.body));
  assert.equal(res.body.data.materials.length, 0, "nothing is invented to fill the gap");
  assert.equal(
    res.body.data.productionCost,
    null,
    "cost is UNKNOWN rather than zero — nothing was costed, which is not the same as free"
  );
});

test("§22: a run with no materials makes the goods and consumes nothing", async (t) => {
  // The other half: allowing the run is only useful if completing it works.
  if (!(await requireDatabase(t))) return;
  const f = await fixture();
  t.after(() => cleanup(f.businessId));

  const created = await newRun(f, { quantityPlanned: 4 });
  assert.equal(created.status, 201, JSON.stringify(created.body));

  const before = { wood: await stockOf(f.businessId, f.woodId), table: await stockOf(f.businessId, f.tableId) };
  const done = await setStatus(f, created.body.data.id, { status: "completed" });

  assert.equal(done.status, 200, JSON.stringify(done.body));
  assert.equal(await stockOf(f.businessId, f.tableId), before.table + 4, "the finished goods exist");
  assert.equal(await stockOf(f.businessId, f.woodId), before.wood, "and nothing was taken for them");
});

test("a run cannot be made of itself, of a stranger, or of nothing", async (t) => {
  if (!(await requireDatabase(t))) return;
  const f = await fixture();
  t.after(() => cleanup(f.businessId));

  const itself = await newRun(f, { materials: [{ materialProductId: f.tableId, quantityRequired: 1 }] });
  assert.equal(itself.status, 422);
  assert.match(itself.body.error.message, /out of itself/);

  const stranger = await newRun(f, { materials: [{ materialProductId: 99999999, quantityRequired: 1 }] });
  assert.equal(stranger.status, 422);

  assert.equal((await newRun(f, { productId: 99999999 })).status, 422);
  assert.equal((await newRun(f, { quantityPlanned: 0 })).status, 422);
});

test("§22: completing a run consumes the materials and makes the goods, together", async (t) => {
  if (!(await requireDatabase(t))) return;
  const f = await fixture();
  t.after(() => cleanup(f.businessId));
  await putBom(f);

  const run = await newRun(f, { quantityPlanned: 10 });
  const id = run.body.data.id;

  assert.equal((await setStatus(f, id, { status: "in_progress" })).status, 200);
  assert.equal(await stockOf(f.businessId, f.woodId), 100, "starting work consumes nothing either");

  const done = await setStatus(f, id, { status: "completed" });
  assert.equal(done.status, 200, JSON.stringify(done.body));

  assert.equal(await stockOf(f.businessId, f.woodId), 50, "100 - 50");
  assert.equal(await stockOf(f.businessId, f.paintId), 30, "50 - 20");
  assert.equal(await stockOf(f.businessId, f.tableId), 10, "and ten tables now exist");

  assert.equal(done.body.data.status, "completed");
  assert.equal(done.body.data.quantityProduced, 10);
  assert.equal(done.body.data.productionCost, 290, "§22: what the batch cost to make");
  assert.ok(done.body.data.startedAt, "§22's history: when it started");
  assert.ok(done.body.data.completedAt, "and when it finished");
  assert.equal(
    done.body.data.materials.find((m) => m.materialProductId === f.woodId).quantityConsumed,
    50,
    "the run records what it actually used"
  );

  // §12: every leg is in the ledger, and says which run caused it.
  const [movements] = await pool.query(
    `SELECT product_id, movement_type, quantity, quantity_before, quantity_after, reference_number
       FROM inventory_movements
      WHERE business_id = ? AND reference_type = 'production' ORDER BY id`,
    [f.businessId]
  );
  assert.equal(movements.length, 3, "two materials out, one product in");
  assert.ok(movements.every((m) => m.movement_type === "production"));
  assert.ok(movements.every((m) => m.reference_number === run.body.data.productionNumber));
  const made = movements.find((m) => Number(m.product_id) === f.tableId);
  assert.equal(Number(made.quantity_before), 0);
  assert.equal(Number(made.quantity_after), 10);
});

test("§22: a batch that yields less than planned records what it made", async (t) => {
  if (!(await requireDatabase(t))) return;
  const f = await fixture();
  t.after(() => cleanup(f.businessId));
  await putBom(f);

  const run = await newRun(f, { quantityPlanned: 10 });
  const done = await setStatus(f, run.body.data.id, { status: "completed", quantityProduced: 8 });

  assert.equal(done.status, 200, JSON.stringify(done.body));
  assert.equal(done.body.data.quantityPlanned, 10);
  assert.equal(done.body.data.quantityProduced, 8, "§22 keeps the two apart for a reason");
  assert.equal(await stockOf(f.businessId, f.tableId), 8, "eight tables exist, not ten");
  assert.equal(
    await stockOf(f.businessId, f.woodId),
    50,
    "and the wood issued to the batch was still cut"
  );
});

test("§22: a run the factory has no materials for is refused, and makes nothing", async (t) => {
  if (!(await requireDatabase(t))) return;
  const f = await fixture({ wood: 10, paint: 50 });
  t.after(() => cleanup(f.businessId));
  await putBom(f);

  // 10 tables need 50 wood; there are 10.
  const run = await newRun(f, { quantityPlanned: 10 });
  const done = await setStatus(f, run.body.data.id, { status: "completed" });

  assert.equal(done.status, 409, JSON.stringify(done.body));
  assert.match(done.body.error.message, /Insufficient stock/);

  assert.equal(await stockOf(f.businessId, f.woodId), 10, "the wood is untouched");
  assert.equal(await stockOf(f.businessId, f.paintId), 50, "the paint too — not half-consumed");
  assert.equal(await stockOf(f.businessId, f.tableId), 0, "and no table was conjured out of nothing");

  const [[still]] = await pool.query(`SELECT status FROM production_orders WHERE id = ?`, [
    run.body.data.id,
  ]);
  assert.equal(still.status, "planned", "a refused run stays where it was");
});

test("§22: materials come off the shelves that hold them (§11)", async (t) => {
  if (!(await requireDatabase(t))) return;
  const f = await fixture({ onShelf: true });
  t.after(() => cleanup(f.businessId));
  await putBom(f);

  const run = await newRun(f, { quantityPlanned: 10 });
  const done = await setStatus(f, run.body.data.id, { status: "completed" });

  assert.equal(done.status, 200, JSON.stringify(done.body));
  const [rows] = await pool.query(
    `SELECT product_id, location_id, quantity FROM inventory WHERE business_id = ? ORDER BY id`,
    [f.businessId]
  );
  const wood = rows.find((r) => Number(r.product_id) === f.woodId && r.location_id === f.locationId);
  assert.equal(Number(wood.quantity), 50, "taken off R-1, where the wood actually was");
  assert.equal(await stockOf(f.businessId, f.tableId), 10);
});

test("completing a run twice does not make the goods twice", async (t) => {
  if (!(await requireDatabase(t))) return;
  const f = await fixture();
  t.after(() => cleanup(f.businessId));
  await putBom(f);

  const run = await newRun(f, { quantityPlanned: 5 });
  const id = run.body.data.id;

  assert.equal((await setStatus(f, id, { status: "completed" })).status, 200);
  const second = await setStatus(f, id, { status: "completed" });
  assert.ok(second.status >= 400, `the second completion must be refused, got ${second.status}`);

  assert.equal(await stockOf(f.businessId, f.tableId), 5, "five tables, once");
  assert.equal(await stockOf(f.businessId, f.woodId), 75, "and the wood was cut once");
});

test("two simultaneous completions produce the batch once", async (t) => {
  if (!(await requireDatabase(t))) return;
  const f = await fixture();
  t.after(() => cleanup(f.businessId));
  await putBom(f);

  const run = await newRun(f, { quantityPlanned: 5 });
  const complete = () => setStatus(f, run.body.data.id, { status: "completed" });

  const [a, b] = await Promise.all([complete(), complete()]);
  const statuses = [a.status, b.status].sort();
  assert.equal(statuses[0], 200, "one completion should succeed");
  assert.ok(statuses[1] >= 400, `the other must not, got ${statuses[1]}`);

  assert.equal(await stockOf(f.businessId, f.tableId), 5);
  assert.equal(await stockOf(f.businessId, f.woodId), 75);
});

test("§22: cancelling an unfinished run leaves stock alone; a finished one is closed", async (t) => {
  if (!(await requireDatabase(t))) return;
  const f = await fixture();
  t.after(() => cleanup(f.businessId));
  await putBom(f);

  const planned = await newRun(f, { quantityPlanned: 5 });
  const cancelled = await setStatus(f, planned.body.data.id, { status: "cancelled" });
  assert.equal(cancelled.status, 200);
  assert.equal(await stockOf(f.businessId, f.woodId), 100, "nothing had been consumed to give back");
  assert.equal(
    (await setStatus(f, planned.body.data.id, { status: "completed" })).status,
    409,
    "a cancelled run is terminal"
  );

  const finished = await newRun(f, { quantityPlanned: 5 });
  await setStatus(f, finished.body.data.id, { status: "completed" });
  const undo = await setStatus(f, finished.body.data.id, { status: "cancelled" });
  assert.equal(undo.status, 409, "goods that exist cannot be un-made");
  assert.equal(await stockOf(f.businessId, f.tableId), 5);
});

test("§21: editing the recipe does not rewrite what a past run consumed", async (t) => {
  if (!(await requireDatabase(t))) return;
  const f = await fixture();
  t.after(() => cleanup(f.businessId));
  await putBom(f);

  const run = await newRun(f, { quantityPlanned: 2 });
  await setStatus(f, run.body.data.id, { status: "completed" });

  // The recipe changes: tables now take 9 wood each.
  await putBom(f, [{ materialProductId: f.woodId, quantityPerUnit: 9 }]);

  const past = await auth(
    request(app).get(`/api/production-orders/${run.body.data.id}`),
    f.token
  ).send();
  const wood = past.body.data.materials.find((m) => m.materialProductId === f.woodId);
  assert.equal(wood.quantityRequired, 10, "2 tables x the 5 the recipe said AT THE TIME");
  assert.equal(wood.quantityConsumed, 10);
  assert.equal(past.body.data.materials.length, 2, "and the paint it used is still on the record");
});

test("a run needs a warehouse to draw from and put into", async (t) => {
  if (!(await requireDatabase(t))) return;
  const f = await fixture();
  t.after(() => cleanup(f.businessId));
  await putBom(f);

  await pool.query(`UPDATE warehouses SET is_default = FALSE WHERE business_id = ?`, [f.businessId]);
  const res = await newRun(f, { quantityPlanned: 1 });
  assert.equal(res.status, 422, JSON.stringify(res.body));
  assert.match(res.body.error.message, /default warehouse/i);

  // Naming one explicitly works even with no default set.
  const named = await newRun(f, { quantityPlanned: 1, warehouseId: f.warehouseId });
  assert.equal(named.status, 201, JSON.stringify(named.body));
  assert.equal(named.body.data.warehouseId, f.warehouseId);
});

// ---- listing and tenancy -----------------------------------------------

test("production orders list, filter and search", async (t) => {
  if (!(await requireDatabase(t))) return;
  const f = await fixture();
  t.after(() => cleanup(f.businessId));
  await putBom(f);

  const first = await newRun(f, { quantityPlanned: 1, batchNumber: "ALPHA" });
  await newRun(f, { quantityPlanned: 1 });
  await setStatus(f, first.body.data.id, { status: "completed" });

  const all = await auth(request(app).get("/api/production-orders?page=1&pageSize=10"), f.token).send();
  assert.equal(all.status, 200);
  assert.equal(all.body.data.length, 2);
  assert.equal(all.body.meta.pagination.total, 2);

  const completed = await auth(
    request(app).get("/api/production-orders?status=completed"),
    f.token
  ).send();
  assert.equal(completed.body.data.length, 1);

  const byProduct = await auth(
    request(app).get(`/api/production-orders?productId=${f.tableId}`),
    f.token
  ).send();
  assert.equal(byProduct.body.data.length, 2);

  const found = await auth(request(app).get("/api/production-orders?search=ALPHA"), f.token).send();
  assert.equal(found.body.data.length, 1, "the batch number is searchable");
});

test("production is tenant-scoped — one factory never sees another's", async (t) => {
  if (!(await requireDatabase(t))) return;
  const a = await fixture();
  const b = await fixture();
  t.after(() => Promise.all([cleanup(a.businessId), cleanup(b.businessId)]));
  await putBom(a);

  const run = await newRun(a, { quantityPlanned: 1 });
  const id = run.body.data.id;

  assert.equal(
    (await auth(request(app).get(`/api/production-orders/${id}`), b.token).send()).status,
    404
  );
  assert.equal((await setStatus(b, id, { status: "completed" })).status, 404);
  assert.equal(
    (await auth(request(app).get("/api/production-orders"), b.token).send()).body.data.length,
    0
  );
  assert.equal(
    (await auth(request(app).get(`/api/products/${a.tableId}/bom`), b.token).send()).status,
    404,
    "nor another tenant's recipe"
  );

  // A run made out of the other tenant's material is refused (§36).
  const crossed = await auth(request(app).post("/api/production-orders"), b.token).send({
    productId: b.tableId,
    quantityPlanned: 1,
    materials: [{ materialProductId: a.woodId, quantityRequired: 1 }],
  });
  assert.equal(crossed.status, 422);
  assert.equal(await stockOf(a.businessId, a.woodId), 100, "and consumes nothing");
});

test("§30: a run and its completion are both in the activity trail", async (t) => {
  if (!(await requireDatabase(t))) return;
  const f = await fixture();
  t.after(() => cleanup(f.businessId));
  await putBom(f);

  const run = await newRun(f, { quantityPlanned: 1 });
  await setStatus(f, run.body.data.id, { status: "completed" });

  let rows = [];
  for (let i = 0; i < 60; i += 1) {
    const [found] = await pool.query(
      `SELECT action, actor_id FROM audit_logs WHERE business_id = ? AND module = 'production' ORDER BY id`,
      [f.businessId]
    );
    rows = found;
    if (rows.length >= 2) break;
    await new Promise((resolve) => setTimeout(resolve, 25));
  }

  const actions = rows.map((r) => r.action);
  assert.ok(actions.includes("production.create"), actions.join(", "));
  assert.ok(actions.includes("production.update"), actions.join(", "));
  assert.ok(rows.every((r) => Number(r.actor_id) === f.userId));
});

test("produced goods can then be sold — §21's two halves share one ledger", async (t) => {
  if (!(await requireDatabase(t))) return;
  const f = await fixture();
  t.after(() => cleanup(f.businessId));
  await putBom(f);

  const run = await newRun(f, { quantityPlanned: 10 });
  await setStatus(f, run.body.data.id, { status: "completed" });

  const sale = await auth(request(app).post("/api/orders"), f.token).send({
    orderType: "quick_sale",
    status: "confirmed",
    items: [{ productId: f.tableId, quantity: 4, unitPrice: 120 }],
  });
  assert.equal(sale.status, 201, JSON.stringify(sale.body));
  assert.equal(await stockOf(f.businessId, f.tableId), 6, "a made table is an ordinary saleable product");
});

after(() => closePool());
