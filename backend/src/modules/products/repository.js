import { defineListSpec } from "../../db/listQuery.js";
import { createCrudRepository } from "../../db/crudRepository.js";
import { queryOne, queryAll } from "../../db/pool.js";

/**
 * Products (§8/§42) — the catalogue's richest entity.
 *
 * QUANTITIES ARE NOT COLUMNS HERE. §8 lists "Current quantity", "Reserved
 * quantity" and "Available quantity" as product fields, but stock lives per
 * location in `inventory`, so they are summed on read. Storing them here as
 * well would be a second source of truth that drifts the first time a
 * transfer or a sale touches one location and not the other
 * (docs/backend-phase3.md §5).
 */
export const PRODUCT_JOINS = `
  LEFT JOIN categories cat ON cat.id = p.category_id AND cat.business_id = p.business_id
  LEFT JOIN units un       ON un.id = p.unit_id AND un.business_id = p.business_id`;

/** The derived stock figures, as a correlated subquery per product. */
const STOCK_COLUMNS = `
  COALESCE((SELECT SUM(i.quantity) FROM inventory i WHERE i.product_id = p.id), 0) AS current_quantity,
  COALESCE((SELECT SUM(i.reserved_quantity) FROM inventory i WHERE i.product_id = p.id), 0) AS reserved_quantity`;

const listSpec = defineListSpec({
  filters: {
    status: { column: "p.status", type: "enum", values: ["active", "inactive", "archived"] },
    productType: { column: "p.product_type", type: "enum", values: ["finished_good", "raw_material"] },
    categoryId: { column: "p.category_id", type: "int" },
    unitId: { column: "p.unit_id", type: "int" },
    minPrice: { column: "p.selling_price", type: "decimal", operator: ">=" },
    maxPrice: { column: "p.selling_price", type: "decimal", operator: "<=" },
  },
  // §32's search: a warehouse user looks up a product by whichever
  // identifier is printed on the thing in front of them.
  search: { columns: ["p.name", "p.sku", "p.barcode", "p.product_code", "p.brand"] },
  sort: {
    allowed: {
      name: "p.name",
      sku: "p.sku",
      sellingPrice: "p.selling_price",
      createdAt: "p.created_at",
      updatedAt: "p.updated_at",
    },
    default: { key: "name", direction: "ASC" },
  },
  dateRange: { column: "p.created_at" },
});

export const productsRepository = createCrudRepository({
  table: "products",
  alias: "p",
  listSpec,
  defaultJoins: PRODUCT_JOINS,
  selectColumns: `p.id, p.name, p.product_code, p.sku, p.barcode, p.brand, p.image_url,
                  p.description, p.short_description, p.status, p.product_type,
                  p.category_id, p.unit_id, p.default_location_id,
                  p.min_stock, p.max_stock, p.reorder_level,
                  p.purchase_cost, p.selling_price, p.wholesale_price, p.discount_price, p.tax_rate,
                  p.size, p.length, p.width, p.height, p.weight, p.color, p.material,
                  p.model, p.manufacturer, p.serial_number, p.batch_number,
                  p.expiry_date, p.warranty_period, p.created_at, p.updated_at,
                  cat.name AS category_name, un.name AS unit_name, un.code AS unit_code,
                  ${STOCK_COLUMNS}`,
  columns: {
    toRow(data, { partial = false } = {}) {
      const row = {};
      const map = {
        name: "name",
        productCode: "product_code",
        sku: "sku",
        barcode: "barcode",
        brand: "brand",
        imageUrl: "image_url",
        description: "description",
        shortDescription: "short_description",
        status: "status",
        productType: "product_type",
        categoryId: "category_id",
        unitId: "unit_id",
        defaultLocationId: "default_location_id",
        minStock: "min_stock",
        maxStock: "max_stock",
        reorderLevel: "reorder_level",
        purchaseCost: "purchase_cost",
        sellingPrice: "selling_price",
        wholesalePrice: "wholesale_price",
        discountPrice: "discount_price",
        taxRate: "tax_rate",
        size: "size",
        length: "length",
        width: "width",
        height: "height",
        weight: "weight",
        color: "color",
        material: "material",
        model: "model",
        manufacturer: "manufacturer",
        serialNumber: "serial_number",
        batchNumber: "batch_number",
        expiryDate: "expiry_date",
        warrantyPeriod: "warranty_period",
      };
      for (const [field, column] of Object.entries(map)) {
        if (data[field] !== undefined) row[column] = data[field];
      }
      void partial;
      return row;
    },
  },
});

/**
 * Whether this product has ever moved, or holds stock.
 *
 * §45/§55: a product that appears on a document must stay readable, so it
 * is archived rather than removed. This is what the controller checks
 * before offering a hard truth about what "delete" means here.
 */
export async function productHasHistory({ businessId, productId }) {
  const row = await queryOne(
    `SELECT 1 AS used FROM inventory_movements
      WHERE business_id = ? AND product_id = ? LIMIT 1`,
    [businessId, productId]
  );
  return Boolean(row);
}

export async function productHoldsStock({ businessId, productId }) {
  const row = await queryOne(
    `SELECT 1 AS used FROM inventory
      WHERE business_id = ? AND product_id = ? AND quantity <> 0 LIMIT 1`,
    [businessId, productId]
  );
  return Boolean(row);
}

/** One product's stock, split by location — §8's "Warehouse/location". */
export async function productStockByLocation({ businessId, productId }) {
  return queryAll(
    `SELECT i.warehouse_id, w.name AS warehouse_name,
            i.location_id, sl.name AS location_name,
            i.quantity, i.reserved_quantity
       FROM inventory i
       JOIN warehouses w ON w.id = i.warehouse_id
       LEFT JOIN storage_locations sl ON sl.id = i.location_id
      WHERE i.business_id = ? AND i.product_id = ?
      ORDER BY w.name, sl.name`,
    [businessId, productId]
  );
}
