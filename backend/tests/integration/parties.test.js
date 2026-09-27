// Customers (§18) and suppliers (§19) against the real database.
//
// The point of interest is the derived totals. They are NOT stored, so these
// prove they follow the documents — including the case that makes storing
// them go wrong: a cancelled order must stop counting.

import { test, after } from "node:test";
import assert from "node:assert/strict";

import { pool, closePool, runInTransaction } from "../../src/db/pool.js";
import { createDefaultRoles } from "../../src/modules/rbac/repository.js";
import { customersRepository, suppliersRepository } from "../../src/modules/parties/repository.js";
import { requireDatabase, testPhone, cleanupTestData } from "./helpers.js";

async function fixture() {
  return runInTransaction(async (conn) => {
    const [b] = await conn.query(
      `INSERT INTO businesses (name, business_type, phone, status) VALUES (?, 'warehouse', ?, 'active')`,
      [`Party ${Date.now()}-${Math.random().toString(36).slice(2, 6)}`, testPhone()]
    );
    const businessId = b.insertId;
    await createDefaultRoles(conn, businessId);
    const [u] = await conn.query(
      `INSERT INTO users (business_id, name, phone, password_hash, is_owner, status)
       VALUES (?, 'Owner', ?, 'x', TRUE, 'active')`,
      [businessId, testPhone()]
    );
    return { businessId, userId: u.insertId };
  });
}

async function cleanup(businessId) {
  if (!businessId) return;
  for (const sql of [
    `DELETE FROM order_items WHERE business_id = ?`,
    `DELETE FROM orders WHERE business_id = ?`,
    `DELETE FROM customers WHERE business_id = ?`,
    `DELETE FROM suppliers WHERE business_id = ?`,
  ]) {
    await pool.query(sql, [businessId]);
  }
  const [users] = await pool.query(`SELECT id FROM users WHERE business_id = ?`, [businessId]);
  await cleanupTestData({ businessIds: [businessId], userIds: users.map((u) => u.id) });
}

const pagination = { page: 1, pageSize: 50, offset: 0 };

/** An order attributed to a customer, at a given status and paid amount. */
async function placeOrder({ businessId, customerId, total, paid = 0, status = "completed" }) {
  const [r] = await pool.query(
    `INSERT INTO orders (business_id, customer_id, order_number, order_type, status,
                         subtotal, grand_total, paid_amount, payment_status, order_date)
     VALUES (?, ?, ?, 'quick_sale', ?, ?, ?, ?, 'unpaid', NOW())`,
    [businessId, customerId, `T-${Date.now()}-${Math.random().toString(36).slice(2, 7)}`, status, total, total, paid]
  );
  return r.insertId;
}

test("a customer's totals are derived from their orders", async (t) => {
  if (!(await requireDatabase(t))) return;
  const f = await fixture();
  t.after(() => cleanup(f.businessId));

  const customerId = await customersRepository.create({
    businessId: f.businessId,
    data: { name: "Derived Totals", phone: testPhone(), status: "active" },
  });

  let row = await customersRepository.findById({ businessId: f.businessId, id: customerId });
  assert.equal(Number(row.total_purchases), 0, "a new customer owes nothing and has bought nothing");
  assert.equal(Number(row.order_count), 0);

  await placeOrder({ businessId: f.businessId, customerId, total: 300, paid: 100 });
  await placeOrder({ businessId: f.businessId, customerId, total: 200, paid: 200 });

  row = await customersRepository.findById({ businessId: f.businessId, id: customerId });
  assert.equal(Number(row.total_purchases), 500, "§18: total purchases is the sum of their orders");
  assert.equal(Number(row.outstanding_balance), 200, "§18: outstanding is what is unpaid across them");
  assert.equal(Number(row.order_count), 2);
});

test("a cancelled order stops counting toward a customer's totals", async (t) => {
  if (!(await requireDatabase(t))) return;
  const f = await fixture();
  t.after(() => cleanup(f.businessId));

  const customerId = await customersRepository.create({
    businessId: f.businessId,
    data: { name: "Cancels A Lot", phone: testPhone() },
  });

  const orderId = await placeOrder({ businessId: f.businessId, customerId, total: 400, paid: 0 });
  assert.equal(
    Number((await customersRepository.findById({ businessId: f.businessId, id: customerId })).outstanding_balance),
    400
  );

  // This is exactly the case that makes a STORED total go wrong: whoever
  // cancels has to remember to adjust it. Derived, it just follows.
  await pool.query(`UPDATE orders SET status = 'cancelled' WHERE id = ?`, [orderId]);

  const row = await customersRepository.findById({ businessId: f.businessId, id: customerId });
  assert.equal(Number(row.outstanding_balance), 0, "a cancelled sale is not money owed");
  assert.equal(Number(row.total_purchases), 0, "nor is it something they bought");
  assert.equal(Number(row.order_count), 0);
});

test("customers and suppliers are tenant-scoped", async (t) => {
  if (!(await requireDatabase(t))) return;
  const a = await fixture();
  const b = await fixture();
  t.after(async () => {
    await cleanup(a.businessId);
    await cleanup(b.businessId);
  });

  await customersRepository.create({ businessId: a.businessId, data: { name: "A's customer" } });
  await suppliersRepository.create({ businessId: a.businessId, data: { name: "A's supplier" } });

  const customers = await customersRepository.list({ businessId: b.businessId, query: {}, pagination });
  const suppliers = await suppliersRepository.list({ businessId: b.businessId, query: {}, pagination });
  assert.equal(customers.rows.length, 0, "§36: B must not see A's customers");
  assert.equal(suppliers.rows.length, 0, "§36: B must not see A's suppliers");
});

test("an archived party disappears from lists but its documents survive", async (t) => {
  if (!(await requireDatabase(t))) return;
  const f = await fixture();
  t.after(() => cleanup(f.businessId));

  const customerId = await customersRepository.create({
    businessId: f.businessId,
    data: { name: "Gone Away", phone: testPhone() },
  });
  const orderId = await placeOrder({ businessId: f.businessId, customerId, total: 100 });

  await customersRepository.softDelete({ businessId: f.businessId, id: customerId });

  const list = await customersRepository.list({ businessId: f.businessId, query: {}, pagination });
  assert.equal(list.rows.length, 0, "an archived customer leaves the list");

  // §45/§55: the order still names them. That is the whole reason archiving
  // is a soft delete rather than a removal.
  const [[order]] = await pool.query(`SELECT customer_id FROM orders WHERE id = ?`, [orderId]);
  assert.equal(order.customer_id, customerId, "the document must still point at them");
});

test("search finds a customer by any of the details §32 lists", async (t) => {
  if (!(await requireDatabase(t))) return;
  const f = await fixture();
  t.after(() => cleanup(f.businessId));

  const phone = testPhone();
  await customersRepository.create({
    businessId: f.businessId,
    data: { name: "Findable Person", phone, email: "findable@example.com", company: "Findable Co" },
  });

  for (const term of ["Findable", phone, "findable@example.com", "Findable Co"]) {
    const result = await customersRepository.list({
      businessId: f.businessId,
      query: { search: term },
      pagination,
    });
    assert.equal(result.rows.length, 1, `searching "${term}" should find them`);
  }

  const none = await customersRepository.list({
    businessId: f.businessId,
    query: { search: "definitely-not-present" },
    pagination,
  });
  assert.equal(none.rows.length, 0);
});

test("a search term containing LIKE wildcards is matched literally", async (t) => {
  if (!(await requireDatabase(t))) return;
  const f = await fixture();
  t.after(() => cleanup(f.businessId));

  await customersRepository.create({ businessId: f.businessId, data: { name: "Ordinary Name" } });
  await customersRepository.create({ businessId: f.businessId, data: { name: "100% Cotton Ltd" } });

  // Without escaping, "%" matches everything and the search silently returns
  // the whole table rather than the one match.
  const result = await customersRepository.list({
    businessId: f.businessId,
    query: { search: "100%" },
    pagination,
  });
  assert.equal(result.rows.length, 1, "a literal % must not behave as a wildcard");
  assert.equal(result.rows[0].name, "100% Cotton Ltd");
});

after(async () => {
  await closePool();
});
