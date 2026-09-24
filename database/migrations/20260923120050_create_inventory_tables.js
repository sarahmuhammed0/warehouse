/**
 * Inventory foundation — §10 (inventory management), §11 (transfers),
 * §12 (stock movements), §44 (alerts), §47 (stock validation).
 *
 * Two tables carry the two different things §10 and §12 ask for, and the
 * distinction is the heart of this module:
 *
 *   `inventory`           — current state. One row per
 *                           (product, variant, warehouse, location). The
 *                           authoritative "how much is there right now".
 *   `inventory_movements` — the ledger. Append-only history of every change,
 *                           with the before/after quantities §12 requires.
 *
 * State is stored, not recomputed from the ledger on every read: §59 has to
 * serve a stock list for 10,000+ products, and summing a movement history
 * of millions of rows to answer "how many chairs" is exactly the query that
 * does not scale. The two are kept honest by §46 — a movement row and the
 * matching `inventory` update are written in one transaction, never
 * separately. §12's "records should never silently disappear" is why the
 * ledger has no `deleted_at` and nothing in the application deletes from it.
 *
 * @param {import('knex').Knex} knex
 */
export async function up(knex) {
  await knex.schema.createTable("inventory", (table) => {
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
      .onDelete("RESTRICT");
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
      .notNullable()
      .references("id")
      .inTable("warehouses")
      .onDelete("RESTRICT");
    table
      .bigInteger("location_id")
      .unsigned()
      .nullable()
      .references("id")
      .inTable("storage_locations")
      .onDelete("RESTRICT");

    // §10's tracked quantities. `quantity` is what is physically present;
    // `reserved_quantity` is how much of it is already promised to open
    // orders. §8's "available quantity" is the difference and is therefore
    // derived, not stored.
    table.decimal("quantity", 14, 3).notNullable().defaultTo(0);
    table.decimal("reserved_quantity", 14, 3).notNullable().defaultTo(0);

    table.timestamp("created_at").notNullable().defaultTo(knex.fn.now());
    table.timestamp("updated_at").notNullable().defaultTo(knex.fn.now());

    // §11/§44's lookups: stock for one product across locations, and the
    // whole of one warehouse.
    table.index(["business_id", "product_id"], "idx_inventory_product");
    table.index(["business_id", "warehouse_id", "location_id"], "idx_inventory_location");
  });

  // The uniqueness rule for `inventory` is "one row per physical slot", and
  // two of the four columns that define a slot are nullable. MySQL treats
  // every NULL as distinct inside a UNIQUE index, so the obvious
  // UNIQUE(product_id, variant_id, warehouse_id, location_id) would happily
  // accept the same (product, warehouse) pair a hundred times as long as
  // variant_id and location_id were NULL — which is precisely the duplicate
  // that makes a stock figure ambiguous.
  //
  // Generated columns give the index a NOT NULL value to work with: 0 is
  // impossible as a real id (both parents are AUTO_INCREMENT from 1), so
  // COALESCE(...,0) collapses "no variant" to one distinct value instead of
  // infinitely many. Raw SQL because Knex's builder has no generated-column
  // API.
  await knex.raw(`
    ALTER TABLE inventory
      ADD COLUMN variant_key BIGINT UNSIGNED
        AS (COALESCE(variant_id, 0)) STORED,
      ADD COLUMN location_key BIGINT UNSIGNED
        AS (COALESCE(location_id, 0)) STORED,
      ADD UNIQUE KEY uq_inventory_slot (product_id, variant_key, warehouse_id, location_key)
  `);

  // §54 forbids negative quantities; §47 permits negative *inventory*, but
  // "only through an explicit business setting". Those two only reconcile if
  // the level and the constraint are separated:
  //
  //   reserved_quantity  — CHECK >= 0 here. Reserving a negative amount is
  //                        meaningless under any business setting.
  //   quantity           — deliberately NOT constrained in the database.
  //                        A CHECK (quantity >= 0) would make §47's setting
  //                        impossible to honour: no service code could ever
  //                        write the negative level the business enabled.
  //                        The non-negative rule is therefore enforced in
  //                        the stock service, which is the only layer that
  //                        can read `inventory.allow_negative_stock` and
  //                        decide. It refuses by default.
  await knex.raw(`
    ALTER TABLE inventory
      ADD CONSTRAINT ck_inventory_reserved_not_negative CHECK (reserved_quantity >= 0)
  `);

  await knex.schema.createTable("inventory_movements", (table) => {
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
      .onDelete("RESTRICT");
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
      .onDelete("RESTRICT");
    table
      .bigInteger("location_id")
      .unsigned()
      .nullable()
      .references("id")
      .inTable("storage_locations")
      .onDelete("RESTRICT");

    // §12's exact list of movement types.
    table
      .enu(
        "movement_type",
        [
          "purchase",
          "sale",
          "return",
          "damage",
          "adjustment",
          "transfer",
          "production",
          "manual_increase",
          "manual_decrease",
        ],
        { useNative: true, enumName: "inventory_movement_type_enum" }
      )
      .notNullable();

    // Signed: negative removes stock. §12 wants quantity plus the before
    // and after, so a row is self-contained evidence — a reader never has
    // to replay the whole ledger to know what the stock was at the time.
    table.decimal("quantity", 14, 3).notNullable();
    table.decimal("quantity_before", 14, 3).notNullable();
    table.decimal("quantity_after", 14, 3).notNullable();

    // §12's "reference order" / reference number. Not a foreign key,
    // because the referent is an order, a purchase, a return, a transfer or
    // a production run depending on `movement_type` — SQL has no
    // polymorphic FK. `reference_type` names the table so the join is
    // unambiguous, and `reference_number` keeps the human-readable document
    // number even if the referenced row is later archived.
    table.string("reference_type", 50).nullable();
    table.bigInteger("reference_id").unsigned().nullable();
    table.string("reference_number", 50).nullable();

    table.string("reason", 255).nullable();
    table.text("note").nullable();

    // §10 requires the user on every record. Nullable only for movements
    // the system makes on its own behalf (a migration, a scheduled job).
    table
      .bigInteger("user_id")
      .unsigned()
      .nullable()
      .references("id")
      .inTable("users")
      .onDelete("SET NULL"); // history outlives the employee who made it

    // The business event's own time, separate from the row's creation
    // time — §13's requirement that a document carry its own date, and
    // what a back-dated stock correction needs.
    table.timestamp("moved_at").notNullable().defaultTo(knex.fn.now());
    table.timestamp("created_at").notNullable().defaultTo(knex.fn.now());

    // §25's stock-movement report: one product's history, newest first.
    table.index(["business_id", "product_id", "moved_at"], "idx_movements_product");
    // §26's operational report, filtered by type over a date range.
    table.index(["business_id", "movement_type", "moved_at"], "idx_movements_type");
    // "what did this order do to stock" — the audit trail from a document.
    table.index(["reference_type", "reference_id"], "idx_movements_reference");
  });

  // §54: "Prevent invalid: Negative quantities". A movement's quantity is a
  // magnitude — §12's `movement_type` already carries the direction
  // (purchase/return/manual_increase add; sale/damage/manual_decrease
  // subtract), and `quantity_before`/`quantity_after` record the effect.
  // Allowing a negative magnitude would let the same movement be expressed
  // two ways, which makes the ledger impossible to sum reliably. Zero is
  // refused too: a movement that changes nothing is not a movement.
  //
  // `quantity_before`/`quantity_after` are deliberately unconstrained —
  // they are observations of the level, which §47 allows to be negative
  // when the business has enabled it.
  await knex.raw(`
    ALTER TABLE inventory_movements
      ADD CONSTRAINT ck_movement_quantity_positive CHECK (quantity > 0)
  `);

  // --------------------------------------------------------------------
  // stock_transfers / stock_transfer_items — §11's location-to-location
  // transfer, with the status and notes §11 asks for.
  // --------------------------------------------------------------------
  await knex.schema.createTable("stock_transfers", (table) => {
    table.bigIncrements("id").unsigned().primary();
    table
      .bigInteger("business_id")
      .unsigned()
      .notNullable()
      .references("id")
      .inTable("businesses")
      .onDelete("RESTRICT");

    table.string("transfer_number", 50).notNullable();

    table
      .bigInteger("from_warehouse_id")
      .unsigned()
      .notNullable()
      .references("id")
      .inTable("warehouses")
      .onDelete("RESTRICT");
    table
      .bigInteger("from_location_id")
      .unsigned()
      .nullable()
      .references("id")
      .inTable("storage_locations")
      .onDelete("RESTRICT");
    table
      .bigInteger("to_warehouse_id")
      .unsigned()
      .notNullable()
      .references("id")
      .inTable("warehouses")
      .onDelete("RESTRICT");
    table
      .bigInteger("to_location_id")
      .unsigned()
      .nullable()
      .references("id")
      .inTable("storage_locations")
      .onDelete("RESTRICT");

    table
      .enu("status", ["draft", "pending", "in_transit", "completed", "cancelled"], {
        useNative: true,
        enumName: "stock_transfer_status_enum",
      })
      .notNullable()
      .defaultTo("draft");

    table.text("note").nullable();
    table.timestamp("transfer_date").notNullable().defaultTo(knex.fn.now());
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
    table.timestamp("deleted_at").nullable();

    // §61 rule 12 — document numbers are unique, per tenant.
    table.unique(["business_id", "transfer_number"], { indexName: "uq_stock_transfers_number" });
    table.index(["business_id", "status", "transfer_date"], "idx_stock_transfers_status");
  });

  await knex.schema.createTable("stock_transfer_items", (table) => {
    table.bigIncrements("id").unsigned().primary();
    table
      .bigInteger("business_id")
      .unsigned()
      .notNullable()
      .references("id")
      .inTable("businesses")
      .onDelete("RESTRICT");
    table
      .bigInteger("transfer_id")
      .unsigned()
      .notNullable()
      .references("id")
      .inTable("stock_transfers")
      .onDelete("CASCADE"); // a line has no meaning without its transfer
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

    table.timestamp("created_at").notNullable().defaultTo(knex.fn.now());

    table.index(["transfer_id"], "idx_stock_transfer_items_transfer");
  });

  await knex.raw(`
    ALTER TABLE stock_transfer_items
      ADD CONSTRAINT ck_transfer_item_quantity_positive CHECK (quantity > 0)
  `);
}

/** @param {import('knex').Knex} knex */
export async function down(knex) {
  await knex.schema.dropTableIfExists("stock_transfer_items");
  await knex.schema.dropTableIfExists("stock_transfers");
  await knex.schema.dropTableIfExists("inventory_movements");
  // The generated columns, unique key and CHECK go with the table.
  await knex.schema.dropTableIfExists("inventory");
}
