import { ok, paginated } from "../../utils/responseEnvelope.js";
import { parsePagination, paginationMeta } from "../../db/pagination.js";
import { errors } from "../../utils/AppError.js";
import { toAppError } from "../../utils/databaseError.js";
import { runInTransaction } from "../../db/pool.js";
import { loadPermissions } from "../../middleware/authorize.js";
import {
  listPurchases,
  findPurchase,
  lockPurchase,
  purchaseItems,
  purchasePayments,
  toStockLines,
  totalPaid,
  supplierExists,
} from "./repository.js";
import {
  createPurchase,
  productResolver,
  assertTransition,
  paymentStatusFor,
  moveStockForPurchase,
  receivesStock,
  recordPayment,
} from "./service.js";

const tenant = (req) => req.auth.businessId;
const num = (v) => (v === null || v === undefined ? null : Number(v));

function purchaseView(row) {
  const total = num(row.total) ?? 0;
  const paidAmount = num(row.paid_amount) ?? 0;
  return {
    id: row.id,
    purchaseNumber: row.purchase_number,
    status: row.status,
    paymentStatus: row.payment_status,
    supplierId: row.supplier_id,
    supplierName: row.supplier_name ?? null,
    supplierPhone: row.supplier_phone ?? null,
    subtotal: num(row.subtotal),
    discountAmount: num(row.discount_amount),
    taxAmount: num(row.tax_amount),
    extraCharges: num(row.extra_charges),
    total,
    paidAmount,
    // Derived, so it cannot disagree with the two numbers it comes from.
    remainingAmount: total - paidAmount,
    itemCount: Number(row.item_count ?? 0),
    note: row.note,
    purchaseDate: row.purchase_date,
    completedAt: row.completed_at,
    createdBy: row.created_by,
    createdByName: row.created_by_name ?? null,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
  };
}

const itemView = (row) => ({
  id: row.id,
  productId: row.product_id,
  variantId: row.variant_id,
  productName: row.product_name,
  sku: row.sku,
  quantity: num(row.quantity),
  unitCost: num(row.unit_cost),
  discountAmount: num(row.discount_amount),
  taxAmount: num(row.tax_amount),
  lineTotal: num(row.line_total),
});

const constraintMessages = { uq_purchases_number: "That purchase number is already in use." };

export async function list(req, res, next) {
  try {
    const pagination = parsePagination(req.query);
    const { rows, total } = await listPurchases({ businessId: tenant(req), query: req.query, pagination });
    res.json(paginated(rows.map(purchaseView), paginationMeta(pagination, total)));
  } catch (err) {
    next(err);
  }
}

export async function get(req, res, next) {
  try {
    const businessId = tenant(req);
    const purchase = await findPurchase({ businessId, id: req.params.id });
    if (!purchase) throw errors.notFound("purchase");

    const view = purchaseView(purchase);
    view.items = (await purchaseItems({ businessId, purchaseId: purchase.id })).map(itemView);

    // §24's financial visibility: what was paid to a supplier is a monetary
    // figure, so the payment history follows the same flag as an order's.
    const permissions = await loadPermissions(req);
    if (permissions.includes("financial.view")) {
      view.payments = (await purchasePayments({ businessId, purchaseId: purchase.id })).map((p) => ({
        id: p.id,
        amount: num(p.amount),
        method: p.method,
        reference: p.reference,
        note: p.note,
        paidAt: p.paid_at,
        createdByName: p.created_by_name,
      }));
    }

    res.json(ok(view));
  } catch (err) {
    next(err);
  }
}

export async function create(req, res, next) {
  try {
    const businessId = tenant(req);

    // §20 records a purchase against a supplier. It stays optional because the
    // column is nullable — a cash purchase from a one-off seller is real — but
    // a supplier that was named has to exist, and has to be this tenant's.
    if (req.body.supplierId && !(await supplierExists({ businessId, supplierId: req.body.supplierId }))) {
      throw errors.validation("The supplier does not exist.");
    }

    const { purchaseId } = await createPurchase({
      businessId,
      userId: req.auth.userId,
      data: req.body,
      resolveProduct: productResolver(businessId),
    });

    const purchase = await findPurchase({ businessId, id: purchaseId });
    const view = purchaseView(purchase);
    view.items = (await purchaseItems({ businessId, purchaseId })).map(itemView);
    res.status(201).json(ok(view));
  } catch (err) {
    next(toAppError(err, { constraintMessages }) ?? err);
  }
}

/**
 * §20's status change — and the only path that receives or reverses a
 * purchase's stock, so the rule lives in one place.
 */
export async function updateStatus(req, res, next) {
  try {
    const businessId = tenant(req);
    const userId = req.auth.userId;
    const { status } = req.body;
    const purchaseId = req.params.id;

    await runInTransaction(async (conn) => {
      // Every decision comes from the LOCKED row. Two concurrent completions
      // that each read on the pool first would both see "pending" and both
      // receive the same delivery.
      const purchase = await lockPurchase({ businessId, id: purchaseId, conn });
      if (!purchase) throw errors.notFound("purchase");

      assertTransition(purchase.status, status);

      const receivedBefore = receivesStock(purchase.status);
      const receivedAfter = receivesStock(status);

      if (receivedBefore !== receivedAfter) {
        const items = toStockLines(await purchaseItems({ businessId, purchaseId, conn }));
        await moveStockForPurchase(conn, {
          businessId,
          userId,
          purchaseId: purchase.id,
          purchaseNumber: purchase.purchase_number,
          items,
          direction: receivedAfter ? +1 : -1,
        });
      }

      await conn.query(
        `UPDATE purchases SET status = ?, updated_at = NOW(),
                completed_at = ${receivedAfter ? "NOW()" : "completed_at"}
          WHERE id = ? AND business_id = ? AND status = ?`,
        [status, purchase.id, businessId, purchase.status]
      );
    });

    const purchase = await findPurchase({ businessId, id: purchaseId });
    const view = purchaseView(purchase);
    view.items = (await purchaseItems({ businessId, purchaseId })).map(itemView);
    res.json(ok(view));
  } catch (err) {
    next(toAppError(err) ?? err);
  }
}

/** §43: paying a supplier, in instalments if that is the arrangement. */
export async function addPayment(req, res, next) {
  try {
    const businessId = tenant(req);
    const userId = req.auth.userId;
    const { amount, method, reference, note } = req.body;
    const purchaseId = req.params.id;

    const result = await runInTransaction(async (conn) => {
      const purchase = await lockPurchase({ businessId, id: purchaseId, conn });
      if (!purchase) throw errors.notFound("purchase");
      if (purchase.status === "cancelled") {
        throw errors.conflict("A cancelled purchase cannot be paid.");
      }

      // Read on the LOCKED row's connection, so two concurrent payments cannot
      // both fit under the same remaining balance.
      const total = Number(purchase.total);
      const alreadyPaid = await totalPaid({ businessId, purchaseId: purchase.id, conn });
      if (alreadyPaid + Number(amount) > total + 0.0001) {
        throw errors.validation(
          `That exceeds the remaining balance of ${(total - alreadyPaid).toFixed(2)}.`
        );
      }

      await recordPayment(conn, {
        businessId,
        purchaseId: purchase.id,
        amount,
        method,
        reference: reference ?? null,
        note: note ?? null,
        userId,
      });

      const paidAmount = alreadyPaid + Number(amount);
      await conn.query(
        `UPDATE purchases SET paid_amount = ?, payment_status = ?, updated_at = NOW()
          WHERE id = ? AND business_id = ?`,
        [paidAmount, paymentStatusFor({ total, paidAmount }), purchase.id, businessId]
      );

      return { purchaseId: purchase.id, paidAmount, remainingAmount: total - paidAmount };
    });

    res.status(201).json(ok(result));
  } catch (err) {
    next(toAppError(err) ?? err);
  }
}
