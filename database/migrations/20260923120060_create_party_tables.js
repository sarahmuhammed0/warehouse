/**
 * Customers and suppliers — §18, §19, §32 (search by name/phone).
 *
 * **What is deliberately absent.** §18 lists "Total purchases" and
 * "Outstanding balance" among a customer's fields, and §19 the same for a
 * supplier. Neither is a column here. Both are sums over `orders` /
 * `purchases` / `payments`, and a stored copy is a second source of truth
 * that goes wrong the first time an order is edited, cancelled or returned
 * — exactly the drift §61 rules 4 and 5 exist to prevent. They are computed
 * on read, from indexes designed for it (see the order/purchase
 * migrations). If a later phase measures that this is too slow at scale,
 * the fix is a maintained projection with its own invalidation rule, not a
 * column nobody can prove is current. Recorded in docs/backend-phase3.md
 * "Derived vs. stored".
 *
 * `order_history` / `purchase_history` (also listed in §18/§19) are
 * likewise relationships, not columns: they are the rows in `orders` /
 * `purchases` that reference this party.
 *
 * @param {import('knex').Knex} knex
 */
export async function up(knex) {
  await knex.schema.createTable("customers", (table) => {
    table.bigIncrements("id").unsigned().primary();
    table
      .bigInteger("business_id")
      .unsigned()
      .notNullable()
      .references("id")
      .inTable("businesses")
      .onDelete("RESTRICT"); // orders reference customers; a business with sales history is archived, not deleted

    table.string("name", 200).notNullable();
    table.string("code", 50).nullable();
    table.string("phone", 20).nullable();
    table.string("phone_secondary", 20).nullable();
    table.string("email", 255).nullable();
    table.string("address", 255).nullable();
    table.string("company", 200).nullable();
    table.text("notes").nullable();

    table
      .enu("status", ["active", "inactive"], { useNative: true, enumName: "customer_status_enum" })
      .notNullable()
      .defaultTo("active");

    table.timestamp("created_at").notNullable().defaultTo(knex.fn.now());
    table.timestamp("updated_at").notNullable().defaultTo(knex.fn.now());
    table.timestamp("deleted_at").nullable();

    // Per tenant (§36). Phone is NOT unique: §18 allows anonymous/cash
    // sales and a household may share a number, so forcing uniqueness here
    // would block legitimate records. The customer *code*, when a business
    // chooses to use one, is the identifier that must not repeat.
    table.unique(["business_id", "code"], { indexName: "uq_customers_code" });

    // §32's "search customers by name, phone".
    table.index(["business_id", "phone"], "idx_customers_phone");
    table.index(["business_id", "name"], "idx_customers_name");
    table.index(["business_id", "status", "deleted_at"], "idx_customers_status");
  });

  await knex.schema.createTable("suppliers", (table) => {
    table.bigIncrements("id").unsigned().primary();
    table
      .bigInteger("business_id")
      .unsigned()
      .notNullable()
      .references("id")
      .inTable("businesses")
      .onDelete("RESTRICT");

    table.string("name", 200).notNullable();
    table.string("code", 50).nullable();
    table.string("company", 200).nullable();
    table.string("contact_person", 150).nullable();
    table.string("phone", 20).nullable();
    table.string("phone_secondary", 20).nullable();
    table.string("email", 255).nullable();
    table.string("address", 255).nullable();
    table.text("notes").nullable();

    table
      .enu("status", ["active", "inactive"], { useNative: true, enumName: "supplier_status_enum" })
      .notNullable()
      .defaultTo("active");

    table.timestamp("created_at").notNullable().defaultTo(knex.fn.now());
    table.timestamp("updated_at").notNullable().defaultTo(knex.fn.now());
    table.timestamp("deleted_at").nullable();

    table.unique(["business_id", "code"], { indexName: "uq_suppliers_code" });

    // §32's "search suppliers by name, phone".
    table.index(["business_id", "phone"], "idx_suppliers_phone");
    table.index(["business_id", "name"], "idx_suppliers_name");
    table.index(["business_id", "status", "deleted_at"], "idx_suppliers_status");
  });

  // §19's "products supplied" — a many-to-many, because one product can
  // have several suppliers and one supplier several products. The supplier's
  // own code and cost for that product live on the link, which is what a
  // purchase form needs to prefill.
  await knex.schema.createTable("supplier_products", (table) => {
    table
      .bigInteger("supplier_id")
      .unsigned()
      .notNullable()
      .references("id")
      .inTable("suppliers")
      .onDelete("CASCADE");
    table
      .bigInteger("product_id")
      .unsigned()
      .notNullable()
      .references("id")
      .inTable("products")
      .onDelete("CASCADE");
    table
      .bigInteger("business_id")
      .unsigned()
      .notNullable()
      .references("id")
      .inTable("businesses")
      .onDelete("RESTRICT");

    table.string("supplier_sku", 100).nullable();
    table.decimal("last_purchase_cost", 14, 2).nullable();

    table.timestamp("created_at").notNullable().defaultTo(knex.fn.now());
    table.timestamp("updated_at").notNullable().defaultTo(knex.fn.now());

    table.primary(["supplier_id", "product_id"], { constraintName: "pk_supplier_products" });
    table.index(["business_id", "product_id"], "idx_supplier_products_product");
  });
}

/** @param {import('knex').Knex} knex */
export async function down(knex) {
  await knex.schema.dropTableIfExists("supplier_products");
  await knex.schema.dropTableIfExists("suppliers");
  await knex.schema.dropTableIfExists("customers");
}
