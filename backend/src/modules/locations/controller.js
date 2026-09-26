import { ok, paginated } from "../../utils/responseEnvelope.js";
import { parsePagination, paginationMeta } from "../../db/pagination.js";
import { errors } from "../../utils/AppError.js";
import { toAppError } from "../../utils/databaseError.js";
import { runInTransaction } from "../../db/pool.js";
import {
  warehousesRepository,
  storageLocationsRepository,
  LOCATION_JOINS,
  clearOtherDefaults,
  warehouseHoldsStock,
  warehouseHasLocations,
  locationHoldsStock,
  warehouseOptions,
  locationOptions,
} from "./repository.js";

const tenant = (req) => req.auth.businessId;

function warehouseView(row) {
  return {
    id: row.id,
    name: row.name,
    code: row.code,
    address: row.address,
    locationType: row.location_type,
    isDefault: Boolean(row.is_default),
    status: row.status,
    locationCount: Number(row.location_count ?? 0),
    createdAt: row.created_at,
    updatedAt: row.updated_at,
  };
}

function locationView(row) {
  return {
    id: row.id,
    warehouseId: row.warehouse_id,
    warehouseName: row.warehouse_name ?? null,
    name: row.name,
    code: row.code,
    aisle: row.aisle,
    rack: row.rack,
    shelf: row.shelf,
    bin: row.bin,
    status: row.status,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
  };
}

const warehouseConstraints = { uq_warehouses_code: "A warehouse with this code already exists." };
const locationConstraints = {
  uq_storage_locations_code: "A location with this code already exists in this warehouse.",
};

// ---- warehouses -----------------------------------------------------------

export async function listWarehouses(req, res, next) {
  try {
    const pagination = parsePagination(req.query);
    const { rows, total } = await warehousesRepository.list({
      businessId: tenant(req),
      query: req.query,
      pagination,
    });
    res.json(paginated(rows.map(warehouseView), paginationMeta(pagination, total)));
  } catch (err) {
    next(err);
  }
}

export async function listWarehouseOptions(req, res, next) {
  try {
    const rows = await warehouseOptions(tenant(req));
    res.json(ok(rows.map((r) => ({ id: r.id, name: r.name, isDefault: Boolean(r.is_default) }))));
  } catch (err) {
    next(err);
  }
}

export async function getWarehouse(req, res, next) {
  try {
    const row = await warehousesRepository.requireById({
      businessId: tenant(req),
      id: req.params.id,
      label: "warehouse",
    });
    res.json(ok(warehouseView(row)));
  } catch (err) {
    next(err);
  }
}

export async function createWarehouse(req, res, next) {
  try {
    const businessId = tenant(req);
    const id = await runInTransaction(async (conn) => {
      const newId = await warehousesRepository.create({ businessId, data: req.body, conn });
      // Setting a default and unsetting the previous one is one change, so
      // it happens in one transaction — otherwise a crash between them
      // leaves the business with two defaults or none.
      if (req.body.isDefault) await clearOtherDefaults(conn, { businessId, keepId: newId });
      return newId;
    });
    res.status(201).json(ok(warehouseView(await warehousesRepository.findById({ businessId, id }))));
  } catch (err) {
    next(toAppError(err, { constraintMessages: warehouseConstraints }) ?? err);
  }
}

export async function updateWarehouse(req, res, next) {
  try {
    const businessId = tenant(req);
    const id = req.params.id;
    await warehousesRepository.requireById({ businessId, id, label: "warehouse" });

    await runInTransaction(async (conn) => {
      await warehousesRepository.update({ businessId, id, data: req.body, conn });
      if (req.body.isDefault) await clearOtherDefaults(conn, { businessId, keepId: id });
    });

    res.json(ok(warehouseView(await warehousesRepository.findById({ businessId, id }))));
  } catch (err) {
    next(toAppError(err, { constraintMessages: warehouseConstraints }) ?? err);
  }
}

export async function deleteWarehouse(req, res, next) {
  try {
    const businessId = tenant(req);
    const id = req.params.id;
    await warehousesRepository.requireById({ businessId, id, label: "warehouse" });

    // Archiving a warehouse that still holds stock would make that stock
    // invisible without moving it anywhere — the quantity would still be in
    // `inventory`, counted by totals, but belonging to nothing a user can
    // open. §12's "records should never silently disappear" covers this.
    if (await warehouseHoldsStock({ businessId, warehouseId: id })) {
      throw errors.conflict("This warehouse still holds stock. Transfer or adjust it to zero first.");
    }
    if (await warehouseHasLocations({ businessId, warehouseId: id })) {
      throw errors.conflict("This warehouse still has storage locations. Archive those first.");
    }

    await warehousesRepository.softDelete({ businessId, id });
    res.json(ok({ id: Number(id), deleted: true }));
  } catch (err) {
    next(err);
  }
}

// ---- storage locations ----------------------------------------------------

/** The warehouse must exist and be this tenant's — an FK alone allows neither. */
async function requireWarehouse({ businessId, warehouseId }) {
  if (warehouseId === undefined) return;
  const warehouse = await warehousesRepository.findById({ businessId, id: warehouseId });
  if (!warehouse) throw errors.validation("The warehouse does not exist.");
}

export async function listStorageLocations(req, res, next) {
  try {
    const pagination = parsePagination(req.query);
    const { rows, total } = await storageLocationsRepository.list({
      businessId: tenant(req),
      query: req.query,
      pagination,
      joins: LOCATION_JOINS,
    });
    res.json(paginated(rows.map(locationView), paginationMeta(pagination, total)));
  } catch (err) {
    next(err);
  }
}

export async function listStorageLocationOptions(req, res, next) {
  try {
    const rows = await locationOptions({
      businessId: tenant(req),
      warehouseId: req.query.warehouseId ? Number(req.query.warehouseId) : null,
    });
    res.json(ok(rows.map((r) => ({ id: r.id, warehouseId: r.warehouse_id, name: r.name }))));
  } catch (err) {
    next(err);
  }
}

export async function getStorageLocation(req, res, next) {
  try {
    const row = await storageLocationsRepository.requireById({
      businessId: tenant(req),
      id: req.params.id,
      joins: LOCATION_JOINS,
      label: "storage location",
    });
    res.json(ok(locationView(row)));
  } catch (err) {
    next(err);
  }
}

export async function createStorageLocation(req, res, next) {
  try {
    const businessId = tenant(req);
    await requireWarehouse({ businessId, warehouseId: req.body.warehouseId });

    const id = await storageLocationsRepository.create({ businessId, data: req.body });
    const row = await storageLocationsRepository.findById({ businessId, id, joins: LOCATION_JOINS });
    res.status(201).json(ok(locationView(row)));
  } catch (err) {
    next(toAppError(err, { constraintMessages: locationConstraints }) ?? err);
  }
}

export async function updateStorageLocation(req, res, next) {
  try {
    const businessId = tenant(req);
    const id = req.params.id;
    await storageLocationsRepository.requireById({ businessId, id, label: "storage location" });
    await requireWarehouse({ businessId, warehouseId: req.body.warehouseId });

    await storageLocationsRepository.update({ businessId, id, data: req.body });
    const row = await storageLocationsRepository.findById({ businessId, id, joins: LOCATION_JOINS });
    res.json(ok(locationView(row)));
  } catch (err) {
    next(toAppError(err, { constraintMessages: locationConstraints }) ?? err);
  }
}

export async function deleteStorageLocation(req, res, next) {
  try {
    const businessId = tenant(req);
    const id = req.params.id;
    await storageLocationsRepository.requireById({ businessId, id, label: "storage location" });

    if (await locationHoldsStock({ businessId, locationId: id })) {
      throw errors.conflict("This location still holds stock. Transfer or adjust it to zero first.");
    }

    await storageLocationsRepository.softDelete({ businessId, id });
    res.json(ok({ id: Number(id), deleted: true }));
  } catch (err) {
    next(err);
  }
}
