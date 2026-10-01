import { ok, paginated } from "../../utils/responseEnvelope.js";
import { parsePagination, paginationMeta } from "../../db/pagination.js";
import { errors } from "../../utils/AppError.js";
import { productsRepository } from "../products/repository.js";
import { warehousesRepository, storageLocationsRepository } from "../locations/repository.js";
import { listLevels, listMovements, lowStockProducts } from "./repository.js";
import { lowStockDefault } from "../settings/policy.js";
import { adjustStock, transferStock } from "./service.js";
import { findVariant } from "../variants/repository.js";

const tenant = (req) => req.auth.businessId;
const num = (v) => (v === null || v === undefined ? null : Number(v));

function levelView(row) {
  const quantity = num(row.quantity) ?? 0;
  const reserved = num(row.reserved_quantity) ?? 0;
  return {
    id: row.id,
    productId: row.product_id,
    productName: row.product_name,
    sku: row.sku,
    variantId: row.variant_id,
    warehouseId: row.warehouse_id,
    warehouseName: row.warehouse_name,
    locationId: row.location_id,
    locationName: row.location_name,
    unitCode: row.unit_code,
    quantity,
    reservedQuantity: reserved,
    availableQuantity: quantity - reserved,
    isLowStock: num(row.reorder_level) !== null && quantity <= num(row.reorder_level),
    updatedAt: row.updated_at,
  };
}

function movementView(row) {
  return {
    id: row.id,
    productId: row.product_id,
    productName: row.product_name,
    sku: row.sku,
    warehouseId: row.warehouse_id,
    warehouseName: row.warehouse_name,
    locationId: row.location_id,
    locationName: row.location_name,
    movementType: row.movement_type,
    quantity: num(row.quantity),
    quantityBefore: num(row.quantity_before),
    quantityAfter: num(row.quantity_after),
    referenceType: row.reference_type,
    referenceId: row.reference_id,
    referenceNumber: row.reference_number,
    reason: row.reason,
    note: row.note,
    userId: row.user_id,
    userName: row.user_name,
    movedAt: row.moved_at,
  };
}

/** Every referenced row must exist AND belong to this tenant (§36). */
async function requireOwnership({ businessId, productId, variantId = null, warehouseId, locationId }) {
  await productsRepository.requireById({ businessId, id: productId, label: "product" });
  if (variantId !== undefined && variantId !== null) {
    // Scoped by BOTH business and product. Checking the business alone would
    // let one product's stock be moved under another product's variant, and
    // checking neither would let a variant id from another tenant name a slot
    // in this one (§36).
    const variant = await findVariant({ businessId, productId, id: variantId });
    if (!variant) throw errors.notFound("variant");
  }
  await warehousesRepository.requireById({ businessId, id: warehouseId, label: "warehouse" });
  if (locationId !== undefined && locationId !== null) {
    const location = await storageLocationsRepository.requireById({
      businessId,
      id: locationId,
      label: "storage location",
    });
    if (String(location.warehouse_id) !== String(warehouseId)) {
      throw errors.validation("That storage location is not in the selected warehouse.");
    }
  }
}

export async function getLevels(req, res, next) {
  try {
    const pagination = parsePagination(req.query);
    const { rows, total } = await listLevels({ businessId: tenant(req), query: req.query, pagination });
    res.json(paginated(rows.map(levelView), paginationMeta(pagination, total)));
  } catch (err) {
    next(err);
  }
}

export async function getMovements(req, res, next) {
  try {
    const pagination = parsePagination(req.query);
    const { rows, total } = await listMovements({ businessId: tenant(req), query: req.query, pagination });
    res.json(paginated(rows.map(movementView), paginationMeta(pagination, total)));
  } catch (err) {
    next(err);
  }
}

/** §44's dashboard alert list. */
export async function getLowStock(req, res, next) {
  try {
    const businessId = tenant(req);
    // §34's setting decides for every product that has no threshold of its own.
    const defaultThreshold = await lowStockDefault({ businessId });
    const rows = await lowStockProducts({ businessId, defaultThreshold });
    res.json(
      ok(
        rows.map((r) => ({
          productId: r.id,
          name: r.name,
          sku: r.sku,
          currentQuantity: num(r.current_quantity),
          reorderLevel: num(r.reorder_level),
          // What the alert actually compared against, which is the product's own
          // level or the business's default — worth returning, because otherwise
          // a row with `reorderLevel: null` looks like it appeared for no reason.
          effectiveReorderLevel: num(r.effective_reorder_level),
          isOutOfStock: Number(r.current_quantity) <= 0,
        }))
      )
    );
  } catch (err) {
    next(err);
  }
}

/**
 * §12's manual increase / decrease / damage / adjustment.
 *
 * `delta` is signed: the sign says which way stock moves, and the movement
 * type says why. The stored movement quantity is the magnitude — see the
 * repository.
 */
export async function adjust(req, res, next) {
  try {
    const businessId = tenant(req);
    const { productId, variantId = null, warehouseId, locationId = null, quantity, movementType, reason, note } = req.body;

    await requireOwnership({ businessId, productId, variantId, warehouseId, locationId });

    const result = await adjustStock({
      businessId,
      userId: req.auth.userId,
      productId,
      variantId,
      warehouseId,
      locationId,
      delta: Number(quantity),
      movementType,
      reason,
      note,
    });

    res.status(201).json(ok(result));
  } catch (err) {
    next(err);
  }
}

/** §11's transfer between locations — both legs, or neither. */
export async function transfer(req, res, next) {
  try {
    const businessId = tenant(req);
    const {
      productId,
      fromWarehouseId,
      fromLocationId = null,
      toWarehouseId,
      toLocationId = null,
      quantity,
      note,
    } = req.body;

    await requireOwnership({
      businessId,
      productId,
      warehouseId: fromWarehouseId,
      locationId: fromLocationId,
    });
    await requireOwnership({
      businessId,
      productId,
      warehouseId: toWarehouseId,
      locationId: toLocationId,
    });

    const result = await transferStock({
      businessId,
      userId: req.auth.userId,
      productId,
      fromWarehouseId,
      fromLocationId,
      toWarehouseId,
      toLocationId,
      quantity: Number(quantity),
      note,
    });

    res.status(201).json(ok(result));
  } catch (err) {
    next(err);
  }
}
