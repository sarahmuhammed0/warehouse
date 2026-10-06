// Every business is born able to hold stock.
//
// It was not. `inventory` is keyed on (business, product, variant, warehouse,
// location), and nothing created a warehouse — not admin creation, not approving
// a self-registration. So a new business could create a product, see it as
// "Out of stock", try to add stock, and fail, because there was nowhere to put
// it. The product list reads quantity as SUM(inventory), so it stayed at zero
// with nothing on screen to explain why.

import { test, after } from "node:test";
import assert from "node:assert/strict";

import { pool, closePool } from "../../src/db/pool.js";
import { createBusinessWithOwner } from "../../src/modules/businesses/repository.js";
import { hashPassword } from "../../src/utils/password.js";
import { requireDatabase, testPhone, cleanupTestData } from "./helpers.js";

async function cleanup(businessId) {
  if (!businessId) return;
  await pool.query(`DELETE FROM warehouses WHERE business_id = ?`, [businessId]);
  await pool.query(`DELETE FROM users WHERE business_id = ?`, [businessId]);
  await pool.query(
    `DELETE rp FROM role_permissions rp JOIN roles r ON r.id = rp.role_id WHERE r.business_id = ?`,
    [businessId]
  );
  await pool.query(`DELETE FROM roles WHERE business_id = ?`, [businessId]);
  await cleanupTestData({ businessIds: [businessId] });
}

test("a new business is created with a default warehouse", async (t) => {
  if (!(await requireDatabase(t))) return;

  const { businessId } = await createBusinessWithOwner({
    business: {
      name: `Warehouse Default ${Date.now()}`,
      businessType: "warehouse",
      phone: testPhone(),
      currency: "IQD",
      language: "en",
      timezone: "UTC",
    },
    owner: { name: "Owner", phone: testPhone(), passwordHash: await hashPassword("Password123") },
  });

  try {
    const [rows] = await pool.query(
      `SELECT name, code, is_default, status FROM warehouses WHERE business_id = ? AND deleted_at IS NULL`,
      [businessId]
    );

    assert.equal(rows.length, 1, "exactly one, so there is no ambiguity about where stock goes");
    assert.equal(rows[0].name, "Main Warehouse");
    assert.equal(Boolean(rows[0].is_default), true, "the client picks the default when adding stock");
    assert.equal(rows[0].status, "active");
  } finally {
    await cleanup(businessId);
  }
});

test("a business created as pending gets one too, so approving is all it needs", async (t) => {
  if (!(await requireDatabase(t))) return;

  // Self-registration creates the business as `pending`. If the warehouse were
  // only created for active businesses, approving would produce exactly the
  // broken state this fixes — which is how the reported fault arose.
  const { businessId } = await createBusinessWithOwner({
    business: {
      name: `Pending Warehouse ${Date.now()}`,
      businessType: "general_factory",
      phone: testPhone(),
      currency: "IQD",
      language: "en",
      timezone: "UTC",
    },
    owner: { name: "Owner", phone: testPhone(), passwordHash: await hashPassword("Password123") },
    status: "pending",
  });

  try {
    const [rows] = await pool.query(
      `SELECT id FROM warehouses WHERE business_id = ? AND deleted_at IS NULL`,
      [businessId]
    );
    assert.equal(rows.length, 1);
  } finally {
    await cleanup(businessId);
  }
});

test("no business in the database is left unable to hold stock", async (t) => {
  if (!(await requireDatabase(t))) return;

  // The migration backfilled the ones that already existed. This is the
  // invariant itself rather than a check of the migration: a business with no
  // warehouse cannot use the feature the product is for, however it got there.
  const [orphans] = await pool.query(
    `SELECT b.id, b.name FROM businesses b
      WHERE b.deleted_at IS NULL
        AND NOT EXISTS (
              SELECT 1 FROM warehouses w
               WHERE w.business_id = b.id AND w.deleted_at IS NULL
            )`
  );

  assert.deepEqual(
    orphans.map((row) => row.name),
    [],
    "these businesses cannot hold stock at all"
  );
});

after(() => closePool());
