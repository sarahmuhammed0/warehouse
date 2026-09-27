import { ok, paginated } from "../../utils/responseEnvelope.js";
import { parsePagination, paginationMeta } from "../../db/pagination.js";
import { errors } from "../../utils/AppError.js";
import { toAppError } from "../../utils/databaseError.js";
import { runInTransaction } from "../../db/pool.js";
import {
  listReturns,
  findReturn,
  lockReturn,
  returnItems,
  returnableLines,
  findOrderForReturn,
} from "./repository.js";
import { createReturn, completeReturn, assertTransition, isReturnable } from "./service.js";

const tenant = (req) => req.auth.businessId;
const num = (v) => (v === null || v === undefined ? null : Number(v));

const returnView = (row) => ({
  id: row.id,
  returnNumber: row.return_number,
  status: row.status,
  orderId: row.order_id,
  orderNumber: row.order_number ?? null,
  customerId: row.customer_id,
  customerName: row.customer_name ?? null,
  reason: row.reason,
  refundAmount: num(row.refund_amount),
  note: row.note,
  itemCount: Number(row.item_count ?? 0),
  returnDate: row.return_date,
  completedAt: row.completed_at,
  createdBy: row.created_by,
  createdByName: row.created_by_name ?? null,
  approvedBy: row.approved_by,
  approvedByName: row.approved_by_name ?? null,
  createdAt: row.created_at,
  updatedAt: row.updated_at,
});

const itemView = (row) => ({
  id: row.id,
  orderItemId: row.order_item_id,
  productId: row.product_id,
  variantId: row.variant_id,
  productName: row.product_name,
  sku: row.sku,
  quantity: num(row.quantity),
  condition: row.item_condition,
  refundAmount: num(row.refund_amount),
});

const constraintMessages = { uq_returns_number: "That return number is already in use." };

export async function list(req, res, next) {
  try {
    const pagination = parsePagination(req.query);
    const { rows, total } = await listReturns({ businessId: tenant(req), query: req.query, pagination });
    res.json(paginated(rows.map(returnView), paginationMeta(pagination, total)));
  } catch (err) {
    next(err);
  }
}

export async function get(req, res, next) {
  try {
    const businessId = tenant(req);
    const returned = await findReturn({ businessId, id: req.params.id });
    if (!returned) throw errors.notFound("return");

    const view = returnView(returned);
    view.items = (await returnItems({ businessId, returnId: returned.id })).map(itemView);
    res.json(ok(view));
  } catch (err) {
    next(err);
  }
}

/**
 * What can still be returned from an order, and for how much.
 *
 * The return form needs this before it can offer anything: which lines the
 * order had, how many of each are left after earlier returns, and what the
 * customer actually paid for them. Computing it in the browser would mean
 * trusting the browser's idea of how much is left.
 */
export async function returnable(req, res, next) {
  try {
    const businessId = tenant(req);
    const order = await findOrderForReturn({ businessId, orderId: req.params.id });
    if (!order) throw errors.notFound("order");

    const lines = await returnableLines({ businessId, orderId: order.id });
    res.json(
      ok({
        orderId: order.id,
        orderNumber: order.order_number,
        status: order.status,
        returnable: isReturnable(order.status),
        customerId: order.customer_id,
        lines,
      })
    );
  } catch (err) {
    next(err);
  }
}

export async function create(req, res, next) {
  try {
    const businessId = tenant(req);
    const order = await findOrderForReturn({ businessId, orderId: req.body.orderId });
    if (!order) throw errors.validation("The order does not exist.");

    // §16 returns goods that were sold. An order whose stock never left has
    // nothing to give back, and a cancelled one already gave it back.
    if (!isReturnable(order.status)) {
      throw errors.validation(`An order that is ${order.status} has nothing to return.`);
    }

    const { returnId } = await createReturn({
      businessId,
      userId: req.auth.userId,
      order,
      data: req.body,
    });

    const returned = await findReturn({ businessId, id: returnId });
    const view = returnView(returned);
    view.items = (await returnItems({ businessId, returnId })).map(itemView);
    res.status(201).json(ok(view));
  } catch (err) {
    next(toAppError(err, { constraintMessages }) ?? err);
  }
}

/**
 * §16's decision points. Approving records who decided; completing is the only
 * path that restocks and refunds, so that rule lives in one place.
 */
export async function updateStatus(req, res, next) {
  try {
    const businessId = tenant(req);
    const userId = req.auth.userId;
    const { status } = req.body;
    const returnId = req.params.id;

    await runInTransaction(async (conn) => {
      // Every decision comes from the LOCKED row: two concurrent completions
      // would otherwise both see "approved" and both restock the goods.
      const returned = await lockReturn({ businessId, id: returnId, conn });
      if (!returned) throw errors.notFound("return");

      assertTransition(returned.status, status);

      if (status === "completed") {
        await completeReturn(conn, { businessId, userId, returned });
        return;
      }

      await conn.query(
        `UPDATE returns SET status = ?, updated_at = NOW(),
                approved_by = ${status === "approved" ? "?" : "approved_by"}
          WHERE id = ? AND business_id = ? AND status = ?`,
        status === "approved"
          ? [status, userId, returned.id, businessId, returned.status]
          : [status, returned.id, businessId, returned.status]
      );
    });

    const returned = await findReturn({ businessId, id: returnId });
    const view = returnView(returned);
    view.items = (await returnItems({ businessId, returnId })).map(itemView);
    res.json(ok(view));
  } catch (err) {
    next(toAppError(err) ?? err);
  }
}
