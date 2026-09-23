/**
 * Storage locations foundation (spec §11).
 *
 * Two levels, because §11 describes two: a *place* ("Main Warehouse",
 * "Showroom", "Production Area") and a *position inside it* — §8's
 * "Shelf/rack/bin". Collapsing them into one self-referencing table would
 * make "which warehouse is this bin in" a recursive query on the hottest
 * join in the inventory module.
 *
 * Runs before the product tables so `products.default_location_id` has
 * something to reference.
 *
 * @param {import('knex').Knex} knex
 */
export async function up(knex) {
  await knex.schema.createTable("warehouses", (table) => {
    table.bigIncrements("id").unsigned().primary();
    table
      .bigInteger("business_id")
      .unsigned()
      .notNullable()
      .references("id")
      .inTable("businesses")
      .onDelete("RESTRICT"); // stock history references warehouses; never cascade-delete one

    table.string("name", 150).notNullable();
    table.string("code", 50).nullable();
    table.string("address", 255).nullable();

    // §11's examples are all *kinds* of place. Typed so a later phase can
    // treat production areas differently from a showroom without parsing
    // the name.
    table
      .enu("location_type", ["warehouse", "showroom", "production_area", "storage_room", "outdoor", "other"], {
        useNative: true,
        enumName: "warehouse_type_enum",
      })
      .notNullable()
      .defaultTo("warehouse");

    // Exactly one per business is the default target for stock with no
    // location given. Enforced as a partial-uniqueness rule in the service
    // layer (MySQL has no filtered unique index); the flag is here so the
    // rule has something to read.
    table.boolean("is_default").notNullable().defaultTo(false);

    table
      .enu("status", ["active", "inactive"], { useNative: true, enumName: "warehouse_status_enum" })
      .notNullable()
      .defaultTo("active");

    table.timestamp("created_at").notNullable().defaultTo(knex.fn.now());
    table.timestamp("updated_at").notNullable().defaultTo(knex.fn.now());
    table.timestamp("deleted_at").nullable();

    // Codes are optional, and MySQL allows many NULLs in a unique index —
    // so this enforces "no two warehouses share a code" without forcing
    // every business to invent codes.
    table.unique(["business_id", "code"], { indexName: "uq_warehouses_code" });
    table.index(["business_id", "status"], "idx_warehouses_business");
  });

  await knex.schema.createTable("storage_locations", (table) => {
    table.bigIncrements("id").unsigned().primary();
    table
      .bigInteger("business_id")
      .unsigned()
      .notNullable()
      .references("id")
      .inTable("businesses")
      .onDelete("RESTRICT");
    table
      .bigInteger("warehouse_id")
      .unsigned()
      .notNullable()
      .references("id")
      .inTable("warehouses")
      .onDelete("RESTRICT");

    // §8's "Shelf/rack/bin" — one label ("A-12-3") plus the structured
    // parts, so a report can group by aisle without string slicing.
    table.string("name", 150).notNullable();
    table.string("code", 50).nullable();
    table.string("aisle", 30).nullable();
    table.string("rack", 30).nullable();
    table.string("shelf", 30).nullable();
    table.string("bin", 30).nullable();

    table
      .enu("status", ["active", "inactive"], { useNative: true, enumName: "storage_location_status_enum" })
      .notNullable()
      .defaultTo("active");

    table.timestamp("created_at").notNullable().defaultTo(knex.fn.now());
    table.timestamp("updated_at").notNullable().defaultTo(knex.fn.now());
    table.timestamp("deleted_at").nullable();

    // Scoped to the warehouse, not the business: "A-1" may legitimately
    // exist in two different warehouses.
    table.unique(["warehouse_id", "code"], { indexName: "uq_storage_locations_code" });
    table.index(["business_id", "warehouse_id", "status"], "idx_storage_locations_warehouse");
  });
}

/** @param {import('knex').Knex} knex */
export async function down(knex) {
  await knex.schema.dropTableIfExists("storage_locations");
  await knex.schema.dropTableIfExists("warehouses");
}
