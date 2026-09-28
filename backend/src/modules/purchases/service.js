import { runInTransaction } from "../../db/pool.js";
import { errors } from "../../utils/AppError.js";
import { nextDocumentNumber } from "../documents/numbering.js";
import { receivedSlots } from "../inventory/repository.js";
import { planOutbound, planInbound, recordedTotal } from "../inventory/allocation.js";
import { adjustStock } from "../inventory/service.js";
import { defaultWarehouseId } from "../locations/repository.js";
import { productSnapshot, variantSnapshot } from "../orders/repository.js";
import { assertPaymentMethodAllowed } from "../settings/policy.js";

/**
 * Purchases from suppliers (§20, §25, §43).
 *
 * The mirror image of the orders module, and deliberately built the same way:
 * a document with lines, a status that decides whether stock has moved, and
 * totals the server computes. The difference is only the direction — a
 * purchase brings goods IN and sends money OUT — so anything that reads the
 * same in both places (numbering, allocation, the payment split) is shared
 * rather than restated.
 */

/** §20's lifecycle. Which transitions are legal, and from where. */
const ALLOWED_TRANSITIONS = {
  draft: ["pending", "completed", "cancelled"],
  pending: ["completed", "cancelled"],
  // A completed purchase can still be cancelled — a delivery is rejected, or
  // was recorded against the wrong supplier — and the goods go back out. What
  // it cannot do is quietly revert to pending with the stock still received.
  completed: ["cancelled"],
  cancelled: [],
};

/**
 * The status at which the goods are actually in the building.
 *
 * Stock moves once, when the purchase is COMPLETED. A pending purchase is an
 * order placed with a supplier and nothing more: counting it as stock is how a
 * warehouse comes to believe it can sell goods still sitting on a lorry.
 */
const STOCK_RECEIVED_FROM = new Set(["completed"]);

export const receivesStock = (status) => STOCK_RECEIVED_FROM.has(status);

/** Rounds to the two decimals every money column actually stores — see orders. */
const money = (value) => Math.round((Number(value) + Number.EPSILON) * 100) / 100;

export function assertTransition(from, to) {
  const allowed = ALLOWED_TRANSITIONS[from] ?? [];
  if (!allowed.includes(to)) {
    throw errors.conflict(`A purchase that is ${from} cannot become ${to}.`);
  }
}

/** §20's payment status, derived from the two numbers rather than stored twice. */
export function paymentStatusFor({ total, paidAmount }) {
  if (paidAmount <= 0) return "unpaid";
  if (paidAmount + 0.0001 >= total) return "paid";
  return "partially_paid";
}

/**
 * Totals, computed server-side from the lines (§43).
 *
 * Never taken from the client, for the same reason as an order's: a total the
 * browser calculated is a total whoever controls the browser can choose, and
 * §25's purchase-cost reporting is only as trustworthy as these numbers.
 */
export function calculateTotals({ items, discountAmount = 0, extraCharges = 0 }) {
  let subtotal = 0;
  let taxTotal = 0;

  const priced = items.map((item) => {
    const quantity = Number(item.quantity);
    const unitCost = Number(item.unitCost);
    const lineDiscount = money(item.discountAmount ?? 0);
    const base = money(money(quantity * unitCost) - lineDiscount);
    if (base < 0) {
      throw errors.validation("A line discount cannot exceed the line's own total.");
    }
    const tax = money(item.taxAmount ?? 0);

    subtotal += base;
    taxTotal += tax;

    return { ...item, quantity, unitCost, discountAmount: lineDiscount, taxAmount: tax, lineTotal: money(base + tax) };
  });

  subtotal = money(subtotal);
  taxTotal = money(taxTotal);

  const total = money(subtotal + taxTotal - money(discountAmount) + money(extraCharges));
  if (total < 0) {
    throw errors.validation("The discount cannot exceed the purchase total.");
  }

  return { items: priced, subtotal, taxTotal, total };
}

/**
 * The §55 snapshot lookup for a purchase line.
 *
 * A purchase line already freezes what was paid per unit; freezing the price
 * but not the name is the half-measure that leaves a two-year-old purchase
 * reading as though it had always been for the renamed product. The variant
 * lookup doubles as the ownership check (§36) — nothing else validates
 * `variantId`.
 */
export function productResolver(businessId) {
  return async (conn, item) => {
    const product = await productSnapshot(conn, { businessId, productId: item.productId });
    if (!product) throw errors.validation(`Product ${item.productId} does not exist.`);
    if (!item.variantId) return product;

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
 * Moves a purchase's goods, in whichever direction.
 *
 * `direction` is +1 when the goods arrive (completion) and -1 when they go back
 * out (a completed purchase later cancelled). Everything goes through
 * `adjustStock`, so the ledger is written and §47 is enforced per leg.
 *
 * `purchases` carries no warehouse of its own, so an arrival lands in the
 * business's default warehouse, location-less — the same place §12's manual
 * increase puts goods when no shelf is named. A reversal then takes them back
 * OUT of the slots the ledger says they were put into, which matters once the
 * receiving clerk has moved them onto a shelf: taking them from the default
 * slot would find nothing there and refuse a cancellation that is perfectly
 * reasonable.
 */
export async function moveStockForPurchase(
  conn,
  { businessId, userId, purchaseId, purchaseNumber, items, direction }
) {
  const slotKey = (item) => `${item.productId}:${item.variantId ?? 0}`;

  const received =
    direction < 0
      ? await receivedSlots({ businessId, referenceType: "purchase", referenceId: purchaseId, conn })
      : new Map();

  const recordedFor = (item) => recordedTotal(received.get(slotKey(item)));

  // Needed to receive into, and as the fallback for a reversal the ledger does
  // not fully account for.
  const needsDefault =
    direction > 0 || items.some((item) => recordedFor(item) < Number(item.quantity));
  const defaultId = needsDefault ? await defaultWarehouseId(businessId, conn) : null;
  if (needsDefault && !defaultId) {
    throw errors.validation("No default warehouse is configured. Create one before receiving stock.");
  }

  for (const item of items) {
    const quantity = Number(item.quantity);
    const legs =
      direction > 0
        ? planInbound({ recorded: [], quantity, fallbackWarehouseId: defaultId })
        : await reversalLegs(conn, { businessId, item, quantity, received: received.get(slotKey(item)), defaultId });

    for (const leg of legs) {
      await adjustStock({
        businessId,
        userId,
        productId: item.productId,
        variantId: item.variantId ?? null,
        warehouseId: leg.warehouseId,
        locationId: leg.locationId,
        delta: direction * leg.quantity,
        movementType: "purchase",
        referenceType: "purchase",
        referenceId: purchaseId,
        referenceNumber: purchaseNumber,
        reason: direction > 0 ? "Received from supplier" : "Purchase cancelled",
        conn,
      });
    }
  }
}

/**
 * Taking goods back out again: from the slots they were received into, as far
 * as those still hold them, and otherwise from wherever the warehouse has them.
 *
 * The second half matters because stock is fungible. Goods received onto A-1
 * and then transferred to B-2 are still the business's goods, and a
 * cancellation that insisted on A-1 would be refused for want of stock the
 * warehouse plainly has.
 */
async function reversalLegs(conn, { businessId, item, quantity, received = [], defaultId }) {
  const legs = [];
  let left = quantity;

  for (const slot of received) {
    if (left <= 0) break;
    const take = Math.min(left, slot.quantity);
    const available = await planOutbound(conn, {
      businessId,
      productId: item.productId,
      variantId: item.variantId ?? null,
      warehouseId: slot.warehouseId,
      quantity: take,
    });
    legs.push(...available);
    left = Math.round((left - take) * 1000) / 1000;
  }

  if (left > 0) {
    legs.push(
      ...(await planOutbound(conn, {
        businessId,
        productId: item.productId,
        variantId: item.variantId ?? null,
        warehouseId: defaultId,
        quantity: left,
      }))
    );
  }

  return legs;
}

/**
 * Creates a purchase with its lines, inside one transaction.
 *
 * The document number is allocated in the same transaction (§61.12), and if
 * the purchase is created already completed the goods are received inside it
 * too — a purchase that exists without the stock it brought in, because a
 * second request failed, is exactly the inconsistency §46 forbids.
 */
export async function createPurchase({ businessId, userId, data, resolveProduct }) {
  return runInTransaction(async (conn) => {
    const purchaseNumber = await nextDocumentNumber(conn, { businessId, documentType: "purchase" });
    const totals = calculateTotals({
      items: data.items,
      discountAmount: data.discountAmount ?? 0,
      extraCharges: data.extraCharges ?? 0,
    });

    // §20's flow is "record the purchase, receive it when it arrives", so a new
    // purchase is PENDING unless the caller says otherwise — a purchase being
    // entered after the goods are already on the shelf passes "completed".
    const status = data.status ?? "pending";
    const paidAmount = money(data.paidAmount ?? 0);
    if (paidAmount > totals.total + 0.0001) {
      throw errors.validation("The amount paid cannot exceed the purchase total.");
    }

    const [result] = await conn.query(
      `INSERT INTO purchases
         (business_id, supplier_id, purchase_number, status, subtotal, discount_amount,
          tax_amount, extra_charges, total, paid_amount, payment_status, note,
          purchase_date, completed_at, created_by)
       VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
      [
        businessId,
        data.supplierId ?? null,
        purchaseNumber,
        status,
        totals.subtotal,
        data.discountAmount ?? 0,
        totals.taxTotal,
        data.extraCharges ?? 0,
        totals.total,
        paidAmount,
        paymentStatusFor({ total: totals.total, paidAmount }),
        data.note ?? null,
        data.purchaseDate ?? new Date(),
        receivesStock(status) ? new Date() : null,
        userId,
      ]
    );
    const purchaseId = result.insertId;

    for (const item of totals.items) {
      const snapshot = await resolveProduct(conn, item);
      await conn.query(
        `INSERT INTO purchase_items
           (business_id, purchase_id, product_id, variant_id, product_name, sku,
            quantity, unit_cost, discount_amount, tax_amount, line_total)
         VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
        [
          businessId,
          purchaseId,
          item.productId,
          item.variantId ?? null,
          snapshot.name,
          snapshot.sku ?? null,
          item.quantity,
          item.unitCost,
          item.discountAmount,
          item.taxAmount,
          item.lineTotal,
        ]
      );
    }

    if (paidAmount > 0) {
      await recordPayment(conn, {
        businessId,
        purchaseId,
        amount: paidAmount,
        method: data.paymentMethod ?? "cash",
        reference: data.paymentReference ?? null,
        userId,
      });
    }

    if (receivesStock(status)) {
      await moveStockForPurchase(conn, {
        businessId,
        userId,
        purchaseId,
        purchaseNumber,
        items: totals.items,
        direction: +1,
      });
    }

    return { purchaseId, purchaseNumber };
  });
}

/**
 * §43's supplier payment — money out, so `outgoing`.
 *
 * The one place a purchase payment is written, which is why the method check
 * lives here: both the initial `paidAmount` on creation and a later instalment
 * come through this function, so neither can record a method §34 has switched
 * off.
 */
export async function recordPayment(conn, { businessId, purchaseId, amount, method, reference, note = null, userId }) {
  await assertPaymentMethodAllowed({ businessId, method, conn });
  await conn.query(
    `INSERT INTO payments
       (business_id, purchase_id, direction, amount, method, reference, note, paid_at, created_by)
     VALUES (?, ?, 'outgoing', ?, ?, ?, ?, NOW(), ?)`,
    [businessId, purchaseId, amount, method, reference, note, userId]
  );
}
