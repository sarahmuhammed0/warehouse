import { defineListSpec, buildWhere, buildOrderBy } from "../../db/listQuery.js";
import { queryAll, queryCount, pool } from "../../db/pool.js";

/** Production orders (§22). */
const listSpec = defineListSpec({
  filters: {
    status: {
      column: "po.status",
      type: "enum",
      values: ["planned", "in_progress", "completed", "cancelled"],
    },
    productId: { column: "po.product_id", type: "int" },
    warehouseId: { column: "po.warehouse_id", type: "int" },
    assignedUserId: { column: "po.assigned_user_id", type: "int" },
  },
  search: { columns: ["po.production_number", "po.batch_number", "p.name"] },
  sort: {
    allowed: {
      productionNumber: "po.production_number",
      productionDate: "po.production_date",
      quantityPlanned: "po.quantity_planned",
      status: "po.status",
      createdAt: "po.created_at",
    },
    default: { key: "createdAt", direction: "DESC" },
  },
  dateRange: { column: "po.production_date" },
});

const JOINS = `
  LEFT JOIN products p ON p.id = po.product_id AND p.business_id = po.business_id
  LEFT JOIN warehouses w ON w.id = po.warehouse_id AND w.business_id = po.business_id
  LEFT JOIN users assignee ON assignee.id = po.assigned_user_id`;

const SELECT_COLUMNS = `
  po.id, po.production_number, po.batch_number, po.status,
  po.product_id, p.name AS product_name, p.sku AS product_sku,
  po.variant_id, po.warehouse_id, w.name AS warehouse_name,
  po.quantity_planned, po.quantity_produced, po.production_cost,
  po.assigned_user_id, assignee.name AS assigned_user_name,
  po.production_date, po.started_at, po.completed_at, po.note,
  po.created_by, po.created_at, po.updated_at,
  (SELECT COUNT(*) FROM production_items pi WHERE pi.production_order_id = po.id) AS material_count`;

export async function listProductionOrders({ businessId, query, pagination }) {
  const where = buildWhere(listSpec, query, { "po.business_id": businessId, "po.deleted_at": null });
  const orderBy = buildOrderBy(listSpec, query, "po.id");

  const rows = await queryAll(
    `SELECT ${SELECT_COLUMNS} FROM production_orders po ${JOINS}
      ${where.sql} ${orderBy} LIMIT ? OFFSET ?`,
    [...where.params, pagination.pageSize, pagination.offset]
  );

  const total = await queryCount(
    `SELECT COUNT(*) AS total FROM production_orders po ${JOINS} ${where.sql}`,
    where.params
  );

  return { rows, total };
}

export async function findProductionOrder({ businessId, id, conn = pool }) {
  const [rows] = await conn.query(
    `SELECT ${SELECT_COLUMNS} FROM production_orders po ${JOINS}
      WHERE po.id = ? AND po.business_id = ? AND po.deleted_at IS NULL LIMIT 1`,
    [id, businessId]
  );
  return rows[0] ?? null;
}

/**
 * The production order, locked for the rest of the transaction.
 *
 * Same rule as `lockOrder`: two concurrent completions that each read on the
 * pool first would both see "in_progress", both consume the materials and both
 * produce the finished goods — a run that doubles its own output.
 */
export async function lockProductionOrder({ businessId, id, conn }) {
  const [rows] = await conn.query(
    `SELECT * FROM production_orders
      WHERE id = ? AND business_id = ? AND deleted_at IS NULL LIMIT 1 FOR UPDATE`,
    [id, businessId]
  );
  return rows[0] ?? null;
}

export async function productionMaterials({ businessId, productionOrderId, conn = pool }) {
  const [rows] = await conn.query(
    `SELECT pi.id, pi.material_product_id, pi.variant_id, pi.quantity_required,
            pi.quantity_consumed, pi.unit_cost,
            m.name AS material_product_name, m.sku AS material_sku,
            u.code AS unit_code, u.name AS unit_name
       FROM production_items pi
       LEFT JOIN products m ON m.id = pi.material_product_id AND m.business_id = pi.business_id
       LEFT JOIN units u ON u.id = m.unit_id
      WHERE pi.business_id = ? AND pi.production_order_id = ? ORDER BY pi.id`,
    [businessId, productionOrderId]
  );
  return rows;
}

/**
 * §21's bill of materials for one finished product.
 *
 * A TEMPLATE, not a record: editing it changes what future runs will need and
 * must never rewrite what a past run actually consumed, which is why
 * `production_items` snapshots the quantities rather than joining back to here.
 */
export async function billOfMaterials({ businessId, productId, conn = pool }) {
  const [rows] = await conn.query(
    `SELECT b.id, b.material_product_id, b.quantity_per_unit, b.note,
            b.unit_id, COALESCE(u.code, mu.code) AS unit_code,
            COALESCE(u.name, mu.name) AS unit_name,
            m.name AS material_product_name, m.sku AS material_sku,
            m.purchase_cost AS material_cost, m.product_type AS material_type
       FROM bill_of_materials b
       JOIN products m ON m.id = b.material_product_id AND m.business_id = b.business_id
       LEFT JOIN units u ON u.id = b.unit_id
       LEFT JOIN units mu ON mu.id = m.unit_id
      WHERE b.business_id = ? AND b.product_id = ? AND b.deleted_at IS NULL
        AND m.deleted_at IS NULL
      ORDER BY b.id`,
    [businessId, productId],
  );
  return rows;
}

/**
 * Replaces a product's whole bill of materials, inside the caller's transaction.
 *
 * REMOVED, not soft-deleted, and that is the schema's decision rather than a
 * shortcut: `uq_bom_product_material` is unique on (product, material) with no
 * regard for `deleted_at`, so one row per pair is all the table can hold —
 * soft-deleting a line and re-adding the same material collides on it. The
 * recipe is current-state only, which is safe precisely because a production
 * run snapshots the quantities it used into `production_items` and never reads
 * them back from here.
 *
 * The upsert also resurrects a row an older build soft-deleted, so a recipe
 * cannot become unrepairable.
 */
export async function replaceBillOfMaterials(conn, { businessId, productId, lines }) {
  const keep = lines.map((line) => line.materialProductId);
  if (keep.length) {
    await conn.query(
      `DELETE FROM bill_of_materials
        WHERE business_id = ? AND product_id = ? AND material_product_id NOT IN (?)`,
      [businessId, productId, keep]
    );
  } else {
    await conn.query(`DELETE FROM bill_of_materials WHERE business_id = ? AND product_id = ?`, [
      businessId,
      productId,
    ]);
  }

  for (const line of lines) {
    await conn.query(
      `INSERT INTO bill_of_materials
         (business_id, product_id, material_product_id, unit_id, quantity_per_unit, note)
       VALUES (?, ?, ?, ?, ?, ?)
       ON DUPLICATE KEY UPDATE
         unit_id = VALUES(unit_id),
         quantity_per_unit = VALUES(quantity_per_unit),
         note = VALUES(note),
         deleted_at = NULL,
         updated_at = NOW()`,
      [
        businessId,
        productId,
        line.materialProductId,
        line.unitId ?? null,
        line.quantityPerUnit,
        line.note ?? null,
      ]
    );
  }
}

/** A product of this tenant, with the fields production needs. */
export async function findProduct({ businessId, productId, conn = pool }) {
  const [rows] = await conn.query(
    `SELECT id, name, sku, product_type, unit_id, purchase_cost FROM products
      WHERE id = ? AND business_id = ? AND deleted_at IS NULL LIMIT 1`,
    [productId, businessId]
  );
  return rows[0] ?? null;
}
