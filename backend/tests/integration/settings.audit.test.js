// §47's negative-stock setting, and §30's activity log.
//
// Both were unreachable before: the setting `allowsNegativeStock` reads had no
// endpoint that could write it, so §47's "explicit business setting" could
// never be given; and every module built after authentication wrote nothing to
// `audit_logs`, so §30's trail covered logins and nothing else.

import { test, after } from "node:test";
import assert from "node:assert/strict";
import request from "supertest";

import { app } from "../../src/app.js";
import { pool, closePool, runInTransaction } from "../../src/db/pool.js";
import { createDefaultRoles, findOwnerRoleId } from "../../src/modules/rbac/repository.js";
import { adjustStock } from "../../src/modules/inventory/service.js";
import { allowsNegativeStock } from "../../src/modules/inventory/repository.js";
import { signAccessToken } from "../../src/utils/token.js";
import { requireDatabase, testPhone, cleanupTestData } from "./helpers.js";

async function fixture() {
  const f = await runInTransaction(async (conn) => {
    const [b] = await conn.query(
      `INSERT INTO businesses (name, business_type, phone, status) VALUES (?, 'warehouse', ?, 'active')`,
      [`Set ${Math.random().toString(36).slice(2, 8)}`, testPhone()]
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
       VALUES (?, 'Widget', ?, 100, 'active')`,
      [businessId, `SKU-${Math.random().toString(36).slice(2, 8)}`]
    );
    return { businessId, userId: u.insertId, warehouseId: w.insertId, productId: p.insertId };
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
    `DELETE FROM audit_logs WHERE business_id = ?`,
    `DELETE FROM inventory_movements WHERE business_id = ?`,
    `DELETE FROM inventory WHERE business_id = ?`,
    `DELETE FROM business_settings WHERE business_id = ?`,
    `DELETE FROM products WHERE business_id = ?`,
    `DELETE FROM warehouses WHERE business_id = ?`,
  ]) {
    await pool.query(sql, [businessId]);
  }
  const [users] = await pool.query(`SELECT id FROM users WHERE business_id = ?`, [businessId]);
  await cleanupTestData({ businessIds: [businessId], userIds: users.map((u) => u.id) });
}

const auth = (req, token) => req.set("Authorization", `Bearer ${token}`);

// -------------------------------------------------------------------------
// §47's setting
// -------------------------------------------------------------------------

test("settings read back with their defaults before anything is stored", async (t) => {
  if (!(await requireDatabase(t))) return;
  const f = await fixture();
  t.after(() => cleanup(f.businessId));

  const res = await auth(request(app).get("/api/settings"), f.token).send();

  assert.equal(res.status, 200);
  assert.equal(res.body.data.values["inventory.allow_negative_stock"], false);
  assert.equal(res.body.data.definitions["inventory.allow_negative_stock"].type, "boolean");
});

test("§47: negative stock is refused by default and permitted once the setting is on", async (t) => {
  if (!(await requireDatabase(t))) return;
  const f = await fixture();
  t.after(() => cleanup(f.businessId));

  const takeTooMuch = () =>
    adjustStock({
      businessId: f.businessId,
      userId: f.userId,
      productId: f.productId,
      warehouseId: f.warehouseId,
      delta: -5,
      movementType: "manual_decrease",
    });

  await assert.rejects(takeTooMuch, /Insufficient stock/, "the default must refuse");
  assert.equal(await allowsNegativeStock(f.businessId), false);

  const patched = await auth(request(app).patch("/api/settings"), f.token).send({
    "inventory.allow_negative_stock": true,
  });
  assert.equal(patched.status, 200, JSON.stringify(patched.body));
  assert.equal(patched.body.data.values["inventory.allow_negative_stock"], true);

  // The service reads the setting, so this is the actual §47 behaviour and not
  // just a row in a table.
  assert.equal(await allowsNegativeStock(f.businessId), true);
  const result = await takeTooMuch();
  assert.equal(result.after, -5);
});

test("turning the setting back off restores the refusal", async (t) => {
  if (!(await requireDatabase(t))) return;
  const f = await fixture();
  t.after(() => cleanup(f.businessId));

  await auth(request(app).patch("/api/settings"), f.token).send({
    "inventory.allow_negative_stock": true,
  });
  // "false" as a string is what an HTML form sends, and Boolean("false") is
  // true — the coercion bug this schema exists to avoid.
  const off = await auth(request(app).patch("/api/settings"), f.token).send({
    "inventory.allow_negative_stock": "false",
  });
  assert.equal(off.status, 200, JSON.stringify(off.body));
  assert.equal(off.body.data.values["inventory.allow_negative_stock"], false);
  assert.equal(await allowsNegativeStock(f.businessId), false);
});

test("an unknown setting key is refused rather than silently stored", async (t) => {
  if (!(await requireDatabase(t))) return;
  const f = await fixture();
  t.after(() => cleanup(f.businessId));

  const res = await auth(request(app).patch("/api/settings"), f.token).send({
    "inventory.allow_negative_stocks": true, // note the typo
  });

  assert.equal(res.status, 422, JSON.stringify(res.body));
  const [rows] = await pool.query(`SELECT COUNT(*) AS n FROM business_settings WHERE business_id = ?`, [
    f.businessId,
  ]);
  assert.equal(Number(rows[0].n), 0, "nothing should have been written");
});

test("settings are tenant-scoped", async (t) => {
  if (!(await requireDatabase(t))) return;
  const a = await fixture();
  const b = await fixture();
  t.after(() => Promise.all([cleanup(a.businessId), cleanup(b.businessId)]));

  await auth(request(app).patch("/api/settings"), a.token).send({
    "inventory.allow_negative_stock": true,
  });

  const other = await auth(request(app).get("/api/settings"), b.token).send();
  assert.equal(other.body.data.values["inventory.allow_negative_stock"], false);
  assert.equal(await allowsNegativeStock(b.businessId), false);
});

// -------------------------------------------------------------------------
// §30's activity log
// -------------------------------------------------------------------------

const auditRows = async (businessId) => {
  const [rows] = await pool.query(
    `SELECT module, action, actor_id, reference_id FROM audit_logs
      WHERE business_id = ? ORDER BY id`,
    [businessId]
  );
  return rows;
};

/**
 * The audit row is written after the response is flushed, so a test that looks
 * immediately can lose the race with its own assertion. This waits for it
 * rather than sleeping a guessed interval.
 */
async function waitForAudit(businessId, count, attempts = 50) {
  for (let i = 0; i < attempts; i += 1) {
    const rows = await auditRows(businessId);
    if (rows.length >= count) return rows;
    await new Promise((resolve) => setTimeout(resolve, 20));
  }
  return auditRows(businessId);
}

test("§30: creating and editing a product is recorded, with who and what", async (t) => {
  if (!(await requireDatabase(t))) return;
  const f = await fixture();
  t.after(() => cleanup(f.businessId));

  const created = await auth(request(app).post("/api/products"), f.token).send({
    name: "Audited Widget",
    sku: `SKU-${Math.random().toString(36).slice(2, 8)}`,
  });
  assert.equal(created.status, 201, JSON.stringify(created.body));
  const productId = created.body.data.id;

  await auth(request(app).patch(`/api/products/${productId}`), f.token).send({ name: "Renamed" });

  const rows = await waitForAudit(f.businessId, 2);
  const actions = rows.map((r) => r.action);

  assert.ok(actions.includes("products.create"), `expected a create, got ${actions.join(", ")}`);
  assert.ok(actions.includes("products.update"), `expected an update, got ${actions.join(", ")}`);

  const create = rows.find((r) => r.action === "products.create");
  assert.equal(create.module, "products");
  assert.equal(Number(create.actor_id), f.userId, "the trail must name who did it");
  assert.equal(Number(create.reference_id), Number(productId), "and what they did it to");
});

test("§30: a read is not an audit event, and neither is a refused write", async (t) => {
  if (!(await requireDatabase(t))) return;
  const f = await fixture();
  t.after(() => cleanup(f.businessId));

  await auth(request(app).get("/api/products"), f.token).send();
  await auth(request(app).get(`/api/products/${f.productId}`), f.token).send();
  // Refused: no name. Nothing changed, so there is nothing to record.
  const refused = await auth(request(app).post("/api/products"), f.token).send({});
  assert.ok(refused.status >= 400);

  // Give the "finish" handler the same chance it would get on a real write.
  await new Promise((resolve) => setTimeout(resolve, 150));
  assert.deepEqual(await auditRows(f.businessId), []);
});

after(() => closePool());
