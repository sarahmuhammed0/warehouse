/**
 * businesses — the tenant entity (architecture §5, spec §3). Every
 * business-owned table from Phase 3 onward carries `business_id` FK'd
 * here. MySQL 8.x syntax throughout (native CHECK-free ENUM, utf8mb4,
 * InnoDB) — no MariaDB-specific constructs.
 *
 * @param {import('knex').Knex} knex
 */
export async function up(knex) {
  await knex.schema.createTable("businesses", (table) => {
    table.bigIncrements("id").unsigned().primary();

    table.string("name", 150).notNullable();
    table
      .enu(
        "business_type",
        [
          "furniture_factory",
          "general_factory",
          "warehouse",
          "storage_store",
          "wholesale_store",
          "distribution_center",
          "custom",
        ],
        { useNative: true, enumName: "business_type_enum" }
      )
      .notNullable();
    table.string("logo_url", 500).nullable();
    table.text("description").nullable();

    // Business contact phone — E.164, see src/utils/phone.js. This is the
    // business's own published contact number, NOT a login credential
    // (that's users.phone) — no uniqueness constraint needed here.
    table.string("phone", 20).notNullable();
    table.string("phone_secondary", 20).nullable();
    table.string("email", 255).nullable();

    table.string("address", 255).nullable();
    table.string("city", 100).nullable();
    table.string("country", 100).nullable();
    table.string("website", 255).nullable();
    table.string("tax_number", 100).nullable();
    table.string("registration_number", 100).nullable();

    table.specificType("currency", "CHAR(3)").notNullable().defaultTo("USD");
    table.string("language", 10).notNullable().defaultTo("en");
    table.string("timezone", 64).notNullable().defaultTo("UTC");

    table
      .enu("status", ["active", "disabled"], { useNative: true, enumName: "business_status_enum" })
      .notNullable()
      .defaultTo("active");

    table.timestamp("created_at").notNullable().defaultTo(knex.fn.now());
    table.timestamp("updated_at").notNullable().defaultTo(knex.fn.now());
    // Soft delete/archival (architecture §45, spec §61 rule 6) — a business
    // is never hard-deleted through the application; see docs/database.md.
    table.timestamp("deleted_at").nullable();

    table.index(["status", "deleted_at"], "idx_businesses_status");
  });
}

/** @param {import('knex').Knex} knex */
export async function down(knex) {
  await knex.schema.dropTableIfExists("businesses");
}
