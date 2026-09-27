/**
 * §55's snapshot, on the two document lines that were missing it.
 *
 * `order_items` already keeps `product_name` and `sku` as they were when the
 * line was written, so renaming a product cannot rewrite the invoices it
 * appears on. A purchase line and a return line are documents in exactly the
 * same sense: a purchase line already freezes `unit_cost`, and freezing the
 * price but not the name is the half-measure that leaves a two-year-old
 * purchase reading as though it had always been for the renamed product.
 *
 * NULLABLE rather than NOT NULL, and deliberately not backfilled. The name at
 * the time is precisely what was never recorded for existing rows, so there is
 * no honest value to write; a reader falls back to the product's current name,
 * which is all it could do before this column existed. New rows always carry
 * the snapshot.
 */

export async function up(knex) {
  await knex.schema.alterTable("purchase_items", (table) => {
    table.string("product_name", 200).nullable().after("variant_id");
    table.string("sku", 100).nullable().after("product_name");
  });

  await knex.schema.alterTable("return_items", (table) => {
    table.string("product_name", 200).nullable().after("variant_id");
    table.string("sku", 100).nullable().after("product_name");
  });
}

export async function down(knex) {
  await knex.schema.alterTable("purchase_items", (table) => {
    table.dropColumn("product_name");
    table.dropColumn("sku");
  });

  await knex.schema.alterTable("return_items", (table) => {
    table.dropColumn("product_name");
    table.dropColumn("sku");
  });
}
