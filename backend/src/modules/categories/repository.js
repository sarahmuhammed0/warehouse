import { defineListSpec } from "../../db/listQuery.js";
import { createCrudRepository } from "../../db/crudRepository.js";
import { queryOne, queryAll } from "../../db/pool.js";

/**
 * The join every read needs: a category shows its parent's NAME, not just an
 * id. Declared on the repository as `defaultJoins` below, so no call site
 * can forget it and hit "Unknown column".
 */
export const CATEGORY_JOINS = `LEFT JOIN categories parent
  ON parent.id = c.parent_id AND parent.business_id = c.business_id AND parent.deleted_at IS NULL`;

/** Categories (§7). Hierarchical: a category may have a parent. */
const listSpec = defineListSpec({
  filters: {
    status: { column: "c.status", type: "enum", values: ["active", "inactive"] },
    parentId: { column: "c.parent_id", type: "int" },
  },
  search: { columns: ["c.name", "c.code"] },
  sort: {
    allowed: { name: "c.name", code: "c.code", sortOrder: "c.sort_order", createdAt: "c.created_at" },
    // §7 lists "Sort order" as a field, so it is what the list honours by
    // default — a business that bothered to order its categories expects to
    // see them in that order.
    default: { key: "sortOrder", direction: "ASC" },
  },
  dateRange: { column: "c.created_at" },
});

export const categoriesRepository = createCrudRepository({
  table: "categories",
  alias: "c",
  listSpec,
  defaultJoins: CATEGORY_JOINS,
  selectColumns: `c.id, c.parent_id, c.name, c.code, c.image_url, c.description,
                  c.sort_order, c.status, c.created_at, c.updated_at,
                  parent.name AS parent_name,
                  (SELECT COUNT(*) FROM products p
                    WHERE p.category_id = c.id AND p.deleted_at IS NULL) AS product_count`,
  columns: {
    toRow(data, { partial = false } = {}) {
      const row = {};
      if (data.name !== undefined) row.name = data.name;
      if (data.code !== undefined) row.code = data.code;
      if (data.parentId !== undefined) row.parent_id = data.parentId;
      if (data.imageUrl !== undefined) row.image_url = data.imageUrl;
      if (data.description !== undefined) row.description = data.description;
      if (data.sortOrder !== undefined) row.sort_order = data.sortOrder;
      if (data.status !== undefined) row.status = data.status;
      if (!partial && row.sort_order === undefined) row.sort_order = 0;
      return row;
    },
  },
});

/** Products still filed under this category (§45 — see the controller). */
export async function categoryInUse({ businessId, categoryId }) {
  const row = await queryOne(
    `SELECT 1 AS used FROM products
      WHERE business_id = ? AND category_id = ? AND deleted_at IS NULL LIMIT 1`,
    [businessId, categoryId]
  );
  return Boolean(row);
}

/** Direct children — a parent cannot be archived while it still has any. */
export async function categoryHasChildren({ businessId, categoryId }) {
  const row = await queryOne(
    `SELECT 1 AS used FROM categories
      WHERE business_id = ? AND parent_id = ? AND deleted_at IS NULL LIMIT 1`,
    [businessId, categoryId]
  );
  return Boolean(row);
}

/**
 * Walks up from `parentId` looking for `categoryId`.
 *
 * §7 allows a parent category, which means the table can describe a cycle:
 * A's parent is B and B's parent is A. Nothing in the schema forbids it —
 * a self-referencing foreign key is perfectly happy — but a cycle makes the
 * tree infinite, and any code that walks it hangs. The check is bounded by
 * depth as a second guard, so a cycle that somehow already exists cannot
 * hang this function either.
 */
export async function wouldCreateCycle({ businessId, categoryId, parentId }) {
  if (!parentId) return false;
  if (String(parentId) === String(categoryId)) return true;

  let current = parentId;
  for (let depth = 0; depth < 50 && current; depth += 1) {
    const row = await queryOne(
      `SELECT parent_id FROM categories WHERE id = ? AND business_id = ? AND deleted_at IS NULL LIMIT 1`,
      [current, businessId]
    );
    if (!row) return false;
    if (String(row.parent_id) === String(categoryId)) return true;
    current = row.parent_id;
  }
  return false;
}

/** Flat list for pickers — §7's tree, unpaginated, active only. */
export async function categoryOptions(businessId) {
  return queryAll(
    `SELECT id, parent_id, name FROM categories
      WHERE business_id = ? AND deleted_at IS NULL AND status = 'active'
      ORDER BY sort_order ASC, name ASC`,
    [businessId]
  );
}
