import { Router } from "express";
import { z } from "zod";

import { authenticate } from "../../middleware/authenticate.js";
import { requireAccountType } from "../../middleware/requireAccountType.js";
import { authorize, loadPermissions } from "../../middleware/authorize.js";
import { validate } from "../../middleware/validate.js";
import { optionalDateSchema } from "../../validation/common.js";
import { ok } from "../../utils/responseEnvelope.js";
import { errors } from "../../utils/AppError.js";
import * as repo from "./repository.js";

const tenant = (req) => req.auth.businessId;
const num = (v) => (v === null || v === undefined ? null : Number(v));

const rangeSchema = z
  .object({ from: optionalDateSchema, to: optionalDateSchema })
  .passthrough()
  .refine((value) => !value.from || !value.to || value.from <= value.to, {
    message: "The start date must not be after the end date.",
    path: ["from"],
  });

const range = (req) => ({ from: req.query.from ?? null, to: req.query.to ?? null });

/**
 * §24's financial visibility, applied to whole reports.
 *
 * A quantity report is operational: a warehouse manager needs to know what is on
 * the shelf. A revenue report is not — §23 gives financial figures to the owner
 * and the accountant, and a sales report IS a financial figure however it is
 * dressed up. So the money-bearing reports need `financial.view` on top of
 * `reports.view`, rather than being quietly returned with the numbers blanked,
 * which would leave a reader unsure whether zero meant zero.
 */
async function requireFinancialView(req) {
  const permissions = await loadPermissions(req);
  if (!permissions.includes("financial.view")) {
    throw errors.forbidden("This report shows financial information.");
  }
}

export const reportsRouter = Router();
reportsRouter.use(authenticate, requireAccountType("business_user"));

/**
 * What reports exist, and which of them this user may actually open.
 *
 * The screen would otherwise have to hard-code the list and guess at the
 * permissions — and a report that appears and then 403s is worse than one that
 * does not appear.
 */
reportsRouter.get("/", authorize("reports.view"), async (req, res, next) => {
  try {
    const permissions = await loadPermissions(req);
    const financial = permissions.includes("financial.view");

    res.json(
      ok(
        REPORTS.map((report) => ({
          key: report.key,
          path: `/api/reports/${report.key}`,
          title: report.title,
          financial: report.financial,
          available: report.financial ? financial : true,
        }))
      )
    );
  } catch (err) {
    next(err);
  }
});

const REPORTS = [
  { key: "inventory", title: "Stock on hand", financial: false },
  { key: "stock-movements", title: "Stock movements", financial: false },
  { key: "production", title: "Production", financial: false },
  { key: "transfers", title: "Transfers", financial: false },
  { key: "returns", title: "Returns", financial: false },
  { key: "sales", title: "Sales", financial: true },
  { key: "purchases", title: "Purchases", financial: true },
  { key: "profit", title: "Revenue, cost and profit", financial: true },
  { key: "products", title: "Product sales", financial: true },
  { key: "customers", title: "Customers", financial: true },
  { key: "outstanding", title: "Outstanding balances", financial: true },
];

/** One place to hang a report's handler, so each is three lines and no more. */
function report(key, { financial = false, handler }) {
  reportsRouter.get(
    `/${key}`,
    authorize("reports.view"),
    validate(rangeSchema, "query"),
    async (req, res, next) => {
      try {
        if (financial) await requireFinancialView(req);
        res.json(ok(await handler(req)));
      } catch (err) {
        next(err);
      }
    }
  );
}

// ---- operational ---------------------------------------------------------

report("inventory", {
  handler: async (req) => {
    const rows = await repo.inventoryReport({ businessId: tenant(req) });
    return {
      rows: rows.map((r) => ({
        productId: r.product_id,
        name: r.name,
        sku: r.sku,
        categoryName: r.category_name,
        unitCode: r.unit_code,
        quantity: num(r.quantity),
        reorderLevel: num(r.reorder_level),
        purchaseCost: num(r.purchase_cost),
        sellingPrice: num(r.selling_price),
        stockValue: num(r.stock_value),
      })),
      totals: {
        products: rows.length,
        quantity: rows.reduce((sum, r) => sum + Number(r.quantity), 0),
        stockValue: round2(rows.reduce((sum, r) => sum + Number(r.stock_value), 0)),
      },
    };
  },
});

report("stock-movements", {
  handler: async (req) => {
    const rows = await repo.stockMovementReport({ businessId: tenant(req), ...range(req) });
    return {
      rows: rows.map((r) => ({
        movementType: r.movement_type,
        movements: Number(r.movements),
        totalQuantity: num(r.total_quantity),
        products: Number(r.products),
      })),
      totals: { movements: rows.reduce((sum, r) => sum + Number(r.movements), 0) },
    };
  },
});

report("production", {
  handler: async (req) => {
    const rows = await repo.productionReport({ businessId: tenant(req), ...range(req) });
    return {
      rows: rows.map((r) => ({
        period: r.period,
        status: r.status,
        runs: Number(r.runs),
        planned: num(r.planned),
        produced: num(r.produced),
        cost: num(r.cost),
      })),
    };
  },
});

report("transfers", {
  handler: async (req) => {
    const rows = await repo.transfersReport({ businessId: tenant(req), ...range(req) });
    return {
      rows: rows.map((r) => ({
        status: r.status,
        transfers: Number(r.transfers),
        quantity: num(r.quantity),
      })),
    };
  },
});

report("returns", {
  handler: async (req) => {
    const rows = await repo.returnsReport({ businessId: tenant(req), ...range(req) });
    return {
      rows: rows.map((r) => ({
        status: r.status,
        returns: Number(r.returns),
        refunded: num(r.refunded),
        quantity: num(r.quantity),
      })),
    };
  },
});

// ---- financial ----------------------------------------------------------

report("sales", {
  financial: true,
  handler: async (req) => {
    const rows = await repo.salesByMonth({ businessId: tenant(req), ...range(req) });
    return {
      rows: rows.map(monthlySales),
      totals: sumOf(rows, ["orders", "subtotal", "tax", "discount", "total", "paid", "outstanding"]),
    };
  },
});

report("purchases", {
  financial: true,
  handler: async (req) => {
    const rows = await repo.purchasesByMonth({ businessId: tenant(req), ...range(req) });
    return {
      rows: rows.map((r) => ({
        period: r.period,
        purchases: Number(r.purchases),
        subtotal: num(r.subtotal),
        tax: num(r.tax),
        total: num(r.total),
        paid: num(r.paid),
        outstanding: num(r.outstanding),
      })),
      totals: sumOf(rows, ["purchases", "subtotal", "tax", "total", "paid", "outstanding"]),
    };
  },
});

/**
 * §25's profit report — and an honest statement of what it can and cannot be.
 *
 * This is CASH-BASIS: revenue is what was sold in the period, cost is what was
 * bought in the period. It is not cost-of-goods-sold, because a true COGS needs
 * the cost of each item AT THE MOMENT IT SOLD, and `order_items` snapshots the
 * selling price (§55) but not the cost. Using today's purchase cost for a sale
 * made a year ago would silently restate old profit every time a supplier
 * changed a price, which is worse than a clearly-labelled cash-basis figure.
 *
 * The response says so in `basis`, so a screen cannot present it as something it
 * is not. Making it accrual-basis is a schema change — a `unit_cost` column on
 * `order_items`, filled at the same moment as the price — and is noted in
 * docs/backend-phase9.md rather than approximated here.
 */
report("profit", {
  financial: true,
  handler: async (req) => {
    const businessId = tenant(req);
    const window = range(req);
    const [sales, purchases] = await Promise.all([
      repo.salesByMonth({ businessId, ...window }),
      repo.purchasesByMonth({ businessId, ...window }),
    ]);

    const periods = [...new Set([...sales.map((r) => r.period), ...purchases.map((r) => r.period)])].sort();
    const salesBy = new Map(sales.map((r) => [r.period, r]));
    const purchasesBy = new Map(purchases.map((r) => [r.period, r]));

    const rows = periods.map((period) => {
      const revenue = Number(salesBy.get(period)?.total ?? 0);
      const cost = Number(purchasesBy.get(period)?.total ?? 0);
      return {
        period,
        revenue: round2(revenue),
        cost: round2(cost),
        profit: round2(revenue - cost),
      };
    });

    return {
      basis: "cash",
      basisNote:
        "Revenue is what was sold in the period and cost is what was bought in it. This is not cost-of-goods-sold: order lines snapshot the selling price, not the cost at the time.",
      rows,
      totals: {
        revenue: round2(rows.reduce((sum, r) => sum + r.revenue, 0)),
        cost: round2(rows.reduce((sum, r) => sum + r.cost, 0)),
        profit: round2(rows.reduce((sum, r) => sum + r.profit, 0)),
      },
    };
  },
});

report("products", {
  financial: true,
  handler: async (req) => {
    const rows = await repo.productSalesReport({ businessId: tenant(req), ...range(req) });
    return {
      rows: rows.map((r) => ({
        productId: r.product_id,
        name: r.product_name,
        sku: r.sku,
        quantitySold: num(r.quantity_sold),
        revenue: num(r.revenue),
        orders: Number(r.orders),
      })),
      totals: sumOf(rows, ["quantity_sold", "revenue"]),
    };
  },
});

report("customers", {
  financial: true,
  handler: async (req) => {
    const rows = await repo.customerReport({ businessId: tenant(req), ...range(req) });
    return {
      rows: rows.map((r) => ({
        customerId: r.customer_id,
        name: r.name,
        phone: r.phone,
        orders: Number(r.orders),
        total: num(r.total),
        paid: num(r.paid),
        outstanding: num(r.outstanding),
        lastOrderDate: r.last_order_date,
      })),
      totals: sumOf(rows, ["orders", "total", "paid", "outstanding"]),
    };
  },
});

report("outstanding", {
  financial: true,
  handler: async (req) => {
    const { receivable, payable } = await repo.outstandingReport({ businessId: tenant(req) });
    return {
      receivable: receivable.map((r) => ({
        orderId: r.id,
        orderNumber: r.order_number,
        orderDate: r.order_date,
        status: r.status,
        paymentStatus: r.payment_status,
        customerName: r.customer_name,
        total: num(r.grand_total),
        paid: num(r.paid_amount),
        outstanding: num(r.outstanding),
      })),
      payable: payable.map((r) => ({
        purchaseId: r.id,
        purchaseNumber: r.purchase_number,
        purchaseDate: r.purchase_date,
        status: r.status,
        paymentStatus: r.payment_status,
        supplierName: r.supplier_name,
        total: num(r.total),
        paid: num(r.paid_amount),
        outstanding: num(r.outstanding),
      })),
      totals: {
        receivable: round2(receivable.reduce((sum, r) => sum + Number(r.outstanding), 0)),
        payable: round2(payable.reduce((sum, r) => sum + Number(r.outstanding), 0)),
      },
    };
  },
});

const monthlySales = (r) => ({
  period: r.period,
  orders: Number(r.orders),
  subtotal: num(r.subtotal),
  tax: num(r.tax),
  discount: num(r.discount),
  total: num(r.total),
  paid: num(r.paid),
  outstanding: num(r.outstanding),
});

const round2 = (value) => Math.round((Number(value) + Number.EPSILON) * 100) / 100;

/** Column totals, so a screen never has to add a page of rows and call it the total. */
function sumOf(rows, columns) {
  const totals = {};
  for (const column of columns) {
    const key = column.replace(/_([a-z])/g, (_, c) => c.toUpperCase());
    totals[key] = round2(rows.reduce((sum, row) => sum + Number(row[column] ?? 0), 0));
  }
  return totals;
}
