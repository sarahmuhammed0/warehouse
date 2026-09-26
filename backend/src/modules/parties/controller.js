import { ok, paginated } from "../../utils/responseEnvelope.js";
import { parsePagination, paginationMeta } from "../../db/pagination.js";
import { errors } from "../../utils/AppError.js";
import { toAppError } from "../../utils/databaseError.js";
import { loadPermissions } from "../../middleware/authorize.js";
import {
  customersRepository,
  suppliersRepository,
  customerHasOrders,
  supplierHasPurchases,
} from "./repository.js";

const tenant = (req) => req.auth.businessId;
const num = (v) => (v === null || v === undefined ? null : Number(v));

/**
 * @param showFinancial §24's "View Financial Information". Outstanding
 *   balance and lifetime value are money, so a user without that permission
 *   sees the contact details and not the numbers.
 */
function partyView(row, { showFinancial, countField }) {
  const view = {
    id: row.id,
    name: row.name,
    code: row.code,
    phone: row.phone,
    phoneSecondary: row.phone_secondary,
    email: row.email,
    address: row.address,
    company: row.company ?? null,
    contactPerson: row.contact_person ?? null,
    notes: row.notes,
    status: row.status,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
  };
  view[countField] = Number(row[countField === "orderCount" ? "order_count" : "purchase_count"] ?? 0);

  if (showFinancial) {
    // §18/§19's totals — derived from the documents, never stored.
    view.totalPurchases = num(row.total_purchases) ?? 0;
    view.outstandingBalance = num(row.outstanding_balance) ?? 0;
  }
  return view;
}

const customerConstraints = { uq_customers_code: "A customer with this code already exists." };
const supplierConstraints = { uq_suppliers_code: "A supplier with this code already exists." };

/**
 * Both parties behave identically, so the five handlers are generated once
 * from a small description rather than written twice with one word changed.
 */
function partyController({ repository, label, countField, constraintMessages, inUse, inUseMessage }) {
  return {
    async list(req, res, next) {
      try {
        const pagination = parsePagination(req.query);
        const permissions = await loadPermissions(req);
        const showFinancial = permissions.includes("financial.view");
        const { rows, total } = await repository.list({
          businessId: tenant(req),
          query: req.query,
          pagination,
        });
        res.json(
          paginated(
            rows.map((r) => partyView(r, { showFinancial, countField })),
            paginationMeta(pagination, total)
          )
        );
      } catch (err) {
        next(err);
      }
    },

    async get(req, res, next) {
      try {
        const permissions = await loadPermissions(req);
        const row = await repository.requireById({ businessId: tenant(req), id: req.params.id, label });
        res.json(
          ok(partyView(row, { showFinancial: permissions.includes("financial.view"), countField }))
        );
      } catch (err) {
        next(err);
      }
    },

    async create(req, res, next) {
      try {
        const businessId = tenant(req);
        const id = await repository.create({ businessId, data: req.body });
        const row = await repository.findById({ businessId, id });
        const permissions = await loadPermissions(req);
        res
          .status(201)
          .json(ok(partyView(row, { showFinancial: permissions.includes("financial.view"), countField })));
      } catch (err) {
        next(toAppError(err, { constraintMessages }) ?? err);
      }
    },

    async update(req, res, next) {
      try {
        const businessId = tenant(req);
        const id = req.params.id;
        await repository.requireById({ businessId, id, label });
        await repository.update({ businessId, id, data: req.body });
        const row = await repository.findById({ businessId, id });
        const permissions = await loadPermissions(req);
        res.json(ok(partyView(row, { showFinancial: permissions.includes("financial.view"), countField })));
      } catch (err) {
        next(toAppError(err, { constraintMessages }) ?? err);
      }
    },

    async remove(req, res, next) {
      try {
        const businessId = tenant(req);
        const id = req.params.id;
        await repository.requireById({ businessId, id, label });

        // §45: a party named on a document stays readable. Archiving one
        // with history would leave those documents pointing at a name no
        // screen will show.
        if (await inUse({ businessId, customerId: id, supplierId: id })) {
          throw errors.conflict(inUseMessage);
        }

        await repository.softDelete({ businessId, id });
        res.json(ok({ id: Number(id), deleted: true }));
      } catch (err) {
        next(err);
      }
    },
  };
}

export const customersController = partyController({
  repository: customersRepository,
  label: "customer",
  countField: "orderCount",
  constraintMessages: customerConstraints,
  inUse: customerHasOrders,
  inUseMessage: "This customer has orders and cannot be removed. Set them inactive instead.",
});

export const suppliersController = partyController({
  repository: suppliersRepository,
  label: "supplier",
  countField: "purchaseCount",
  constraintMessages: supplierConstraints,
  inUse: supplierHasPurchases,
  inUseMessage: "This supplier has purchases and cannot be removed. Set them inactive instead.",
});
