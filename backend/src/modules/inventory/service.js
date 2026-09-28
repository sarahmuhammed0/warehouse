import { runInTransaction } from "../../db/pool.js";
import { errors } from "../../utils/AppError.js";
import { ensureSlot, applyMovement, allowsNegativeStock } from "./repository.js";

/**
 * The one place stock changes.
 *
 * Every caller — a manual adjustment now, a sale or a purchase later — goes
 * through here, so §12's guarantee holds by construction rather than by
 * everyone remembering: the level and the ledger move together, inside one
 * transaction, or neither moves.
 *
 * §47's negative-stock rule lives here too, for a reason that is easy to get
 * wrong: it CANNOT be a database CHECK. The specification says negative
 * inventory is permitted "only through an explicit business setting", and a
 * CHECK cannot read a setting — it would make the permitted case impossible.
 * So the service is the only layer that can decide, and it refuses by
 * default.
 */
export async function adjustStock({
  businessId,
  userId,
  productId,
  variantId = null,
  warehouseId,
  locationId = null,
  delta,
  movementType,
  reason = null,
  note = null,
  referenceType = null,
  referenceId = null,
  referenceNumber = null,
  conn = null,
}) {
  if (!Number.isFinite(delta) || delta === 0) {
    // §54: a movement of zero is not a movement, and the CHECK constraint
    // on inventory_movements.quantity would refuse it anyway — better to
    // say why than to surface a database error.
    throw errors.validation("The quantity must not be zero.");
  }

  const run = async (transaction) => {
    const slot = await ensureSlot(transaction, {
      businessId,
      productId,
      warehouseId,
      locationId,
      variantId,
    });

    const before = Number(slot.quantity);
    const after = before + delta;

    if (after < 0 && !(await allowsNegativeStock(businessId, transaction))) {
      // §47's own example wording: the message names what is actually
      // available, because "insufficient stock" alone leaves the user
      // guessing how much they can take.
      throw errors.conflict(`Insufficient stock. Available quantity: ${before}.`);
    }

    const result = await applyMovement(transaction, {
      businessId,
      slot,
      productId,
      variantId,
      warehouseId,
      locationId,
      delta,
      movementType,
      reason,
      note,
      referenceType,
      referenceId,
      referenceNumber,
      userId,
    });

    return { productId, warehouseId, locationId, ...result };
  };

  // A caller already inside a transaction (a sale writing several lines)
  // passes its connection so everything commits or rolls back as one unit.
  // Starting a nested transaction here would silently commit half a sale.
  return conn ? run(conn) : runInTransaction(run);
}

/**
 * §11's location-to-location transfer, as one atomic operation.
 *
 * Both legs happen in a single transaction, so there is never a moment where
 * stock has left the source and not arrived at the destination — a window in
 * which the business would simply appear to own less than it does.
 */
export async function transferStock({
  businessId,
  userId,
  productId,
  variantId = null,
  fromWarehouseId,
  fromLocationId = null,
  toWarehouseId,
  toLocationId = null,
  quantity,
  note = null,
  referenceNumber = null,
  referenceType = null,
  referenceId = null,
  // A caller that is already inside a transaction — a transfer DOCUMENT moving
  // all of its lines (§11) — passes its connection. Opening a second
  // transaction here would check out another connection and then wait on the
  // locks the caller is holding, until MySQL times it out. Same rule as
  // `adjustStock` and `cancelOrder`.
  conn = null,
}) {
  if (!(quantity > 0)) throw errors.validation("The transfer quantity must be greater than zero.");

  const sameSlot =
    String(fromWarehouseId) === String(toWarehouseId) &&
    String(fromLocationId ?? "") === String(toLocationId ?? "");
  if (sameSlot) {
    throw errors.validation("The source and destination are the same location.");
  }

  const run = async (conn) => {
    const out = await adjustStock({
      businessId,
      userId,
      productId,
      variantId,
      warehouseId: fromWarehouseId,
      locationId: fromLocationId,
      delta: -quantity,
      movementType: "transfer",
      reason: "Transfer out",
      note,
      referenceType,
      referenceId,
      referenceNumber,
      conn,
    });

    const into = await adjustStock({
      businessId,
      userId,
      productId,
      variantId,
      warehouseId: toWarehouseId,
      locationId: toLocationId,
      delta: quantity,
      movementType: "transfer",
      reason: "Transfer in",
      note,
      referenceType,
      referenceId,
      referenceNumber,
      conn,
    });

    return { from: out, to: into, quantity };
  };

  return conn ? run(conn) : runInTransaction(run);
}
