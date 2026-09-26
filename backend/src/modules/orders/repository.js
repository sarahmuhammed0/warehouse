import { defineListSpec, buildWhere, buildOrderBy } from "../../db/listQuery.js";
import { queryAll, queryCount, queryOne, pool } from "../../db/pool.js";

/** Sales and orders (§13/§14). */
const listSpec = defineListSpec({
  filters: {
    status: {
      column: "o.status",
      type: "enum",
      values: [
        "draft",
        "pending",
        "confirmed",
        "processing",
        "ready",
        "completed",
        "cancelled",
        "returned",
        "partially_returned",
      ],
    },
    orderType: { column: "o.order_type", type: "enum", values: ["standard", "quick_sale"] },
    paymentStatus: { column: "o.payment_status", type: "enum", values: ["paid", "partially_paid", "unpaid"] },
    customerId: { column: "o.customer_id", type: "int" },
  },
  search: { columns: ["o.order_number", "c.name", "c.phone"] },
  sort: {
    allowed: {
      orderNumber: "o.order_number",
      orderDate: "o.order_date",
      grandTotal: "o.grand_total",
      status: "o.status",
    },
    // Newest first: the question is almost always about a recent order.
    default: { key: "orderDate", direction: "DESC" },
  },
  dateRange: { column: "o.order_date" },
});

const JOINS = `LEFT JOIN customers c ON c.id = o.customer_id AND c.business_id = o.business_id`;

export async function listOrders({ businessId, query, pagination }) {
  const where = buildWhere(listSpec, query, { "o.business_id": businessId, "o.deleted_at": null });
  const orderBy = buildOrderBy(listSpec, query, "o.id");

  const rows = await queryAll(
    `SELECT o.id, o.order_number, o.order_type, o.status, o.payment_status,
            o.subtotal, o.discount_amount, o.tax_amount, o.extra_charges,
            o.grand_total, o.paid_amount, o.notes, o.order_date, o.completed_at,
            o.cancelled_at, o.cancel_reason, o.created_at, o.updated_at,
            o.customer_id, c.name AS customer_name, c.phone AS customer_phone,
            (SELECT COUNT(*) FROM order_items oi WHERE oi.order_id = o.id) AS item_count
       FROM orders o ${JOINS} ${where.sql} ${orderBy} LIMIT ? OFFSET ?`,
    [...where.params, pagination.pageSize, pagination.offset]
  );

  const total = await queryCount(
    `SELECT COUNT(*) AS total FROM orders o ${JOINS} ${where.sql}`,
    where.params
  );

  return { rows, total };
}

export async function findOrder({ businessId, id, conn = pool }) {
  const [rows] = await conn.query(
    `SELECT o.*, c.name AS customer_name, c.phone AS customer_phone
       FROM orders o ${JOINS}
      WHERE o.id = ? AND o.business_id = ? AND o.deleted_at IS NULL LIMIT 1`,
    [id, businessId]
  );
  return rows[0] ?? null;
}

export async function orderItems({ businessId, orderId, conn = pool }) {
  const [rows] = await conn.query(
    `SELECT id, product_id, variant_id, product_name, sku, quantity, unit_price,
            discount_amount, tax_amount, line_total
       FROM order_items WHERE business_id = ? AND order_id = ? ORDER BY id`,
    [businessId, orderId]
  );
  return rows;
}

/**
 * Order lines in the shape the stock service expects.
 *
 * Needed because `orderItems` returns raw database rows (`product_id`)
 * while a freshly-created order passes request-shaped lines (`productId`).
 * Both end up moving stock, and the mismatch is invisible until the path
 * that uses database rows runs — a cancellation inserted a NULL product
 * before this existed. One explicit conversion beats a service that quietly
 * accepts either spelling.
 */
export function toStockLines(rows) {
  return rows.map((row) => ({
    productId: row.product_id ?? row.productId,
    variantId: row.variant_id ?? row.variantId ?? null,
    quantity: Number(row.quantity),
  }));
}

export async function orderPayments({ businessId, orderId }) {
  return queryAll(
    `SELECT p.id, p.amount, p.method, p.reference, p.note, p.paid_at, p.created_by, u.name AS created_by_name
       FROM payments p LEFT JOIN users u ON u.id = p.created_by
      WHERE p.business_id = ? AND p.order_id = ? ORDER BY p.paid_at DESC, p.id DESC`,
    [businessId, orderId]
  );
}

/** §15's edit history — append-only, never overwritten. */
export async function orderEdits({ businessId, orderId }) {
  return queryAll(
    `SELECT e.id, e.field_name, e.previous_value, e.new_value, e.reason,
            e.created_at, u.name AS changed_by_name
       FROM order_edits e LEFT JOIN users u ON u.id = e.changed_by
      WHERE e.business_id = ? AND e.order_id = ? ORDER BY e.id DESC`,
    [businessId, orderId]
  );
}

/** §15: record a change rather than silently overwriting it. */
export async function recordEdit(
  conn,
  { businessId, orderId, orderItemId = null, fieldName, previousValue, newValue, reason, userId }
) {
  await conn.query(
    `INSERT INTO order_edits
       (business_id, order_id, order_item_id, field_name, previous_value, new_value, reason, changed_by)
     VALUES (?, ?, ?, ?, ?, ?, ?, ?)`,
    [
      businessId,
      orderId,
      orderItemId,
      fieldName,
      previousValue === null || previousValue === undefined ? null : String(previousValue),
      newValue === null || newValue === undefined ? null : String(newValue),
      reason ?? null,
      userId,
    ]
  );
}

/** The product fields a line must snapshot (§55). */
export async function productSnapshot(conn, { businessId, productId }) {
  const [rows] = await conn.query(
    `SELECT id, name, sku, selling_price FROM products
      WHERE id = ? AND business_id = ? AND deleted_at IS NULL LIMIT 1`,
    [productId, businessId]
  );
  return rows[0] ?? null;
}

export async function totalPaid({ businessId, orderId, conn = pool }) {
  const [rows] = await conn.query(
    `SELECT COALESCE(SUM(amount), 0) AS paid FROM payments WHERE business_id = ? AND order_id = ?`,
    [businessId, orderId]
  );
  return Number(rows[0].paid);
}

export async function customerExists({ businessId, customerId }) {
  const row = await queryOne(
    `SELECT 1 AS ok FROM customers WHERE id = ? AND business_id = ? AND deleted_at IS NULL LIMIT 1`,
    [customerId, businessId]
  );
  return Boolean(row);
}
