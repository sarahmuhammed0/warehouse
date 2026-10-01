import { defineListSpec, buildWhere, buildOrderBy } from "../../db/listQuery.js";
import { queryAll, queryCount, pool } from "../../db/pool.js";

/** §11's stock transfers, as documents. */
const listSpec = defineListSpec({
  filters: {
    status: {
      column: "t.status",
      type: "enum",
      values: ["draft", "pending", "in_transit", "completed", "cancelled"],
    },
    fromWarehouseId: { column: "t.from_warehouse_id", type: "int" },
    toWarehouseId: { column: "t.to_warehouse_id", type: "int" },
  },
  search: { columns: ["t.transfer_number", "fw.name", "tw.name"] },
  sort: {
    allowed: {
      transferNumber: "t.transfer_number",
      transferDate: "t.transfer_date",
      status: "t.status",
    },
    default: { key: "transferDate", direction: "DESC" },
  },
  dateRange: { column: "t.transfer_date" },
});

const JOINS = `
  LEFT JOIN warehouses fw ON fw.id = t.from_warehouse_id AND fw.business_id = t.business_id
  LEFT JOIN warehouses tw ON tw.id = t.to_warehouse_id AND tw.business_id = t.business_id
  LEFT JOIN storage_locations fl ON fl.id = t.from_location_id
  LEFT JOIN storage_locations tl ON tl.id = t.to_location_id
  LEFT JOIN users u ON u.id = t.created_by`;

const SELECT_COLUMNS = `
  t.id, t.transfer_number, t.status, t.note, t.transfer_date, t.completed_at,
  t.created_by, u.name AS created_by_name, t.created_at, t.updated_at,
  t.from_warehouse_id, fw.name AS from_warehouse_name,
  t.from_location_id, fl.name AS from_location_name,
  t.to_warehouse_id, tw.name AS to_warehouse_name,
  t.to_location_id, tl.name AS to_location_name,
  (SELECT COUNT(*) FROM stock_transfer_items i WHERE i.transfer_id = t.id) AS item_count,
  (SELECT COALESCE(SUM(i.quantity), 0) FROM stock_transfer_items i WHERE i.transfer_id = t.id) AS total_quantity,
  -- What the transfer is OF, for a list that shows one line per transfer. The
  -- lowest item id is the first line as it was entered; item_count above says
  -- whether there are others, so a one-product transfer reads exactly and a
  -- multi-product one is never silently presented as if it were only this.
  (SELECT p.name FROM stock_transfer_items i JOIN products p ON p.id = i.product_id
    WHERE i.transfer_id = t.id ORDER BY i.id LIMIT 1) AS first_product_name`;

export async function listTransfers({ businessId, query, pagination }) {
  const where = buildWhere(listSpec, query, { "t.business_id": businessId, "t.deleted_at": null });
  const orderBy = buildOrderBy(listSpec, query, "t.id");

  const rows = await queryAll(
    `SELECT ${SELECT_COLUMNS} FROM stock_transfers t ${JOINS} ${where.sql} ${orderBy} LIMIT ? OFFSET ?`,
    [...where.params, pagination.pageSize, pagination.offset]
  );
  const total = await queryCount(
    `SELECT COUNT(*) AS total FROM stock_transfers t ${JOINS} ${where.sql}`,
    where.params
  );
  return { rows, total };
}

export async function findTransfer({ businessId, id, conn = pool }) {
  const [rows] = await conn.query(
    `SELECT ${SELECT_COLUMNS} FROM stock_transfers t ${JOINS}
      WHERE t.id = ? AND t.business_id = ? AND t.deleted_at IS NULL LIMIT 1`,
    [id, businessId]
  );
  return rows[0] ?? null;
}

/**
 * The transfer row, locked for the rest of the transaction.
 *
 * Same rule as every other document: two concurrent completions that each read
 * on the pool first would both see "pending" and both move the goods.
 */
export async function lockTransfer({ businessId, id, conn }) {
  const [rows] = await conn.query(
    `SELECT * FROM stock_transfers
      WHERE id = ? AND business_id = ? AND deleted_at IS NULL LIMIT 1 FOR UPDATE`,
    [id, businessId]
  );
  return rows[0] ?? null;
}

export async function transferItems({ businessId, transferId, conn = pool }) {
  const [rows] = await conn.query(
    `SELECT i.id, i.product_id, i.variant_id, i.quantity,
            p.name AS product_name, p.sku
       FROM stock_transfer_items i
       LEFT JOIN products p ON p.id = i.product_id AND p.business_id = i.business_id
      WHERE i.business_id = ? AND i.transfer_id = ? ORDER BY i.id`,
    [businessId, transferId]
  );
  return rows;
}

export async function insertTransfer(conn, { businessId, userId, transferNumber, data, status }) {
  const [result] = await conn.query(
    `INSERT INTO stock_transfers
       (business_id, transfer_number, from_warehouse_id, from_location_id,
        to_warehouse_id, to_location_id, status, note, transfer_date, completed_at, created_by)
     VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
    [
      businessId,
      transferNumber,
      data.fromWarehouseId,
      data.fromLocationId ?? null,
      data.toWarehouseId,
      data.toLocationId ?? null,
      status,
      data.note ?? null,
      data.transferDate ?? new Date(),
      status === "completed" ? new Date() : null,
      userId,
    ]
  );
  return result.insertId;
}

export async function insertTransferItem(conn, { businessId, transferId, item }) {
  await conn.query(
    `INSERT INTO stock_transfer_items (business_id, transfer_id, product_id, variant_id, quantity)
     VALUES (?, ?, ?, ?, ?)`,
    [businessId, transferId, item.productId, item.variantId ?? null, item.quantity]
  );
}

export async function setTransferStatus(conn, { businessId, id, from, status }) {
  const [result] = await conn.query(
    `UPDATE stock_transfers
        SET status = ?, updated_at = NOW(),
            completed_at = ${status === "completed" ? "NOW()" : "completed_at"}
      WHERE id = ? AND business_id = ? AND status = ?`,
    [status, id, businessId, from]
  );
  return result.affectedRows;
}

/** Every referenced warehouse, location and product must be this tenant's (§36). */
export async function ownershipProblem({ businessId, data }) {
  const warehouseIds = [data.fromWarehouseId, data.toWarehouseId];
  const [warehouses] = await pool.query(
    `SELECT id FROM warehouses WHERE business_id = ? AND id IN (?) AND deleted_at IS NULL`,
    [businessId, warehouseIds]
  );
  if (warehouses.length !== new Set(warehouseIds.map(String)).size) {
    return "One of those warehouses does not exist.";
  }

  const locationIds = [data.fromLocationId, data.toLocationId].filter((v) => v != null);
  if (locationIds.length) {
    const [locations] = await pool.query(
      `SELECT id FROM storage_locations
        WHERE business_id = ? AND id IN (?) AND deleted_at IS NULL`,
      [businessId, locationIds]
    );
    if (locations.length !== new Set(locationIds.map(String)).size) {
      return "One of those storage locations does not exist.";
    }
  }

  const productIds = [...new Set(data.items.map((item) => item.productId))];
  const [products] = await pool.query(
    `SELECT id FROM products WHERE business_id = ? AND id IN (?) AND deleted_at IS NULL`,
    [businessId, productIds]
  );
  if (products.length !== productIds.length) {
    return "One of those products does not exist.";
  }

  return null;
}
