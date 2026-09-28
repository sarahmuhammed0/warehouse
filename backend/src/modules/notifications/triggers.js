// What actually RAISES a notification (§31).
//
// The table and the list endpoint are the easy half. A notifications screen that
// is always empty because nothing ever writes to it is the failure this file
// exists to prevent, so each trigger here is called from the code path that
// causes the event — inside the same transaction, so a notification cannot
// describe something that was rolled back.
//
// Only events a business would act on. "A product was edited" is in §30's audit
// trail, where history belongs; a notification is an interruption, and one that
// fires for everything is one nobody reads.

import { notify } from "./repository.js";
import { lowStockDefault } from "../settings/policy.js";

/**
 * §44's stock alert, raised when a movement takes a product to or below its
 * threshold.
 *
 * Checked after the movement rather than on a schedule: the moment stock crosses
 * the line is the moment someone can still do something about it, and a nightly
 * sweep would tell them the morning after they ran out.
 *
 * Never throws. A notification is a courtesy, and a failure to raise one must
 * not roll back the stock movement that earned it — the movement is the fact,
 * the notification is a message about it.
 */
export async function notifyStockLevel(conn, { businessId, productId, quantityAfter }) {
  try {
    const [[product]] = await conn.query(
      `SELECT name, sku, reorder_level FROM products
        WHERE id = ? AND business_id = ? AND deleted_at IS NULL LIMIT 1`,
      [productId, businessId]
    );
    if (!product) return;

    // The product's own threshold, or the business's default — the same rule
    // §44's low-stock list uses, so the alert and the list cannot disagree.
    const threshold =
      product.reorder_level === null
        ? await lowStockDefault({ businessId, conn })
        : Number(product.reorder_level);

    const quantity = Number(quantityAfter);
    const label = product.sku ? `${product.name} (${product.sku})` : product.name;

    if (quantity <= 0) {
      await notify(conn, {
        businessId,
        type: "out_of_stock",
        title: `Out of stock: ${product.name}`,
        body: `${label} has run out.`,
        referenceType: "products",
        referenceId: productId,
      });
      return;
    }

    if (quantity <= threshold) {
      await notify(conn, {
        businessId,
        type: "low_stock",
        title: `Low stock: ${product.name}`,
        body: `${label} is down to ${quantity}, at or below its threshold of ${threshold}.`,
        referenceType: "products",
        referenceId: productId,
      });
    }
  } catch {
    // Deliberately swallowed — see the note above. The movement stands.
  }
}

/** §31's "new order". Raised when an order is created, not when it is confirmed. */
export async function notifyNewOrder(conn, { businessId, orderId, orderNumber, customerName, total }) {
  try {
    await notify(conn, {
      businessId,
      type: "new_order",
      title: `New order ${orderNumber}`,
      body: customerName
        ? `${customerName} — ${Number(total).toFixed(2)}.`
        : `Walk-in — ${Number(total).toFixed(2)}.`,
      referenceType: "orders",
      referenceId: orderId,
    });
  } catch {
    /* a notification must not fail the order */
  }
}

/** §16's return request, which somebody has to approve. */
export async function notifyReturnRequest(conn, { businessId, returnId, returnNumber, reason }) {
  try {
    await notify(conn, {
      businessId,
      type: "return_request",
      title: `Return requested: ${returnNumber}`,
      body: reason ? `Reason: ${reason}` : "A return is waiting for approval.",
      referenceType: "returns",
      referenceId: returnId,
    });
  } catch {
    /* as above */
  }
}

/** §22's finished batch — the goods are on the shelf and can be sold. */
export async function notifyProductionCompleted(
  conn,
  { businessId, productionOrderId, productionNumber, productName, quantityProduced }
) {
  try {
    await notify(conn, {
      businessId,
      type: "production_completed",
      title: `Production complete: ${productionNumber}`,
      body: `${quantityProduced} × ${productName} are ready.`,
      referenceType: "production_orders",
      referenceId: productionOrderId,
    });
  } catch {
    /* as above */
  }
}

/** §11's arrival, so the receiving end knows to put it away. */
export async function notifyTransferReceived(
  conn,
  { businessId, transferId, transferNumber, toWarehouseName }
) {
  try {
    await notify(conn, {
      businessId,
      type: "transfer_received",
      title: `Transfer arrived: ${transferNumber}`,
      body: toWarehouseName ? `Received at ${toWarehouseName}.` : "A transfer has arrived.",
      referenceType: "stock_transfers",
      referenceId: transferId,
    });
  } catch {
    /* as above */
  }
}
