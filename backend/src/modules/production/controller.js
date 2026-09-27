import { ok, paginated } from "../../utils/responseEnvelope.js";
import { parsePagination, paginationMeta } from "../../db/pagination.js";
import { errors } from "../../utils/AppError.js";
import { toAppError } from "../../utils/databaseError.js";
import { runInTransaction } from "../../db/pool.js";
import {
  listProductionOrders,
  findProductionOrder,
  lockProductionOrder,
  productionMaterials,
  billOfMaterials,
  replaceBillOfMaterials,
  findProduct,
} from "./repository.js";
import {
  createProductionOrder,
  completeProductionOrder,
  assertTransition,
  movesStock,
} from "./service.js";

const tenant = (req) => req.auth.businessId;
const num = (v) => (v === null || v === undefined ? null : Number(v));

const orderView = (row) => ({
  id: row.id,
  productionNumber: row.production_number,
  batchNumber: row.batch_number,
  status: row.status,
  productId: row.product_id,
  productName: row.product_name ?? null,
  productSku: row.product_sku ?? null,
  variantId: row.variant_id,
  warehouseId: row.warehouse_id,
  warehouseName: row.warehouse_name ?? null,
  quantityPlanned: num(row.quantity_planned),
  quantityProduced: num(row.quantity_produced),
  productionCost: num(row.production_cost),
  assignedUserId: row.assigned_user_id,
  assignedUserName: row.assigned_user_name ?? null,
  materialCount: Number(row.material_count ?? 0),
  productionDate: row.production_date,
  startedAt: row.started_at,
  completedAt: row.completed_at,
  note: row.note,
  createdBy: row.created_by,
  createdAt: row.created_at,
  updatedAt: row.updated_at,
});

const materialView = (row) => ({
  id: row.id,
  materialProductId: row.material_product_id,
  materialProductName: row.material_product_name,
  materialSku: row.material_sku,
  variantId: row.variant_id,
  quantityRequired: num(row.quantity_required),
  quantityConsumed: num(row.quantity_consumed),
  unitCost: num(row.unit_cost),
  unitCode: row.unit_code ?? null,
  unitName: row.unit_name ?? null,
});

const bomView = (row) => ({
  id: row.id,
  materialProductId: row.material_product_id,
  materialProductName: row.material_product_name,
  materialSku: row.material_sku,
  quantityPerUnit: num(row.quantity_per_unit),
  unitId: row.unit_id,
  unitCode: row.unit_code ?? null,
  unitName: row.unit_name ?? null,
  materialCost: num(row.material_cost),
  note: row.note,
});

const constraintMessages = {
  uq_production_number: "That production number is already in use.",
  ck_bom_not_self_referencing: "A product cannot be made out of itself.",
};

// ---- §21's bill of materials -------------------------------------------

export async function getBom(req, res, next) {
  try {
    const businessId = tenant(req);
    const product = await findProduct({ businessId, productId: req.params.id });
    if (!product) throw errors.notFound("product");

    const lines = await billOfMaterials({ businessId, productId: product.id });
    res.json(
      ok({
        productId: product.id,
        productName: product.name,
        lines: lines.map(bomView),
      })
    );
  } catch (err) {
    next(err);
  }
}

/**
 * Replaces the whole bill of materials in one call.
 *
 * A recipe is edited as a whole — a line removed, another's quantity changed —
 * and a per-line REST surface would make the client send several requests that
 * must all succeed to leave a coherent recipe. One PUT inside one transaction
 * cannot half-apply.
 */
export async function putBom(req, res, next) {
  try {
    const businessId = tenant(req);
    const product = await findProduct({ businessId, productId: req.params.id });
    if (!product) throw errors.notFound("product");

    const lines = req.body.lines;
    const seen = new Set();
    for (const line of lines) {
      if (String(line.materialProductId) === String(product.id)) {
        throw errors.validation("A product cannot be made out of itself.");
      }
      if (seen.has(String(line.materialProductId))) {
        throw errors.validation("The same material appears twice — combine the quantities instead.");
      }
      seen.add(String(line.materialProductId));

      const material = await findProduct({ businessId, productId: line.materialProductId });
      if (!material) throw errors.validation(`Material ${line.materialProductId} does not exist.`);
    }

    await runInTransaction((conn) => replaceBillOfMaterials(conn, { businessId, productId: product.id, lines }));

    const saved = await billOfMaterials({ businessId, productId: product.id });
    res.json(ok({ productId: product.id, productName: product.name, lines: saved.map(bomView) }));
  } catch (err) {
    next(toAppError(err, { constraintMessages }) ?? err);
  }
}

// ---- §22's production orders -------------------------------------------

export async function list(req, res, next) {
  try {
    const pagination = parsePagination(req.query);
    const { rows, total } = await listProductionOrders({
      businessId: tenant(req),
      query: req.query,
      pagination,
    });
    res.json(paginated(rows.map(orderView), paginationMeta(pagination, total)));
  } catch (err) {
    next(err);
  }
}

export async function get(req, res, next) {
  try {
    const businessId = tenant(req);
    const order = await findProductionOrder({ businessId, id: req.params.id });
    if (!order) throw errors.notFound("production order");

    const view = orderView(order);
    view.materials = (
      await productionMaterials({ businessId, productionOrderId: order.id })
    ).map(materialView);
    res.json(ok(view));
  } catch (err) {
    next(err);
  }
}

export async function create(req, res, next) {
  try {
    const businessId = tenant(req);
    const { productionOrderId } = await createProductionOrder({
      businessId,
      userId: req.auth.userId,
      data: req.body,
    });

    const order = await findProductionOrder({ businessId, id: productionOrderId });
    const view = orderView(order);
    view.materials = (
      await productionMaterials({ businessId, productionOrderId })
    ).map(materialView);
    res.status(201).json(ok(view));
  } catch (err) {
    next(toAppError(err, { constraintMessages }) ?? err);
  }
}

/**
 * §22's status change — and the only path that consumes materials or produces
 * finished goods, so the rule lives in one place.
 */
export async function updateStatus(req, res, next) {
  try {
    const businessId = tenant(req);
    const userId = req.auth.userId;
    const { status, quantityProduced } = req.body;
    const id = req.params.id;

    await runInTransaction(async (conn) => {
      // Every decision comes from the LOCKED row: two concurrent completions
      // would otherwise both consume the materials and both produce the goods.
      const order = await lockProductionOrder({ businessId, id, conn });
      if (!order) throw errors.notFound("production order");

      assertTransition(order.status, status);

      if (movesStock(status)) {
        await completeProductionOrder(conn, { businessId, userId, order, quantityProduced });
        return;
      }

      await conn.query(
        `UPDATE production_orders
            SET status = ?, updated_at = NOW(),
                started_at = ${status === "in_progress" ? "COALESCE(started_at, NOW())" : "started_at"}
          WHERE id = ? AND business_id = ? AND status = ?`,
        [status, order.id, businessId, order.status]
      );
    });

    const order = await findProductionOrder({ businessId, id });
    const view = orderView(order);
    view.materials = (await productionMaterials({ businessId, productionOrderId: id })).map(materialView);
    res.json(ok(view));
  } catch (err) {
    next(toAppError(err) ?? err);
  }
}
