import { ok, paginated } from "../../utils/responseEnvelope.js";
import { parsePagination, paginationMeta } from "../../db/pagination.js";
import { errors } from "../../utils/AppError.js";
import { toAppError } from "../../utils/databaseError.js";
import { unitsRepository, unitInUse } from "./repository.js";

/** One shape wherever a unit is returned, so clients parse it once. */
function toView(row) {
  return {
    id: row.id,
    name: row.name,
    code: row.code,
    decimalPlaces: row.decimal_places,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
  };
}

/**
 * Duplicate-code conflicts, phrased for the person who hit them. Without
 * this the generic mapper says "already exists" without saying what does —
 * and the constraint name must never reach the client (§53).
 */
const constraintMessages = {
  uq_units_code: "A unit with this code already exists.",
};

/** The tenant, always from the verified token — never from the request. */
const tenant = (req) => req.auth.businessId;

export async function listUnits(req, res, next) {
  try {
    const pagination = parsePagination(req.query);
    const { rows, total } = await unitsRepository.list({
      businessId: tenant(req),
      query: req.query,
      pagination,
    });
    res.json(paginated(rows.map(toView), paginationMeta(pagination, total)));
  } catch (err) {
    next(err);
  }
}

export async function getUnit(req, res, next) {
  try {
    const row = await unitsRepository.requireById({
      businessId: tenant(req),
      id: req.params.id,
      label: "unit",
    });
    res.json(ok(toView(row)));
  } catch (err) {
    next(err);
  }
}

export async function createUnit(req, res, next) {
  try {
    const id = await unitsRepository.create({ businessId: tenant(req), data: req.body });
    const row = await unitsRepository.findById({ businessId: tenant(req), id });
    res.status(201).json(ok(toView(row)));
  } catch (err) {
    next(toAppError(err, { constraintMessages }) ?? err);
  }
}

export async function updateUnit(req, res, next) {
  try {
    const businessId = tenant(req);
    const updated = await unitsRepository.update({ businessId, id: req.params.id, data: req.body });
    if (!updated) throw errors.notFound("unit");
    res.json(ok(toView(await unitsRepository.findById({ businessId, id: req.params.id }))));
  } catch (err) {
    next(toAppError(err, { constraintMessages }) ?? err);
  }
}

export async function deleteUnit(req, res, next) {
  try {
    const businessId = tenant(req);
    const id = req.params.id;

    // Exists, and is this tenant's, before anything else is considered.
    await unitsRepository.requireById({ businessId, id, label: "unit" });

    if (await unitInUse({ businessId, unitId: id })) {
      // §45: archiving must not make an existing record unreadable. A
      // product whose unit disappeared cannot say what its quantity means.
      throw errors.conflict(
        "This unit is still used by one or more products. Change those products first."
      );
    }

    await unitsRepository.softDelete({ businessId, id });
    res.json(ok({ id: Number(id), deleted: true }));
  } catch (err) {
    next(err);
  }
}
