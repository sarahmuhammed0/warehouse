import { ok, paginated } from "../../utils/responseEnvelope.js";
import { parsePagination, paginationMeta } from "../../db/pagination.js";
import { errors } from "../../utils/AppError.js";
import { toAppError } from "../../utils/databaseError.js";
import { runInTransaction } from "../../db/pool.js";
import { loadPermissions } from "../../middleware/authorize.js";
import {
  listOrders,
  findOrder,
  lockOrder,
  orderItems,
  orderPayments,
  orderEdits,
  recordEdit,
  toStockLines,
  totalPaid,
  customerExists,
} from "./repository.js";
import {
  createOrder,
  productResolver,
  cancelOrder,
  assertTransition,
  paymentStatusFor,
  moveStockForOrder,
} from "./service.js";

const tenant = (req) => req.auth.businessId;
const num = (v) => (v === null || v === undefined ? null : Number(v));

function orderView(row) {
  const grandTotal = num(row.grand_total) ?? 0;
  const paidAmount = num(row.paid_amount) ?? 0;
  return {
    id: row.id,
    orderNumber: row.order_number,
    orderType: row.order_type,
    status: row.status,
    paymentStatus: row.payment_status,
    customerId: row.customer_id,
    customerName: row.customer_name ?? null,
    customerPhone: row.customer_phone ?? null,
    subtotal: num(row.subtotal),
    discountAmount: num(row.discount_amount),
    taxAmount: num(row.tax_amount),
    extraCharges: num(row.extra_charges),
    grandTotal,
    paidAmount,
    // §43's remaining amount — derived, so it cannot disagree with the two
    // numbers it comes from.
    remainingAmount: grandTotal - paidAmount,
    itemCount: Number(row.item_count ?? 0),
    notes: row.notes,
    orderDate: row.order_date,
    completedAt: row.completed_at,
    cancelledAt: row.cancelled_at,
    cancelReason: row.cancel_reason,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
  };
}

const itemView = (row) => ({
  id: row.id,
  productId: row.product_id,
  productName: row.product_name,
  sku: row.sku,
  quantity: num(row.quantity),
  unitPrice: num(row.unit_price),
  discountAmount: num(row.discount_amount),
  taxAmount: num(row.tax_amount),
  lineTotal: num(row.line_total),
});

const constraintMessages = { uq_orders_number: "That order number is already in use." };

export async function list(req, res, next) {
  try {
    const pagination = parsePagination(req.query);
    const { rows, total } = await listOrders({ businessId: tenant(req), query: req.query, pagination });
    res.json(paginated(rows.map(orderView), paginationMeta(pagination, total)));
  } catch (err) {
    next(err);
  }
}

export async function get(req, res, next) {
  try {
    const businessId = tenant(req);
    const order = await findOrder({ businessId, id: req.params.id });
    if (!order) throw errors.notFound("order");

    const view = orderView(order);
    view.items = (await orderItems({ businessId, orderId: order.id })).map(itemView);

    const permissions = await loadPermissions(req);
    if (permissions.includes("financial.view")) {
      view.payments = (await orderPayments({ businessId, orderId: order.id })).map((p) => ({
        id: p.id,
        amount: num(p.amount),
        method: p.method,
        reference: p.reference,
        note: p.note,
        paidAt: p.paid_at,
        createdByName: p.created_by_name,
      }));
    }

    // §15: the edit trail belongs to the order, and is read-only.
    view.edits = (await orderEdits({ businessId, orderId: order.id })).map((e) => ({
      id: e.id,
      fieldName: e.field_name,
      previousValue: e.previous_value,
      newValue: e.new_value,
      reason: e.reason,
      changedByName: e.changed_by_name,
      createdAt: e.created_at,
    }));

    res.json(ok(view));
  } catch (err) {
    next(err);
  }
}

export async function create(req, res, next) {
  try {
    const businessId = tenant(req);

    if (req.body.customerId && !(await customerExists({ businessId, customerId: req.body.customerId }))) {
      throw errors.validation("The customer does not exist.");
    }

    const { orderId } = await createOrder({
      businessId,
      userId: req.auth.userId,
      data: req.body,
      // §55: the line snapshots the product as it is NOW. Passed in so the
      // service reads it inside the same transaction.
      resolveProduct: productResolver(businessId),
    });

    const order = await findOrder({ businessId, id: orderId });
    const view = orderView(order);
    view.items = (await orderItems({ businessId, orderId })).map(itemView);
    res.status(201).json(ok(view));
  } catch (err) {
    next(toAppError(err, { constraintMessages }) ?? err);
  }
}

/**
 * §14's status change. Stock moves when the order is confirmed, and this is
 * the only path that does it — so the rule lives in one place rather than
 * being repeated by every caller who might set a status.
 */
export async function updateStatus(req, res, next) {
  try {
    const businessId = tenant(req);
    const userId = req.auth.userId;
    const { status, reason } = req.body;

    // §17 requires a reason, so the record can answer "why" later. Checked
    // before opening a transaction, since it needs nothing from the row.
    if (status === "cancelled" && !reason) {
      throw errors.validation("A cancellation reason is required.");
    }

    const orderId = req.params.id;

    await runInTransaction(async (conn) => {
      // EVERY decision below is made from the LOCKED row, not from one read
      // on the pool beforehand. Reading first and acting after is a
      // check-then-act race: two concurrent confirmations would both see
      // "draft", both pass assertTransition, and both ship the stock.
      const order = await lockOrder({ businessId, id: orderId, conn });
      if (!order) throw errors.notFound("order");

      if (status === "cancelled") {
        const items = toStockLines(await orderItems({ businessId, orderId, conn }));
        await cancelOrder({ businessId, userId, order, reason, items, conn });
        return;
      }

      assertTransition(order.status, status);

      const committed = ["confirmed", "processing", "ready", "completed"];
      const committedBefore = committed.includes(order.status);
      const committedAfter = committed.includes(status);

      // Crossing into a committed status is when the goods leave. Moving
      // between two committed statuses must NOT move stock again.
      if (!committedBefore && committedAfter) {
        const items = toStockLines(await orderItems({ businessId, orderId, conn }));
        await moveStockForOrder(conn, {
          businessId,
          userId,
          orderId: order.id,
          orderNumber: order.order_number,
          items,
          direction: -1,
        });
      }

      await recordEdit(conn, {
        businessId,
        orderId: order.id,
        fieldName: "status",
        previousValue: order.status,
        newValue: status,
        reason,
        userId,
      });

      await conn.query(
        `UPDATE orders SET status = ?, updated_at = NOW(),
                completed_at = ${status === "completed" ? "NOW()" : "completed_at"}
          WHERE id = ? AND business_id = ? AND status = ?`,
        [status, order.id, businessId, order.status]
      );
    });

    res.json(ok(orderView(await findOrder({ businessId, id: orderId }))));
  } catch (err) {
    next(err);
  }
}

/**
 * §13's payments, including partial ones.
 *
 * `paid_amount` on the order is a running total maintained IN THE SAME
 * TRANSACTION as the payment row — it is stored because `payment_status`
 * is derived from it and must be indexable, and the two would drift if
 * written separately.
 */
export async function addPayment(req, res, next) {
  try {
    const businessId = tenant(req);
    const userId = req.auth.userId;
    const { amount, method, reference, note } = req.body;

    const orderId = req.params.id;

    const result = await runInTransaction(async (conn) => {
      // Lock the order FIRST, and read every number from the locked row.
      // Without this, two payments arriving together both read the same
      // "already paid" total, both fit under the remaining balance, and both
      // are accepted — leaving paid_amount contradicting the payments it is
      // supposed to summarise.
      const locked = await lockOrder({ businessId, id: orderId, conn });
      if (!locked) throw errors.notFound("order");
      if (locked.status === "cancelled") {
        throw errors.conflict("A cancelled order cannot take a payment.");
      }

      const alreadyPaid = await totalPaid({ businessId, orderId: locked.id, conn });
      const grandTotal = Number(locked.grand_total);

      if (alreadyPaid + Number(amount) > grandTotal + 0.0001) {
        // Overpaying is almost always a typo, and letting it through
        // produces a negative balance that looks like the business owes
        // the customer money.
        throw errors.validation(
          `That exceeds the remaining balance of ${(grandTotal - alreadyPaid).toFixed(2)}.`
        );
      }

      await conn.query(
        `INSERT INTO payments (business_id, order_id, direction, amount, method, reference, note, paid_at, created_by)
         -- 'incoming': money coming IN from a customer. A purchase
         -- payment is 'outgoing' — see the purchases module.
         VALUES (?, ?, 'incoming', ?, ?, ?, ?, NOW(), ?)`,
        [businessId, locked.id, amount, method, reference ?? null, note ?? null, userId]
      );

      const paidAmount = alreadyPaid + Number(amount);
      await conn.query(
        `UPDATE orders SET paid_amount = ?, payment_status = ?, updated_at = NOW()
          WHERE id = ? AND business_id = ?`,
        [paidAmount, paymentStatusFor({ grandTotal, paidAmount }), locked.id, businessId]
      );

      return { orderId: locked.id, paidAmount, remainingAmount: grandTotal - paidAmount };
    });

    res.status(201).json(ok(result));
  } catch (err) {
    next(err);
  }
}
