/**
 * Sales, orders, order edit history and payments — §13, §14, §15, §17,
 * §43, and §61 rules 4/5/6.
 *
 * **One table for sales and orders.** §13 describes creating a sale and §14
 * says "every sale should have an order/document number" and then gives the
 * order's statuses — they are one entity seen from two angles, not two.
 * `order_type` distinguishes a walk-in quick sale from a standard order, so
 * the Sales and Orders screens filter the same table rather than two tables
 * drifting apart on tax rules and return handling. (The Flutter demo layer
 * already models it this way — `OrderType.quickSale` / `.standard`.)
 *
 * @param {import('knex').Knex} knex
 */
export async function up(knex) {
  await knex.schema.createTable("orders", (table) => {
    table.bigIncrements("id").unsigned().primary();
    table
      .bigInteger("business_id")
      .unsigned()
      .notNullable()
      .references("id")
      .inTable("businesses")
      .onDelete("RESTRICT");
    // Nullable: §18 allows anonymous/cash sales.
    table
      .bigInteger("customer_id")
      .unsigned()
      .nullable()
      .references("id")
      .inTable("customers")
      .onDelete("RESTRICT"); // a customer with order history cannot be erased

    table.string("order_number", 50).notNullable();

    table
      .enu("order_type", ["standard", "quick_sale"], {
        useNative: true,
        enumName: "order_type_enum",
      })
      .notNullable()
      .defaultTo("standard");

    // §14's exact status list.
    table
      .enu(
        "status",
        [
          "draft",
          "pending",
          "confirmed",
          "processing",
          "ready",
          "completed",
          "cancelled",
          "returned",
          "partially_returned",
        ],
        { useNative: true, enumName: "order_status_enum" }
      )
      .notNullable()
      .defaultTo("draft");

    // §13's money columns and §13's payment status.
    table.decimal("subtotal", 14, 2).notNullable().defaultTo(0);
    table.decimal("discount_amount", 14, 2).notNullable().defaultTo(0);
    table.decimal("tax_amount", 14, 2).notNullable().defaultTo(0);
    table.decimal("extra_charges", 14, 2).notNullable().defaultTo(0);
    table.decimal("grand_total", 14, 2).notNullable().defaultTo(0);
    // Stored, transaction-maintained. Same reasoning as `purchases.paid_amount`
    // — see that migration's header. "Remaining" stays derived.
    table.decimal("paid_amount", 14, 2).notNullable().defaultTo(0);

    table
      .enu("payment_status", ["paid", "partially_paid", "unpaid"], {
        useNative: true,
        enumName: "order_payment_status_enum",
      })
      .notNullable()
      .defaultTo("unpaid");

    table.text("notes").nullable();

    // The document's own date (§27's PDF prints it), separate from the row's
    // creation timestamp.
    table.timestamp("order_date").notNullable().defaultTo(knex.fn.now());
    table.timestamp("completed_at").nullable();

    // §17's cancellation record: who, when, why, and what it was before.
    table.timestamp("cancelled_at").nullable();
    table
      .bigInteger("cancelled_by")
      .unsigned()
      .nullable()
      .references("id")
      .inTable("users")
      .onDelete("SET NULL");
    table.string("cancel_reason", 500).nullable();
    table.string("status_before_cancel", 30).nullable();

    // §55's "who created it?" — the first question auditability must answer.
    table
      .bigInteger("created_by")
      .unsigned()
      .nullable()
      .references("id")
      .inTable("users")
      .onDelete("SET NULL"); // the document outlives the employee

    table.timestamp("created_at").notNullable().defaultTo(knex.fn.now());
    table.timestamp("updated_at").notNullable().defaultTo(knex.fn.now());
    // §45/§61 rule 6 — financial records are archived, never hard-deleted.
    table.timestamp("deleted_at").nullable();

    // §61 rule 12, enforced by the database rather than hoped for.
    table.unique(["business_id", "order_number"], { indexName: "uq_orders_number" });

    // §43's order table and §25's sales reports, each index earning its
    // place: the default list (status over a date range), per-customer
    // history (§18), the outstanding-payments report (§25), the
    // Sales-vs-Orders split, and §25's "sales by employee".
    table.index(["business_id", "status", "order_date"], "idx_orders_status_date");
    table.index(["business_id", "customer_id", "order_date"], "idx_orders_customer");
    table.index(["business_id", "payment_status"], "idx_orders_payment_status");
    table.index(["business_id", "order_type", "order_date"], "idx_orders_type_date");
    table.index(["business_id", "created_by"], "idx_orders_created_by");
  });

  await knex.schema.createTable("order_items", (table) => {
    table.bigIncrements("id").unsigned().primary();
    table
      .bigInteger("business_id")
      .unsigned()
      .notNullable()
      .references("id")
      .inTable("businesses")
      .onDelete("RESTRICT");
    table
      .bigInteger("order_id")
      .unsigned()
      .notNullable()
      .references("id")
      .inTable("orders")
      .onDelete("CASCADE");
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

    // Copied onto the line at the time of sale, for the same reason
    // purchase lines copy cost: §55 must answer "what prices?" about a
    // document from last year, and the product's price has moved since.
    table.string("product_name", 200).notNullable();
    table.string("sku", 100).nullable();
    table.decimal("quantity", 14, 3).notNullable();
    table.decimal("unit_price", 14, 2).notNullable();
    table.decimal("discount_amount", 14, 2).notNullable().defaultTo(0);
    table.decimal("tax_amount", 14, 2).notNullable().defaultTo(0);
    table.decimal("line_total", 14, 2).notNullable();

    table.timestamp("created_at").notNullable().defaultTo(knex.fn.now());
    table.timestamp("updated_at").notNullable().defaultTo(knex.fn.now());

    table.index(["order_id"], "idx_order_items_order");
    // §25's "sales by product" and §5's top-products chart.
    table.index(["business_id", "product_id"], "idx_order_items_product");
  });

  await knex.raw(`
    ALTER TABLE order_items
      ADD CONSTRAINT ck_order_item_quantity_positive CHECK (quantity > 0),
      ADD CONSTRAINT ck_order_item_price_not_negative CHECK (unit_price >= 0)
  `);

  await knex.raw(`
    ALTER TABLE orders
      ADD CONSTRAINT ck_order_paid_not_negative CHECK (paid_amount >= 0),
      ADD CONSTRAINT ck_order_total_not_negative CHECK (grand_total >= 0)
  `);

  // --------------------------------------------------------------------
  // order_edits — §15, which is unusually explicit: "never silently
  // overwrite important financial/order information", and then lists the
  // fields to record. One row per changed field, because that is what
  // §15's example shows ("Quantity changed: 10 → 8, by Admin User, at
  // 2026-09-16 14:20") and it is what a diff view needs.
  //
  // Append-only: no `updated_at`, no `deleted_at`, and nothing in the
  // application updates or deletes from it.
  // --------------------------------------------------------------------
  await knex.schema.createTable("order_edits", (table) => {
    table.bigIncrements("id").unsigned().primary();
    table
      .bigInteger("business_id")
      .unsigned()
      .notNullable()
      .references("id")
      .inTable("businesses")
      .onDelete("RESTRICT");
    table
      .bigInteger("order_id")
      .unsigned()
      .notNullable()
      .references("id")
      .inTable("orders")
      .onDelete("CASCADE");
    // Null when the change was to the order as a whole rather than a line.
    table
      .bigInteger("order_item_id")
      .unsigned()
      .nullable()
      .references("id")
      .inTable("order_items")
      .onDelete("SET NULL"); // the history survives the line being removed

    table.string("field_name", 100).notNullable(); // "quantity", "unit_price", "status"
    table.string("previous_value", 500).nullable();
    table.string("new_value", 500).nullable();
    table.string("reason", 500).nullable(); // §15's "reason if required"

    table
      .bigInteger("changed_by")
      .unsigned()
      .nullable()
      .references("id")
      .inTable("users")
      .onDelete("SET NULL");
    table.timestamp("created_at").notNullable().defaultTo(knex.fn.now());

    table.index(["order_id", "created_at"], "idx_order_edits_order");
    table.index(["business_id", "created_at"], "idx_order_edits_business");
  });

  // --------------------------------------------------------------------
  // payments — §13's payment methods, §25's payments/outstanding reports.
  //
  // One table for money in (against an order) and money out (against a
  // purchase), because a payment has the same shape either way and §26
  // reports on both under one "Payments" heading. Which one it belongs to
  // is enforced, not merely intended: the CHECK below makes a payment that
  // points at neither — or at both — impossible to insert.
  // --------------------------------------------------------------------
  await knex.schema.createTable("payments", (table) => {
    table.bigIncrements("id").unsigned().primary();
    table
      .bigInteger("business_id")
      .unsigned()
      .notNullable()
      .references("id")
      .inTable("businesses")
      .onDelete("RESTRICT");
    table
      .bigInteger("order_id")
      .unsigned()
      .nullable()
      .references("id")
      .inTable("orders")
      .onDelete("RESTRICT"); // a paid order cannot be erased out from under its payment
    table
      .bigInteger("purchase_id")
      .unsigned()
      .nullable()
      .references("id")
      .inTable("purchases")
      .onDelete("RESTRICT");

    table
      .enu("direction", ["incoming", "outgoing"], {
        useNative: true,
        enumName: "payment_direction_enum",
      })
      .notNullable();

    table.decimal("amount", 14, 2).notNullable();
    // §13: "payment methods should be configurable". The enum is the closed
    // set §13 names; a business's *enabled* subset is a setting in
    // `business_settings`, which is what "configurable" means here — the
    // database still refuses a method the software does not understand.
    table
      .enu("method", ["cash", "bank_transfer", "card", "other"], {
        useNative: true,
        enumName: "payment_method_enum",
      })
      .notNullable();

    table.string("reference", 100).nullable(); // cheque no., transfer id
    table.text("note").nullable();
    table.timestamp("paid_at").notNullable().defaultTo(knex.fn.now());
    table
      .bigInteger("created_by")
      .unsigned()
      .nullable()
      .references("id")
      .inTable("users")
      .onDelete("SET NULL");
    table.timestamp("created_at").notNullable().defaultTo(knex.fn.now());

    table.index(["business_id", "paid_at"], "idx_payments_date");
    table.index(["order_id"], "idx_payments_order");
    table.index(["purchase_id"], "idx_payments_purchase");
    table.index(["business_id", "method", "paid_at"], "idx_payments_method");
  });

  await knex.raw(`
    ALTER TABLE payments
      ADD CONSTRAINT ck_payment_amount_positive CHECK (amount > 0),
      ADD CONSTRAINT ck_payment_exactly_one_parent CHECK (
        (order_id IS NOT NULL AND purchase_id IS NULL)
        OR (order_id IS NULL AND purchase_id IS NOT NULL)
      )
  `);
}

/** @param {import('knex').Knex} knex */
export async function down(knex) {
  await knex.schema.dropTableIfExists("payments");
  await knex.schema.dropTableIfExists("order_edits");
  await knex.schema.dropTableIfExists("order_items");
  await knex.schema.dropTableIfExists("orders");
}
