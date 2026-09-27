import { defineListSpec } from "../../db/listQuery.js";
import { createCrudRepository } from "../../db/crudRepository.js";
import { queryOne } from "../../db/pool.js";

/**
 * Customers (§18) and suppliers (§19) in one module: they are the same
 * shape — a party the business trades with — and differ only in which
 * documents point at them. Two near-identical files would drift.
 *
 * TOTALS ARE NOT STORED. §18 lists "Total purchases" and "Outstanding
 * balance" as customer fields, but both are sums over that customer's
 * orders. Storing them would mean every edit, cancellation and return has
 * to remember to adjust them, and the first one that forgets leaves a
 * number that is quietly wrong forever (docs/backend-phase3.md §5).
 */

const partySort = (alias) => ({
  allowed: {
    name: `${alias}.name`,
    code: `${alias}.code`,
    createdAt: `${alias}.created_at`,
  },
  default: { key: "name", direction: "ASC" },
});

const customerListSpec = defineListSpec({
  filters: { status: { column: "c.status", type: "enum", values: ["active", "inactive"] } },
  // §32: found by whichever detail the person on the phone gives you.
  search: { columns: ["c.name", "c.phone", "c.email", "c.company", "c.code"] },
  sort: partySort("c"),
  dateRange: { column: "c.created_at" },
});

/**
 * §18's derived figures, as correlated subqueries.
 *
 * WHICH ORDERS COUNT: only those the business has actually committed to.
 *   - `cancelled` — never happened. Counting it overstates both the
 *     customer's history and what they owe.
 *   - `draft` and `pending` — not yet a sale. A draft is a basket someone
 *     is still building and a pending order has not been confirmed; no stock
 *     has moved for either (see STOCK_COMMITTED_FROM in orders/service.js).
 *     Billing a customer for an unconfirmed draft is the kind of error that
 *     gets noticed by the customer.
 * A `returned` order still counts: it happened, and the return has its own
 * offsetting record.
 */
const COUNTED_ORDER_STATUSES = `o.status NOT IN ('cancelled', 'draft', 'pending')`;

const CUSTOMER_TOTALS = `
  COALESCE((SELECT SUM(o.grand_total) FROM orders o
             WHERE o.customer_id = c.id AND o.business_id = c.business_id
               AND o.deleted_at IS NULL AND ${COUNTED_ORDER_STATUSES}), 0) AS total_purchases,
  COALESCE((SELECT SUM(o.grand_total - o.paid_amount) FROM orders o
             WHERE o.customer_id = c.id AND o.business_id = c.business_id
               AND o.deleted_at IS NULL AND ${COUNTED_ORDER_STATUSES}), 0) AS outstanding_balance,
  (SELECT COUNT(*) FROM orders o
    WHERE o.customer_id = c.id AND o.business_id = c.business_id
      AND o.deleted_at IS NULL AND ${COUNTED_ORDER_STATUSES}) AS order_count`;

export const customersRepository = createCrudRepository({
  table: "customers",
  alias: "c",
  listSpec: customerListSpec,
  selectColumns: `c.id, c.name, c.code, c.phone, c.phone_secondary, c.email, c.address,
                  c.company, c.notes, c.status, c.created_at, c.updated_at,
                  ${CUSTOMER_TOTALS}`,
  columns: { toRow: partyRow(["company"]) },
});

const supplierListSpec = defineListSpec({
  filters: { status: { column: "s.status", type: "enum", values: ["active", "inactive"] } },
  search: { columns: ["s.name", "s.phone", "s.email", "s.company", "s.contact_person", "s.code"] },
  sort: partySort("s"),
  dateRange: { column: "s.created_at" },
});

/** §19's equivalents, over purchases rather than orders — same rule. */
const COUNTED_PURCHASE_STATUSES = `pu.status NOT IN ('cancelled', 'draft', 'pending')`;

const SUPPLIER_TOTALS = `
  COALESCE((SELECT SUM(pu.total) FROM purchases pu
             WHERE pu.supplier_id = s.id AND pu.business_id = s.business_id
               AND pu.deleted_at IS NULL AND ${COUNTED_PURCHASE_STATUSES}), 0) AS total_purchases,
  COALESCE((SELECT SUM(pu.total - pu.paid_amount) FROM purchases pu
             WHERE pu.supplier_id = s.id AND pu.business_id = s.business_id
               AND pu.deleted_at IS NULL AND ${COUNTED_PURCHASE_STATUSES}), 0) AS outstanding_balance,
  (SELECT COUNT(*) FROM purchases pu
    WHERE pu.supplier_id = s.id AND pu.business_id = s.business_id
      AND pu.deleted_at IS NULL AND ${COUNTED_PURCHASE_STATUSES}) AS purchase_count`;

export const suppliersRepository = createCrudRepository({
  table: "suppliers",
  alias: "s",
  listSpec: supplierListSpec,
  selectColumns: `s.id, s.name, s.code, s.company, s.contact_person, s.phone, s.phone_secondary,
                  s.email, s.address, s.notes, s.status, s.created_at, s.updated_at,
                  ${SUPPLIER_TOTALS}`,
  columns: { toRow: partyRow(["company", "contactPerson"]) },
});

/** Shared column mapping — the two parties differ by a field or two. */
function partyRow(extraFields) {
  const base = {
    name: "name",
    code: "code",
    phone: "phone",
    phoneSecondary: "phone_secondary",
    email: "email",
    address: "address",
    notes: "notes",
    status: "status",
    company: "company",
    contactPerson: "contact_person",
  };
  const allowed = new Set([
    "name",
    "code",
    "phone",
    "phoneSecondary",
    "email",
    "address",
    "notes",
    "status",
    ...extraFields,
  ]);

  return function toRow(data, { partial = false } = {}) {
    const row = {};
    for (const [field, column] of Object.entries(base)) {
      if (!allowed.has(field)) continue;
      if (data[field] !== undefined) row[column] = data[field];
    }
    void partial;
    return row;
  };
}

/** Documents that would be orphaned by archiving this party (§45). */
export async function customerHasOrders({ businessId, customerId }) {
  const row = await queryOne(
    `SELECT 1 AS used FROM orders WHERE business_id = ? AND customer_id = ? AND deleted_at IS NULL LIMIT 1`,
    [businessId, customerId]
  );
  return Boolean(row);
}

export async function supplierHasPurchases({ businessId, supplierId }) {
  const row = await queryOne(
    `SELECT 1 AS used FROM purchases WHERE business_id = ? AND supplier_id = ? AND deleted_at IS NULL LIMIT 1`,
    [businessId, supplierId]
  );
  return Boolean(row);
}
