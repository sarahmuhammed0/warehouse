import { queryAll, pool } from "../../db/pool.js";

/**
 * §9's product variants — one product, several sellable forms.
 *
 * A variant is NOT a product: it shares the product's identity and category and
 * differs in the things a buyer chooses between (a size, a colour). What it does
 * NOT share is stock: `inventory` is keyed per variant, so each form has its own
 * level, which is the whole reason they exist rather than being separate
 * products with duplicated names.
 *
 * Not paginated: a product has a handful of variants, and the edit screen needs
 * all of them.
 */
export async function listVariants({ businessId, productId }) {
  return queryAll(
    `SELECT v.id, v.product_id, v.name, v.sku, v.barcode, v.purchase_cost,
            v.selling_price, v.attributes, v.image_url, v.status,
            v.created_at, v.updated_at,
            COALESCE((
              SELECT SUM(i.quantity) FROM inventory i
               WHERE i.business_id = v.business_id AND i.variant_id = v.id
            ), 0) AS quantity
       FROM product_variants v
      WHERE v.business_id = ? AND v.product_id = ? AND v.deleted_at IS NULL
      ORDER BY v.id`,
    [businessId, productId]
  );
}

export async function findVariant({ businessId, productId, id, conn = pool }) {
  const [rows] = await conn.query(
    `SELECT id, product_id, name, sku, barcode, purchase_cost, selling_price,
            attributes, image_url, status, created_at, updated_at
       FROM product_variants
      WHERE id = ? AND product_id = ? AND business_id = ? AND deleted_at IS NULL LIMIT 1`,
    [id, productId, businessId]
  );
  return rows[0] ?? null;
}

export async function createVariant(conn, { businessId, productId, data }) {
  const [result] = await conn.query(
    `INSERT INTO product_variants
       (business_id, product_id, name, sku, barcode, purchase_cost, selling_price,
        attributes, image_url, status)
     VALUES (?, ?, ?, ?, ?, ?, ?, CAST(? AS JSON), ?, ?)`,
    [
      businessId,
      productId,
      data.name ?? null,
      data.sku ?? null,
      data.barcode ?? null,
      data.purchaseCost ?? null,
      data.sellingPrice ?? null,
      JSON.stringify(data.attributes ?? {}),
      data.imageUrl ?? null,
      data.status ?? "active",
    ]
  );
  return result.insertId;
}

export async function updateVariant(conn, { businessId, productId, id, data }) {
  const columns = {
    name: "name",
    sku: "sku",
    barcode: "barcode",
    purchaseCost: "purchase_cost",
    sellingPrice: "selling_price",
    imageUrl: "image_url",
    status: "status",
  };

  const sets = [];
  const params = [];
  for (const [key, column] of Object.entries(columns)) {
    if (data[key] === undefined) continue;
    sets.push(`${column} = ?`);
    params.push(data[key]);
  }
  if (data.attributes !== undefined) {
    sets.push("attributes = CAST(? AS JSON)");
    params.push(JSON.stringify(data.attributes));
  }
  if (sets.length === 0) return 1;

  const [result] = await conn.query(
    `UPDATE product_variants SET ${sets.join(", ")}, updated_at = NOW()
      WHERE id = ? AND product_id = ? AND business_id = ? AND deleted_at IS NULL`,
    [...params, id, productId, businessId]
  );
  return result.affectedRows;
}

/** §45: archived, because documents and stock movements still reference it. */
export async function softDeleteVariant(conn, { businessId, productId, id }) {
  const [result] = await conn.query(
    `UPDATE product_variants SET deleted_at = NOW(), status = 'inactive', updated_at = NOW()
      WHERE id = ? AND product_id = ? AND business_id = ? AND deleted_at IS NULL`,
    [id, productId, businessId]
  );
  return result.affectedRows;
}

/** Stock still standing against a variant — what makes deleting it a bad idea. */
export async function variantStock({ businessId, id }) {
  const rows = await queryAll(
    `SELECT COALESCE(SUM(quantity), 0) AS quantity FROM inventory
      WHERE business_id = ? AND variant_id = ?`,
    [businessId, id]
  );
  return Number(rows[0]?.quantity ?? 0);
}

export async function productExists({ businessId, productId, conn = pool }) {
  const [rows] = await conn.query(
    `SELECT 1 AS ok FROM products WHERE id = ? AND business_id = ? AND deleted_at IS NULL LIMIT 1`,
    [productId, businessId]
  );
  return rows.length > 0;
}
