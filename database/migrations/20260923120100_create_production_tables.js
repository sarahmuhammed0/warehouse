/**
 * Production — §21 (the module), §22 (production history).
 *
 * **Raw materials are products.** §21 lists raw materials with their own
 * name, SKU, quantity, unit, cost, supplier and minimum stock — which is
 * the product table, field for field. So a material is a row in `products`,
 * not a parallel `raw_materials` table. That is not a shortcut: it is what
 * makes §21's "raw materials decrease, finished goods increase" a single
 * kind of stock movement instead of two systems that have to agree, and it
 * means a material can be purchased (§20), counted (§10), transferred
 * (§11) and reported on (§25) with no special cases anywhere.
 *
 * What distinguishes a material from a finished good is its role in a bill
 * of materials, not its type — and a business can legitimately both sell a
 * component and consume it, which a type column would make awkward.
 *
 * @param {import('knex').Knex} knex
 */
export async function up(knex) {
  // --------------------------------------------------------------------
  // bill_of_materials — §21's recipe: what one unit of a product requires.
  // A self-join on products (finished good → material).
  // --------------------------------------------------------------------
  await knex.schema.createTable("bill_of_materials", (table) => {
    table.bigIncrements("id").unsigned().primary();
    table
      .bigInteger("business_id")
      .unsigned()
      .notNullable()
      .references("id")
      .inTable("businesses")
      .onDelete("RESTRICT");
    table
      .bigInteger("product_id")
      .unsigned()
      .notNullable()
      .references("id")
      .inTable("products")
      .onDelete("CASCADE"); // the recipe belongs to the finished product
    table
      .bigInteger("material_product_id")
      .unsigned()
      .notNullable()
      .references("id")
      .inTable("products")
      .onDelete("RESTRICT"); // a material used in a recipe cannot be erased
    table
      .bigInteger("unit_id")
      .unsigned()
      .nullable()
      .references("id")
      .inTable("units")
      .onDelete("RESTRICT");

    // §21's example: one table needs 5 pieces of wood, 20 screws, 1 litre
    // of paint, 4 metal legs. Per ONE unit produced.
    table.decimal("quantity_per_unit", 14, 3).notNullable();
    table.text("note").nullable();

    table.timestamp("created_at").notNullable().defaultTo(knex.fn.now());
    table.timestamp("updated_at").notNullable().defaultTo(knex.fn.now());
    table.timestamp("deleted_at").nullable();

    // A material appears at most once in a product's recipe — two rows for
    // the same material would make "how much wood" ambiguous.
    table.unique(["product_id", "material_product_id"], { indexName: "uq_bom_product_material" });
    table.index(["business_id", "product_id"], "idx_bom_product");
    // "which recipes use this material" — needed before a material can be
    // archived, and for a where-used report.
    table.index(["business_id", "material_product_id"], "idx_bom_material");
  });

  // A product cannot be its own ingredient. MySQL 8 evaluates this CHECK on
  // every insert/update, so the simplest cycle is impossible outright;
  // longer cycles (A needs B, B needs A) are a graph property no single-row
  // constraint can see, and are the production service's job to reject.
  await knex.raw(`
    ALTER TABLE bill_of_materials
      ADD CONSTRAINT ck_bom_not_self_referencing CHECK (product_id <> material_product_id),
      ADD CONSTRAINT ck_bom_quantity_positive CHECK (quantity_per_unit > 0)
  `);

  // --------------------------------------------------------------------
  // production_orders — §22's production history, field for field.
  // --------------------------------------------------------------------
  await knex.schema.createTable("production_orders", (table) => {
    table.bigIncrements("id").unsigned().primary();
    table
      .bigInteger("business_id")
      .unsigned()
      .notNullable()
      .references("id")
      .inTable("businesses")
      .onDelete("RESTRICT");
    table
      .bigInteger("product_id")
      .unsigned()
      .notNullable()
      .references("id")
      .inTable("products")
      .onDelete("RESTRICT"); // the finished good
    table
      .bigInteger("variant_id")
      .unsigned()
      .nullable()
      .references("id")
      .inTable("product_variants")
      .onDelete("RESTRICT");
    table
      .bigInteger("warehouse_id")
      .unsigned()
      .nullable()
      .references("id")
      .inTable("warehouses")
      .onDelete("RESTRICT"); // where the finished goods land

    table.string("production_number", 50).notNullable();
    table.string("batch_number", 100).nullable(); // §21's "production batch"

    table.decimal("quantity_planned", 14, 3).notNullable();
    // Separate from planned, because §22 tracks a run that produced fewer
    // than intended, and §21's "quantity produced" is what increases stock.
    table.decimal("quantity_produced", 14, 3).notNullable().defaultTo(0);
    table.decimal("production_cost", 14, 2).nullable(); // §21/§22

    // §22's exact status list.
    table
      .enu("status", ["planned", "in_progress", "completed", "cancelled"], {
        useNative: true,
        enumName: "production_status_enum",
      })
      .notNullable()
      .defaultTo("planned");

    // §22's employee/team, start time, completion time.
    table
      .bigInteger("assigned_user_id")
      .unsigned()
      .nullable()
      .references("id")
      .inTable("users")
      .onDelete("SET NULL");
    table.date("production_date").nullable();
    table.timestamp("started_at").nullable();
    table.timestamp("completed_at").nullable();
    table.text("note").nullable();

    table
      .bigInteger("created_by")
      .unsigned()
      .nullable()
      .references("id")
      .inTable("users")
      .onDelete("SET NULL");

    table.timestamp("created_at").notNullable().defaultTo(knex.fn.now());
    table.timestamp("updated_at").notNullable().defaultTo(knex.fn.now());
    table.timestamp("deleted_at").nullable();

    table.unique(["business_id", "production_number"], { indexName: "uq_production_number" });
    table.index(["business_id", "status", "production_date"], "idx_production_status_date");
    table.index(["business_id", "product_id"], "idx_production_product");
  });

  await knex.raw(`
    ALTER TABLE production_orders
      ADD CONSTRAINT ck_production_planned_positive CHECK (quantity_planned > 0),
      ADD CONSTRAINT ck_production_produced_not_negative CHECK (quantity_produced >= 0)
  `);

  // --------------------------------------------------------------------
  // production_items — §22's "materials used".
  //
  // A snapshot of the recipe as it was applied to THIS run, not a live view
  // of `bill_of_materials`: the recipe can be edited afterwards, and §55's
  // auditability means a completed run must keep reporting the quantities
  // and costs it actually consumed. `quantity_required` is what the recipe
  // asked for; `quantity_consumed` is what was really taken.
  // --------------------------------------------------------------------
  await knex.schema.createTable("production_items", (table) => {
    table.bigIncrements("id").unsigned().primary();
    table
      .bigInteger("business_id")
      .unsigned()
      .notNullable()
      .references("id")
      .inTable("businesses")
      .onDelete("RESTRICT");
    table
      .bigInteger("production_order_id")
      .unsigned()
      .notNullable()
      .references("id")
      .inTable("production_orders")
      .onDelete("CASCADE");
    table
      .bigInteger("material_product_id")
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

    table.decimal("quantity_required", 14, 3).notNullable();
    table.decimal("quantity_consumed", 14, 3).notNullable().defaultTo(0);
    // Cost at the time of consumption — see the purchase/order line
    // migrations for why prices are copied onto documents.
    table.decimal("unit_cost", 14, 2).nullable();

    table.timestamp("created_at").notNullable().defaultTo(knex.fn.now());
    table.timestamp("updated_at").notNullable().defaultTo(knex.fn.now());

    table.unique(["production_order_id", "material_product_id", "variant_id"], {
      indexName: "uq_production_items_material",
    });
    table.index(["business_id", "material_product_id"], "idx_production_items_material");
  });

  await knex.raw(`
    ALTER TABLE production_items
      ADD CONSTRAINT ck_production_item_required_positive CHECK (quantity_required > 0),
      ADD CONSTRAINT ck_production_item_consumed_not_negative CHECK (quantity_consumed >= 0)
  `);
}

/** @param {import('knex').Knex} knex */
export async function down(knex) {
  await knex.schema.dropTableIfExists("production_items");
  await knex.schema.dropTableIfExists("production_orders");
  await knex.schema.dropTableIfExists("bill_of_materials");
}
