/**
 * Returns — §16, and §61 rule 3 ("returns must correctly affect inventory").
 *
 * §16 allows returning a whole order, selected products, or a partial
 * quantity — so a return is its own document with its own lines, not a flag
 * on the order. `return_items.order_item_id` ties each returned line back to
 * the exact line it came from, which is what makes "how much of this line is
 * still returnable" answerable without guessing between two lines of the
 * same product at different prices.
 *
 * `condition` is what §61 rule 3 turns on: a sellable return goes back into
 * `inventory`, a damaged one is recorded as a movement but does not restore
 * sellable stock. The column exists so that rule has an input; the rule
 * itself is the returns phase's work.
 *
 * @param {import('knex').Knex} knex
 */
export async function up(knex) {
  await knex.schema.createTable("returns", (table) => {
    table.bigIncrements("id").unsigned().primary();
    table
      .bigInteger("business_id")
      .unsigned()
      .notNullable()
      .references("id")
      .inTable("businesses")
      .onDelete("RESTRICT");
    // §16's "original order" — required: a return always has one.
    table
      .bigInteger("order_id")
      .unsigned()
      .notNullable()
      .references("id")
      .inTable("orders")
      .onDelete("RESTRICT"); // the order a return refers to cannot be erased
    // Denormalised from the order for the same reason §16 lists it
    // separately: a return report groups by customer, and the order may be
    // an anonymous cash sale with no customer at all.
    table
      .bigInteger("customer_id")
      .unsigned()
      .nullable()
      .references("id")
      .inTable("customers")
      .onDelete("RESTRICT");

    table.string("return_number", 50).notNullable();

    // §16's exact status list.
    table
      .enu("status", ["requested", "approved", "rejected", "completed"], {
        useNative: true,
        enumName: "return_status_enum",
      })
      .notNullable()
      .defaultTo("requested");

    table.string("reason", 500).nullable(); // §16's "return reason"
    table.decimal("refund_amount", 14, 2).notNullable().defaultTo(0);
    table.text("note").nullable();

    table.timestamp("return_date").notNullable().defaultTo(knex.fn.now());
    table.timestamp("completed_at").nullable();
    table
      .bigInteger("created_by")
      .unsigned()
      .nullable()
      .references("id")
      .inTable("users")
      .onDelete("SET NULL");
    // §24 lists Approve as its own permission, so who approved is a
    // separate fact from who raised it.
    table
      .bigInteger("approved_by")
      .unsigned()
      .nullable()
      .references("id")
      .inTable("users")
      .onDelete("SET NULL");

    table.timestamp("created_at").notNullable().defaultTo(knex.fn.now());
    table.timestamp("updated_at").notNullable().defaultTo(knex.fn.now());
    table.timestamp("deleted_at").nullable();

    table.unique(["business_id", "return_number"], { indexName: "uq_returns_number" });
    // §25's return history and return amounts, over a date range.
    table.index(["business_id", "status", "return_date"], "idx_returns_status_date");
    table.index(["order_id"], "idx_returns_order");
    table.index(["business_id", "customer_id"], "idx_returns_customer");
  });

  await knex.schema.createTable("return_items", (table) => {
    table.bigIncrements("id").unsigned().primary();
    table
      .bigInteger("business_id")
      .unsigned()
      .notNullable()
      .references("id")
      .inTable("businesses")
      .onDelete("RESTRICT");
    table
      .bigInteger("return_id")
      .unsigned()
      .notNullable()
      .references("id")
      .inTable("returns")
      .onDelete("CASCADE");
    // Which line of the original order this is a return of. RESTRICT
    // because the returned quantity of a line is computed by summing these
    // rows — losing them would silently make the line returnable twice.
    table
      .bigInteger("order_item_id")
      .unsigned()
      .notNullable()
      .references("id")
      .inTable("order_items")
      .onDelete("RESTRICT");
    table
      .bigInteger("product_id")
      .unsigned()
      .notNullable()
      .references("id")
      .inTable("products")
      .onDelete("RESTRICT");
    table
      .bigInteger("variant_id")
      .unsigned()
      .nullable()
      .references("id")
      .inTable("product_variants")
      .onDelete("RESTRICT");

    table.decimal("quantity", 14, 3).notNullable();
    // §16's "condition" — the input to §61 rule 3.
    table
      .enu("item_condition", ["sellable", "damaged"], {
        useNative: true,
        enumName: "return_item_condition_enum",
      })
      .notNullable()
      .defaultTo("sellable");
    table.decimal("refund_amount", 14, 2).notNullable().defaultTo(0);

    table.timestamp("created_at").notNullable().defaultTo(knex.fn.now());
    table.timestamp("updated_at").notNullable().defaultTo(knex.fn.now());

    table.index(["return_id"], "idx_return_items_return");
    // "how much of this order line has come back" — the returnable-quantity
    // check, and §25's returned-products report.
    table.index(["order_item_id"], "idx_return_items_order_item");
    table.index(["business_id", "product_id"], "idx_return_items_product");
  });

  await knex.raw(`
    ALTER TABLE return_items
      ADD CONSTRAINT ck_return_item_quantity_positive CHECK (quantity > 0),
      ADD CONSTRAINT ck_return_item_refund_not_negative CHECK (refund_amount >= 0)
  `);
}

/** @param {import('knex').Knex} knex */
export async function down(knex) {
  await knex.schema.dropTableIfExists("return_items");
  await knex.schema.dropTableIfExists("returns");
}
