import { errors } from "../../utils/AppError.js";
import { transferStock } from "../inventory/service.js";
import { transferItems } from "./repository.js";
import { notifyTransferReceived } from "../notifications/triggers.js";

/**
 * §11's transfer, as a document with a lifecycle.
 *
 * `POST /api/inventory/transfer` already moves stock between two slots in one
 * atomic step, and still does — that is the right shape for a clerk moving a
 * pallet now. This module is the other case §11 describes: a transfer that is
 * RAISED, travels, and ARRIVES, possibly between buildings and possibly not
 * today. It therefore has a status, and stock moves when it is confirmed
 * arrived — not when it is written down.
 */

/** §11's lifecycle. */
const ALLOWED_TRANSITIONS = {
  draft: ["pending", "in_transit", "completed", "cancelled"],
  pending: ["in_transit", "completed", "cancelled"],
  in_transit: ["completed", "cancelled"],
  // Terminal. The goods are on the destination shelf; undoing that is a new
  // transfer in the other direction, which is also what a warehouse would do.
  completed: [],
  cancelled: [],
};

/**
 * Stock moves at COMPLETION, once, and in one step.
 *
 * `in_transit` is deliberately NOT a stock state. Modelling goods as "left the
 * source but not arrived" would need a third place for them to sit — an
 * in-transit slot nothing else understands — and every report would then have to
 * know about it. The honest simplification is that the stock is the source's
 * until it arrives, and the document says it is travelling.
 */
const MOVED_AT = "completed";

export const movesStock = (status) => status === MOVED_AT;

export function assertTransition(from, to) {
  const allowed = ALLOWED_TRANSITIONS[from] ?? [];
  if (!allowed.includes(to)) {
    throw errors.conflict(`A transfer that is ${from} cannot become ${to}.`);
  }
}

export function assertDifferentSlots(data) {
  const sameWarehouse = String(data.fromWarehouseId) === String(data.toWarehouseId);
  const sameLocation = String(data.fromLocationId ?? "") === String(data.toLocationId ?? "");
  if (sameWarehouse && sameLocation) {
    throw errors.validation("The source and destination are the same location.");
  }
}

/**
 * Moves every line of the transfer, inside the caller's transaction.
 *
 * Each line goes through `transferStock`, which is the inventory module's own
 * two-legged move: out of the source slot and into the destination, with a
 * ledger row for each leg (§12) and §47 deciding whether the source may go
 * short. Doing it here line by line rather than reimplementing the move is what
 * keeps a transfer's stock effect identical to a direct one.
 */
export async function moveTransferStock(conn, { businessId, userId, transfer }) {
  const items = await transferItems({ businessId, transferId: transfer.id, conn });
  if (items.length === 0) {
    throw errors.validation("A transfer with no items moves nothing.");
  }

  for (const item of items) {
    await transferStock({
      businessId,
      userId,
      productId: item.product_id,
      variantId: item.variant_id ?? null,
      fromWarehouseId: transfer.from_warehouse_id,
      fromLocationId: transfer.from_location_id ?? null,
      toWarehouseId: transfer.to_warehouse_id,
      toLocationId: transfer.to_location_id ?? null,
      quantity: Number(item.quantity),
      note: transfer.note ?? null,
      // §12: the ledger names the document that caused the movement, so a
      // stock count that looks wrong can be traced back to this transfer.
      referenceType: "transfer",
      referenceId: transfer.id,
      referenceNumber: transfer.transfer_number,
      conn,
    });
  }

  // §31: the goods have landed, and somebody at the destination has to put them
  // away. Raised here rather than in the route because this is the function that
  // knows the stock actually moved.
  const [[destination]] = await conn.query(`SELECT name FROM warehouses WHERE id = ? LIMIT 1`, [
    transfer.to_warehouse_id,
  ]);
  await notifyTransferReceived(conn, {
    businessId,
    transferId: transfer.id,
    transferNumber: transfer.transfer_number,
    toWarehouseName: destination?.name ?? null,
  });
}
