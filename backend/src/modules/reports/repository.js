import { queryAll } from "../../db/pool.js";

/**
 * §25's reports, computed in the database.
 *
 * Every figure here comes from documents the business recorded — orders,
 * purchases, movements, returns — and nothing is estimated or filled in. A
 * report with an invented number in it is worse than a missing report, because
 * someone will make a decision on it.
 *
 * All of them are tenant-scoped and take a date range. The range is applied to
 * the DOCUMENT's own date (an order's `order_date`, a purchase's
 * `purchase_date`) rather than to `created_at`: a business entering last week's
 * paperwork today means it to count as last week's.
 */

/** A closed range, or open at either end. Both bounds are inclusive by date. */
function rangeClause(column, { from, to }) {
  const parts = [];
  const params = [];
  if (from) {
    parts.push(`${column} >= ?`);
    params.push(`${from} 00:00:00`);
  }
  if (to) {
    parts.push(`${column} <= ?`);
    params.push(`${to} 23:59:59`);
  }
  return { sql: parts.length ? `AND ${parts.join(" AND ")}` : "", params };
}

/**
 * The order statuses that count as business done.
 *
 * A draft or pending order is a conversation, not revenue, and a cancelled one
 * never happened. Counting either would make every sales figure optimistic —
 * the same rule the customer-balance queries already use.
 */
const COUNTED_ORDERS = `o.status NOT IN ('draft', 'pending', 'cancelled')`;
const COUNTED_PURCHASES = `pu.status NOT IN ('draft', 'pending', 'cancelled')`;

// ---- stock ---------------------------------------------------------------

/** §25's inventory report: what is on hand, where, and what it is worth. */
export async function inventoryReport({ businessId }) {
  return queryAll(
    `SELECT p.id AS product_id, p.name, p.sku, p.reorder_level,
            u.code AS unit_code,
            c.name AS category_name,
            COALESCE(SUM(i.quantity), 0) AS quantity,
            p.purchase_cost,
            p.selling_price,
            -- Valued at what it cost, not what it might sell for: §61's
            -- financial figures are what the business has spent and received,
            -- and an unsold item has not earned its margin yet.
            ROUND(COALESCE(SUM(i.quantity), 0) * COALESCE(p.purchase_cost, 0), 2) AS stock_value
       FROM products p
       LEFT JOIN inventory i ON i.product_id = p.id AND i.business_id = p.business_id
       LEFT JOIN units u     ON u.id = p.unit_id
       LEFT JOIN categories c ON c.id = p.category_id AND c.business_id = p.business_id
      WHERE p.business_id = ? AND p.deleted_at IS NULL
      GROUP BY p.id
      ORDER BY p.name`,
    [businessId]
  );
}

/** §12's ledger, totalled by movement type. */
export async function stockMovementReport({ businessId, from, to }) {
  const range = rangeClause("m.moved_at", { from, to });
  return queryAll(
    `SELECT m.movement_type,
            COUNT(*) AS movements,
            SUM(m.quantity) AS total_quantity,
            COUNT(DISTINCT m.product_id) AS products
       FROM inventory_movements m
      WHERE m.business_id = ? ${range.sql}
      GROUP BY m.movement_type
      ORDER BY m.movement_type`,
    [businessId, ...range.params]
  );
}

// ---- sales and money -----------------------------------------------------

/** §25's sales report, one row per month. */
export async function salesByMonth({ businessId, from, to }) {
  const range = rangeClause("o.order_date", { from, to });
  return queryAll(
    `SELECT DATE_FORMAT(o.order_date, '%Y-%m') AS period,
            COUNT(*) AS orders,
            SUM(o.subtotal) AS subtotal,
            SUM(o.tax_amount) AS tax,
            SUM(o.discount_amount) AS discount,
            SUM(o.grand_total) AS total,
            SUM(o.paid_amount) AS paid,
            SUM(o.grand_total - o.paid_amount) AS outstanding
       FROM orders o
      WHERE o.business_id = ? AND o.deleted_at IS NULL AND ${COUNTED_ORDERS} ${range.sql}
      GROUP BY period
      ORDER BY period`,
    [businessId, ...range.params]
  );
}

/** The same shape for purchases, so revenue and cost can be read side by side. */
export async function purchasesByMonth({ businessId, from, to }) {
  const range = rangeClause("pu.purchase_date", { from, to });
  return queryAll(
    `SELECT DATE_FORMAT(pu.purchase_date, '%Y-%m') AS period,
            COUNT(*) AS purchases,
            SUM(pu.subtotal) AS subtotal,
            SUM(pu.tax_amount) AS tax,
            SUM(pu.total) AS total,
            SUM(pu.paid_amount) AS paid,
            SUM(pu.total - pu.paid_amount) AS outstanding
       FROM purchases pu
      WHERE pu.business_id = ? AND pu.deleted_at IS NULL AND ${COUNTED_PURCHASES} ${range.sql}
      GROUP BY period
      ORDER BY period`,
    [businessId, ...range.params]
  );
}

/** What each product actually sold, by quantity and by value (§25's top sellers). */
export async function productSalesReport({ businessId, from, to, limit = 100 }) {
  const range = rangeClause("o.order_date", { from, to });
  return queryAll(
    `SELECT oi.product_id, oi.product_name, oi.sku,
            SUM(oi.quantity) AS quantity_sold,
            SUM(oi.line_total) AS revenue,
            COUNT(DISTINCT o.id) AS orders
       FROM order_items oi
       JOIN orders o ON o.id = oi.order_id AND o.business_id = oi.business_id
      WHERE oi.business_id = ? AND o.deleted_at IS NULL AND ${COUNTED_ORDERS} ${range.sql}
      GROUP BY oi.product_id, oi.product_name, oi.sku
      ORDER BY revenue DESC
      LIMIT ?`,
    [businessId, ...range.params, limit]
  );
}

/** §25's customer report: what each customer has bought and still owes (§18). */
export async function customerReport({ businessId, from, to }) {
  const range = rangeClause("o.order_date", { from, to });
  return queryAll(
    `SELECT c.id AS customer_id, c.name, c.phone,
            COUNT(o.id) AS orders,
            COALESCE(SUM(o.grand_total), 0) AS total,
            COALESCE(SUM(o.paid_amount), 0) AS paid,
            COALESCE(SUM(o.grand_total - o.paid_amount), 0) AS outstanding,
            MAX(o.order_date) AS last_order_date
       FROM customers c
       LEFT JOIN orders o
         ON o.customer_id = c.id AND o.business_id = c.business_id
        AND o.deleted_at IS NULL AND ${COUNTED_ORDERS} ${range.sql}
      WHERE c.business_id = ? AND c.deleted_at IS NULL
      GROUP BY c.id
      ORDER BY outstanding DESC, total DESC`,
    [...range.params, businessId]
  );
}

/**
 * §25/§43's outstanding balances, both directions.
 *
 * Receivable is what customers owe on orders; payable is what this business owes
 * suppliers on purchases. Returned as one call because the question "how exposed
 * are we" needs both halves, and fetching them separately invites showing one.
 */
export async function outstandingReport({ businessId }) {
  const receivable = await queryAll(
    `SELECT o.id, o.order_number, o.order_date, o.status, o.payment_status,
            o.grand_total, o.paid_amount, (o.grand_total - o.paid_amount) AS outstanding,
            c.name AS customer_name
       FROM orders o
       LEFT JOIN customers c ON c.id = o.customer_id AND c.business_id = o.business_id
      WHERE o.business_id = ? AND o.deleted_at IS NULL AND ${COUNTED_ORDERS}
        AND (o.grand_total - o.paid_amount) > 0
      ORDER BY outstanding DESC`,
    [businessId]
  );

  const payable = await queryAll(
    `SELECT pu.id, pu.purchase_number, pu.purchase_date, pu.status, pu.payment_status,
            pu.total, pu.paid_amount, (pu.total - pu.paid_amount) AS outstanding,
            s.name AS supplier_name
       FROM purchases pu
       LEFT JOIN suppliers s ON s.id = pu.supplier_id AND s.business_id = pu.business_id
      WHERE pu.business_id = ? AND pu.deleted_at IS NULL AND ${COUNTED_PURCHASES}
        AND (pu.total - pu.paid_amount) > 0
      ORDER BY outstanding DESC`,
    [businessId]
  );

  return { receivable, payable };
}

// ---- the other documents -------------------------------------------------

/** §22's production history, totalled by month. */
export async function productionReport({ businessId, from, to }) {
  const range = rangeClause("po.created_at", { from, to });
  return queryAll(
    `SELECT DATE_FORMAT(po.created_at, '%Y-%m') AS period,
            po.status,
            COUNT(*) AS runs,
            SUM(po.quantity_planned) AS planned,
            SUM(po.quantity_produced) AS produced,
            SUM(COALESCE(po.production_cost, 0)) AS cost
       FROM production_orders po
      WHERE po.business_id = ? AND po.deleted_at IS NULL ${range.sql}
      GROUP BY period, po.status
      ORDER BY period, po.status`,
    [businessId, ...range.params]
  );
}

/** §16's returns, by status and reason volume. */
export async function returnsReport({ businessId, from, to }) {
  const range = rangeClause("r.return_date", { from, to });
  return queryAll(
    `SELECT r.status,
            COUNT(*) AS returns,
            SUM(r.refund_amount) AS refunded,
            COALESCE(SUM((
              SELECT SUM(ri.quantity) FROM return_items ri WHERE ri.return_id = r.id
            )), 0) AS quantity
       FROM returns r
      WHERE r.business_id = ? AND r.deleted_at IS NULL ${range.sql}
      GROUP BY r.status
      ORDER BY r.status`,
    [businessId, ...range.params]
  );
}

/** §11's transfers, by status. */
export async function transfersReport({ businessId, from, to }) {
  const range = rangeClause("t.transfer_date", { from, to });
  return queryAll(
    `SELECT t.status,
            COUNT(*) AS transfers,
            COALESCE(SUM((
              SELECT SUM(i.quantity) FROM stock_transfer_items i WHERE i.transfer_id = t.id
            )), 0) AS quantity
       FROM stock_transfers t
      WHERE t.business_id = ? AND t.deleted_at IS NULL ${range.sql}
      GROUP BY t.status
      ORDER BY t.status`,
    [businessId, ...range.params]
  );
}
