import { defineListSpec, buildWhere, buildOrderBy } from "../../db/listQuery.js";
import { queryAll, queryCount, queryOne, pool } from "../../db/pool.js";

/** Purchases from suppliers (§20). */
const listSpec = defineListSpec({
  filters: {
    status: { column: "pu.status", type: "enum", values: ["draft", "pending", "completed", "cancelled"] },
    paymentStatus: {
      column: "pu.payment_status",
      type: "enum",
      values: ["paid", "partially_paid", "unpaid"],
    },
    supplierId: { column: "pu.supplier_id", type: "int" },
  },
  search: { columns: ["pu.purchase_number", "s.name", "s.phone"] },
  sort: {
    allowed: {
      purchaseNumber: "pu.purchase_number",
      purchaseDate: "pu.purchase_date",
      total: "pu.total",
      status: "pu.status",
    },
    // Newest first, for the same reason as orders: the question is almost
    // always about a recent purchase.
    default: { key: "purchaseDate", direction: "DESC" },
  },
  dateRange: { column: "pu.purchase_date" },
});

const JOINS = `LEFT JOIN suppliers s ON s.id = pu.supplier_id AND s.business_id = pu.business_id`;

export async function listPurchases({ businessId, query, pagination }) {
  const where = buildWhere(listSpec, query, { "pu.business_id": businessId, "pu.deleted_at": null });
  const orderBy = buildOrderBy(listSpec, query, "pu.id");

  const rows = await queryAll(
    `SELECT pu.id, pu.purchase_number, pu.status, pu.payment_status,
            pu.subtotal, pu.discount_amount, pu.tax_amount, pu.extra_charges,
            pu.total, pu.paid_amount, pu.note, pu.purchase_date, pu.completed_at,
            pu.created_at, pu.updated_at, pu.created_by,
            pu.supplier_id, s.name AS supplier_name, s.phone AS supplier_phone,
            u.name AS created_by_name,
            (SELECT COUNT(*) FROM purchase_items pi WHERE pi.purchase_id = pu.id) AS item_count
       FROM purchases pu ${JOINS}
       LEFT JOIN users u ON u.id = pu.created_by
       ${where.sql} ${orderBy} LIMIT ? OFFSET ?`,
    [...where.params, pagination.pageSize, pagination.offset]
  );

  const total = await queryCount(
    `SELECT COUNT(*) AS total FROM purchases pu ${JOINS} ${where.sql}`,
    where.params
  );

  return { rows, total };
}

export async function findPurchase({ businessId, id, conn = pool }) {
  const [rows] = await conn.query(
    `SELECT pu.*, s.name AS supplier_name, s.phone AS supplier_phone,
            u.name AS created_by_name,
            (SELECT COUNT(*) FROM purchase_items pi WHERE pi.purchase_id = pu.id) AS item_count
       FROM purchases pu ${JOINS}
       LEFT JOIN users u ON u.id = pu.created_by
      WHERE pu.id = ? AND pu.business_id = ? AND pu.deleted_at IS NULL LIMIT 1`,
    [id, businessId]
  );
  return rows[0] ?? null;
}

/**
 * The purchase row, locked for the rest of the transaction.
 *
 * Same rule as `lockOrder`: every decision that depends on the purchase's
 * current state — is this transition legal, has the stock already been
 * received, how much is still owed to the supplier — is made from a row read
 * THIS way. Two concurrent completions that each read on the pool first would
 * both see "pending" and both receive the goods.
 */
export async function lockPurchase({ businessId, id, conn }) {
  const [rows] = await conn.query(
    `SELECT * FROM purchases
      WHERE id = ? AND business_id = ? AND deleted_at IS NULL
      LIMIT 1
      FOR UPDATE`,
    [id, businessId]
  );
  return rows[0] ?? null;
}

export async function purchaseItems({ businessId, purchaseId, conn = pool }) {
  const [rows] = await conn.query(
    `SELECT pi.id, pi.product_id, pi.variant_id,
            -- The snapshot, falling back to the product's current name only
            -- for rows written before the column existed.
            COALESCE(pi.product_name, p.name) AS product_name,
            COALESCE(pi.sku, p.sku) AS sku,
            pi.quantity, pi.unit_cost, pi.discount_amount, pi.tax_amount, pi.line_total
       FROM purchase_items pi
       LEFT JOIN products p ON p.id = pi.product_id AND p.business_id = pi.business_id
      WHERE pi.business_id = ? AND pi.purchase_id = ? ORDER BY pi.id`,
    [businessId, purchaseId]
  );
  return rows;
}

/** Purchase lines in the shape the stock service expects — see toStockLines. */
export function toStockLines(rows) {
  return rows.map((row) => ({
    productId: row.product_id ?? row.productId,
    variantId: row.variant_id ?? row.variantId ?? null,
    quantity: Number(row.quantity),
  }));
}

export async function purchasePayments({ businessId, purchaseId }) {
  return queryAll(
    `SELECT p.id, p.amount, p.method, p.reference, p.note, p.paid_at, u.name AS created_by_name
       FROM payments p LEFT JOIN users u ON u.id = p.created_by
      WHERE p.business_id = ? AND p.purchase_id = ? ORDER BY p.paid_at DESC, p.id DESC`,
    [businessId, purchaseId]
  );
}

/**
 * What has actually been paid to the supplier on this purchase.
 *
 * `outgoing` is money paid out, which is what a purchase payment is;
 * `incoming` on a purchase is a refund from the supplier, so it subtracts.
 * Summing both directions would let a refund push a purchase to "paid".
 */
export async function totalPaid({ businessId, purchaseId, conn = pool }) {
  const [rows] = await conn.query(
    `SELECT COALESCE(SUM(CASE WHEN direction = 'outgoing' THEN amount ELSE -amount END), 0) AS paid
       FROM payments WHERE business_id = ? AND purchase_id = ?`,
    [businessId, purchaseId]
  );
  return Number(rows[0].paid);
}

export async function supplierExists({ businessId, supplierId }) {
  const row = await queryOne(
    `SELECT 1 AS ok FROM suppliers WHERE id = ? AND business_id = ? AND deleted_at IS NULL LIMIT 1`,
    [supplierId, businessId]
  );
  return Boolean(row);
}
