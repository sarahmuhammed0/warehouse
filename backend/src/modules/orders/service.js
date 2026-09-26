import { runInTransaction } from "../../db/pool.js";
import { errors } from "../../utils/AppError.js";
import { nextDocumentNumber } from "../documents/numbering.js";
import { adjustStock } from "../inventory/service.js";
import { defaultWarehouseId } from "../locations/repository.js";
import { recordEdit } from "./repository.js";

/**
 * Sales and orders (§13–§15, §17, §43).
 *
 * ONE TABLE FOR BOTH. §13's sale and §14's order share every column and
 * every line-item shape; they differ in whether the goods leave immediately.
 * `order_type` is that difference, and two tables would have meant two of
 * everything — two numbering sequences, two payment paths, two sets of
 * stock effects that must agree.
 */

/** §14's lifecycle. Which transitions are legal, and from where. */
const ALLOWED_TRANSITIONS = {
  draft: ["pending", "confirmed", "cancelled"],
  pending: ["confirmed", "cancelled"],
  confirmed: ["processing", "ready", "completed", "cancelled"],
  processing: ["ready", "completed", "cancelled"],
  ready: ["completed", "cancelled"],
  // Terminal. A completed order is edited through a return (§16), not by
  // being moved back — §61's history must stay consistent.
  completed: [],
  cancelled: [],
  returned: [],
  partially_returned: ["returned"],
};

/**
 * The statuses at which stock has actually left the building.
 *
 * Stock moves once, when an order is CONFIRMED — not when it is drafted
 * (nothing is promised yet) and not when it is completed (by then it has
 * long gone). Getting this wrong in either direction is the classic
 * inventory bug: reserve too early and you cannot sell what you have;
 * too late and you sell what you have already given away.
 */
const STOCK_COMMITTED_FROM = new Set(["confirmed", "processing", "ready", "completed"]);

export function assertTransition(from, to) {
  const allowed = ALLOWED_TRANSITIONS[from] ?? [];
  if (!allowed.includes(to)) {
    throw errors.conflict(`An order that is ${from} cannot become ${to}.`);
  }
}

/** §13's payment status, derived from the two numbers rather than stored twice. */
export function paymentStatusFor({ grandTotal, paidAmount }) {
  if (paidAmount <= 0) return "unpaid";
  // A tolerance, because these are decimals: a customer who pays the exact
  // total to the fill should not be left a cent "unpaid".
  if (paidAmount + 0.0001 >= grandTotal) return "paid";
  return "partially_paid";
}

/**
 * Totals, computed server-side from the lines (§43).
 *
 * Never taken from the client: a total the browser calculated is a total an
 * attacker can choose, and a rounding difference between two clients would
 * produce invoices that do not add up.
 */
export function calculateTotals({ items, discountAmount = 0, extraCharges = 0 }) {
  let subtotal = 0;
  let taxTotal = 0;

  const priced = items.map((item) => {
    const quantity = Number(item.quantity);
    const unitPrice = Number(item.unitPrice);
    const lineDiscount = Number(item.discountAmount ?? 0);
    const base = quantity * unitPrice - lineDiscount;
    const tax = item.taxRate ? (base * Number(item.taxRate)) / 100 : Number(item.taxAmount ?? 0);

    subtotal += base;
    taxTotal += tax;

    return { ...item, quantity, unitPrice, discountAmount: lineDiscount, taxAmount: tax, lineTotal: base + tax };
  });

  const grandTotal = subtotal + taxTotal - Number(discountAmount) + Number(extraCharges);
  if (grandTotal < 0) {
    throw errors.validation("The discount cannot exceed the order total.");
  }

  return { items: priced, subtotal, taxTotal, grandTotal };
}

/**
 * Creates an order with its lines, inside one transaction.
 *
 * The document number is allocated in this same transaction (§61.12) — see
 * documents/numbering.js for why that matters.
 */
export async function createOrder({ businessId, userId, data, resolveProduct }) {
  return runInTransaction(async (conn) => {
    // §13's sale is numbered INV-, §14's order ORD- (see numbering.js).
    const documentType = data.orderType === "quick_sale" ? "sale" : "order";
    const orderNumber = await nextDocumentNumber(conn, { businessId, documentType });

    const totals = calculateTotals({
      items: data.items,
      discountAmount: data.discountAmount ?? 0,
      extraCharges: data.extraCharges ?? 0,
    });

    const status = data.status ?? "draft";
    const paidAmount = 0;

    const [result] = await conn.query(
      `INSERT INTO orders
         (business_id, customer_id, order_number, order_type, status, subtotal, discount_amount,
          tax_amount, extra_charges, grand_total, paid_amount, payment_status, notes,
          order_date, created_by)
       VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
      [
        businessId,
        data.customerId ?? null,
        orderNumber,
        data.orderType,
        status,
        totals.subtotal,
        data.discountAmount ?? 0,
        totals.taxTotal,
        data.extraCharges ?? 0,
        totals.grandTotal,
        paidAmount,
        paymentStatusFor({ grandTotal: totals.grandTotal, paidAmount }),
        data.notes ?? null,
        data.orderDate ?? new Date(),
        userId,
      ]
    );
    const orderId = result.insertId;

    for (const item of totals.items) {
      // §55: the line keeps the name, SKU and price AS THEY WERE. A product
      // renamed or repriced next year must not silently rewrite what this
      // invoice says was sold.
      const product = await resolveProduct(conn, item.productId);
      await conn.query(
        `INSERT INTO order_items
           (business_id, order_id, product_id, variant_id, product_name, sku,
            quantity, unit_price, discount_amount, tax_amount, line_total)
         VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
        [
          businessId,
          orderId,
          item.productId,
          item.variantId ?? null,
          product.name,
          product.sku,
          item.quantity,
          item.unitPrice,
          item.discountAmount,
          item.taxAmount,
          item.lineTotal,
        ]
      );
    }

    // If the order is created already confirmed, the stock leaves now.
    if (STOCK_COMMITTED_FROM.has(status)) {
      await moveStockForOrder(conn, {
        businessId,
        userId,
        orderId,
        orderNumber,
        items: totals.items,
        direction: -1,
      });
    }

    return { orderId, orderNumber };
  });
}

/**
 * Applies an order's stock effect, one movement per line.
 *
 * `direction` is -1 when goods leave (a sale) and +1 when they come back (a
 * cancellation or a return). Everything goes through `adjustStock`, so the
 * ledger is written and §47 is enforced for each line.
 */
export async function moveStockForOrder(
  conn,
  { businessId, userId, orderId, orderNumber, items, direction, movementType = "sale" }
) {
  const warehouseId = await defaultWarehouseId(businessId, conn);
  if (!warehouseId) {
    // Better than a foreign-key error three layers down: the business has
    // simply never set up a warehouse, and that is fixable.
    throw errors.validation("No default warehouse is configured. Create one before selling stock.");
  }

  for (const item of items) {
    await adjustStock({
      businessId,
      userId,
      productId: item.productId,
      warehouseId,
      delta: direction * Number(item.quantity),
      movementType,
      referenceType: "order",
      referenceId: orderId,
      referenceNumber: orderNumber,
      reason: direction < 0 ? "Sold" : "Returned to stock",
      conn,
    });
  }
}

/** §17's cancellation: who, when, why, and what it was before. */
export async function cancelOrder({ businessId, userId, order, reason, items }) {
  return runInTransaction(async (conn) => {
    assertTransition(order.status, "cancelled");

    // Stock only comes back if it actually left. Cancelling a draft that
    // never moved anything must not invent inventory.
    if (STOCK_COMMITTED_FROM.has(order.status)) {
      await moveStockForOrder(conn, {
        businessId,
        userId,
        orderId: order.id,
        orderNumber: order.order_number,
        items,
        direction: +1,
        movementType: "return",
      });
    }

    await conn.query(
      `UPDATE orders
          SET status = 'cancelled', cancelled_at = NOW(), cancelled_by = ?,
              cancel_reason = ?, status_before_cancel = ?
        WHERE id = ? AND business_id = ?`,
      [userId, reason, order.status, order.id, businessId]
    );

    // §17's own columns record who/when/why, but a cancellation is also a
    // status change, and §15's trail is where someone looks to see
    // everything that happened to this order in one list. Leaving it out
    // made the trail skip the single most important event.
    await recordEdit(conn, {
      businessId,
      orderId: order.id,
      fieldName: "status",
      previousValue: order.status,
      newValue: "cancelled",
      reason,
      userId,
    });
  });
}
