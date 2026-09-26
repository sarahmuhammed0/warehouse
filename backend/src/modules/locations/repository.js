import { defineListSpec } from "../../db/listQuery.js";
import { createCrudRepository } from "../../db/crudRepository.js";
import { queryOne, queryAll, pool } from "../../db/pool.js";

/** Warehouses (§11). */
const warehouseListSpec = defineListSpec({
  filters: {
    status: { column: "w.status", type: "enum", values: ["active", "inactive"] },
    locationType: {
      column: "w.location_type",
      type: "enum",
      values: ["warehouse", "showroom", "production_area", "storage_room", "outdoor", "other"],
    },
  },
  search: { columns: ["w.name", "w.code", "w.address"] },
  sort: {
    allowed: { name: "w.name", code: "w.code", createdAt: "w.created_at" },
    default: { key: "name", direction: "ASC" },
  },
  dateRange: { column: "w.created_at" },
});

export const warehousesRepository = createCrudRepository({
  table: "warehouses",
  alias: "w",
  listSpec: warehouseListSpec,
  selectColumns: `w.id, w.name, w.code, w.address, w.location_type, w.is_default, w.status,
                  w.created_at, w.updated_at,
                  (SELECT COUNT(*) FROM storage_locations sl
                    WHERE sl.warehouse_id = w.id AND sl.deleted_at IS NULL) AS location_count`,
  columns: {
    toRow(data, { partial = false } = {}) {
      const row = {};
      if (data.name !== undefined) row.name = data.name;
      if (data.code !== undefined) row.code = data.code;
      if (data.address !== undefined) row.address = data.address;
      if (data.locationType !== undefined) row.location_type = data.locationType;
      if (data.isDefault !== undefined) row.is_default = data.isDefault;
      if (data.status !== undefined) row.status = data.status;
      if (!partial && row.location_type === undefined) row.location_type = "warehouse";
      return row;
    },
  },
});

/**
 * Declared on the repository as `defaultJoins` below: `selectColumns`
 * references `w.name`, so a query without this join fails with "Unknown
 * column" — and that must not depend on each call site remembering.
 */
export const LOCATION_JOINS = `JOIN warehouses w
  ON w.id = sl.warehouse_id AND w.business_id = sl.business_id`;

/** Storage locations (§11's shelf/rack/bin), always inside one warehouse. */
const locationListSpec = defineListSpec({
  filters: {
    status: { column: "sl.status", type: "enum", values: ["active", "inactive"] },
    warehouseId: { column: "sl.warehouse_id", type: "int" },
  },
  search: { columns: ["sl.name", "sl.code", "sl.aisle", "sl.rack", "sl.shelf", "sl.bin"] },
  sort: {
    allowed: { name: "sl.name", code: "sl.code", createdAt: "sl.created_at" },
    default: { key: "name", direction: "ASC" },
  },
  dateRange: { column: "sl.created_at" },
});

export const storageLocationsRepository = createCrudRepository({
  table: "storage_locations",
  alias: "sl",
  listSpec: locationListSpec,
  defaultJoins: LOCATION_JOINS,
  selectColumns: `sl.id, sl.warehouse_id, sl.name, sl.code, sl.aisle, sl.rack, sl.shelf, sl.bin,
                  sl.status, sl.created_at, sl.updated_at, w.name AS warehouse_name`,
  columns: {
    toRow(data, { partial = false } = {}) {
      const row = {};
      if (data.warehouseId !== undefined) row.warehouse_id = data.warehouseId;
      if (data.name !== undefined) row.name = data.name;
      if (data.code !== undefined) row.code = data.code;
      if (data.aisle !== undefined) row.aisle = data.aisle;
      if (data.rack !== undefined) row.rack = data.rack;
      if (data.shelf !== undefined) row.shelf = data.shelf;
      if (data.bin !== undefined) row.bin = data.bin;
      if (data.status !== undefined) row.status = data.status;
      void partial;
      return row;
    },
  },
});


/**
 * Exactly one default warehouse per business.
 *
 * Run inside the same transaction as the write that set a new default, so
 * there is never a moment with two — §11 has a "default" so that stock with
 * no location specified has somewhere to go, and two answers to that is the
 * same as none.
 */
export async function clearOtherDefaults(conn, { businessId, keepId }) {
  await conn.query(
    `UPDATE warehouses SET is_default = FALSE
      WHERE business_id = ? AND id <> ? AND is_default = TRUE AND deleted_at IS NULL`,
    [businessId, keepId]
  );
}

/** Stock held anywhere in this warehouse — archiving it would hide stock. */
export async function warehouseHoldsStock({ businessId, warehouseId }) {
  const row = await queryOne(
    `SELECT 1 AS used FROM inventory
      WHERE business_id = ? AND warehouse_id = ? AND quantity <> 0 LIMIT 1`,
    [businessId, warehouseId]
  );
  return Boolean(row);
}

export async function locationHoldsStock({ businessId, locationId }) {
  const row = await queryOne(
    `SELECT 1 AS used FROM inventory
      WHERE business_id = ? AND location_id = ? AND quantity <> 0 LIMIT 1`,
    [businessId, locationId]
  );
  return Boolean(row);
}

export async function warehouseHasLocations({ businessId, warehouseId }) {
  const row = await queryOne(
    `SELECT 1 AS used FROM storage_locations
      WHERE business_id = ? AND warehouse_id = ? AND deleted_at IS NULL LIMIT 1`,
    [businessId, warehouseId]
  );
  return Boolean(row);
}

/** Pickers: warehouses, and the locations inside one. */
export async function warehouseOptions(businessId) {
  return queryAll(
    `SELECT id, name, is_default FROM warehouses
      WHERE business_id = ? AND deleted_at IS NULL AND status = 'active'
      ORDER BY is_default DESC, name ASC`,
    [businessId]
  );
}

export async function locationOptions({ businessId, warehouseId }) {
  return queryAll(
    `SELECT id, warehouse_id, name FROM storage_locations
      WHERE business_id = ? AND deleted_at IS NULL AND status = 'active'
        AND (? IS NULL OR warehouse_id = ?)
      ORDER BY name ASC`,
    [businessId, warehouseId ?? null, warehouseId ?? null]
  );
}

/** The business's default warehouse, if it has one. */
export async function defaultWarehouseId(businessId, conn = pool) {
  const [rows] = await conn.query(
    `SELECT id FROM warehouses
      WHERE business_id = ? AND is_default = TRUE AND deleted_at IS NULL AND status = 'active'
      LIMIT 1`,
    [businessId]
  );
  return rows[0]?.id ?? null;
}
