import { Router } from "express";
import { z } from "zod";

import { authenticate } from "../../middleware/authenticate.js";
import { requireAccountType } from "../../middleware/requireAccountType.js";
import { authorize } from "../../middleware/authorize.js";
import { auditTrail } from "../../middleware/auditTrail.js";
import { validate, validateRequest } from "../../middleware/validate.js";
import {
  idParamsSchema,
  idSchema,
  listQuerySchema,
  optionalString,
  enumSchema,
  positiveQuantitySchema,
  optionalDateSchema,
} from "../../validation/common.js";
import { ok, paginated } from "../../utils/responseEnvelope.js";
import { parsePagination, paginationMeta } from "../../db/pagination.js";
import { errors } from "../../utils/AppError.js";
import { toAppError } from "../../utils/databaseError.js";
import { runInTransaction } from "../../db/pool.js";
import { nextDocumentNumber } from "../documents/numbering.js";
import * as repo from "./repository.js";
import { assertTransition, assertDifferentSlots, moveTransferStock, movesStock } from "./service.js";

const tenant = (req) => req.auth.businessId;
const num = (v) => (v === null || v === undefined ? null : Number(v));

const transferView = (row) => ({
  id: row.id,
  transferNumber: row.transfer_number,
  status: row.status,
  fromWarehouseId: row.from_warehouse_id,
  fromWarehouseName: row.from_warehouse_name ?? null,
  fromLocationId: row.from_location_id,
  fromLocationName: row.from_location_name ?? null,
  toWarehouseId: row.to_warehouse_id,
  toWarehouseName: row.to_warehouse_name ?? null,
  toLocationId: row.to_location_id,
  toLocationName: row.to_location_name ?? null,
  itemCount: Number(row.item_count ?? 0),
  note: row.note,
  transferDate: row.transfer_date,
  completedAt: row.completed_at,
  createdBy: row.created_by,
  createdByName: row.created_by_name ?? null,
  createdAt: row.created_at,
  updatedAt: row.updated_at,
});

const itemView = (row) => ({
  id: row.id,
  productId: row.product_id,
  productName: row.product_name,
  sku: row.sku,
  variantId: row.variant_id,
  quantity: num(row.quantity),
});

const itemSchema = z.object({
  productId: idSchema,
  variantId: idSchema.nullable().optional(),
  quantity: positiveQuantitySchema,
});

const createSchema = z.object({
  fromWarehouseId: idSchema,
  fromLocationId: idSchema.nullable().optional(),
  toWarehouseId: idSchema,
  toLocationId: idSchema.nullable().optional(),
  items: z.array(itemSchema).min(1, "A transfer needs at least one item."),
  note: optionalString(5000),
  transferDate: optionalDateSchema,
  // `completed` at creation is the common case: a clerk moving a pallet now and
  // writing it down as they do it.
  status: enumSchema(["draft", "pending", "in_transit", "completed"], "Status").optional(),
});

const statusSchema = z.object({
  status: enumSchema(["pending", "in_transit", "completed", "cancelled"], "Status"),
});

export const transfersRouter = Router();
transfersRouter.use(authenticate, requireAccountType("business_user"), auditTrail("inventory"));

/**
 * Gated on `inventory.*` — §11 is part of stock control, and the people who move
 * goods between shelves are the people who run inventory.
 */
transfersRouter.get("/", authorize("inventory.view"), validate(listQuerySchema, "query"), async (req, res, next) => {
  try {
    const pagination = parsePagination(req.query);
    const { rows, total } = await repo.listTransfers({
      businessId: tenant(req),
      query: req.query,
      pagination,
    });
    res.json(paginated(rows.map(transferView), paginationMeta(pagination, total)));
  } catch (err) {
    next(err);
  }
});

transfersRouter.get(
  "/:id",
  authorize("inventory.view"),
  validate(idParamsSchema, "params"),
  async (req, res, next) => {
    try {
      const businessId = tenant(req);
      const transfer = await repo.findTransfer({ businessId, id: req.params.id });
      if (!transfer) throw errors.notFound("transfer");

      const view = transferView(transfer);
      view.items = (await repo.transferItems({ businessId, transferId: transfer.id })).map(itemView);
      res.json(ok(view));
    } catch (err) {
      next(err);
    }
  }
);

transfersRouter.post("/", authorize("inventory.edit"), validate(createSchema), async (req, res, next) => {
  try {
    const businessId = tenant(req);
    const userId = req.auth.userId;

    assertDifferentSlots(req.body);
    const problem = await repo.ownershipProblem({ businessId, data: req.body });
    if (problem) throw errors.validation(problem);

    const status = req.body.status ?? "pending";

    const transferId = await runInTransaction(async (conn) => {
      const transferNumber = await nextDocumentNumber(conn, { businessId, documentType: "transfer" });
      const id = await repo.insertTransfer(conn, {
        businessId,
        userId,
        transferNumber,
        data: req.body,
        status,
      });
      for (const item of req.body.items) {
        await repo.insertTransferItem(conn, { businessId, transferId: id, item });
      }

      // Created as already arrived: the goods move inside the same transaction,
      // so a transfer cannot exist without the movement it describes (§46).
      if (movesStock(status)) {
        const transfer = await repo.lockTransfer({ businessId, id, conn });
        await moveTransferStock(conn, { businessId, userId, transfer });
      }
      return id;
    });

    const transfer = await repo.findTransfer({ businessId, id: transferId });
    const view = transferView(transfer);
    view.items = (await repo.transferItems({ businessId, transferId })).map(itemView);
    res.status(201).json(ok(view));
  } catch (err) {
    next(toAppError(err, { constraintMessages }) ?? err);
  }
});

/** The only path that moves a transfer's stock, so the rule lives in one place. */
transfersRouter.patch(
  "/:id/status",
  authorize("inventory.edit"),
  validateRequest({ params: idParamsSchema, body: statusSchema }),
  async (req, res, next) => {
    try {
      const businessId = tenant(req);
      const userId = req.auth.userId;
      const { status } = req.body;
      const id = req.params.id;

      await runInTransaction(async (conn) => {
        // Every decision from the LOCKED row: two concurrent completions would
        // otherwise both see "in_transit" and both move the goods.
        const transfer = await repo.lockTransfer({ businessId, id, conn });
        if (!transfer) throw errors.notFound("transfer");

        assertTransition(transfer.status, status);

        if (movesStock(status)) {
          await moveTransferStock(conn, { businessId, userId, transfer });
        }

        const affected = await repo.setTransferStatus(conn, {
          businessId,
          id,
          from: transfer.status,
          status,
        });
        if (affected === 0) throw errors.conflict("That transfer changed while this was being saved.");
      });

      const transfer = await repo.findTransfer({ businessId, id });
      const view = transferView(transfer);
      view.items = (await repo.transferItems({ businessId, transferId: id })).map(itemView);
      res.json(ok(view));
    } catch (err) {
      next(toAppError(err) ?? err);
    }
  }
);

const constraintMessages = {
  uq_stock_transfers_number: "That transfer number is already in use.",
};
