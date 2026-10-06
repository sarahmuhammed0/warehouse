// The counts behind the navigation badges — "what is new since I last looked".
//
// What has to be true for a badge to be worth drawing:
//   it counts only what arrived AFTER the moment the caller names,
//   it counts only the caller's own tenant (§36),
//   it tells a business user nothing about a module their role cannot open,
//   each entity answers to its OWN `since`, because the items are marked read
//     one at a time, and
//   a nonsense `since` is refused rather than treated as the beginning of time,
//     which would badge every record that has ever existed.

import { test, after } from "node:test";
import assert from "node:assert/strict";
import request from "supertest";

import { app } from "../../src/app.js";
import { pool, closePool, runInTransaction } from "../../src/db/pool.js";
import { createDefaultRoles, findOwnerRoleId } from "../../src/modules/rbac/repository.js";
import { signAccessToken } from "../../src/utils/token.js";
import { requireDatabase, testPhone, cleanupTestData, createTestSystemAdmin } from "./helpers.js";

const auth = (req, token) => req.set("Authorization", `Bearer ${token}`);

/** A business with an owner, and a clock to place records either side of. */
async function fixture() {
  return runInTransaction(async (conn) => {
    const [b] = await conn.query(
      `INSERT INTO businesses (name, business_type, phone, status) VALUES (?, 'general_factory', ?, 'active')`,
      [`Activity ${Date.now()}-${Math.random().toString(36).slice(2, 6)}`, testPhone()]
    );
    const businessId = b.insertId;
    await createDefaultRoles(conn, businessId);
    const ownerRoleId = await findOwnerRoleId(conn, businessId);

    const [u] = await conn.query(
      `INSERT INTO users (business_id, name, phone, password_hash, is_owner, role_id, status)
       VALUES (?, 'Owner', ?, 'x', TRUE, ?, 'active')`,
      [businessId, testPhone(), ownerRoleId]
    );
    const [unit] = await conn.query(
      `INSERT INTO units (business_id, name, code, decimal_places) VALUES (?, 'Piece', ?, 0)`,
      [businessId, `pc${Math.random().toString(36).slice(2, 6)}`]
    );
    // Every business has one — `createBusinessWithOwner` makes it in the same
    // transaction, and `business.default-warehouse.test.js` asserts that no
    // business anywhere is without. Test files run in parallel, so a fixture
    // that skipped it would fail that invariant from the next file over.
    await conn.query(
      `INSERT INTO warehouses (business_id, name, code, location_type, is_default, status)
       VALUES (?, 'Main Warehouse', 'MAIN', 'warehouse', TRUE, 'active')`,
      [businessId]
    );
    return { businessId, userId: u.insertId, unitId: unit.insertId, ownerRoleId };
  });
}

/** A product stamped at an exact moment, so "since" has something to bite on. */
async function productAt(f, name, createdAt) {
  const [r] = await pool.query(
    `INSERT INTO products (business_id, name, sku, product_type, unit_id, purchase_cost, selling_price, status, created_at)
     VALUES (?, ?, ?, 'finished_good', ?, 1, 2, 'active', ?)`,
    [f.businessId, name, `${name}-${Date.now()}-${Math.random().toString(36).slice(2, 6)}`, f.unitId, createdAt]
  );
  return r.insertId;
}

const tokenFor = (f) =>
  signAccessToken({ accountType: "business_user", userId: f.userId, businessId: f.businessId });

const counts = (token, qs) => auth(request(app).get(`/api/activity/counts?${qs}`), token);

const iso = (d) => d.toISOString().slice(0, 19).replace("T", " ");

/// Before every record these tests create, so "since EPOCH" means "everything".
/// Deliberately not equal to any record's own timestamp: the comparison is
/// `created_at > since`, so a record created exactly AT the moment the caller
/// last looked has already been seen and must not be counted again.
const EPOCH = new Date("2019-01-01T00:00:00Z");
const OLD = new Date("2020-01-01T00:00:00Z");
const RECENT = new Date("2030-01-01T00:00:00Z");

/// `cleanupTestData` knows about users, roles and warehouses; these tests also
/// make units, products and orders, which hold the business down by FK.
async function cleanup(businessId) {
  for (const sql of [
    `DELETE FROM order_items WHERE business_id = ?`,
    `DELETE FROM orders WHERE business_id = ?`,
    `DELETE FROM products WHERE business_id = ?`,
    `DELETE FROM units WHERE business_id = ?`,
    // Before the roles `cleanupTestData` removes: these users were given a role
    // id, and `users.role_id` holds it down. The shared helper only deletes the
    // users whose ids it was handed, and these were made here.
    `DELETE FROM audit_logs WHERE business_id = ?`,
    `DELETE FROM users WHERE business_id = ?`,
  ]) {
    await pool.query(sql, [businessId]);
  }
  await cleanupTestData({ businessIds: [businessId] });
}

test("counts only what arrived after the moment the caller names", async (t) => {
  if (!(await requireDatabase(t))) return;
  const f = await fixture();
  t.after(() => cleanup(f.businessId));

  await productAt(f, "Old", iso(OLD));
  await productAt(f, "NewA", iso(new Date("2031-01-01T00:00:00Z")));
  await productAt(f, "NewB", iso(new Date("2031-02-01T00:00:00Z")));

  const all = await counts(tokenFor(f), `products=${encodeURIComponent(EPOCH.toISOString())}`);
  assert.equal(all.status, 200, JSON.stringify(all.body));
  assert.equal(all.body.data.products, 3, "everything, when the caller has never looked");

  const since = await counts(tokenFor(f), `products=${encodeURIComponent(RECENT.toISOString())}`);
  assert.equal(since.body.data.products, 2, "only the two created after that moment");

  const future = await counts(tokenFor(f), `products=${encodeURIComponent("2040-01-01T00:00:00Z")}`);
  assert.equal(future.body.data.products, 0, "nothing is newer than the future");
});

test("each entity answers to its own `since` — reading one does not clear another", async (t) => {
  // The point of the per-entity parameter: opening Products marks only Products
  // read, and Orders must keep its own badge.
  if (!(await requireDatabase(t))) return;
  const f = await fixture();
  t.after(() => cleanup(f.businessId));

  await productAt(f, "P", iso(new Date("2031-01-01T00:00:00Z")));
  await pool.query(
    `INSERT INTO orders (business_id, order_number, order_type, status, grand_total, created_by, created_at)
     VALUES (?, ?, 'standard', 'pending', 10, ?, ?)`,
    [f.businessId, `ORD-${Date.now()}`, f.userId, iso(new Date("2031-01-01T00:00:00Z"))]
  );

  const res = await counts(
    tokenFor(f),
    `products=${encodeURIComponent("2040-01-01T00:00:00Z")}&orders=${encodeURIComponent(OLD.toISOString())}`
  );

  assert.equal(res.body.data.products, 0, "Products was just read");
  assert.equal(res.body.data.orders, 1, "Orders was not, and still has one waiting");
});

test("an entity that was not asked about is absent, not reported as zero", async (t) => {
  if (!(await requireDatabase(t))) return;
  const f = await fixture();
  t.after(() => cleanup(f.businessId));
  await productAt(f, "P", iso(new Date("2031-01-01T00:00:00Z")));

  const res = await counts(tokenFor(f), `products=${encodeURIComponent(OLD.toISOString())}`);

  assert.equal(res.body.data.products, 1);
  assert.equal("orders" in res.body.data, false, '"did not ask" and "nothing new" are different facts');
});

test("§36: one business never counts another's records", async (t) => {
  if (!(await requireDatabase(t))) return;
  const [a, b] = [await fixture(), await fixture()];
  t.after(() => cleanup(a.businessId));
  t.after(() => cleanup(b.businessId));

  await productAt(b, "TheirsOne", iso(new Date("2031-01-01T00:00:00Z")));
  await productAt(b, "TheirsTwo", iso(new Date("2031-01-01T00:00:00Z")));

  const res = await counts(tokenFor(a), `products=${encodeURIComponent(OLD.toISOString())}`);
  assert.equal(res.body.data.products, 0, "A has none of its own, and must not see B's two");
});

test("a role that cannot open a module is not told how much is in it", async (t) => {
  // The navigation hides what a role cannot open, so a well-behaved client never
  // asks — which is not a reason for the server to answer.
  if (!(await requireDatabase(t))) return;
  const f = await fixture();
  t.after(() => cleanup(f.businessId));
  await productAt(f, "P", iso(new Date("2031-01-01T00:00:00Z")));

  const [[role]] = await pool.query(
    `SELECT id FROM roles WHERE business_id = ? AND name = 'Accountant' AND deleted_at IS NULL LIMIT 1`,
    [f.businessId]
  );
  const accountantRoleId = role.id;
  const [staff] = await pool.query(
    `INSERT INTO users (business_id, name, phone, password_hash, is_owner, role_id, status)
     VALUES (?, 'Accountant', ?, 'x', FALSE, ?, 'active')`,
    [f.businessId, testPhone(), accountantRoleId]
  );
  const staffToken = signAccessToken({
    accountType: "business_user",
    userId: staff.insertId,
    businessId: f.businessId,
  });

  const res = await counts(staffToken, `products=${encodeURIComponent(OLD.toISOString())}`);

  assert.equal(res.status, 200);
  assert.equal("products" in res.body.data, false, "the Accountant has no products.view, so there is no count");
});

test("a `since` that is not a date is refused, not treated as the beginning of time", async (t) => {
  if (!(await requireDatabase(t))) return;
  const f = await fixture();
  t.after(() => cleanup(f.businessId));

  const res = await counts(tokenFor(f), "products=yesterday-ish");

  assert.equal(res.status, 422, "silently counting everything would look like a broken badge");
});

test("a System Admin counts across every tenant, and a business user cannot reach that route", async (t) => {
  if (!(await requireDatabase(t))) return;
  const f = await fixture();
  const admin = await createTestSystemAdmin({ phone: testPhone() });
  t.after(async () => {
    await cleanup(f.businessId);
    await cleanupTestData({ adminIds: [admin.id] });
  });

  await productAt(f, "Fresh", iso(new Date("2031-01-01T00:00:00Z")));
  const adminToken = signAccessToken({ accountType: "system_admin", userId: admin.id });

  const res = await auth(
    request(app).get(`/api/admin/activity/counts?products=${encodeURIComponent(RECENT.toISOString())}`),
    adminToken
  );
  assert.equal(res.status, 200, JSON.stringify(res.body));
  assert.ok(res.body.data.products >= 1, "the platform operator sees the product that was just created");

  // And the two routes stay apart: §57's oversight is not a business endpoint.
  const crossed = await auth(
    request(app).get(`/api/admin/activity/counts?products=${encodeURIComponent(OLD.toISOString())}`),
    tokenFor(f)
  );
  assert.equal(crossed.status, 403, "a business user must not reach the platform-wide count");
});

after(async () => {
  await closePool();
});
