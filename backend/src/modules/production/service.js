import { runInTransaction } from "../../db/pool.js";
import { errors } from "../../utils/AppError.js";
import { nextDocumentNumber } from "../documents/numbering.js";
import { planOutbound } from "../inventory/allocation.js";
import { adjustStock } from "../inventory/service.js";
import { defaultWarehouseId, warehousesRepository } from "../locations/repository.js";
import { findUser } from "../users/repository.js";
import { billOfMaterials, findProduct, productionMaterials } from "./repository.js";
import { notifyProductionCompleted } from "../notifications/triggers.js";

/**
 * Production and the bill of materials (§21, §22).
 *
 * §21's raw materials are PRODUCTS — the schema decision recorded in
 * docs/architecture.md — so a production run is not a special kind of stock
 * event. It is several ordinary ones inside a single transaction: each material
 * leaves stock, the finished good enters it, and the ledger explains both. That
 * is the whole reason it goes through `adjustStock` like everything else: a run
 * that consumed its materials but crashed before producing anything would leave
 * a factory believing it owns wood it has already cut.
 */

/** §22's lifecycle. */
const ALLOWED_TRANSITIONS = {
  planned: ["in_progress", "completed", "cancelled"],
  in_progress: ["completed", "cancelled"],
  // Terminal. Un-completing a run would have to un-consume materials that have
  // physically been cut and un-make goods that exist.
  completed: [],
  cancelled: [],
};

/**
 * Nothing moves until a run COMPLETES.
 *
 * Consuming on "in progress" would be closer to how a factory floor actually
 * works, but it makes cancellation a restocking problem — how much of the wood
 * is left, and in what state — that §22 says nothing about. Completion is the
 * point at which both sides are known, so both sides happen there.
 */
const STOCK_MOVED_FROM = new Set(["completed"]);

export const movesStock = (status) => STOCK_MOVED_FROM.has(status);

const money = (value) => Math.round((Number(value) + Number.EPSILON) * 100) / 100;
const qty = (value) => Math.round((Number(value) + Number.EPSILON) * 1000) / 1000;

export function assertTransition(from, to) {
  const allowed = ALLOWED_TRANSITIONS[from] ?? [];
  if (!allowed.includes(to)) {
    throw errors.conflict(`A production order that is ${from} cannot become ${to}.`);
  }
}

/**
 * What a run of `quantity` needs, from the product's bill of materials.
 *
 * §21's own example — "Paint: 1 liter, Wood: 5 pieces" per unit — scales with
 * the batch, so the BOM stores a per-unit figure and this multiplies it. The
 * result is SNAPSHOTTED onto the run, so editing the recipe afterwards changes
 * the next batch and not the history of this one.
 */
export async function materialsForRun({ businessId, productId, quantity, conn }) {
  const bom = await billOfMaterials({ businessId, productId, conn });
  return bom.map((line) => ({
    materialProductId: line.material_product_id,
    quantityRequired: qty(Number(line.quantity_per_unit) * Number(quantity)),
    // The cost of the materials as they stand today — what this batch cost to
    // make. A later price rise must not restate the cost of goods already made.
    unitCost: line.material_cost === null ? null : money(line.material_cost),
  }));
}

/**
 * Creates a production order and snapshots what it will need.
 *
 * Materials come from the BOM unless the caller sends its own list — a real run
 * substitutes a material often enough (§21's recipe is a default, not a law)
 * and the frontend's form lets the operator adjust the lines before saving.
 */
export async function createProductionOrder({ businessId, userId, data }) {
  return runInTransaction(async (conn) => {
    const product = await findProduct({ businessId, productId: data.productId, conn });
    if (!product) throw errors.validation("The product does not exist.");

    const materials = data.materials?.length
      ? data.materials.map((line) => ({
          materialProductId: line.materialProductId,
          quantityRequired: qty(line.quantityRequired),
          unitCost: line.unitCost === undefined ? undefined : line.unitCost,
        }))
      : await materialsForRun({
          businessId,
          productId: product.id,
          quantity: data.quantityPlanned,
          conn,
        });

    if (!materials.length) {
      throw errors.validation(
        `"${product.name}" has no bill of materials, so there is nothing to make it from. Add one first, or send the materials with the run.`
      );
    }

    // Every material must be this tenant's own product, and must not be the
    // finished good itself — the database's own CHECK forbids that in a BOM,
    // and a run that consumes what it produces is the same mistake.
    for (const line of materials) {
      if (String(line.materialProductId) === String(product.id)) {
        throw errors.validation("A product cannot be made out of itself.");
      }
      const material = await findProduct({ businessId, productId: line.materialProductId, conn });
      if (!material) {
        throw errors.validation(`Material ${line.materialProductId} does not exist.`);
      }
      if (line.unitCost === undefined) {
        line.unitCost = material.purchase_cost === null ? null : money(material.purchase_cost);
      }
    }

    // Both of these arrive as bare numbers the client chooses, and both were
    // inserted without a tenant check (§36) while every product on the same run
    // was checked. The warehouse one is the worse of the two: a run naming
    // another factory's warehouse would have drawn that factory's materials and
    // put the finished goods there. The assignment is a smaller leak of the same
    // shape — somebody else's staff listed as responsible for your run — and it
    // only became reachable from the UI when the Employee field started sending
    // an id instead of discarding a typed name.
    const warehouseId = data.warehouseId ?? (await defaultWarehouseId(businessId, conn));
    if (!warehouseId) {
      throw errors.validation("No default warehouse is configured. Create one before producing stock.");
    }
    if (data.warehouseId && !(await warehousesRepository.findById({ businessId, id: data.warehouseId }))) {
      throw errors.validation(`Warehouse ${data.warehouseId} does not exist.`);
    }
    if (data.assignedUserId && !(await findUser({ businessId, id: data.assignedUserId, conn }))) {
      throw errors.validation(`User ${data.assignedUserId} does not exist.`);
    }

    const productionNumber = await nextDocumentNumber(conn, { businessId, documentType: "production" });
    const status = data.status ?? "planned";

    const [result] = await conn.query(
      `INSERT INTO production_orders
         (business_id, product_id, variant_id, warehouse_id, production_number, batch_number,
          quantity_planned, quantity_produced, production_cost, status, assigned_user_id,
          production_date, started_at, note, created_by)
       VALUES (?, ?, ?, ?, ?, ?, ?, 0, ?, ?, ?, ?, ?, ?, ?)`,
      [
        businessId,
        product.id,
        data.variantId ?? null,
        warehouseId,
        productionNumber,
        data.batchNumber ?? null,
        qty(data.quantityPlanned),
        estimatedCost(materials),
        status,
        data.assignedUserId ?? null,
        data.productionDate ?? null,
        status === "in_progress" ? new Date() : null,
        data.note ?? null,
        userId,
      ]
    );
    const productionOrderId = result.insertId;

    for (const line of materials) {
      await conn.query(
        `INSERT INTO production_items
           (business_id, production_order_id, material_product_id, variant_id,
            quantity_required, quantity_consumed, unit_cost)
         VALUES (?, ?, ?, ?, ?, 0, ?)`,
        [
          businessId,
          productionOrderId,
          line.materialProductId,
          line.variantId ?? null,
          line.quantityRequired,
          line.unitCost ?? null,
        ]
      );
    }

    return { productionOrderId, productionNumber };
  });
}

/** What the run is expected to cost, from the snapshotted material costs. */
function estimatedCost(materials) {
  const known = materials.filter((line) => line.unitCost !== null && line.unitCost !== undefined);
  if (!known.length) return null;
  return money(known.reduce((sum, line) => sum + line.unitCost * line.quantityRequired, 0));
}

/**
 * §22's completion: the materials are consumed and the finished goods appear,
 * inside the caller's transaction, or neither happens.
 *
 * Runs on the caller's connection because the production row is already locked
 * — opening a second transaction here would wait on that lock until MySQL timed
 * it out.
 */
export async function completeProductionOrder(conn, { businessId, userId, order, quantityProduced }) {
  const materials = await productionMaterials({
    businessId,
    productionOrderId: order.id,
    conn,
  });

  const produced = qty(quantityProduced ?? order.quantity_planned);
  if (produced <= 0) {
    throw errors.validation("A completed run must have produced something.");
  }

  let cost = 0;
  let costKnown = false;

  for (const material of materials) {
    const required = qty(material.quantity_required);
    if (required <= 0) continue;

    // The materials leave the run's own warehouse, across whichever shelves
    // hold them (§11), and §47 decides what happens if there are not enough —
    // which is the honest answer: a factory cannot cut wood it does not have.
    const legs = await planOutbound(conn, {
      businessId,
      productId: material.material_product_id,
      variantId: material.variant_id ?? null,
      warehouseId: order.warehouse_id,
      quantity: required,
    });

    for (const leg of legs) {
      await adjustStock({
        businessId,
        userId,
        productId: material.material_product_id,
        variantId: material.variant_id ?? null,
        warehouseId: leg.warehouseId,
        locationId: leg.locationId,
        delta: -leg.quantity,
        movementType: "production",
        referenceType: "production",
        referenceId: order.id,
        referenceNumber: order.production_number,
        reason: "Consumed in production",
        conn,
      });
    }

    await conn.query(
      `UPDATE production_items SET quantity_consumed = ?, updated_at = NOW() WHERE id = ?`,
      [required, material.id]
    );

    if (material.unit_cost !== null) {
      cost += Number(material.unit_cost) * required;
      costKnown = true;
    }
  }

  // And the finished goods exist. Into the run's warehouse, location-less, the
  // same place a delivery arrives — nothing has put them on a shelf yet.
  await adjustStock({
    businessId,
    userId,
    productId: order.product_id,
    variantId: order.variant_id ?? null,
    warehouseId: order.warehouse_id,
    locationId: null,
    delta: +produced,
    movementType: "production",
    referenceType: "production",
    referenceId: order.id,
    referenceNumber: order.production_number,
    reason: "Produced",
    conn,
  });

  await conn.query(
    `UPDATE production_orders
        SET status = 'completed', quantity_produced = ?, production_cost = ?,
            started_at = COALESCE(started_at, NOW()), completed_at = NOW(), updated_at = NOW()
      WHERE id = ? AND business_id = ? AND status = ?`,
    [produced, costKnown ? money(cost) : null, order.id, businessId, order.status]
  );

  // §31: the batch is finished and the goods are sellable — which is news to
  // whoever is taking orders for them.
  const [[product]] = await conn.query(`SELECT name FROM products WHERE id = ? LIMIT 1`, [
    order.product_id,
  ]);
  await notifyProductionCompleted(conn, {
    businessId,
    productionOrderId: order.id,
    productionNumber: order.production_number,
    productName: product?.name ?? "the product",
    quantityProduced: produced,
  });
}
