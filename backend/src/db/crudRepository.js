import { pool, queryAll, queryOne, queryCount } from "./pool.js";
import { buildWhere, buildOrderBy } from "./listQuery.js";
import { errors } from "../utils/AppError.js";

/**
 * The parts every business-module repository repeats: a tenant-scoped paged
 * list, a tenant-scoped read, create, update and soft delete.
 *
 * TENANT SCOPING IS NOT OPTIONAL HERE. Every query this builds starts from
 * `business_id = ?` and `deleted_at IS NULL`, applied as the *scope* rather
 * than as a filter, so nothing a client sends can widen it. §36 is the
 * strictest rule in the specification, and the way it gets broken in
 * practice is one hand-written query that forgot the predicate — so the
 * modules do not hand-write it.
 *
 * Deliberately not an ORM and not a base class: it is a set of functions a
 * module calls with its own table name, list spec and column mapping. A
 * module that needs something unusual writes that query itself rather than
 * bending an abstraction, which is what keeps this small.
 */
/**
 * `defaultJoins` belongs to the repository, not to each call site. When a
 * module's `selectColumns` reference a joined table — a category's parent
 * name, a location's warehouse name — every query that omits the join fails
 * with "Unknown column". Making the caller remember it is a trap that fires
 * on whichever path was tested least.
 */
export function createCrudRepository({
  table,
  alias,
  listSpec,
  columns,
  selectColumns,
  defaultJoins = "",
  softDelete = true,
}) {
  const scope = (businessId) => {
    const s = { [`${alias}.business_id`]: businessId };
    if (softDelete) s[`${alias}.deleted_at`] = null;
    return s;
  };

  /** The SELECT list, built once. */
  const projection = selectColumns ?? `${alias}.*`;

  return {
    table,
    alias,
    listSpec,

    /** Paged, filtered, sorted — all through the allowlist, never raw input. */
    async list({ businessId, query, pagination, joins = defaultJoins }) {
      const where = buildWhere(listSpec, query, scope(businessId));
      const orderBy = buildOrderBy(listSpec, query, `${alias}.id`);

      const rows = await queryAll(
        `SELECT ${projection} FROM ${table} ${alias} ${joins} ${where.sql} ${orderBy} LIMIT ? OFFSET ?`,
        [...where.params, pagination.pageSize, pagination.offset]
      );

      // Same WHERE and the same parameters as the page query, so the total
      // can never describe a different filter than the rows do.
      const total = await queryCount(
        `SELECT COUNT(*) AS total FROM ${table} ${alias} ${joins} ${where.sql}`,
        where.params
      );

      return { rows, total };
    },

    /** One row, or null. Scoped, so another tenant's id simply is not found. */
    async findById({ businessId, id, joins = defaultJoins }) {
      const deleted = softDelete ? `AND ${alias}.deleted_at IS NULL` : "";
      return queryOne(
        `SELECT ${projection} FROM ${table} ${alias} ${joins}
          WHERE ${alias}.id = ? AND ${alias}.business_id = ? ${deleted} LIMIT 1`,
        [id, businessId]
      );
    },

    /**
     * Same as findById but throws instead of returning null. A 404 rather
     * than a 403 for another tenant's row is deliberate: "this exists but
     * is not yours" is itself information (§36).
     */
    async requireById({ businessId, id, joins = defaultJoins, label = "record" }) {
      const row = await this.findById({ businessId, id, joins });
      // `errors.notFound` phrases the sentence itself, so this passes the
      // noun only: "That product could not be found."
      if (!row) throw errors.notFound(label);
      return row;
    },

    /** Insert. `businessId` is set here, never taken from the payload. */
    async create({ businessId, data, conn = pool }) {
      const values = { business_id: businessId, ...columns.toRow(data) };
      const names = Object.keys(values);
      const [result] = await conn.query(
        `INSERT INTO ${table} (${names.join(", ")}) VALUES (${names.map(() => "?").join(", ")})`,
        Object.values(values)
      );
      return result.insertId;
    },

    /**
     * Partial update. Only the fields present in `data` are written, so an
     * omitted field keeps its value rather than being nulled — a PUT that
     * silently blanks what the client did not send is a data-loss bug.
     *
     * Returns false when nothing matched, which the caller turns into a 404.
     */
    async update({ businessId, id, data, conn = pool }) {
      const values = columns.toRow(data, { partial: true });
      if (Object.keys(values).length === 0) return true;

      const assignments = Object.keys(values).map((name) => `${name} = ?`);
      const deleted = softDelete ? "AND deleted_at IS NULL" : "";
      const [result] = await conn.query(
        `UPDATE ${table} SET ${assignments.join(", ")}, updated_at = NOW()
          WHERE id = ? AND business_id = ? ${deleted}`,
        [...Object.values(values), id, businessId]
      );
      return result.affectedRows === 1;
    },

    /**
     * Soft delete (§45/§61 rule 6) — the row stays, so documents that
     * reference it keep meaning something. A module whose table has no
     * `deleted_at` must not use this.
     */
    async softDelete({ businessId, id, conn = pool }) {
      if (!softDelete) throw new Error(`${table} is not soft-deletable`);
      const [result] = await conn.query(
        `UPDATE ${table} SET deleted_at = NOW() WHERE id = ? AND business_id = ? AND deleted_at IS NULL`,
        [id, businessId]
      );
      return result.affectedRows === 1;
    },
  };
}
