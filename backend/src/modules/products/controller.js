import { ok, paginated } from "../../utils/responseEnvelope.js";
import { parsePagination, paginationMeta } from "../../db/pagination.js";
import { errors } from "../../utils/AppError.js";
import { toAppError } from "../../utils/databaseError.js";
import { loadPermissions } from "../../middleware/authorize.js";
import { categoriesRepository } from "../categories/repository.js";
import { unitsRepository } from "../units/repository.js";
import { storageLocationsRepository } from "../locations/repository.js";
import {
  productsRepository,
  productHasHistory,
  productHoldsStock,
  productStockByLocation,
} from "./repository.js";

const tenant = (req) => req.auth.businessId;

/** Money and quantities arrive as exact strings (DECIMAL, never a float). */
const num = (value) => (value === null || value === undefined ? null : Number(value));

/**
 * @param showFinancial §24's "View Financial Information". Cost and margin
 *   are withheld from a user without it — a Sales Staff member sees what a
 *   product sells for, not what it cost the business.
 */
function toView(row, { showFinancial }) {
  const current = num(row.current_quantity) ?? 0;
  const reserved = num(row.reserved_quantity) ?? 0;

  const view = {
    id: row.id,
    name: row.name,
    productCode: row.product_code,
    sku: row.sku,
    barcode: row.barcode,
    brand: row.brand,
    imageUrl: row.image_url,
    description: row.description,
    shortDescription: row.short_description,
    status: row.status,
    productType: row.product_type,
    categoryId: row.category_id,
    categoryName: row.category_name ?? null,
    unitId: row.unit_id,
    unitName: row.unit_name ?? null,
    unitCode: row.unit_code ?? null,
    defaultLocationId: row.default_location_id,

    // §8's three quantity fields. All derived from `inventory`, never
    // stored on the product — available is what is left once reservations
    // are accounted for.
    currentQuantity: current,
    reservedQuantity: reserved,
    availableQuantity: current - reserved,

    minStock: num(row.min_stock),
    maxStock: num(row.max_stock),
    reorderLevel: num(row.reorder_level),

    // §44's alerts, computed here so every client agrees on the thresholds.
    isOutOfStock: current <= 0,
    isLowStock: current > 0 && num(row.reorder_level) !== null && current <= num(row.reorder_level),
    isOverstock: num(row.max_stock) !== null && current > num(row.max_stock),

    sellingPrice: num(row.selling_price),
    wholesalePrice: num(row.wholesale_price),
    discountPrice: num(row.discount_price),
    taxRate: num(row.tax_rate),

    size: row.size,
    length: num(row.length),
    width: num(row.width),
    height: num(row.height),
    weight: num(row.weight),
    color: row.color,
    material: row.material,
    model: row.model,
    manufacturer: row.manufacturer,
    serialNumber: row.serial_number,
    batchNumber: row.batch_number,
    expiryDate: row.expiry_date,
    warrantyPeriod: row.warranty_period,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
  };

  if (showFinancial) {
    view.purchaseCost = num(row.purchase_cost);
    // §8's "Profit margin", derived rather than stored so it cannot
    // disagree with the two numbers it comes from.
    const cost = num(row.purchase_cost);
    const price = num(row.selling_price);
    view.marginPercent = cost && price && cost !== 0 ? ((price - cost) / cost) * 100 : null;
  }

  return view;
}

const constraintMessages = {
  uq_products_sku: "A product with this SKU already exists.",
  uq_products_barcode: "A product with this barcode already exists.",
  uq_products_code: "A product with this code already exists.",
};

/**
 * Category, unit and default location must each exist AND belong to this
 * business. The foreign keys constrain the id but know nothing about who
 * owns the row, so without this a client could attach another tenant's
 * category to its own product (§36).
 */
async function validateReferences({ businessId, body }) {
  const checks = [
    ["categoryId", categoriesRepository, "category"],
    ["unitId", unitsRepository, "unit"],
    ["defaultLocationId", storageLocationsRepository, "default location"],
  ];
  for (const [field, repository, label] of checks) {
    const id = body[field];
    if (id === undefined || id === null) continue;
    const row = await repository.findById({ businessId, id });
    if (!row) throw errors.validation(`The ${label} does not exist.`);
  }
}

export async function listProducts(req, res, next) {
  try {
    const businessId = tenant(req);
    const pagination = parsePagination(req.query);
    const permissions = await loadPermissions(req);
    const showFinancial = permissions.includes("financial.view");

    const { rows, total } = await productsRepository.list({ businessId, query: req.query, pagination });
    res.json(paginated(rows.map((r) => toView(r, { showFinancial })), paginationMeta(pagination, total)));
  } catch (err) {
    next(err);
  }
}

export async function getProduct(req, res, next) {
  try {
    const businessId = tenant(req);
    const permissions = await loadPermissions(req);
    const row = await productsRepository.requireById({ businessId, id: req.params.id, label: "product" });

    const view = toView(row, { showFinancial: permissions.includes("financial.view") });
    // §8's "Warehouse/location": where this product's stock actually sits.
    view.stockByLocation = (await productStockByLocation({ businessId, productId: req.params.id })).map(
      (s) => ({
        warehouseId: s.warehouse_id,
        warehouseName: s.warehouse_name,
        locationId: s.location_id,
        locationName: s.location_name,
        quantity: num(s.quantity),
        reservedQuantity: num(s.reserved_quantity),
      })
    );

    res.json(ok(view));
  } catch (err) {
    next(err);
  }
}

export async function createProduct(req, res, next) {
  try {
    const businessId = tenant(req);
    await validateReferences({ businessId, body: req.body });

    const id = await productsRepository.create({ businessId, data: req.body });
    const row = await productsRepository.findById({ businessId, id });
    const permissions = await loadPermissions(req);
    res.status(201).json(ok(toView(row, { showFinancial: permissions.includes("financial.view") })));
  } catch (err) {
    next(toAppError(err, { constraintMessages }) ?? err);
  }
}

export async function updateProduct(req, res, next) {
  try {
    const businessId = tenant(req);
    const id = req.params.id;
    await productsRepository.requireById({ businessId, id, label: "product" });
    await validateReferences({ businessId, body: req.body });

    await productsRepository.update({ businessId, id, data: req.body });
    const row = await productsRepository.findById({ businessId, id });
    const permissions = await loadPermissions(req);
    res.json(ok(toView(row, { showFinancial: permissions.includes("financial.view") })));
  } catch (err) {
    next(toAppError(err, { constraintMessages }) ?? err);
  }
}

export async function deleteProduct(req, res, next) {
  try {
    const businessId = tenant(req);
    const id = req.params.id;
    await productsRepository.requireById({ businessId, id, label: "product" });

    // Stock that still exists cannot be archived away: the quantity would
    // remain in `inventory`, counted in totals, attached to a product no
    // list will show (§12).
    if (await productHoldsStock({ businessId, productId: id })) {
      throw errors.conflict("This product still has stock. Adjust it to zero or transfer it first.");
    }

    // A product with movement history is archived, never removed — §55
    // needs those documents to keep answering what was sold. The soft
    // delete does exactly that, so this is not a refusal, just the reason
    // the row survives.
    await productsRepository.softDelete({ businessId, id });
    const archived = await productHasHistory({ businessId, productId: id });
    res.json(ok({ id: Number(id), deleted: true, retainedForHistory: archived }));
  } catch (err) {
    next(err);
  }
}
