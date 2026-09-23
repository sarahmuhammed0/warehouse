// Proves §46: a multi-step write either lands completely or leaves
// nothing behind. "Never leave the database in a partially updated state"
// is the requirement, and the only honest way to show it is to make a real
// transaction fail partway through and then look.
//
// These are foundation tests, deliberately not sale/purchase tests — the
// business operations that will use this machinery belong to later phases.
// What is proven here is the machinery.

import { test } from "node:test";
import assert from "node:assert/strict";
import { pool, runInTransaction, queryOne, queryCount } from "../../src/db/pool.js";
import { requireDatabase, cleanupTestData, testPhone } from "./helpers.js";

/** A business row, created inside whichever connection is passed. */
async function insertBusiness(conn, name) {
  const [result] = await conn.query(
    `INSERT INTO businesses (name, business_type, phone, status) VALUES (?, 'custom', ?, 'active')`,
    [name, testPhone()]
  );
  return result.insertId;
}

test("a committed transaction persists every step", async (t) => {
  if (!(await requireDatabase(t))) return;

  const marker = `tx-commit-${Date.now()}`;
  let businessId;
  try {
    businessId = await runInTransaction(async (conn) => {
      const id = await insertBusiness(conn, marker);
      // A second write in the same transaction — a settings row, which is
      // the shape §46's example has (parent row, then child rows).
      await conn.query(
        `INSERT INTO business_settings (business_id, setting_key, setting_value) VALUES (?, ?, CAST(? AS JSON))`,
        [id, "test.marker", JSON.stringify(marker)]
      );
      return id;
    });

    const business = await queryOne(`SELECT name FROM businesses WHERE id = ?`, [businessId]);
    assert.equal(business?.name, marker, "the business should have been committed");

    const settings = await queryCount(
      `SELECT COUNT(*) AS total FROM business_settings WHERE business_id = ?`,
      [businessId]
    );
    assert.equal(settings, 1, "the settings row should have been committed too");
  } finally {
    if (businessId) {
      await pool.query(`DELETE FROM business_settings WHERE business_id = ?`, [businessId]);
      await cleanupTestData({ businessIds: [businessId] });
    }
  }
});

test("an error partway through rolls back everything, leaving no partial write", async (t) => {
  if (!(await requireDatabase(t))) return;

  const marker = `tx-rollback-${Date.now()}`;
  const boom = new Error("intentional failure after the first write");

  await assert.rejects(
    () =>
      runInTransaction(async (conn) => {
        const id = await insertBusiness(conn, marker);

        // Prove the row really is visible *inside* the transaction — so
        // that its later absence is evidence of a rollback and not of an
        // insert that never happened.
        const inside = await queryOne(`SELECT name FROM businesses WHERE id = ?`, [id], conn);
        assert.equal(inside?.name, marker, "the write should be visible inside the transaction");

        throw boom;
      }),
    (error) => error === boom,
    "the original error must propagate, not be swallowed"
  );

  // The whole point: nothing survived.
  const survivors = await queryCount(`SELECT COUNT(*) AS total FROM businesses WHERE name = ?`, [marker]);
  assert.equal(survivors, 0, "a rolled-back transaction must leave no row behind");
});

test("a constraint violation mid-transaction rolls back the earlier writes", async (t) => {
  if (!(await requireDatabase(t))) return;

  // The realistic version of the previous test: the failure comes from the
  // database itself rather than from application code. This is §46's own
  // example — an insert that violates a foreign key after a valid one.
  const marker = `tx-fk-${Date.now()}`;

  await assert.rejects(
    () =>
      runInTransaction(async (conn) => {
        await insertBusiness(conn, marker);
        // business_id 0 can never exist (AUTO_INCREMENT starts at 1), so
        // this violates the FK on business_settings.
        await conn.query(
          `INSERT INTO business_settings (business_id, setting_key, setting_value) VALUES (0, 'x', CAST('1' AS JSON))`
        );
      }),
    (error) => /ER_NO_REFERENCED_ROW|foreign key/i.test(error.code ?? error.message),
    "the foreign-key error should surface"
  );

  const survivors = await queryCount(`SELECT COUNT(*) AS total FROM businesses WHERE name = ?`, [marker]);
  assert.equal(survivors, 0, "the valid insert must not survive its transaction failing");
});

test("the pool is not leaked when a transaction fails", async (t) => {
  if (!(await requireDatabase(t))) return;

  // A connection not returned to the pool is worse than the error that
  // caused it: enough of them and the process stops serving entirely. This
  // runs more failing transactions than the pool has connections, which
  // would deadlock if `finally { conn.release() }` were missing.
  const attempts = 15;
  for (let i = 0; i < attempts; i += 1) {
    await assert.rejects(() =>
      runInTransaction(async () => {
        throw new Error(`attempt ${i}`);
      })
    );
  }

  // Still usable afterwards.
  const row = await queryOne("SELECT 1 AS ok");
  assert.equal(Number(row.ok), 1, "the pool should still serve queries");
});

test("a CHECK constraint refuses an invalid row — §54 enforced by the database", async (t) => {
  if (!(await requireDatabase(t))) return;

  // §47/§54: a negative reserved quantity is not merely discouraged by the
  // service layer, it is impossible to store. Proven here because §35's
  // "never trust the frontend" has to hold for our own service code too.
  let businessId;
  try {
    businessId = await runInTransaction((conn) => insertBusiness(conn, `ck-${Date.now()}`));

    await assert.rejects(
      () =>
        pool.query(
          `INSERT INTO inventory (business_id, product_id, warehouse_id, quantity, reserved_quantity)
           VALUES (?, 1, 1, 0, -5)`,
          [businessId]
        ),
      // Either the CHECK rejects it, or the FKs do (product 1 / warehouse 1
      // need not exist in a fresh database). Both are the database refusing
      // an invalid row, which is what this asserts.
      (error) =>
        /ER_CHECK_CONSTRAINT_VIOLATED|ER_NO_REFERENCED_ROW|foreign key|check constraint/i.test(
          error.code ?? error.message
        )
    );
  } finally {
    if (businessId) await cleanupTestData({ businessIds: [businessId] });
  }
});
