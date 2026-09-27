import { defineListSpec, buildWhere, buildOrderBy } from "../../db/listQuery.js";
import { queryAll, queryCount, pool } from "../../db/pool.js";

/** Returns (§16). */
const listSpec = defineListSpec({
  filters: {
    status: {
      column: "r.status",
      type: "enum",
      values: ["requested", "approved", "rejected", "completed"],
    },
    orderId: { column: "r.order_id", type: "int" },
    customerId: { column: "r.customer_id", type: "int" },
  },
  search: { columns: ["r.return_number", "o.order_number", "c.name"] },
  sort: {
    allowed: {
      returnNumber: "r.return_number",
      returnDate: "r.return_date",
      refundAmount: "r.refund_amount",
      status: "r.status",
    },
    default: { key: "returnDate", direction: "DESC" },
  },
  dateRange: { column: "r.return_date" },
});

const JOINS = `
  LEFT JOIN orders o ON o.id = r.order_id AND o.business_id = r.business_id
  LEFT JOIN customers c ON c.id = r.customer_id AND c.business_id = r.business_id`;

const SELECT_COLUMNS = `
  r.id, r.return_number, r.status, r.reason, r.refund_amount, r.note,
  r.return_date, r.completed_at, r.created_at, r.updated_at,
  r.order_id, o.order_number, r.customer_id, c.name AS customer_name,
  r.created_by, r.approved_by,
  requester.name AS created_by_name, approver.name AS approved_by_name,
  (SELECT COUNT(*) FROM return_items ri WHERE ri.return_id = r.id) AS item_count`;

const USER_JOINS = `
  LEFT JOIN users requester ON requester.id = r.created_by
  LEFT JOIN users approver ON approver.id = r.approved_by`;

export async function listReturns({ businessId, query, pagination }) {
  const where = buildWhere(listSpec, query, { "r.business_id": businessId, "r.deleted_at": null });
  const orderBy = buildOrderBy(listSpec, query, "r.id");

  const rows = await queryAll(
    `SELECT ${SELECT_COLUMNS} FROM returns r ${JOINS} ${USER_JOINS}
      ${where.sql} ${orderBy} LIMIT ? OFFSET ?`,
    [...where.params, pagination.pageSize, pagination.offset]
  );

  const total = await queryCount(
    `SELECT COUNT(*) AS total FROM returns r ${JOINS} ${where.sql}`,
    where.params
  );

  return { rows, total };
}

export async function findReturn({ businessId, id, conn = pool }) {
  const [rows] = await conn.query(
    `SELECT ${SELECT_COLUMNS} FROM returns r ${JOINS} ${USER_JOINS}
      WHERE r.id = ? AND r.business_id = ? AND r.deleted_at IS NULL LIMIT 1`,
    [id, businessId]
  );
  return rows[0] ?? null;
}

/**
 * The return row, locked for the rest of the transaction.
 *
 * Same rule as `lockOrder`: two concurrent completions that each read on the
 * pool first would both see "approved" and both restock the goods.
 */
export async function lockReturn({ businessId, id, conn }) {
  const [rows] = await conn.query(
    `SELECT * FROM returns WHERE id = ? AND business_id = ? AND deleted_at IS NULL LIMIT 1 FOR UPDATE`,
    [id, businessId]
  );
  return rows[0] ?? null;
}

export async function returnItems({ businessId, returnId, conn = pool }) {
  const [rows] = await conn.query(
    `SELECT ri.id, ri.order_item_id, ri.product_id, ri.variant_id,
            COALESCE(ri.product_name, p.name) AS product_name,
            COALESCE(ri.sku, p.sku) AS sku,
            ri.quantity, ri.item_condition, ri.refund_amount
       FROM return_items ri
       LEFT JOIN products p ON p.id = ri.product_id AND p.business_id = ri.business_id
      WHERE ri.business_id = ? AND ri.return_id = ? ORDER BY ri.id`,
    [businessId, returnId]
  );
  return rows;
}

/**
 * What each line of an order still has left to return.
 *
 * `returned` counts every return that has not been REJECTED — a requested or
 * approved return has not moved stock yet, but the goods are already claimed,
 * and letting a second request claim them again is how a business ends up
 * refunding the same three chairs twice.
 */
export async function returnableLines({ businessId, orderId, conn = pool }) {
  const [rows] = await conn.query(
    `SELECT oi.id, oi.product_id, oi.variant_id, oi.product_name, oi.sku,
            oi.quantity, oi.unit_price, oi.line_total,
            COALESCE((
              SELECT SUM(ri.quantity) FROM return_items ri
                JOIN returns r ON r.id = ri.return_id
               WHERE ri.order_item_id = oi.id
                 AND r.business_id = oi.business_id
                 AND r.status <> 'rejected'
                 AND r.deleted_at IS NULL
            ), 0) AS returned
       FROM order_items oi
      WHERE oi.business_id = ? AND oi.order_id = ?
      ORDER BY oi.id`,
    [businessId, orderId]
  );
  return rows.map((row) => ({
    id: row.id,
    productId: row.product_id,
    variantId: row.variant_id,
    productName: row.product_name,
    sku: row.sku,
    quantity: Number(row.quantity),
    unitPrice: Number(row.unit_price),
    lineTotal: Number(row.line_total),
    returned: Number(row.returned),
    remaining: Number(row.quantity) - Number(row.returned),
  }));
}

/** Everything a return needs to know about the order it is against. */
export async function findOrderForReturn({ businessId, orderId, conn = pool }) {
  const [rows] = await conn.query(
    `SELECT id, order_number, status, customer_id, grand_total, paid_amount
       FROM orders
      WHERE id = ? AND business_id = ? AND deleted_at IS NULL LIMIT 1`,
    [orderId, businessId]
  );
  return rows[0] ?? null;
}
