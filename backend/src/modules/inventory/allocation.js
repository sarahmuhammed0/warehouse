// Which SLOTS a document's stock moves through (§11, §12, §47).
//
// Stock is tracked per slot — a warehouse, and optionally a shelf, rack or bin
// inside it — so "this order ships 10" is not yet an instruction: something has
// to say which shelves the 10 come off, and a return has to say which shelves
// they go back onto. That decision is the same for a sale, a purchase
// reversal, a return and a production run, which is why it lives here rather
// than in whichever module needed it first.
//
// Everything here returns a PLAN — a list of legs, each naming a slot and a
// quantity — and moves nothing itself. The caller passes each leg to
// `adjustStock`, so the ledger and the level still move together in one
// transaction, and §47 still governs every single leg.

import { errors } from "../../utils/AppError.js";
import { stockedSlots, allowsNegativeStock } from "./repository.js";

/** Quantities are DECIMAL(14,3); this keeps the arithmetic there too. */
export const qty = (value) => Math.round((Number(value) + Number.EPSILON) * 1000) / 1000;

/**
 * Where a quantity comes OUT of: the slots in `warehouseId` that hold this
 * product, fullest first.
 *
 * Before this existed, an outbound move always debited the warehouse's
 * location-less slot and nothing else — so a business that had put its stock
 * away on a shelf, which is §11's whole point, could not sell it: every
 * confirmation answered "Insufficient stock. Available quantity: 0" with the
 * goods in plain sight on A-1.
 *
 * @returns {Promise<Array<{warehouseId: number, locationId: number|null, quantity: number}>>}
 */
export async function planOutbound(conn, { businessId, productId, variantId = null, warehouseId, quantity }) {
  const slots = await stockedSlots({ businessId, productId, variantId, warehouseId, conn });

  const legs = [];
  let left = quantity;
  for (const slot of slots) {
    if (left <= 0) break;
    const take = Math.min(left, slot.quantity);
    legs.push({ warehouseId, locationId: slot.locationId, quantity: qty(take) });
    left = qty(left - take);
  }

  if (left > 0) {
    // The warehouse does not hold enough. §47 decides what happens next, and
    // it decides on the WAREHOUSE's total rather than one shelf's: a business
    // told "Available quantity: 0" when nine of the ten it asked for are on
    // the shelf has been told something untrue.
    const available = qty(slots.reduce((sum, slot) => sum + slot.quantity, 0));
    if (!(await allowsNegativeStock(businessId, conn))) {
      throw errors.conflict(`Insufficient stock. Available quantity: ${available}.`);
    }
    // Explicitly permitted to go negative: the shortfall comes out of the slot
    // the goods nominally sit in — the fullest shelf, or the warehouse itself
    // when it holds none of this product at all.
    legs.push({ warehouseId, locationId: slots[0]?.locationId ?? null, quantity: left });
  }

  return legs;
}

/**
 * Where a quantity goes BACK to: the slots it came out of, in the quantities
 * it left in, read from the ledger (see `originalSlots`/`receivedSlots`).
 *
 * Anything the ledger does not account for — a line added after the document
 * moved, or a document that never moved stock at all — goes to
 * `fallbackWarehouseId`, location-less.
 *
 * @param {{recorded?: Array<{warehouseId: number, locationId: number|null, quantity: number}>,
 *          quantity: number, fallbackWarehouseId: number|null}} args
 */
export function planInbound({ recorded = [], quantity, fallbackWarehouseId }) {
  const legs = [];
  let left = quantity;
  for (const leg of recorded) {
    if (left <= 0) break;
    const give = Math.min(left, leg.quantity);
    legs.push({ warehouseId: leg.warehouseId, locationId: leg.locationId, quantity: qty(give) });
    left = qty(left - give);
  }
  if (left > 0) {
    if (!fallbackWarehouseId) {
      throw errors.validation("No default warehouse is configured. Create one before moving stock.");
    }
    legs.push({ warehouseId: fallbackWarehouseId, locationId: null, quantity: left });
  }
  return legs;
}

/** How much of a line the ledger already accounts for. */
export const recordedTotal = (recorded = []) => qty(recorded.reduce((sum, leg) => sum + leg.quantity, 0));
