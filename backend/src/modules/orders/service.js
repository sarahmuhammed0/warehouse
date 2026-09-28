import { runInTransaction } from "../../db/pool.js";
import { errors } from "../../utils/AppError.js";
import { nextDocumentNumber } from "../documents/numbering.js";
import { originalSlots } from "../inventory/repository.js";
import { planOutbound, planInbound, recordedTotal } from "../inventory/allocation.js";
import { adjustStock } from "../inventory/service.js";
import { defaultWarehouseId } from "../locations/repository.js";
import { recordEdit, productSnapshot, variantSnapshot } from "./repository.js";
import { notifyNewOrder } from "../notifications/triggers.js";

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
  /**
   * REOPENING, and only to `pending` — the approved scope in
   * docs/architecture.md's decision table ("Cancelled → Pending only,
   * permission-gated"), which the transition map had left out.
   *
   * `pending` specifically, never straight back to `confirmed`: cancelling
   * returned the goods to stock, so a reopened order has no claim on them.
   * Landing in `pending` means the stock leaves again when someone confirms
   * it — through the one path that moves stock — rather than the order
   * quietly re-acquiring inventory it had given back.
   */
  cancelled: ["pending"],
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

/**
 * Rounds to the two decimals every money column actually stores.
 *
 * Without this the totals in the response are not the totals in the database:
 * `grand_total` is DECIMAL(14,2), so MySQL rounds whatever it is given, and an
 * order's stored lines then add up to *near* its stored total rather than to
 * it. That gap is what leaves an invoice a cent short, and what makes
 * `addPayment`'s remaining-balance check disagree with the figure the customer
 * was shown. The epsilon nudge is for the usual binary-float edge (1.005).
 */
const money = (value) => Math.round((Number(value) + Number.EPSILON) * 100) / 100;

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
    const lineDiscount = money(item.discountAmount ?? 0);
    const base = money(money(quantity * unitPrice) - lineDiscount);
    if (base < 0) {
      // A per-line discount larger than the line itself makes the line pay
      // the customer. The order-level check below cannot catch it, because
      // one negative line is easily hidden by other positive ones.
      throw errors.validation("A line discount cannot exceed the line's own total.");
    }
    const tax = money(
      item.taxRate ? (base * Number(item.taxRate)) / 100 : Number(item.taxAmount ?? 0)
    );

    subtotal += base;
    taxTotal += tax;

    return {
      ...item,
      quantity,
      unitPrice,
      discountAmount: lineDiscount,
      taxAmount: tax,
      lineTotal: money(base + tax),
    };
  });

  subtotal = money(subtotal);
  taxTotal = money(taxTotal);

  const grandTotal = money(subtotal + taxTotal - money(discountAmount) + money(extraCharges));
  if (grandTotal < 0) {
    throw errors.validation("The discount cannot exceed the order total.");
  }

  return { items: priced, subtotal, taxTotal, grandTotal };
}

/**
 * The §55 snapshot lookup `createOrder` calls for each line.
 *
 * A factory here rather than a closure in the controller, so the tests drive
 * the REAL resolver: a hand-written stand-in in a test cannot fail when
 * production's variant ownership check changes, which is precisely when it
 * should.
 */
export function productResolver(businessId) {
  return async (conn, item) => {
    const product = await productSnapshot(conn, { businessId, productId: item.productId });
    if (!product) throw errors.validation(`Product ${item.productId} does not exist.`);
    if (!item.variantId) return product;

    // §9: a variant line snapshots the VARIANT's identity — its own SKU is
    // what the warehouse will be asked to pick. The lookup also doubles as
    // the ownership check (§36): nothing else validates `variantId`, so
    // without it a line could carry another tenant's variant, or a variant
    // belonging to an entirely different product.
    const variant = await variantSnapshot(conn, {
      businessId,
      productId: item.productId,
      variantId: item.variantId,
    });
    if (!variant) {
      throw errors.validation(`Variant ${item.variantId} does not belong to that product.`);
    }
    return {
      name: variant.name ? `${product.name} — ${variant.name}` : product.name,
      sku: variant.sku ?? product.sku,
    };
  };
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
      const product = await resolveProduct(conn, item);
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

    // §31: somebody should know a sale came in. Raised on creation rather than
    // on confirmation, because the point of the message is that there is
    // something new to deal with.
    //
    // The customer's name is looked up rather than taken from the request: the
    // client sends an id, and a notification that read "Walk-in" for every named
    // customer would be worse than no notification — it would be wrong.
    let customerName = null;
    if (data.customerId) {
      const [[customer]] = await conn.query(
        `SELECT name FROM customers WHERE id = ? AND business_id = ? LIMIT 1`,
        [data.customerId, businessId]
      );
      customerName = customer?.name ?? null;
    }

    await notifyNewOrder(conn, {
      businessId,
      orderId,
      orderNumber,
      customerName,
      total: totals.grandTotal,
    });

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
  const slotKey = (item) => `${item.productId}:${item.variantId ?? 0}`;

  // Goods coming back go back where they came from, in the quantities they
  // left in, not to whatever the default warehouse is today — see
  // originalSlots.
  const origins =
    direction > 0
      ? await originalSlots({ businessId, referenceType: "order", referenceId: orderId, conn })
      : new Map();

  const recordedFor = (item) => recordedTotal(origins.get(slotKey(item)));

  // The default is the warehouse an outbound line is drawn from, and the
  // fallback for a returned line the ledger does not fully account for (a
  // line added after the order shipped).
  const needsDefault =
    direction < 0 || items.some((item) => recordedFor(item) < Number(item.quantity));
  const defaultId = needsDefault ? await defaultWarehouseId(businessId, conn) : null;
  if (needsDefault && !defaultId) {
    // Better than a foreign-key error three layers down: the business has
    // simply never set up a warehouse, and that is fixable.
    throw errors.validation("No default warehouse is configured. Create one before selling stock.");
  }

  for (const item of items) {
    const quantity = Number(item.quantity);
    // One line can span several shelves in either direction, so what moves
    // is a plan of legs rather than a single slot.
    const legs =
      direction > 0
        ? planInbound({ recorded: origins.get(slotKey(item)), quantity, fallbackWarehouseId: defaultId })
        : await planOutbound(conn, {
            businessId,
            productId: item.productId,
            variantId: item.variantId ?? null,
            warehouseId: defaultId,
            quantity,
          });

    for (const leg of legs) {
      await adjustStock({
        businessId,
        userId,
        productId: item.productId,
        // §9's variants share a product but not a stock level, so a movement
        // that forgets the variant credits or debits the wrong slot entirely.
        variantId: item.variantId ?? null,
        warehouseId: leg.warehouseId,
        locationId: leg.locationId,
        delta: direction * leg.quantity,
        movementType,
        referenceType: "order",
        referenceId: orderId,
        referenceNumber: orderNumber,
        reason: direction < 0 ? "Sold" : "Returned to stock",
        conn,
      });
    }
  }
}


/**
 * §17's cancellation: who, when, why, and what it was before.
 *
 * `conn` is the caller's transaction, and passing it is not optional in
 * practice: the caller has the order row locked, and `runInTransaction`
 * checks out a SECOND connection, which would then wait on that lock until
 * MySQL's timeout fires. Same rule as `adjustStock`.
 */
export async function cancelOrder({ businessId, userId, order, reason, items, conn = null }) {
  const run = async (conn) => {
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
              cancel_reason = ?, status_before_cancel = ?, updated_at = NOW()
        WHERE id = ? AND business_id = ? AND status = ?`,
      [userId, reason, order.status, order.id, businessId, order.status]
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
  };

  return conn ? run(conn) : runInTransaction(run);
}
