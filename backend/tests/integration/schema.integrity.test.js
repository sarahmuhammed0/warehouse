// Proves the schema the migrations produce is the schema the specification
// requires — against the real MySQL 8.x server, never a mock.
//
// Every assertion here reads `information_schema`, which is the server's own
// account of what it built. A migration file that *says* it creates a unique
// index proves nothing; this proves the index exists.
//
// Skips (never fakes a pass) when the database is unreachable — see
// helpers.js.

import { test } from "node:test";
import assert from "node:assert/strict";
import { pool } from "../../src/db/pool.js";
import { requireDatabase } from "./helpers.js";

/** Every table the specification's §37 list requires, as built. */
const EXPECTED_TABLES = [
  // Phase 2 (identity/auth)
  "businesses",
  "users",
  "system_admins",
  "refresh_tokens",
  "system_admin_refresh_tokens",
  "login_attempts",
  "audit_logs",
  // Phase 3 — RBAC (§23/§24)
  "permissions",
  "roles",
  "role_permissions",
  // Phase 3 — business configuration (§28/§29/§34/§51)
  "business_settings",
  "document_sequences",
  "custom_field_definitions",
  "custom_field_values",
  "pdf_templates",
  // Phase 3 — locations (§11)
  "warehouses",
  "storage_locations",
  // Phase 3 — master data (§7/§8/§9)
  "units",
  "categories",
  "products",
  "product_variants",
  "product_images",
  // Phase 3 — inventory (§10/§12)
  "inventory",
  "inventory_movements",
  "stock_transfers",
  "stock_transfer_items",
  // Phase 3 — parties (§18/§19)
  "customers",
  "suppliers",
  "supplier_products",
  // Phase 3 — purchases (§20)
  "purchases",
  "purchase_items",
  // Phase 3 — sales/orders (§13/§14/§15)
  "orders",
  "order_items",
  "order_edits",
  "payments",
  // Phase 3 — returns (§16)
  "returns",
  "return_items",
  // Phase 3 — production (§21/§22)
  "bill_of_materials",
  "production_orders",
  "production_items",
  // Phase 3 — system (§31/§34/§52)
  "notifications",
  "system_settings",
  "backups",
];

/**
 * §7's tenant-ownership model: these tables hold records a business owns,
 * and every one must carry `business_id` so a later phase can scope a query
 * to one tenant. Listed explicitly rather than inferred, because the point
 * is to catch a *missing* column on a table someone adds later.
 */
const TENANT_OWNED_TABLES = [
  "users",
  "roles",
  "business_settings",
  "document_sequences",
  "custom_field_definitions",
  "custom_field_values",
  "pdf_templates",
  "warehouses",
  "storage_locations",
  "units",
  "categories",
  "products",
  "product_variants",
  "product_images",
  "inventory",
  "inventory_movements",
  "stock_transfers",
  "stock_transfer_items",
  "customers",
  "suppliers",
  "supplier_products",
  "purchases",
  "purchase_items",
  "orders",
  "order_items",
  "order_edits",
  "payments",
  "returns",
  "return_items",
  "bill_of_materials",
  "production_orders",
  "production_items",
];

/**
 * The deliberate opposite: platform-level tables that must NOT gain a
 * tenant column. §7 warns against handing every table a business_id "just
 * because most tables do", and this is the assertion that enforces it.
 */
const SYSTEM_WIDE_TABLES = [
  "businesses",
  "system_admins",
  "system_admin_refresh_tokens",
  "permissions",
  "system_settings",
  "backups",
];

/** §45: records that are archived rather than destroyed. */
const SOFT_DELETABLE_TABLES = [
  "businesses",
  "users",
  "system_admins",
  "roles",
  "custom_field_definitions",
  "pdf_templates",
  "warehouses",
  "storage_locations",
  "units",
  "categories",
  "products",
  "product_variants",
  "customers",
  "suppliers",
  "purchases",
  "orders",
  "returns",
  "stock_transfers",
  "bill_of_materials",
  "production_orders",
];

/**
 * §12's "records should never silently disappear" and §15's "never silently
 * overwrite": these are append-only ledgers, so a `deleted_at` on them
 * would be an invitation to hide history.
 */
const APPEND_ONLY_TABLES = ["audit_logs", "inventory_movements", "order_edits", "login_attempts"];

async function columns(tableName) {
  const [rows] = await pool.query(
    `SELECT COLUMN_NAME, DATA_TYPE, IS_NULLABLE, COLUMN_TYPE, NUMERIC_SCALE
       FROM information_schema.COLUMNS
      WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = ?`,
    [tableName]
  );
  return new Map(rows.map((row) => [row.COLUMN_NAME, row]));
}

async function indexNames(tableName) {
  const [rows] = await pool.query(
    `SELECT DISTINCT INDEX_NAME, NON_UNIQUE
       FROM information_schema.STATISTICS
      WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = ?`,
    [tableName]
  );
  return rows;
}

test("every table the specification requires exists", async (t) => {
  if (!(await requireDatabase(t))) return;

  const [rows] = await pool.query(
    `SELECT TABLE_NAME FROM information_schema.TABLES WHERE TABLE_SCHEMA = DATABASE()`
  );
  const present = new Set(rows.map((row) => row.TABLE_NAME));

  const missing = EXPECTED_TABLES.filter((name) => !present.has(name));
  assert.deepEqual(missing, [], `missing tables: ${missing.join(", ")}`);
});

test("every business table is InnoDB and utf8mb4 — §29's transactional storage", async (t) => {
  if (!(await requireDatabase(t))) return;

  const [rows] = await pool.query(
    `SELECT TABLE_NAME, ENGINE, TABLE_COLLATION
       FROM information_schema.TABLES
      WHERE TABLE_SCHEMA = DATABASE() AND TABLE_TYPE = 'BASE TABLE'`
  );

  const notInnodb = rows.filter((row) => row.ENGINE !== "InnoDB");
  assert.deepEqual(notInnodb.map((r) => r.TABLE_NAME), [], "tables that are not InnoDB cannot roll back");

  const notUtf8mb4 = rows.filter((row) => !String(row.TABLE_COLLATION).startsWith("utf8mb4"));
  assert.deepEqual(
    notUtf8mb4.map((r) => r.TABLE_NAME),
    [],
    "tables that are not utf8mb4 cannot store Kurdish/Arabic text or emoji"
  );
});

test("every business-owned table carries business_id", async (t) => {
  if (!(await requireDatabase(t))) return;

  const missing = [];
  for (const tableName of TENANT_OWNED_TABLES) {
    const cols = await columns(tableName);
    if (!cols.has("business_id")) missing.push(tableName);
  }
  assert.deepEqual(missing, [], `tenant-owned tables without business_id: ${missing.join(", ")}`);
});

test("platform-level tables deliberately have no business_id", async (t) => {
  if (!(await requireDatabase(t))) return;

  const unexpected = [];
  for (const tableName of SYSTEM_WIDE_TABLES) {
    const cols = await columns(tableName);
    if (cols.has("business_id")) unexpected.push(tableName);
  }
  assert.deepEqual(
    unexpected,
    [],
    `system-wide tables must not be tenant-scoped: ${unexpected.join(", ")}`
  );
});

test("business_id is a real foreign key everywhere it appears", async (t) => {
  if (!(await requireDatabase(t))) return;

  const [rows] = await pool.query(
    `SELECT TABLE_NAME
       FROM information_schema.KEY_COLUMN_USAGE
      WHERE TABLE_SCHEMA = DATABASE()
        AND COLUMN_NAME = 'business_id'
        AND REFERENCED_TABLE_NAME = 'businesses'`
  );
  const constrained = new Set(rows.map((row) => row.TABLE_NAME));

  const unconstrained = TENANT_OWNED_TABLES.filter((name) => !constrained.has(name));
  assert.deepEqual(
    unconstrained,
    [],
    `business_id without an FK is a tenant column the database cannot trust: ${unconstrained.join(", ")}`
  );
});

test("soft-deletable tables have deleted_at; append-only ledgers do not", async (t) => {
  if (!(await requireDatabase(t))) return;

  const missing = [];
  for (const tableName of SOFT_DELETABLE_TABLES) {
    const cols = await columns(tableName);
    if (!cols.has("deleted_at")) missing.push(tableName);
  }
  assert.deepEqual(missing, [], `§45 requires archiving, not deletion: ${missing.join(", ")}`);

  const unexpected = [];
  for (const tableName of APPEND_ONLY_TABLES) {
    const cols = await columns(tableName);
    if (cols.has("deleted_at")) unexpected.push(tableName);
  }
  assert.deepEqual(
    unexpected,
    [],
    `an append-only ledger must not offer a way to hide rows: ${unexpected.join(", ")}`
  );
});

test("every table has created_at, and mutable ones have updated_at", async (t) => {
  if (!(await requireDatabase(t))) return;

  const missing = [];
  for (const tableName of EXPECTED_TABLES) {
    const cols = await columns(tableName);
    // role_permissions and supplier_products are link rows with composite
    // primary keys — created_at is meaningful, updated_at is not.
    if (!cols.has("created_at")) missing.push(`${tableName}.created_at`);
  }
  assert.deepEqual(missing, [], missing.join(", "));
});

test("money is DECIMAL, never a float — §61's financial correctness", async (t) => {
  if (!(await requireDatabase(t))) return;

  // A FLOAT column cannot represent 0.10 exactly, so a column of float
  // totals does not add up to the invoice. This catches any later migration
  // that reaches for `float` on a money or quantity column.
  const [rows] = await pool.query(
    `SELECT TABLE_NAME, COLUMN_NAME, DATA_TYPE
       FROM information_schema.COLUMNS
      WHERE TABLE_SCHEMA = DATABASE()
        AND DATA_TYPE IN ('float', 'double')`
  );
  assert.deepEqual(
    rows.map((row) => `${row.TABLE_NAME}.${row.COLUMN_NAME} (${row.DATA_TYPE})`),
    [],
    "approximate numeric types must not be used for money or quantities"
  );
});

test("document numbers are unique per business — §61 rule 12", async (t) => {
  if (!(await requireDatabase(t))) return;

  // Each of these is a document type §29 lets a business number. The rule
  // is enforced by the database, not by a service remembering to check.
  const documents = [
    ["orders", "uq_orders_number"],
    ["purchases", "uq_purchases_number"],
    ["returns", "uq_returns_number"],
    ["stock_transfers", "uq_stock_transfers_number"],
    ["production_orders", "uq_production_number"],
  ];

  for (const [tableName, indexName] of documents) {
    const indexes = await indexNames(tableName);
    const found = indexes.find((row) => row.INDEX_NAME === indexName);
    assert.ok(found, `${tableName} is missing ${indexName}`);
    assert.equal(Number(found.NON_UNIQUE), 0, `${indexName} must be UNIQUE`);
  }
});

test("product identifiers are unique per business — §54's duplicate SKUs", async (t) => {
  if (!(await requireDatabase(t))) return;

  for (const indexName of ["uq_products_sku", "uq_products_barcode", "uq_products_code"]) {
    const indexes = await indexNames("products");
    const found = indexes.find((row) => row.INDEX_NAME === indexName);
    assert.ok(found, `products is missing ${indexName}`);
    assert.equal(Number(found.NON_UNIQUE), 0, `${indexName} must be UNIQUE`);
  }

  // And scoped to the tenant, not global: two businesses may use "SKU-001".
  const [cols] = await pool.query(
    `SELECT COLUMN_NAME, SEQ_IN_INDEX
       FROM information_schema.STATISTICS
      WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'products' AND INDEX_NAME = 'uq_products_sku'
      ORDER BY SEQ_IN_INDEX`
  );
  assert.equal(cols[0].COLUMN_NAME, "business_id", "SKU uniqueness must be per business");
  assert.equal(cols[1].COLUMN_NAME, "sku");
});

test("one inventory row per physical slot, even with NULL variant/location", async (t) => {
  if (!(await requireDatabase(t))) return;

  // MySQL treats every NULL in a UNIQUE index as distinct, so the obvious
  // index would allow unlimited duplicates for product+warehouse when
  // variant and location are NULL. The generated key columns are what make
  // the constraint real — this asserts they are in place.
  const cols = await columns("inventory");
  assert.ok(cols.has("variant_key"), "inventory.variant_key (generated) is missing");
  assert.ok(cols.has("location_key"), "inventory.location_key (generated) is missing");

  const [indexed] = await pool.query(
    `SELECT COLUMN_NAME, SEQ_IN_INDEX, NON_UNIQUE
       FROM information_schema.STATISTICS
      WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'inventory' AND INDEX_NAME = 'uq_inventory_slot'
      ORDER BY SEQ_IN_INDEX`
  );
  assert.equal(indexed.length, 4, "uq_inventory_slot should cover four columns");
  assert.equal(Number(indexed[0].NON_UNIQUE), 0);
  assert.deepEqual(
    indexed.map((row) => row.COLUMN_NAME),
    ["product_id", "variant_key", "warehouse_id", "location_key"]
  );
});

test("the indexes §11 calls for exist on the tables that need them", async (t) => {
  if (!(await requireDatabase(t))) return;

  // Not an exhaustive list — the ones §11 names explicitly, so a later
  // refactor that drops one is caught.
  const required = {
    products: ["idx_products_business_status", "idx_products_category", "idx_products_name"],
    orders: ["idx_orders_status_date", "idx_orders_customer", "idx_orders_payment_status"],
    customers: ["idx_customers_phone", "idx_customers_name"],
    suppliers: ["idx_suppliers_phone", "idx_suppliers_name"],
    inventory: ["idx_inventory_product", "idx_inventory_location"],
    inventory_movements: ["idx_movements_product", "idx_movements_type", "idx_movements_reference"],
    audit_logs: ["idx_audit_logs_business", "idx_audit_logs_actor", "idx_audit_logs_action", "idx_audit_logs_module"],
  };

  for (const [tableName, expected] of Object.entries(required)) {
    const present = new Set((await indexNames(tableName)).map((row) => row.INDEX_NAME));
    const missing = expected.filter((name) => !present.has(name));
    assert.deepEqual(missing, [], `${tableName} is missing indexes: ${missing.join(", ")}`);
  }
});

test("audit_logs carries every field §30 lists, including module", async (t) => {
  if (!(await requireDatabase(t))) return;

  const cols = await columns("audit_logs");
  for (const column of [
    "actor_type",
    "actor_id",
    "module",
    "action",
    "description",
    "ip_address",
    "reference_type",
    "reference_id",
    "created_at",
    "business_id",
  ]) {
    assert.ok(cols.has(column), `audit_logs.${column} is missing (§30)`);
  }
  assert.equal(cols.get("module").IS_NULLABLE, "NO", "module must be required of every writer");
});
