/**
 * Every business needs somewhere to put stock, and the ones created before now
 * have nowhere.
 *
 * `inventory` is keyed on (business, product, variant, warehouse, location), so
 * a business with no warehouse cannot hold stock at all. Nothing created one:
 * not admin business creation, not approving a self-registration. The result
 * looked like a bug in the product screen rather than a missing record —
 *
 *   create a product            it appears, quantity 0, "OUT OF STOCK"
 *   add stock to it             fails; the client has no warehouse to name
 *   the product list            reads quantity as SUM(inventory), so: still 0
 *
 * — and the failure surfaced as "Unable to save", because the dialog discarded
 * the real reason. A business could be used for an afternoon before anyone
 * worked out that the core feature had never been available.
 *
 * `createBusinessWithOwner` now creates one with the business. This gives the
 * same thing to businesses that already exist.
 *
 * Only businesses with NO warehouse at all are touched. One that already has
 * any is left exactly as it is — including which of them is the default, which
 * is a choice somebody made.
 */

export async function up(knex) {
  await knex.raw(`
    INSERT INTO warehouses (business_id, name, code, location_type, is_default, status)
    SELECT b.id, 'Main Warehouse', 'MAIN', 'warehouse', TRUE, 'active'
      FROM businesses b
     WHERE b.deleted_at IS NULL
       AND NOT EXISTS (
             SELECT 1 FROM warehouses w
              WHERE w.business_id = b.id AND w.deleted_at IS NULL
           )
  `);
}

export async function down(knex) {
  // Only the untouched ones this migration could have added: still named and
  // coded as created, still the default, and — the part that matters — holding
  // no stock and referenced by no movement. A warehouse someone has since put
  // stock into is theirs now, whoever created it, and removing it would take
  // the stock with it.
  await knex.raw(`
    DELETE w FROM warehouses w
     WHERE w.name = 'Main Warehouse'
       AND w.code = 'MAIN'
       AND w.is_default = TRUE
       AND NOT EXISTS (SELECT 1 FROM inventory i WHERE i.warehouse_id = w.id)
       AND NOT EXISTS (
             SELECT 1 FROM inventory_movements m
              WHERE m.warehouse_id = w.id
           )
       AND NOT EXISTS (SELECT 1 FROM storage_locations s WHERE s.warehouse_id = w.id)
  `);
}
