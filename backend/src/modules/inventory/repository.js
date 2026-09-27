import { defineListSpec, buildWhere, buildOrderBy } from "../../db/listQuery.js";
import { queryAll, queryCount, queryOne } from "../../db/pool.js";

/**
 * Inventory (§10/§12). Two tables, two different things:
 *
 *   `inventory`            — STATE. How much is where, right now.
 *   `inventory_movements`  — HISTORY. Every change, append-only, forever.
 *
 * Neither is derivable from the other cheaply enough to drop one. Summing
 * millions of movements to answer "how many chairs" is the query §59 cannot
 * afford; and a level with no history cannot answer §12's "who moved this,
 * and when". They are kept honest by being written in the same transaction,
 * never one without the other.
 */

const levelListSpec = defineListSpec({
  filters: {
    productId: { column: "i.product_id", type: "int" },
    warehouseId: { column: "i.warehouse_id", type: "int" },
    locationId: { column: "i.location_id", type: "int" },
    categoryId: { column: "p.category_id", type: "int" },
  },
  search: { columns: ["p.name", "p.sku", "p.barcode"] },
  sort: {
    allowed: {
      product: "p.name",
      quantity: "i.quantity",
      updatedAt: "i.updated_at",
    },
    default: { key: "product", direction: "ASC" },
  },
  dateRange: { column: "i.updated_at" },
});

const LEVEL_JOINS = `
  JOIN products p        ON p.id = i.product_id AND p.business_id = i.business_id
  JOIN warehouses w      ON w.id = i.warehouse_id AND w.business_id = i.business_id
  LEFT JOIN storage_locations sl ON sl.id = i.location_id
  LEFT JOIN units un     ON un.id = p.unit_id`;

/** Stock levels, one row per (product, variant, warehouse, location) slot. */
export async function listLevels({ businessId, query, pagination }) {
  const where = buildWhere(levelListSpec, query, {
    "i.business_id": businessId,
    "p.deleted_at": null,
  });
  const orderBy = buildOrderBy(levelListSpec, query, "i.id");

  const rows = await queryAll(
    `SELECT i.id, i.product_id, i.variant_id, i.warehouse_id, i.location_id,
            i.quantity, i.reserved_quantity, i.updated_at,
            p.name AS product_name, p.sku, p.reorder_level, p.max_stock,
            w.name AS warehouse_name, sl.name AS location_name,
            un.code AS unit_code
       FROM inventory i ${LEVEL_JOINS} ${where.sql} ${orderBy} LIMIT ? OFFSET ?`,
    [...where.params, pagination.pageSize, pagination.offset]
  );

  const total = await queryCount(
    `SELECT COUNT(*) AS total FROM inventory i ${LEVEL_JOINS} ${where.sql}`,
    where.params
  );

  return { rows, total };
}

const movementListSpec = defineListSpec({
  filters: {
    productId: { column: "m.product_id", type: "int" },
    warehouseId: { column: "m.warehouse_id", type: "int" },
    movementType: {
      column: "m.movement_type",
      type: "enum",
      values: [
        "purchase",
        "sale",
        "return",
        "damage",
        "adjustment",
        "transfer",
        "production",
        "manual_increase",
        "manual_decrease",
      ],
    },
  },
  search: { columns: ["p.name", "p.sku", "m.reason", "m.reference_number"] },
  sort: {
    allowed: { movedAt: "m.moved_at", product: "p.name" },
    // §12's ledger reads newest first: the question is almost always "what
    // just happened", not "what happened when we opened".
    default: { key: "movedAt", direction: "DESC" },
  },
  dateRange: { column: "m.moved_at" },
});

const MOVEMENT_JOINS = `
  JOIN products p    ON p.id = m.product_id AND p.business_id = m.business_id
  LEFT JOIN warehouses w ON w.id = m.warehouse_id
  LEFT JOIN storage_locations sl ON sl.id = m.location_id
  LEFT JOIN users u  ON u.id = m.user_id`;

/** §12's stock-movement history. */
export async function listMovements({ businessId, query, pagination }) {
  const where = buildWhere(movementListSpec, query, { "m.business_id": businessId });
  const orderBy = buildOrderBy(movementListSpec, query, "m.id");

  const rows = await queryAll(
    `SELECT m.id, m.product_id, m.warehouse_id, m.location_id, m.movement_type,
            m.quantity, m.quantity_before, m.quantity_after,
            m.reference_type, m.reference_id, m.reference_number,
            m.reason, m.note, m.user_id, m.moved_at,
            p.name AS product_name, p.sku,
            w.name AS warehouse_name, sl.name AS location_name,
            u.name AS user_name
       FROM inventory_movements m ${MOVEMENT_JOINS} ${where.sql} ${orderBy} LIMIT ? OFFSET ?`,
    [...where.params, pagination.pageSize, pagination.offset]
  );

  const total = await queryCount(
    `SELECT COUNT(*) AS total FROM inventory_movements m ${MOVEMENT_JOINS} ${where.sql}`,
    where.params
  );

  return { rows, total };
}

/**
 * The stock row for one slot, locked FOR UPDATE.
 *
 * The lock is the whole point. Two concurrent sales of the last item would
 * otherwise both read "1 available", both decide it is fine, and both write
 * 0 — overselling by one. Reading the row FOR UPDATE inside the transaction
 * makes the second wait for the first to commit, so it sees the real level.
 */
export async function lockSlot(conn, { businessId, productId, warehouseId, locationId = null, variantId = null }) {
  const [rows] = await conn.query(
    `SELECT id, quantity, reserved_quantity FROM inventory
      WHERE business_id = ? AND product_id = ? AND warehouse_id = ?
        AND COALESCE(location_id, 0) = COALESCE(?, 0)
        AND COALESCE(variant_id, 0) = COALESCE(?, 0)
      LIMIT 1
      FOR UPDATE`,
    [businessId, productId, warehouseId, locationId, variantId]
  );
  return rows[0] ?? null;
}

/**
 * Returns the slot, locked, creating it at zero if this is the first time
 * anything has been stored there.
 *
 * The row is created FIRST and only then locked — the same gap-lock trap as
 * document numbering. Locking a row that does not exist takes a GAP lock,
 * and two concurrent movements into a new (product, warehouse) slot would
 * each hold one and then collide on `uq_inventory_slot`, failing one of
 * them and rolling back whatever order it belonged to.
 *
 * `ON DUPLICATE KEY UPDATE` is a no-op that exists only to take the row
 * lock: the unique index covers the generated `variant_key`/`location_key`
 * columns, so a concurrent insert of the same slot queues behind the first
 * instead of erroring.
 */
export async function ensureSlot(conn, args) {
  const { businessId, productId, warehouseId, locationId = null, variantId = null } = args;
  await conn.query(
    `INSERT INTO inventory (business_id, product_id, variant_id, warehouse_id, location_id, quantity, reserved_quantity)
     VALUES (?, ?, ?, ?, ?, 0, 0)
     ON DUPLICATE KEY UPDATE updated_at = updated_at`,
    [businessId, productId, variantId, warehouseId, locationId]
  );
  return lockSlot(conn, args);
}

/** Applies a delta to a locked slot and records the movement — together. */
export async function applyMovement(
  conn,
  {
    businessId,
    slot,
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
    userId,
  }
) {
  const before = Number(slot.quantity);
  const after = before + delta;

  await conn.query(`UPDATE inventory SET quantity = ?, updated_at = NOW() WHERE id = ?`, [after, slot.id]);

  // §12: every movement carries product, quantity, before, after, type,
  // user, date, location, note and reference. The quantity stored is a
  // magnitude — the type carries the direction — which is why the CHECK
  // constraint can require it to be positive.
  await conn.query(
    `INSERT INTO inventory_movements
       (business_id, product_id, variant_id, warehouse_id, location_id, movement_type,
        quantity, quantity_before, quantity_after, reference_type, reference_id,
        reference_number, reason, note, user_id, moved_at)
     VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, NOW())`,
    [
      businessId,
      productId,
      variantId,
      warehouseId,
      locationId,
      movementType,
      Math.abs(delta),
      before,
      after,
      referenceType,
      referenceId,
      referenceNumber,
      reason,
      note,
      userId,
    ]
  );

  return { before, after };
}

/**
 * The slots inside one warehouse that actually hold this product, fullest
 * first.
 *
 * Stock is tracked per SLOT — a warehouse, and optionally a shelf, rack or
 * bin inside it (§11). So "ship it from the default warehouse" does not yet
 * say where the goods come from: a business that puts its stock on shelf A-1
 * holds nothing at all in that warehouse's location-less slot, and a sale
 * that debits only that slot is refused for want of stock the business is
 * standing next to.
 *
 * Fullest first, so a line is satisfied from as few shelves as possible.
 *
 * NOT `FOR UPDATE`, deliberately, and this cost a round of intermittent
 * failures to learn. Locking the whole range looks safer and is not: the read
 * only decides a PLAN, and every leg of that plan then goes through
 * `adjustStock`, which locks its own slot with `ensureSlot` and recomputes the
 * level under that lock — so two concurrent sales cannot oversell whatever this
 * read told them. What the range lock did add was a deadlock class: a
 * range scan takes gap locks across the index, `ensureSlot` inserts into those
 * same gaps, and two transactions working on neighbouring slots could each hold
 * what the other needed. MySQL kills one, `databaseError.js` maps it to a 409,
 * and a perfectly ordinary confirmation fails for no reason the user can see.
 *
 * The cost of reading unlocked is a stale plan: a leg can find less than it
 * expected and be refused with "Insufficient stock" while another shelf still
 * had some. That fails in the safe direction — nothing is ever oversold — and
 * the caller retries.
 */
export async function stockedSlots({ businessId, productId, variantId = null, warehouseId, conn }) {
  const [rows] = await conn.query(
    `SELECT warehouse_id, location_id, quantity FROM inventory
      WHERE business_id = ? AND product_id = ? AND warehouse_id = ?
        AND COALESCE(variant_id, 0) = COALESCE(?, 0)
        AND quantity > 0
      ORDER BY quantity DESC, id ASC`,
    [businessId, productId, warehouseId, variantId]
  );
  return rows.map((row) => ({
    warehouseId: row.warehouse_id,
    locationId: row.location_id,
    quantity: Number(row.quantity),
  }));
}

/**
 * Which slots a document's stock actually moved through, and how much through
 * each, keyed by product and variant.
 *
 * Undoing a stock movement has to put the goods back where they were, or take
 * them back from where they were put. The obvious shortcut — use the default
 * warehouse — is wrong twice over: the default can be changed between the sale
 * and the cancellation, and a business with more than one warehouse sells from
 * all of them. Either way the stock silently teleports to another building,
 * and the ledger reads as though it was always there.
 *
 * A list per key, not one slot, because one line can move through several
 * shelves (see `stockedSlots`) — collapsing it to the first would pile all ten
 * units back onto the shelf that only ever held four.
 *
 * The direction has to be read from the LEVELS, not from the quantity: the
 * stored quantity is a magnitude, so a return of 3 and a sale of 3 are the same
 * number, and the sale must not be mistaken for the return that undid it.
 *
 * @param {"out"|"in"} moved  "out" for the slots stock LEFT (a sale), "in" for
 *                            the slots it was PUT INTO (a purchase receipt)
 */
async function documentSlots({ businessId, referenceType, referenceId, moved, conn }) {
  const direction = moved === "in" ? "quantity_after > quantity_before" : "quantity_after < quantity_before";
  const [rows] = await conn.query(
    `SELECT product_id, variant_id, warehouse_id, location_id, quantity
       FROM inventory_movements
      WHERE business_id = ? AND reference_type = ? AND reference_id = ?
        AND ${direction}
      ORDER BY id`,
    [businessId, referenceType, referenceId]
  );

  const slots = new Map();
  for (const row of rows) {
    const key = `${row.product_id}:${row.variant_id ?? 0}`;
    if (!slots.has(key)) slots.set(key, []);
    slots.get(key).push({
      warehouseId: row.warehouse_id,
      locationId: row.location_id,
      quantity: Number(row.quantity),
    });
  }
  return slots;
}

/** The slots a document's stock LEFT — where a cancellation returns it to. */
export const originalSlots = (args) => documentSlots({ ...args, moved: "out" });

/** The slots a document's stock was PUT INTO — where a reversal takes it from. */
export const receivedSlots = (args) => documentSlots({ ...args, moved: "in" });

/**
 * §47's switch: negative stock is allowed "only through an explicit business
 * setting". Read from `business_settings`, defaulting to false — the safe
 * answer for a business that has never configured it.
 */
export async function allowsNegativeStock(businessId, conn) {
  const runner = conn
    ? async (sql, params) => (await conn.query(sql, params))[0][0] ?? null
    : queryOne;
  const row = await runner(
    `SELECT setting_value FROM business_settings
      WHERE business_id = ? AND setting_key = 'inventory.allow_negative_stock' LIMIT 1`,
    [businessId]
  );
  if (!row) return false;
  const raw = typeof row.setting_value === "string" ? row.setting_value : JSON.stringify(row.setting_value);
  return raw === "true" || raw === '"true"' || raw === "1";
}

/** §44's alerts: everything at or below its reorder level. */
export async function lowStockProducts({ businessId, limit = 50 }) {
  return queryAll(
    `SELECT p.id, p.name, p.sku, p.reorder_level, p.max_stock,
            COALESCE(SUM(i.quantity), 0) AS current_quantity
       FROM products p
       LEFT JOIN inventory i ON i.product_id = p.id
      WHERE p.business_id = ? AND p.deleted_at IS NULL AND p.status = 'active'
      GROUP BY p.id
     HAVING current_quantity <= p.reorder_level
      ORDER BY (current_quantity - p.reorder_level) ASC
      LIMIT ?`,
    [businessId, limit]
  );
}
