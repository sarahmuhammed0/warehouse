import { runInTransaction } from "../../db/pool.js";
import { errors } from "../../utils/AppError.js";
import { nextDocumentNumber } from "../documents/numbering.js";
import { originalSlots } from "../inventory/repository.js";
import { planInbound } from "../inventory/allocation.js";
import { adjustStock } from "../inventory/service.js";
import { defaultWarehouseId } from "../locations/repository.js";
import { totalPaid } from "../orders/repository.js";
import { paymentStatusFor } from "../orders/service.js";
import { returnableLines, returnItems } from "./repository.js";
import { notifyReturnRequest } from "../notifications/triggers.js";

/**
 * Returns (§16).
 *
 * THE POLICY, because §16 says only "per the configured return process" and a
 * warehouse cannot run on that: the project's approved reading (see
 * docs/architecture.md's decision table) is TWO-STAGE and CONDITION-GATED.
 *
 *   - Nothing moves on Approval. An approval is a decision, not a delivery;
 *     the goods are still in the customer's car.
 *   - On Completion, SELLABLE items go back into stock — into the slots they
 *     were sold from, so they reappear on the shelf the picker took them from.
 *   - DAMAGED items never re-enter stock. They came back, and the return
 *     document records that they came back damaged, but a warehouse that
 *     restocks a broken chair will eventually sell it.
 *   - The refund is money going back OUT, recorded against the order, so the
 *     order's paid figure falls and a refunded order stops reading as paid.
 */

/** §16's lifecycle. */
const ALLOWED_TRANSITIONS = {
  requested: ["approved", "rejected"],
  // A rejection after approval is still possible because NOTHING has moved
  // yet — that is the point of the two-stage policy. Once completed, the
  // goods are back on the shelf and the money is back with the customer, so
  // the document is closed.
  approved: ["completed", "rejected"],
  rejected: [],
  completed: [],
};

/** The order statuses a return can be raised against: the goods have left. */
const RETURNABLE_ORDER_STATUSES = new Set([
  "confirmed",
  "processing",
  "ready",
  "completed",
  "partially_returned",
]);

const money = (value) => Math.round((Number(value) + Number.EPSILON) * 100) / 100;
const qty = (value) => Math.round((Number(value) + Number.EPSILON) * 1000) / 1000;

export function assertTransition(from, to) {
  const allowed = ALLOWED_TRANSITIONS[from] ?? [];
  if (!allowed.includes(to)) {
    throw errors.conflict(`A return that is ${from} cannot become ${to}.`);
  }
}

export const isReturnable = (orderStatus) => RETURNABLE_ORDER_STATUSES.has(orderStatus);

/**
 * Prices the requested lines against the order they came from.
 *
 * The refund cap is what the customer actually paid for the quantity being
 * returned — the line's own total, pro-rated. Taking the client's figure on
 * trust would let a return refund more than the sale ever charged, and §61's
 * financial consistency is exactly the thing a refund can break.
 */
export function priceReturn({ lines, items, refundAmount }) {
  const byId = new Map(lines.map((line) => [String(line.id), line]));
  let cap = 0;

  const priced = items.map((item) => {
    const line = byId.get(String(item.orderItemId));
    if (!line) {
      throw errors.validation(`Line ${item.orderItemId} is not part of that order.`);
    }
    const quantity = qty(item.quantity);
    if (quantity > line.remaining + 0.0001) {
      throw errors.validation(
        line.remaining <= 0
          ? `"${line.productName}" has already been returned in full.`
          : `Only ${line.remaining} of "${line.productName}" can still be returned.`
      );
    }

    // Pro-rata, so a part-return of a discounted line refunds the discounted
    // price rather than the list price.
    const lineRefund = money((line.lineTotal * quantity) / line.quantity);
    cap += lineRefund;

    return {
      orderItemId: line.id,
      productId: line.productId,
      variantId: line.variantId ?? null,
      productName: line.productName,
      sku: line.sku,
      quantity,
      condition: item.condition ?? "sellable",
      refundAmount: lineRefund,
    };
  });

  cap = money(cap);
  const requested = refundAmount === undefined || refundAmount === null ? cap : money(refundAmount);
  if (requested > cap + 0.0001) {
    throw errors.validation(
      `A refund of ${requested.toFixed(2)} exceeds the ${cap.toFixed(2)} paid for those items.`
    );
  }

  return { items: priced, refundAmount: requested, cap };
}

/** Creates a return request. Nothing moves — §16's first stage is a decision. */
export async function createReturn({ businessId, userId, order, data }) {
  return runInTransaction(async (conn) => {
    const lines = await returnableLines({ businessId, orderId: order.id, conn });
    const priced = priceReturn({ lines, items: data.items, refundAmount: data.refundAmount });

    const returnNumber = await nextDocumentNumber(conn, { businessId, documentType: "return" });

    const [result] = await conn.query(
      `INSERT INTO returns
         (business_id, order_id, customer_id, return_number, status, reason,
          refund_amount, note, return_date, created_by)
       VALUES (?, ?, ?, ?, 'requested', ?, ?, ?, ?, ?)`,
      [
        businessId,
        order.id,
        order.customer_id ?? null,
        returnNumber,
        data.reason,
        priced.refundAmount,
        data.note ?? null,
        data.returnDate ?? new Date(),
        userId,
      ]
    );
    const returnId = result.insertId;

    for (const item of priced.items) {
      await conn.query(
        `INSERT INTO return_items
           (business_id, return_id, order_item_id, product_id, variant_id, product_name, sku,
            quantity, item_condition, refund_amount)
         VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
        [
          businessId,
          returnId,
          item.orderItemId,
          item.productId,
          item.variantId,
          item.productName,
          item.sku,
          item.quantity,
          item.condition,
          item.refundAmount,
        ]
      );
    }

    // §31: a return request is waiting for a decision, which is exactly the kind
    // of thing that sits unnoticed until the customer rings to ask.
    await notifyReturnRequest(conn, {
      businessId,
      returnId,
      returnNumber,
      reason: data.reason,
    });

    return { returnId, returnNumber };
  });
}

/**
 * §16's second stage, and the only place a return touches stock or money.
 *
 * Runs on the caller's connection — it is called with the return row already
 * locked, and opening a second transaction here would check out another
 * connection and wait on the lock the caller is holding.
 */
export async function completeReturn(conn, { businessId, userId, returned }) {
  const items = await returnItems({ businessId, returnId: returned.id, conn });

  // Sellable goods go back to the slots they were sold from. Damaged goods do
  // not go back at all — see this module's header.
  const sellable = items.filter((item) => item.item_condition === "sellable");

  if (sellable.length) {
    const origins = await originalSlots({
      businessId,
      referenceType: "order",
      referenceId: returned.order_id,
      conn,
    });
    const slotKey = (item) => `${item.product_id}:${item.variant_id ?? 0}`;

    // Only needed if the ledger cannot account for a line — a quick sale
    // recorded before the shelf existed, say.
    const fallback = await defaultWarehouseId(businessId, conn);

    for (const item of sellable) {
      const legs = planInbound({
        recorded: origins.get(slotKey(item)),
        quantity: Number(item.quantity),
        fallbackWarehouseId: fallback,
      });
      for (const leg of legs) {
        await adjustStock({
          businessId,
          userId,
          productId: item.product_id,
          variantId: item.variant_id ?? null,
          warehouseId: leg.warehouseId,
          locationId: leg.locationId,
          delta: +leg.quantity,
          movementType: "return",
          referenceType: "return",
          referenceId: returned.id,
          referenceNumber: returned.return_number,
          reason: "Returned by customer",
          conn,
        });
      }
    }
  }

  const refund = money(returned.refund_amount);
  if (refund > 0) {
    // A refund is money leaving, recorded against the ORDER so the order's
    // own paid figure falls. `totalPaid` nets the two directions, which is
    // why a refund must not be written as another `incoming` payment.
    await conn.query(
      `INSERT INTO payments
         (business_id, order_id, direction, amount, method, reference, note, paid_at, created_by)
       VALUES (?, ?, 'outgoing', ?, 'cash', ?, ?, NOW(), ?)`,
      [businessId, returned.order_id, refund, returned.return_number, "Customer refund", userId]
    );

    const paidAmount = await totalPaid({ businessId, orderId: returned.order_id, conn });
    const [[order]] = await conn.query(`SELECT grand_total FROM orders WHERE id = ?`, [
      returned.order_id,
    ]);
    await conn.query(
      `UPDATE orders SET paid_amount = ?, payment_status = ?, updated_at = NOW() WHERE id = ? AND business_id = ?`,
      [
        paidAmount,
        paymentStatusFor({ grandTotal: Number(order.grand_total), paidAmount }),
        returned.order_id,
        businessId,
      ]
    );
  }

  // Marked completed FIRST, because the order's own status is decided from the
  // completed returns — including this one.
  await conn.query(
    `UPDATE returns SET status = 'completed', completed_at = NOW(), updated_at = NOW()
      WHERE id = ? AND business_id = ? AND status = ?`,
    [returned.id, businessId, returned.status]
  );

  await settleOrderReturnStatus(conn, { businessId, orderId: returned.order_id });
}

/**
 * Moves the ORDER to `returned` or `partially_returned` (§16).
 *
 * This is the one sanctioned way a completed order's status changes, which is
 * why it does not go through the order module's `assertTransition` — that map
 * makes `completed` terminal precisely so nothing else can move it.
 */
async function settleOrderReturnStatus(conn, { businessId, orderId }) {
  // COMPLETED returns only, and deliberately not the wider "not rejected" set
  // `returnableLines` uses. That set exists to stop two requests claiming the
  // same three chairs; this one answers a different question — how much has
  // actually come back — and a merely requested return must not make an order
  // read as partially returned before anyone has approved it.
  const [[totals]] = await conn.query(
    `SELECT
       (SELECT COALESCE(SUM(oi.quantity), 0) FROM order_items oi
         WHERE oi.business_id = ? AND oi.order_id = ?) AS sold,
       (SELECT COALESCE(SUM(ri.quantity), 0) FROM return_items ri
          JOIN returns r ON r.id = ri.return_id
         WHERE r.business_id = ? AND r.order_id = ?
           AND r.status = 'completed' AND r.deleted_at IS NULL) AS returned`,
    [businessId, orderId, businessId, orderId]
  );

  const sold = qty(totals.sold);
  const returnedQuantity = qty(totals.returned);
  if (returnedQuantity <= 0) return;

  const status = returnedQuantity + 0.0001 >= sold ? "returned" : "partially_returned";
  await conn.query(
    `UPDATE orders SET status = ?, updated_at = NOW() WHERE id = ? AND business_id = ?`,
    [status, orderId, businessId]
  );
}
