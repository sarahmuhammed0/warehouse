/**
 * Master data foundation — §7 (categories), §8 (products), §9 (variants),
 * §33 (barcodes), §42 (the product table's columns).
 *
 * **Where stock quantity lives, and why it is not here.** §8 lists "Current
 * quantity" among a product's inventory information, and it would be easy
 * to put an integer on `products`. This schema does not, because §11 lets
 * the same product sit in several locations at once: a single number on the
 * product could only ever be a total, and a total stored beside the
 * per-location rows it summarises is a second source of truth that drifts.
 * Quantity therefore lives in `inventory`, one row per
 * (product, variant, warehouse, location); a product's "current quantity"
 * is a SUM over those rows. §61 rule 1 is satisfied by updating the
 * inventory row inside the sale's transaction. See docs/backend-phase3.md
 * "Derived vs. stored".
 *
 * @param {import('knex').Knex} knex
 */
export async function up(knex) {
  // --------------------------------------------------------------------
  // units — §8's unit of measurement, §34's "Units" setting.
  // Business-owned because §34 puts units under a business's own Inventory
  // Settings: one business counts in "Sheet", another in "Set".
  // --------------------------------------------------------------------
  await knex.schema.createTable("units", (table) => {
    table.bigIncrements("id").unsigned().primary();
    table
      .bigInteger("business_id")
      .unsigned()
      .notNullable()
      .references("id")
      .inTable("businesses")
      .onDelete("RESTRICT");

    table.string("name", 50).notNullable(); // "Kilogram"
    table.string("code", 20).notNullable(); // "kg"
    // Whether quantities may be fractional. "Piece" cannot be 2.5; "Metre"
    // can. §54 must reject an invalid quantity, and this is what tells it
    // which quantities are invalid for a given product.
    table.integer("decimal_places").unsigned().notNullable().defaultTo(0);

    table.timestamp("created_at").notNullable().defaultTo(knex.fn.now());
    table.timestamp("updated_at").notNullable().defaultTo(knex.fn.now());
    table.timestamp("deleted_at").nullable();

    table.unique(["business_id", "code"], { indexName: "uq_units_code" });
  });

  // --------------------------------------------------------------------
  // categories — §7, including its parent/subcategory structure.
  // --------------------------------------------------------------------
  await knex.schema.createTable("categories", (table) => {
    table.bigIncrements("id").unsigned().primary();
    table
      .bigInteger("business_id")
      .unsigned()
      .notNullable()
      .references("id")
      .inTable("businesses")
      .onDelete("RESTRICT");
    // Self-referencing, for §7's parent/subcategory structure. RESTRICT so
    // a parent with children cannot vanish and orphan them.
    table
      .bigInteger("parent_id")
      .unsigned()
      .nullable()
      .references("id")
      .inTable("categories")
      .onDelete("RESTRICT");

    table.string("name", 150).notNullable();
    table.string("code", 50).nullable();
    table.string("image_url", 500).nullable();
    table.text("description").nullable();
    table.integer("sort_order").notNullable().defaultTo(0);

    table
      .enu("status", ["active", "inactive"], { useNative: true, enumName: "category_status_enum" })
      .notNullable()
      .defaultTo("active");

    table.timestamp("created_at").notNullable().defaultTo(knex.fn.now());
    table.timestamp("updated_at").notNullable().defaultTo(knex.fn.now());
    table.timestamp("deleted_at").nullable();

    table.unique(["business_id", "code"], { indexName: "uq_categories_code" });
    table.index(["business_id", "parent_id", "sort_order"], "idx_categories_tree");
    table.index(["business_id", "status"], "idx_categories_status");
  });

  // --------------------------------------------------------------------
  // products — §8 and §42.
  //
  // Money is DECIMAL(14,2), never FLOAT: §61 makes financial records
  // authoritative, and binary floating point cannot represent 0.10
  // exactly, so a column of FLOAT totals does not add up to the invoice.
  // Quantities are DECIMAL(14,3) so a unit with decimal places (metres,
  // kilograms) is representable without switching types per product.
  // --------------------------------------------------------------------
  await knex.schema.createTable("products", (table) => {
    table.bigIncrements("id").unsigned().primary();
    table
      .bigInteger("business_id")
      .unsigned()
      .notNullable()
      .references("id")
      .inTable("businesses")
      .onDelete("RESTRICT");
    table
      .bigInteger("category_id")
      .unsigned()
      .nullable()
      .references("id")
      .inTable("categories")
      .onDelete("RESTRICT");
    table
      .bigInteger("unit_id")
      .unsigned()
      .nullable()
      .references("id")
      .inTable("units")
      .onDelete("RESTRICT");
    // §8's "Warehouse/location" as the product's *default* — where new
    // stock goes when no location is specified. Actual holdings are in
    // `inventory`, which may span several locations.
    table
      .bigInteger("default_location_id")
      .unsigned()
      .nullable()
      .references("id")
      .inTable("storage_locations")
      .onDelete("SET NULL");

    // Basic information (§8)
    table.string("name", 200).notNullable();
    table.string("product_code", 100).nullable();
    table.string("sku", 100).nullable();
    table.string("barcode", 100).nullable();
    table.string("brand", 150).nullable();
    table.string("image_url", 500).nullable();
    table.text("description").nullable();
    table.string("short_description", 500).nullable();
    // §45 names the soft-delete vocabulary for important records verbatim:
    // "active / archived / deleted_at". `archived` is therefore the spec's
    // word and is used as-is.
    //
    // DEVIATION (documented): `inactive` is not in the specification. §8 and
    // §7 both list "Status" as a product/category field without enumerating
    // its values, and §45's pair cannot express a product that is
    // temporarily not offered but must still appear in catalogue management
    // — distinct from archived, which §45 pairs with `deleted_at` for
    // records withdrawn from every list. Kept as the minimum third value,
    // not as a redesign of §45's pattern.
    table
      .enu("status", ["active", "inactive", "archived"], {
        useNative: true,
        enumName: "product_status_enum",
      })
      .notNullable()
      .defaultTo("active");

    // DEVIATION (required by implementation): §8's field list has no
    // "product type". It is added because §21 cannot be implemented without
    // it — "Raw materials decrease / Finished goods increase" requires
    // knowing which a product is, and the Phase 3 decision that raw
    // materials ARE products (one table, one stock ledger) puts both kinds
    // in this table. The values are §21's own two terms, nothing more.
    table
      .enu("product_type", ["finished_good", "raw_material"], {
        useNative: true,
        enumName: "product_type_enum",
      })
      .notNullable()
      .defaultTo("finished_good");

    // Stock rules (§8, §44). The *levels* are product policy and belong
    // here; the *quantities* are per-location state and do not.
    table.decimal("min_stock", 14, 3).notNullable().defaultTo(0);
    table.decimal("max_stock", 14, 3).nullable();
    table.decimal("reorder_level", 14, 3).notNullable().defaultTo(0);

    // Deliberately NO per-product `allow_negative_stock` column. §47 is
    // explicit that negative inventory is enabled "only through an explicit
    // business setting", so the switch lives once in `business_settings`
    // under `inventory.allow_negative_stock`. A per-product override would
    // be a second place to say the same thing, and a way to defeat the
    // business-level rule §47 asks for.
    //
    // Deliberately NO `track_inventory` column either: the specification
    // never mentions untracked or non-stock products.

    // Financial information (§8)
    table.decimal("purchase_cost", 14, 2).nullable();
    table.decimal("selling_price", 14, 2).nullable();
    table.decimal("wholesale_price", 14, 2).nullable();
    table.decimal("discount_price", 14, 2).nullable();
    table.decimal("tax_rate", 6, 3).nullable(); // percent, e.g. 15.000

    // Optional information (§8). Nullable throughout — §8 says "do not
    // force unnecessary fields"; an electronics warehouse fills almost
    // none of these and a furniture factory fills most.
    table.string("size", 100).nullable();
    table.decimal("length", 12, 3).nullable();
    table.decimal("width", 12, 3).nullable();
    table.decimal("height", 12, 3).nullable();
    table.decimal("weight", 12, 3).nullable();
    table.string("color", 50).nullable();
    table.string("material", 100).nullable();
    table.string("model", 100).nullable();
    table.string("manufacturer", 150).nullable();
    table.string("serial_number", 100).nullable();
    table.string("batch_number", 100).nullable();
    table.date("expiry_date").nullable();
    table.string("warranty_period", 50).nullable();

    table.timestamp("created_at").notNullable().defaultTo(knex.fn.now());
    table.timestamp("updated_at").notNullable().defaultTo(knex.fn.now());
    table.timestamp("deleted_at").nullable();

    // §54's "duplicate SKUs" must be impossible, and §36 means uniqueness
    // is per tenant — two businesses may both use "SKU-001". All three are
    // nullable, and MySQL permits repeated NULLs in a unique index, so a
    // business that does not use barcodes is not forced to invent them.
    table.unique(["business_id", "sku"], { indexName: "uq_products_sku" });
    table.unique(["business_id", "barcode"], { indexName: "uq_products_barcode" });
    table.unique(["business_id", "product_code"], { indexName: "uq_products_code" });

    // §11's searchable/filterable fields, each with a reason:
    // list-and-filter the catalogue; filter by category; §32's name search.
    table.index(["business_id", "status", "deleted_at"], "idx_products_business_status");
    table.index(["business_id", "category_id"], "idx_products_category");
    table.index(["business_id", "name"], "idx_products_name");
  });

  // §54: "Prevent invalid: Negative quantities" / "Invalid prices". These
  // are stock *policy* levels and money, none of which has a meaning below
  // zero, and none of which §47's negative-inventory setting applies to —
  // that setting is about the actual level in `inventory`, not about what a
  // product's reorder threshold may be. `max_stock` is checked only when
  // present, since NULL means "no ceiling configured".
  await knex.raw(`
    ALTER TABLE products
      ADD CONSTRAINT ck_products_min_stock_not_negative     CHECK (min_stock >= 0),
      ADD CONSTRAINT ck_products_reorder_level_not_negative CHECK (reorder_level >= 0),
      ADD CONSTRAINT ck_products_max_stock_not_negative     CHECK (max_stock IS NULL OR max_stock >= 0),
      ADD CONSTRAINT ck_products_purchase_cost_not_negative CHECK (purchase_cost IS NULL OR purchase_cost >= 0),
      ADD CONSTRAINT ck_products_selling_price_not_negative CHECK (selling_price IS NULL OR selling_price >= 0),
      ADD CONSTRAINT ck_products_wholesale_not_negative     CHECK (wholesale_price IS NULL OR wholesale_price >= 0),
      ADD CONSTRAINT ck_products_discount_not_negative      CHECK (discount_price IS NULL OR discount_price >= 0),
      ADD CONSTRAINT ck_products_tax_rate_not_negative      CHECK (tax_rate IS NULL OR tax_rate >= 0)
  `);

  // --------------------------------------------------------------------
  // product_variants — §9.
  // A variant carries its own SKU, barcode, price and cost, and its own
  // stock (via `inventory.variant_id`). Attributes are JSON because §9's
  // axes differ per product — colour for a sofa, size for a table — and a
  // fixed column set would fit neither.
  // --------------------------------------------------------------------
  await knex.schema.createTable("product_variants", (table) => {
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
      .onDelete("RESTRICT"); // variants are referenced by order lines and stock history

    table.string("name", 200).nullable(); // "Charcoal / 3-seat"
    table.string("sku", 100).nullable();
    table.string("barcode", 100).nullable();
    table.decimal("purchase_cost", 14, 2).nullable();
    table.decimal("selling_price", 14, 2).nullable();
    table.json("attributes").nullable(); // {"color":"Charcoal","size":"3-seat"}
    table.string("image_url", 500).nullable();

    table
      .enu("status", ["active", "inactive"], { useNative: true, enumName: "variant_status_enum" })
      .notNullable()
      .defaultTo("active");

    table.timestamp("created_at").notNullable().defaultTo(knex.fn.now());
    table.timestamp("updated_at").notNullable().defaultTo(knex.fn.now());
    table.timestamp("deleted_at").nullable();

    // A variant SKU/barcode shares the product namespace — scanning a
    // barcode must identify one sellable thing, whether that is a product
    // or one of its variants. Enforced per table here; the cross-table
    // rule is the service layer's (documented in docs/backend-phase3.md).
    table.unique(["business_id", "sku"], { indexName: "uq_variants_sku" });
    table.unique(["business_id", "barcode"], { indexName: "uq_variants_barcode" });
    table.index(["product_id", "status"], "idx_variants_product");
  });

  // --------------------------------------------------------------------
  // product_images — §8's "multiple images".
  // --------------------------------------------------------------------
  await knex.schema.createTable("product_images", (table) => {
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
      .onDelete("CASCADE"); // an image has no meaning without its product

    table.string("url", 500).notNullable();
    table.string("alt_text", 255).nullable();
    table.integer("sort_order").notNullable().defaultTo(0);
    table.boolean("is_primary").notNullable().defaultTo(false);

    table.timestamp("created_at").notNullable().defaultTo(knex.fn.now());

    table.index(["product_id", "sort_order"], "idx_product_images_product");
  });
}

/** @param {import('knex').Knex} knex */
export async function down(knex) {
  await knex.schema.dropTableIfExists("product_images");
  await knex.schema.dropTableIfExists("product_variants");
  await knex.schema.dropTableIfExists("products");
  await knex.schema.dropTableIfExists("categories");
  await knex.schema.dropTableIfExists("units");
}
