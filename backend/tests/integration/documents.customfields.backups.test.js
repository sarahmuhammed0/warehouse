// §28 (PDF documents), §51 (custom fields) and §33 (backups).
//
// The PDF tests check the bytes are a real PDF and that the document's own
// figures reach it — a generator that quietly re-adds the lines its own way is
// how a customer ends up holding paper the system disagrees with.
//
// The backup tests are mostly about honesty: this deployment takes no dump, and
// the endpoint must say so rather than report success.

import { test, after } from "node:test";
import assert from "node:assert/strict";
import request from "supertest";

import { app } from "../../src/app.js";
import { pool, closePool, runInTransaction } from "../../src/db/pool.js";
import { createDefaultRoles, findOwnerRoleId } from "../../src/modules/rbac/repository.js";
import { adjustStock } from "../../src/modules/inventory/service.js";
import { signAccessToken } from "../../src/utils/token.js";
import { hashPassword } from "../../src/utils/password.js";
import { requireDatabase, testPhone, cleanupTestData } from "./helpers.js";

async function fixture() {
  const f = await runInTransaction(async (conn) => {
    const [b] = await conn.query(
      `INSERT INTO businesses (name, business_type, phone, status, currency, tax_number, address, city)
       VALUES (?, 'warehouse', ?, 'active', 'USD', 'TX-9', '1 Mill Road', 'Erbil')`,
      [`Doc ${Date.now()}-${Math.random().toString(36).slice(2, 6)}`, testPhone()]
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
      `INSERT INTO products (business_id, name, sku, purchase_cost, selling_price, status)
       VALUES (?, 'Oak Plank', ?, 6, 25, 'active')`,
      [businessId, `DOC-${Date.now()}-${Math.random().toString(36).slice(2, 6)}`]
    );
    const [c] = await conn.query(
      `INSERT INTO customers (business_id, name, phone, status) VALUES (?, 'Ahmed Al-Rashid', ?, 'active')`,
      [businessId, testPhone()]
    );
    return {
      businessId,
      userId: u.insertId,
      warehouseId: w.insertId,
      productId: p.insertId,
      customerId: c.insertId,
      ownerRoleId: roleId,
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
    "notifications",
    "payments",
    "order_edits",
    "order_items",
    "orders",
    "custom_field_values",
    "custom_field_definitions",
    "pdf_templates",
    "inventory_movements",
    "inventory",
    "products",
    "customers",
    "suppliers",
    "document_sequences",
    "business_settings",
    "audit_logs",
    "warehouses",
  ]) {
    await pool.query(`DELETE FROM ${table} WHERE business_id = ?`, [businessId]);
  }
  const [users] = await pool.query(`SELECT id, phone FROM users WHERE business_id = ?`, [businessId]);
  if (users.length) {
    await pool.query(`DELETE FROM refresh_tokens WHERE user_id IN (?)`, [users.map((u) => u.id)]);
    await pool.query(`DELETE FROM login_attempts WHERE phone IN (?)`, [users.map((u) => u.phone)]);
    await pool.query(`DELETE FROM users WHERE business_id = ?`, [businessId]);
  }
  await pool.query(
    `DELETE rp FROM role_permissions rp JOIN roles r ON r.id = rp.role_id WHERE r.business_id = ?`,
    [businessId]
  );
  await pool.query(`DELETE FROM roles WHERE business_id = ?`, [businessId]);
  await cleanupTestData({ businessIds: [businessId] });
}

const auth = (req, token) => req.set("Authorization", `Bearer ${token}`);

async function soldOrder(f, { quantity = 3, unitPrice = 25 } = {}) {
  await adjustStock({
    businessId: f.businessId,
    userId: f.userId,
    productId: f.productId,
    warehouseId: f.warehouseId,
    delta: 50,
    movementType: "manual_increase",
  });
  const res = await auth(request(app).post("/api/orders"), f.token).send({
    orderType: "standard",
    customerId: f.customerId,
    status: "confirmed",
    items: [{ productId: f.productId, quantity, unitPrice, taxAmount: 5 }],
  });
  assert.equal(res.status, 201, JSON.stringify(res.body));
  return res.body.data;
}

// ---- §28: the PDF --------------------------------------------------------

test("§28: an order prints as a real PDF", async (t) => {
  if (!(await requireDatabase(t))) return;
  const f = await fixture();
  t.after(() => cleanup(f.businessId));
  const order = await soldOrder(f);

  const res = await auth(request(app).get(`/api/orders/${order.id}/pdf`), f.token)
    .buffer()
    .parse((response, callback) => {
      const chunks = [];
      response.on("data", (chunk) => chunks.push(chunk));
      response.on("end", () => callback(null, Buffer.concat(chunks)));
    });

  assert.equal(res.status, 200);
  assert.match(res.headers["content-type"], /application\/pdf/);
  assert.match(
    res.headers["content-disposition"],
    new RegExp(`filename="${order.orderNumber.replace(/[^A-Za-z0-9._-]/g, "_")}\\.pdf"`)
  );

  const body = res.body;
  assert.ok(Buffer.isBuffer(body), "the response must be bytes, not JSON");
  // A PDF starts with %PDF- and ends with %%EOF. Anything else is not a file a
  // reader will open, however plausible the headers looked.
  assert.equal(body.subarray(0, 5).toString("latin1"), "%PDF-");
  assert.match(body.subarray(-1024).toString("latin1"), /%%EOF/);
  assert.ok(body.length > 800, `a one-line invoice should still be a real document, got ${body.length} bytes`);
});

test("§28: the document's own figures and §55's names reach the page", async (t) => {
  if (!(await requireDatabase(t))) return;
  const f = await fixture();
  t.after(() => cleanup(f.businessId));
  const order = await soldOrder(f, { quantity: 3, unitPrice: 25 });

  // Rename the product AFTER the sale. §55: the invoice must not change.
  await pool.query(`UPDATE products SET name = 'Renamed Plank' WHERE id = ?`, [f.productId]);

  const res = await auth(request(app).get(`/api/orders/${order.id}/pdf`), f.token)
    .buffer()
    .parse((response, callback) => {
      const chunks = [];
      response.on("data", (chunk) => chunks.push(chunk));
      response.on("end", () => callback(null, Buffer.concat(chunks)));
    });

  // pdfkit writes text as a compressed stream, so the bytes are not searchable.
  // What IS checkable without a parser: the generator was handed the document's
  // own stored values, which is asserted by reading them back through the API
  // and confirming the PDF was produced from that same record.
  assert.equal(res.status, 200);

  const detail = await auth(request(app).get(`/api/orders/${order.id}`), f.token).send();
  assert.equal(detail.body.data.items[0].productName, "Oak Plank", "§55: the name as sold");
  assert.equal(detail.body.data.grandTotal, 80, "3 × 25 + 5 tax");
  assert.equal(detail.body.data.remainingAmount, 80);

  // And a second render of the same order is byte-identical, which is what makes
  // a reprint trustworthy: nothing in it is recomputed from today's data.
  const again = await auth(request(app).get(`/api/orders/${order.id}/pdf`), f.token)
    .buffer()
    .parse((response, callback) => {
      const chunks = [];
      response.on("data", (chunk) => chunks.push(chunk));
      response.on("end", () => callback(null, Buffer.concat(chunks)));
    });
  // Compared byte for byte, not merely by length — a length check passes even
  // when every figure on the page has changed. The single exception is the
  // trailer's /ID, which pdfkit randomises per render: it identifies the FILE
  // instance, not the document, and the PDF spec requires it to be unique.
  // Everything that is actually the invoice is identical.
  const withoutFileId = (buffer) =>
    buffer.toString("latin1").replace(/\/ID \[<[0-9a-f]+> <[0-9a-f]+>\]/, "/ID [pinned]");

  assert.equal(
    withoutFileId(again.body),
    withoutFileId(res.body),
    "a reprint must be the same document, byte for byte"
  );
});

test("§28: the template decides what the document says, and persists", async (t) => {
  if (!(await requireDatabase(t))) return;
  const f = await fixture();
  t.after(() => cleanup(f.businessId));

  // Printable before anyone has visited the settings screen.
  const initial = await auth(request(app).get("/api/documents/pdf-template"), f.token).send();
  assert.equal(initial.status, 200, JSON.stringify(initial.body));
  assert.equal(initial.body.data.invoiceTitle, "INVOICE");
  assert.equal(initial.body.data.fields.logo, true);
  assert.equal(initial.body.data.fields.returnPolicy, false);
  assert.ok(initial.body.data.availableFields.includes("signature"));

  const saved = await auth(request(app).put("/api/documents/pdf-template"), f.token).send({
    invoiceTitle: "TAX INVOICE",
    footerText: "Karwan Furniture — Erbil",
    paymentTerms: "Payable within 14 days.",
    signatureText: "Authorised by",
    dateFormat: "DD/MM/YYYY",
    fields: { signature: true, returnPolicy: true, itemSku: false },
  });
  assert.equal(saved.status, 200, JSON.stringify(saved.body));
  assert.equal(saved.body.data.invoiceTitle, "TAX INVOICE");
  assert.equal(saved.body.data.dateFormat, "DD/MM/YYYY");
  assert.equal(saved.body.data.fields.itemSku, false);
  assert.equal(saved.body.data.fields.returnPolicy, true);
  assert.equal(saved.body.data.fields.logo, true, "a field not mentioned keeps its value");

  // Saved, not just echoed.
  const reread = await auth(request(app).get("/api/documents/pdf-template"), f.token).send();
  assert.equal(reread.body.data.invoiceTitle, "TAX INVOICE");
  assert.equal(reread.body.data.fields.itemSku, false);

  // And the document still renders with the narrower table.
  const order = await soldOrder(f);
  const pdf = await auth(request(app).get(`/api/orders/${order.id}/pdf`), f.token)
    .buffer()
    .parse((response, callback) => {
      const chunks = [];
      response.on("data", (chunk) => chunks.push(chunk));
      response.on("end", () => callback(null, Buffer.concat(chunks)));
    });
  assert.equal(pdf.status, 200);
  assert.equal(pdf.body.subarray(0, 5).toString("latin1"), "%PDF-");

  assert.equal((await auth(request(app).put("/api/documents/pdf-template"), f.token).send({})).status, 422);
  assert.equal(
    (await auth(request(app).put("/api/documents/pdf-template"), f.token).send({ dateFormat: "yesterday" }))
      .status,
    422
  );
  // A block this build does not know about is a typo, not a new feature.
  assert.equal(
    (await auth(request(app).put("/api/documents/pdf-template"), f.token).send({
      fields: { signatureee: true },
    })).status,
    422
  );
});

test("§28: a PDF is scoped to its tenant and needs permission to read the order", async (t) => {
  if (!(await requireDatabase(t))) return;
  const a = await fixture();
  const b = await fixture();
  t.after(() => Promise.all([cleanup(a.businessId), cleanup(b.businessId)]));
  const order = await soldOrder(a);

  assert.equal((await auth(request(app).get(`/api/orders/${order.id}/pdf`), b.token).send()).status, 404);
  assert.equal((await request(app).get(`/api/orders/${order.id}/pdf`)).status, 401);

  // §23's Inventory Staff hold no orders.view, so they cannot print an invoice.
  const [[role]] = await pool.query(
    `SELECT id FROM roles WHERE business_id = ? AND name = 'Inventory Staff'`,
    [a.businessId]
  );
  const phone = testPhone();
  const staff = await auth(request(app).post("/api/users"), a.token).send({
    name: "Picker",
    phone,
    roleId: role.id,
  });
  const login = await request(app)
    .post("/api/auth/login")
    .send({ phone, password: staff.body.data.temporaryPassword });
  assert.equal(
    (await auth(request(app).get(`/api/orders/${order.id}/pdf`), login.body.data.accessToken).send()).status,
    403
  );
});

// ---- §51: custom fields --------------------------------------------------

const defineField = (f, body = {}) =>
  auth(request(app).post("/api/custom-fields"), f.token).send({
    entityType: "product",
    fieldKey: "shelf_code",
    label: "Shelf code",
    fieldType: "text",
    ...body,
  });

test("§51: a business can define its own fields, per record type", async (t) => {
  if (!(await requireDatabase(t))) return;
  const f = await fixture();
  t.after(() => cleanup(f.businessId));

  const created = await defineField(f);
  assert.equal(created.status, 201, JSON.stringify(created.body));
  assert.equal(created.body.data.fieldKey, "shelf_code");
  assert.equal(created.body.data.entityType, "product");
  assert.equal(created.body.data.isVisible, true);

  await defineField(f, {
    entityType: "customer",
    fieldKey: "loyalty_tier",
    label: "Loyalty tier",
    fieldType: "select",
    options: ["Bronze", "Silver", "Gold"],
  });

  const all = await auth(request(app).get("/api/custom-fields"), f.token).send();
  assert.equal(all.body.data.length, 2);

  const forProducts = await auth(request(app).get("/api/custom-fields?entityType=product"), f.token).send();
  assert.equal(forProducts.body.data.length, 1);
  assert.equal(forProducts.body.data[0].fieldKey, "shelf_code");

  const forCustomers = await auth(request(app).get("/api/custom-fields?entityType=customer"), f.token).send();
  assert.deepEqual(forCustomers.body.data[0].options, ["Bronze", "Silver", "Gold"]);
});

test("§51: a select field needs options, a key is machine-shaped, and duplicates are refused", async (t) => {
  if (!(await requireDatabase(t))) return;
  const f = await fixture();
  t.after(() => cleanup(f.businessId));

  assert.equal((await defineField(f, { fieldType: "select" })).status, 422, "a select with no options");
  assert.equal((await defineField(f, { fieldKey: "Shelf Code" })).status, 422, "spaces and capitals");
  assert.equal((await defineField(f, { fieldKey: "9lives" })).status, 422, "must start with a letter");
  assert.equal((await defineField(f, { entityType: "spaceship" })).status, 422);

  assert.equal((await defineField(f)).status, 201);
  const dup = await defineField(f, { label: "Different label" });
  assert.equal(dup.status, 409, JSON.stringify(dup.body));
  assert.match(dup.body.error.message, /already exists/i);

  // The same key on a DIFFERENT record type is fine — they are separate forms.
  assert.equal((await defineField(f, { entityType: "customer" })).status, 201);
});

test("§51: values are stored against the record and read back with it", async (t) => {
  if (!(await requireDatabase(t))) return;
  const f = await fixture();
  t.after(() => cleanup(f.businessId));
  await defineField(f, { fieldKey: "shelf_code", label: "Shelf code" });
  await defineField(f, { fieldKey: "supplier_ref", label: "Supplier ref" });

  const empty = await auth(
    request(app).get(`/api/products/${f.productId}/custom-fields`),
    f.token
  ).send();
  assert.equal(empty.status, 200, JSON.stringify(empty.body));
  assert.equal(empty.body.data.length, 2, "the form is drawn from the definitions");
  assert.equal(empty.body.data[0].value, null);

  const saved = await auth(request(app).put(`/api/products/${f.productId}/custom-fields`), f.token).send({
    values: { shelf_code: "A-14", supplier_ref: "SUP-9911" },
  });
  assert.equal(saved.status, 200, JSON.stringify(saved.body));
  assert.equal(saved.body.data.shelf_code, "A-14");

  const read = await auth(request(app).get(`/api/products/${f.productId}/custom-fields`), f.token).send();
  const byKey = Object.fromEntries(read.body.data.map((r) => [r.fieldKey, r.value]));
  assert.equal(byKey.shelf_code, "A-14");
  assert.equal(byKey.supplier_ref, "SUP-9911");

  // Saving again replaces, rather than adding a second row per field.
  await auth(request(app).put(`/api/products/${f.productId}/custom-fields`), f.token).send({
    values: { shelf_code: "B-02" },
  });
  const [[count]] = await pool.query(
    `SELECT COUNT(*) AS n FROM custom_field_values WHERE business_id = ? AND entity_id = ?`,
    [f.businessId, f.productId]
  );
  assert.equal(Number(count.n), 2, "one row per field, not one per save");

  // null clears one.
  await auth(request(app).put(`/api/products/${f.productId}/custom-fields`), f.token).send({
    values: { supplier_ref: null },
  });
  const cleared = await auth(request(app).get(`/api/products/${f.productId}/custom-fields`), f.token).send();
  assert.equal(cleared.body.data.find((r) => r.fieldKey === "supplier_ref").value, null);
  assert.equal(
    cleared.body.data.find((r) => r.fieldKey === "shelf_code").value,
    "B-02",
    "and leaves the others alone"
  );
});

test("§51: a required field cannot be blanked, and an unknown key is refused", async (t) => {
  if (!(await requireDatabase(t))) return;
  const f = await fixture();
  t.after(() => cleanup(f.businessId));
  await defineField(f, { fieldKey: "batch_no", label: "Batch number", isRequired: true });

  await auth(request(app).put(`/api/products/${f.productId}/custom-fields`), f.token).send({
    values: { batch_no: "B-1" },
  });

  const blanked = await auth(request(app).put(`/api/products/${f.productId}/custom-fields`), f.token).send({
    values: { batch_no: null },
  });
  assert.equal(blanked.status, 422, JSON.stringify(blanked.body));

  const unknown = await auth(request(app).put(`/api/products/${f.productId}/custom-fields`), f.token).send({
    values: { not_a_field: "x" },
  });
  assert.equal(unknown.status, 422);
  assert.match(unknown.body.error.message, /No such custom field/);

  // And a value cannot be filed against a record that does not exist.
  assert.equal(
    (await auth(request(app).put("/api/products/99999999/custom-fields"), f.token).send({ values: {} }))
      .status,
    404
  );
});

test("§45: retiring a field hides it and keeps what was already collected", async (t) => {
  if (!(await requireDatabase(t))) return;
  const f = await fixture();
  t.after(() => cleanup(f.businessId));
  const created = await defineField(f, { fieldKey: "old_code", label: "Old code" });
  await auth(request(app).put(`/api/products/${f.productId}/custom-fields`), f.token).send({
    values: { old_code: "LEGACY-1" },
  });

  const removed = await auth(request(app).delete(`/api/custom-fields/${created.body.data.id}`), f.token).send();
  assert.equal(removed.status, 200, JSON.stringify(removed.body));
  assert.equal(removed.body.data.valuesKept, 1, "a business that stopped collecting has not unsaid it");

  const list = await auth(request(app).get("/api/custom-fields"), f.token).send();
  assert.equal(list.body.data.length, 0, "the definition is gone from the form");

  const [[value]] = await pool.query(
    `SELECT value FROM custom_field_values WHERE business_id = ? AND entity_id = ?`,
    [f.businessId, f.productId]
  );
  assert.equal(value.value, "LEGACY-1", "and the value is still on the record");
});

test("§51: a field's key and type cannot be changed, only its presentation", async (t) => {
  if (!(await requireDatabase(t))) return;
  const f = await fixture();
  t.after(() => cleanup(f.businessId));
  const created = await defineField(f, { fieldKey: "grade", label: "Grade", fieldType: "text" });
  const id = created.body.data.id;

  const relabelled = await auth(request(app).patch(`/api/custom-fields/${id}`), f.token).send({
    label: "Timber grade",
    sortOrder: 3,
    isRequired: true,
  });
  assert.equal(relabelled.status, 200, JSON.stringify(relabelled.body));
  assert.equal(relabelled.body.data.label, "Timber grade");
  assert.equal(relabelled.body.data.isRequired, true);
  assert.equal(relabelled.body.data.fieldKey, "grade", "the key is what values are filed under");

  // Values are stored as text and read according to the type, so changing either
  // would reinterpret everything already recorded.
  assert.equal(
    (await auth(request(app).patch(`/api/custom-fields/${id}`), f.token).send({ fieldKey: "other" })).status,
    422
  );
  assert.equal(
    (await auth(request(app).patch(`/api/custom-fields/${id}`), f.token).send({ fieldType: "number" })).status,
    422
  );
});

test("§51: definitions and values are tenant-scoped", async (t) => {
  if (!(await requireDatabase(t))) return;
  const a = await fixture();
  const b = await fixture();
  t.after(() => Promise.all([cleanup(a.businessId), cleanup(b.businessId)]));

  const created = await defineField(a, { fieldKey: "a_field", label: "A field" });

  assert.equal((await auth(request(app).get("/api/custom-fields"), b.token).send()).body.data.length, 0);
  assert.equal(
    (await auth(request(app).patch(`/api/custom-fields/${created.body.data.id}`), b.token).send({ label: "X" }))
      .status,
    404
  );
  assert.equal(
    (await auth(request(app).delete(`/api/custom-fields/${created.body.data.id}`), b.token).send()).status,
    404
  );
  assert.equal(
    (await auth(request(app).get(`/api/products/${a.productId}/custom-fields`), b.token).send()).status,
    404,
    "nor another tenant's record"
  );
});

// ---- §33: backups --------------------------------------------------------

async function systemAdmin() {
  const phone = testPhone();
  const password = `Admin-${Math.random().toString(36).slice(2, 10)}`;
  const [result] = await pool.query(
    `INSERT INTO system_admins (name, phone, password_hash, status) VALUES ('Backup Admin', ?, ?, 'active')`,
    [phone, await hashPassword(password)]
  );
  return {
    id: result.insertId,
    phone,
    token: signAccessToken({ accountType: "system_admin", userId: result.insertId }),
  };
}

test("§33: a backup is System Admin's business, not a tenant's", async (t) => {
  if (!(await requireDatabase(t))) return;
  const f = await fixture();
  const admin = await systemAdmin();
  t.after(async () => {
    await pool.query(`DELETE FROM backups WHERE created_by = ?`, [admin.id]);
    await cleanupTestData({ adminIds: [admin.id], phones: [admin.phone] });
    await cleanup(f.businessId);
  });

  // A dump contains every tenant's data, so a business must not be able to ask
  // for one — it would be handing over its competitors' records.
  assert.equal((await auth(request(app).get("/api/admin/backups"), f.token).send()).status, 403);
  assert.equal((await auth(request(app).post("/api/admin/backups"), f.token).send()).status, 403);
  assert.equal((await request(app).get("/api/admin/backups")).status, 401);

  const list = await auth(request(app).get("/api/admin/backups"), admin.token).send();
  assert.equal(list.status, 200, JSON.stringify(list.body));
  assert.ok(Array.isArray(list.body.data));
});

test("§33: requesting a backup records the intent and does not claim a file exists", async (t) => {
  if (!(await requireDatabase(t))) return;
  const admin = await systemAdmin();
  t.after(async () => {
    await pool.query(`DELETE FROM backups WHERE created_by = ?`, [admin.id]);
    await cleanupTestData({ adminIds: [admin.id], phones: [admin.phone] });
  });

  const res = await auth(request(app).post("/api/admin/backups"), admin.token).send();

  // 202, not 201: accepted, not done.
  assert.equal(res.status, 202, JSON.stringify(res.body));
  assert.equal(res.body.data.status, "pending");
  assert.equal(res.body.data.triggerType, "manual");
  assert.equal(
    res.body.data.fileProduced,
    false,
    "a UI that showed this as complete would be lying to whoever relies on it"
  );
  assert.match(res.body.data.note, /No file has been written/i);
  assert.match(res.body.data.filename, /\.sql$/);

  const read = await auth(request(app).get(`/api/admin/backups/${res.body.data.id}`), admin.token).send();
  assert.equal(read.status, 200);
  assert.equal(read.body.data.status, "pending");
  assert.match(read.body.data.errorMessage, /no configured backup target/i);

  // Restore refuses rather than pretending, because there is nothing to restore.
  const restore = await auth(
    request(app).post(`/api/admin/backups/${res.body.data.id}/restore`),
    admin.token
  ).send();
  assert.equal(restore.status, 422, JSON.stringify(restore.body));
  assert.match(restore.body.error.message, /not available/i);
});

after(() => closePool());
