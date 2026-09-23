/**
 * Per-business configuration foundation — §34 (Settings), §29 (document
 * numbering), §51 (custom fields), §28 (PDF template builder), §49/§50
 * (dashboard + factory-type module configuration).
 *
 * @param {import('knex').Knex} knex
 */
export async function up(knex) {
  // --------------------------------------------------------------------
  // business_settings — key/value, not a column per setting.
  //
  // §34 lists six groups of settings and §49/§50/§51 add three more, and
  // every later phase adds to them. A column-per-setting table would mean a
  // migration every time a checkbox is added to Settings, and a row 80
  // columns wide of which any given screen reads four. Key/value with a
  // JSON value keeps one row per setting, lets a group be fetched with one
  // indexed prefix query, and needs no schema change to add a setting.
  //
  // The tradeoff, recorded honestly: the database cannot type-check a
  // setting's value. That is why §54's validation layer owns the per-key
  // schema — the catalog of valid keys and their shapes lives in code
  // (backend/src/validation/), which is also where it can be versioned and
  // tested. The database's job here is ownership and uniqueness.
  // --------------------------------------------------------------------
  await knex.schema.createTable("business_settings", (table) => {
    table.bigIncrements("id").unsigned().primary();
    table
      .bigInteger("business_id")
      .unsigned()
      .notNullable()
      .references("id")
      .inTable("businesses")
      .onDelete("CASCADE"); // settings are meaningless without their business

    // "sales.invoice_prefix", "inventory.allow_negative_stock", …
    table.string("setting_key", 100).notNullable();
    table.json("setting_value").notNullable();

    table.timestamp("created_at").notNullable().defaultTo(knex.fn.now());
    table.timestamp("updated_at").notNullable().defaultTo(knex.fn.now());

    // One value per key per business — the whole point of the table.
    table.unique(["business_id", "setting_key"], { indexName: "uq_business_settings_key" });
  });

  // --------------------------------------------------------------------
  // document_sequences — §29's configurable numbering (INV/SALE/ORD/RET/PUR).
  //
  // The sequence is state, so it lives in a row that a transaction can lock
  // (`SELECT ... FOR UPDATE`) while it allocates the next number. That is
  // the only way §61 rule 12 ("document numbers must be unique") survives
  // two concurrent sales: MAX(order_number)+1 computed outside a lock hands
  // the same number to both. The generated number is then *also* protected
  // by a unique index on the document table itself, so a bug in the
  // allocator fails loudly instead of duplicating an invoice.
  // --------------------------------------------------------------------
  await knex.schema.createTable("document_sequences", (table) => {
    table.bigIncrements("id").unsigned().primary();
    table
      .bigInteger("business_id")
      .unsigned()
      .notNullable()
      .references("id")
      .inTable("businesses")
      .onDelete("CASCADE");

    table
      .enu(
        "document_type",
        ["invoice", "sale", "order", "return", "purchase", "production", "transfer"],
        { useNative: true, enumName: "document_sequence_type_enum" }
      )
      .notNullable();

    table.string("prefix", 20).notNullable();
    table.bigInteger("next_number").unsigned().notNullable().defaultTo(1);
    // "ORD-2026-000001" in §14 pads to six digits; configurable because
    // §29 lets the business choose the format.
    table.integer("number_padding").unsigned().notNullable().defaultTo(6);
    // Whether the sequence restarts each calendar year, as §14's example
    // number (which embeds 2026) implies is possible.
    table.boolean("include_year").notNullable().defaultTo(true);
    table.integer("current_year").unsigned().nullable();

    table.timestamp("created_at").notNullable().defaultTo(knex.fn.now());
    table.timestamp("updated_at").notNullable().defaultTo(knex.fn.now());

    table.unique(["business_id", "document_type"], { indexName: "uq_document_sequences_type" });
  });

  // --------------------------------------------------------------------
  // custom_field_definitions / custom_field_values — §51.
  //
  // §51 is explicit: "support configurable custom fields rather than
  // hard-coding every industry". So a furniture factory's "Wood type" and a
  // spare-parts warehouse's "Vehicle model" are rows here, never columns on
  // `products`.
  // --------------------------------------------------------------------
  await knex.schema.createTable("custom_field_definitions", (table) => {
    table.bigIncrements("id").unsigned().primary();
    table
      .bigInteger("business_id")
      .unsigned()
      .notNullable()
      .references("id")
      .inTable("businesses")
      .onDelete("CASCADE");

    // Which module's records carry this field. An enum rather than free
      // text so a typo cannot create an orphan field nothing ever shows.
    table
      .enu(
        "entity_type",
        ["product", "category", "customer", "supplier", "order", "purchase", "production"],
        { useNative: true, enumName: "custom_field_entity_enum" }
      )
      .notNullable();

    table.string("field_key", 64).notNullable();
    table.string("label", 150).notNullable();
    table
      .enu("field_type", ["text", "number", "date", "boolean", "select", "multiselect"], {
        useNative: true,
        enumName: "custom_field_type_enum",
      })
      .notNullable();
    // Allowed values for select/multiselect. Null for the other types.
    table.json("options").nullable();
    table.boolean("is_required").notNullable().defaultTo(false);
    table.boolean("is_visible").notNullable().defaultTo(true);
    table.integer("sort_order").notNullable().defaultTo(0);

    table.timestamp("created_at").notNullable().defaultTo(knex.fn.now());
    table.timestamp("updated_at").notNullable().defaultTo(knex.fn.now());
    table.timestamp("deleted_at").nullable();

    table.unique(["business_id", "entity_type", "field_key"], {
      indexName: "uq_custom_fields_key",
    });
    table.index(["business_id", "entity_type", "sort_order"], "idx_custom_fields_entity");
  });

  await knex.schema.createTable("custom_field_values", (table) => {
    table.bigIncrements("id").unsigned().primary();
    table
      .bigInteger("business_id")
      .unsigned()
      .notNullable()
      .references("id")
      .inTable("businesses")
      .onDelete("CASCADE");
    table
      .bigInteger("definition_id")
      .unsigned()
      .notNullable()
      .references("id")
      .inTable("custom_field_definitions")
      .onDelete("CASCADE"); // removing the field removes its stored values

    // Intentionally NOT a foreign key: the row this value belongs to lives
    // in whichever table `definition_id`'s entity_type names, and SQL has
    // no polymorphic FK. The integrity rule — that entity_id exists in that
    // table — is enforced by the service that writes it, and the pairing is
    // narrow (one column, one enum on the definition) rather than a general
    // polymorphic association. Recorded as a deliberate exception to §9's
    // "create correct foreign-key relationships".
    table.bigInteger("entity_id").unsigned().notNullable();

    // One column, not one per type: the definition already declares the
    // type, and a five-column row with four NULLs reads worse and indexes
    // no better. Cast on read, validated on write by §22's layer.
    table.text("value").nullable();

    table.timestamp("created_at").notNullable().defaultTo(knex.fn.now());
    table.timestamp("updated_at").notNullable().defaultTo(knex.fn.now());

    // One value per field per record.
    table.unique(["definition_id", "entity_id"], { indexName: "uq_custom_field_values_record" });
    table.index(["business_id", "entity_id"], "idx_custom_field_values_entity");
  });

  // --------------------------------------------------------------------
  // pdf_templates — §27's document content and §28's per-field toggles.
  //
  // The text settings are columns because §28 names them exactly and they
  // are a fixed, closed list. The toggles are one JSON document
  // (`enabled_fields`) because §28's example is a checklist that grows with
  // the invoice layout, and 15 boolean columns would mean a migration per
  // checkbox for no gain — nothing queries or joins on them; they are read
  // whole when a PDF is rendered.
  // --------------------------------------------------------------------
  await knex.schema.createTable("pdf_templates", (table) => {
    table.bigIncrements("id").unsigned().primary();
    table
      .bigInteger("business_id")
      .unsigned()
      .notNullable()
      .references("id")
      .inTable("businesses")
      .onDelete("CASCADE");

    table.string("name", 100).notNullable();
    table.string("invoice_title", 100).notNullable().defaultTo("INVOICE");

    table.string("logo_url", 500).nullable();
    table.string("header_text", 500).nullable();
    table.string("footer_text", 500).nullable();
    table.string("thank_you_message", 255).nullable();
    table.text("return_policy").nullable();
    table.text("payment_terms").nullable();
    table.string("signature_text", 150).nullable();

    // Presentation only. The business's authoritative currency/timezone
    // live on `businesses`; these let one template render differently
    // (§28 lists both as template settings).
    table.char("currency", 3).nullable();
    table.string("date_format", 32).notNullable().defaultTo("YYYY-MM-DD");

    table.json("enabled_fields").nullable();

    table.boolean("is_default").notNullable().defaultTo(false);

    table.timestamp("created_at").notNullable().defaultTo(knex.fn.now());
    table.timestamp("updated_at").notNullable().defaultTo(knex.fn.now());
    table.timestamp("deleted_at").nullable();

    table.unique(["business_id", "name"], { indexName: "uq_pdf_templates_name" });
    table.index(["business_id", "is_default"], "idx_pdf_templates_default");
  });
}

/** @param {import('knex').Knex} knex */
export async function down(knex) {
  await knex.schema.dropTableIfExists("pdf_templates");
  await knex.schema.dropTableIfExists("custom_field_values");
  await knex.schema.dropTableIfExists("custom_field_definitions");
  await knex.schema.dropTableIfExists("document_sequences");
  await knex.schema.dropTableIfExists("business_settings");
}
