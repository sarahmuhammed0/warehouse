import { defineListSpec } from "../../db/listQuery.js";
import { createCrudRepository } from "../../db/crudRepository.js";
import { queryOne } from "../../db/pool.js";

/**
 * Units of measurement (§8/§34). Column names come from here and never from
 * the request — see src/db/listQuery.js.
 */
const listSpec = defineListSpec({
  search: { columns: ["u.name", "u.code"] },
  sort: {
    allowed: { name: "u.name", code: "u.code", createdAt: "u.created_at" },
    default: { key: "name", direction: "ASC" },
  },
  dateRange: { column: "u.created_at" },
});

export const unitsRepository = createCrudRepository({
  table: "units",
  alias: "u",
  listSpec,
  selectColumns: "u.id, u.name, u.code, u.decimal_places, u.created_at, u.updated_at",
  columns: {
    /**
     * API shape → row shape. `partial` is what makes an update leave
     * unmentioned fields alone instead of nulling them.
     */
    toRow(data, { partial = false } = {}) {
      const row = {};
      if (data.name !== undefined) row.name = data.name;
      if (data.code !== undefined) row.code = data.code;
      if (data.decimalPlaces !== undefined) row.decimal_places = data.decimalPlaces;
      // A create needs the column's default spelled out; an update must not
      // send a column the caller did not mention.
      if (!partial && row.decimal_places === undefined) row.decimal_places = 0;
      return row;
    },
  },
});

/**
 * Whether any product still measures in this unit.
 *
 * Checked before archiving one: §45 keeps records readable, and a product
 * whose unit has vanished cannot say what "5" means. The database would
 * refuse a hard delete (`products.unit_id` is RESTRICT), but a soft delete
 * slips past that constraint entirely — so the rule has to be enforced here.
 */
export async function unitInUse({ businessId, unitId }) {
  const row = await queryOne(
    `SELECT 1 AS used FROM products
      WHERE business_id = ? AND unit_id = ? AND deleted_at IS NULL LIMIT 1`,
    [businessId, unitId]
  );
  return Boolean(row);
}
