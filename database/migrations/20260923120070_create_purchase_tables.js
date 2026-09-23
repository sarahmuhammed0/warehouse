/**
 * Purchases — §20, and §25's purchase reports.
 *
 * `paid_amount` is stored here, and that is a deliberate exception to this
 * schema's "derive aggregates, don't store them" rule (see the party
 * migration for the rule). §20 lists "Paid amount" and "Remaining balance"
 * as fields of a purchase, and `payment_status` is a function of them — a
 * status the database cannot derive is a status the database cannot index,
 * and §25's "outstanding payments" report filters on exactly that. So the
 * running total lives here, and §46 is what keeps it true: a payment row
 * and this column are written in the same transaction, never apart. The
 * remaining balance stays derived (`total - paid_amount`), because two
 * stored numbers that must sum to a third is one too many.
 *
 * @param {import('knex').Knex} knex
 */
export async function up(knex) {
  await knex.schema.createTable("purchases", (table) => {
    table.bigIncrements("id").unsigned().primary();
    table
      .bigInteger("business_id")
      .unsigned()
      .notNullable()
      .references("id")
      .inTable("businesses")
      .onDelete("RESTRICT");
    table
      .bigInteger("supplier_id")
      .unsigned()
      .nullable()
      .references("id")
      .inTable("suppliers")
      .onDelete("RESTRICT"); // a supplier with purchase history cannot be erased

    table.string("purchase_number", 50).notNullable();

    table
      .enu("status", ["draft", "pending", "completed", "cancelled"], {
        useNative: true,
        enumName: "purchase_status_enum",
      })
      .notNullable()
      .defaultTo("draft");

    // §11's money columns. DECIMAL, not FLOAT — see the product migration.
    table.decimal("subtotal", 14, 2).notNullable().defaultTo(0);
    table.decimal("discount_amount", 14, 2).notNullable().defaultTo(0);
    table.decimal("tax_amount", 14, 2).notNullable().defaultTo(0);
    table.decimal("extra_charges", 14, 2).notNullable().defaultTo(0);
    table.decimal("total", 14, 2).notNullable().defaultTo(0);
    table.decimal("paid_amount", 14, 2).notNullable().defaultTo(0);

    table
      .enu("payment_status", ["paid", "partially_paid", "unpaid"], {
        useNative: true,
        enumName: "purchase_payment_status_enum",
      })
      .notNullable()
      .defaultTo("unpaid");

    table.text("note").nullable();
    // The document's own date (§20), distinct from when the row was typed in.
    table.timestamp("purchase_date").notNullable().defaultTo(knex.fn.now());
    table.timestamp("completed_at").nullable();
    table
      .bigInteger("created_by")
      .unsigned()
      .nullable()
      .references("id")
      .inTable("users")
      .onDelete("SET NULL");

    table.timestamp("created_at").notNullable().defaultTo(knex.fn.now());
    table.timestamp("updated_at").notNullable().defaultTo(knex.fn.now());
    // §45: a purchase is a financial record. Archived, never hard-deleted.
    table.timestamp("deleted_at").nullable();

    table.unique(["business_id", "purchase_number"], { indexName: "uq_purchases_number" });
    // §25's "purchases by date" and "purchases by supplier".
    table.index(["business_id", "purchase_date"], "idx_purchases_date");
    table.index(["business_id", "supplier_id", "purchase_date"], "idx_purchases_supplier");
    table.index(["business_id", "status"], "idx_purchases_status");
    // §25's outstanding-payments report, and the supplier balance §19 shows.
    table.index(["business_id", "payment_status"], "idx_purchases_payment_status");
  });

  await knex.schema.createTable("purchase_items", (table) => {
    table.bigIncrements("id").unsigned().primary();
    table
      .bigInteger("business_id")
      .unsigned()
      .notNullable()
      .references("id")
      .inTable("businesses")
      .onDelete("RESTRICT");
    table
      .bigInteger("purchase_id")
      .unsigned()
      .notNullable()
      .references("id")
      .inTable("purchases")
      .onDelete("CASCADE"); // a line cannot outlive its document
    table
      .bigInteger("product_id")
      .unsigned()
      .notNullable()
      .references("id")
      .inTable("products")
      .onDelete("RESTRICT"); // a product that has been purchased cannot be erased
    table
      .bigInteger("variant_id")
      .unsigned()
      .nullable()
      .references("id")
      .inTable("product_variants")
      .onDelete("RESTRICT");

    table.decimal("quantity", 14, 3).notNullable();
    // The cost AT THE TIME of purchase, copied onto the line rather than
    // read from the product. §55 requires a historical document to answer
    // "what prices?" — and it must keep answering the same way after
    // someone edits the product's cost next month.
    table.decimal("unit_cost", 14, 2).notNullable();
    table.decimal("discount_amount", 14, 2).notNullable().defaultTo(0);
    table.decimal("tax_amount", 14, 2).notNullable().defaultTo(0);
    table.decimal("line_total", 14, 2).notNullable();

    table.timestamp("created_at").notNullable().defaultTo(knex.fn.now());
    table.timestamp("updated_at").notNullable().defaultTo(knex.fn.now());

    table.index(["purchase_id"], "idx_purchase_items_purchase");
    // §25's "purchase costs" per product.
    table.index(["business_id", "product_id"], "idx_purchase_items_product");
  });

  // §54: quantities cannot be negative, prices cannot be invalid.
  await knex.raw(`
    ALTER TABLE purchase_items
      ADD CONSTRAINT ck_purchase_item_quantity_positive CHECK (quantity > 0),
      ADD CONSTRAINT ck_purchase_item_cost_not_negative CHECK (unit_cost >= 0)
  `);

  await knex.raw(`
    ALTER TABLE purchases
      ADD CONSTRAINT ck_purchase_paid_not_negative CHECK (paid_amount >= 0),
      ADD CONSTRAINT ck_purchase_total_not_negative CHECK (total >= 0)
  `);
}

/** @param {import('knex').Knex} knex */
export async function down(knex) {
  await knex.schema.dropTableIfExists("purchase_items");
  await knex.schema.dropTableIfExists("purchases");
}
