/**
 * "No threshold of its own" needs to be expressible, and was not.
 *
 * `reorder_level` and `min_stock` were NOT NULL DEFAULT 0, which caused two
 * problems that look unrelated and are the same one:
 *
 *  1. §44's low-stock alert could not fall back to the business's default
 *     setting, because every product already had a threshold — 0 — and
 *     `quantity <= 0` is only ever true for a product that is completely out.
 *     A product nobody had configured could run down to nothing without
 *     appearing in the alert list until it was already too late.
 *
 *  2. §54's "null clears the field" could not be honoured. The API accepts
 *     `reorderLevel: null` and means it; the column rejected it, so the request
 *     failed with a database-shaped message about a missing value.
 *
 * Now NULL means "use the business default" and 0 means "only tell me when it
 * is actually empty" — two different intentions that were previously the same
 * value.
 *
 * EXISTING ROWS ARE LEFT ALONE. A stored 0 was written under the old rule, and
 * rewriting it to NULL would change the meaning of data this migration did not
 * author: a business that deliberately set 0 would silently start getting
 * alerts at the default threshold instead.
 */

export async function up(knex) {
  await knex.raw(`ALTER TABLE products MODIFY COLUMN reorder_level DECIMAL(14,3) NULL DEFAULT NULL`);
  await knex.raw(`ALTER TABLE products MODIFY COLUMN min_stock DECIMAL(14,3) NULL DEFAULT NULL`);
}

export async function down(knex) {
  // Rows that are NULL now have no honest pre-migration equivalent; 0 is the
  // value they would have had, and is what the old default would have given them.
  await knex.raw(`UPDATE products SET reorder_level = 0 WHERE reorder_level IS NULL`);
  await knex.raw(`UPDATE products SET min_stock = 0 WHERE min_stock IS NULL`);
  await knex.raw(`ALTER TABLE products MODIFY COLUMN reorder_level DECIMAL(14,3) NOT NULL DEFAULT 0.000`);
  await knex.raw(`ALTER TABLE products MODIFY COLUMN min_stock DECIMAL(14,3) NOT NULL DEFAULT 0.000`);
}
