/**
 * Notifications (§31), system-wide settings (§2/§34) and backup history
 * (§52) — the last three foundations, and the two clearest examples of §7's
 * warning about tenant columns.
 *
 * `notifications.business_id` is NULLABLE: §31's list is mostly per-business
 * ("low stock", "new order") but ends with "important system alert", and
 * §56's admin dashboard shows platform-level "system alerts" that belong to
 * no tenant. A NOT NULL tenant column would have forced those to be
 * attributed to an arbitrary business.
 *
 * `system_settings` has NO tenant column at all, and neither does `backups`.
 * These are the platform's own records — §2's "manage system-wide
 * configuration" and "manage backups" are System Admin capabilities, and a
 * business_id here would be meaningless at best and a tenant-isolation bug
 * waiting to happen at worst.
 *
 * @param {import('knex').Knex} knex
 */
export async function up(knex) {
  await knex.schema.createTable("notifications", (table) => {
    table.bigIncrements("id").unsigned().primary();
    // Null for a platform-level alert — see the header.
    table
      .bigInteger("business_id")
      .unsigned()
      .nullable()
      .references("id")
      .inTable("businesses")
      .onDelete("CASCADE"); // a business's notifications go with it
    // Null when the notification is for the whole business rather than one
    // person (§31's low-stock alert is not addressed to an individual).
    table
      .bigInteger("user_id")
      .unsigned()
      .nullable()
      .references("id")
      .inTable("users")
      .onDelete("CASCADE");

    // §31's exact list, plus the catch-all it ends with.
    table
      .enu(
        "notification_type",
        [
          "low_stock",
          "out_of_stock",
          "new_order",
          "return_request",
          "pending_payment",
          "production_completed",
          "transfer_received",
          "system_alert",
        ],
        { useNative: true, enumName: "notification_type_enum" }
      )
      .notNullable();

    table.string("title", 200).notNullable();
    table.string("body", 500).notNullable();

    // What the notification is about, so tapping it can open the record.
    // Not a foreign key for the same reason as `inventory_movements` —
    // the referent's table varies by type.
    table.string("reference_type", 50).nullable();
    table.bigInteger("reference_id").unsigned().nullable();

    // Read state as a timestamp, not a boolean: it answers both "is it
    // read" and "when", and costs the same.
    table.timestamp("read_at").nullable();
    table.timestamp("created_at").notNullable().defaultTo(knex.fn.now());

    // The bell's unread count and its newest-first list — the two queries
    // this table exists to serve.
    table.index(["business_id", "read_at", "created_at"], "idx_notifications_business_unread");
    table.index(["user_id", "read_at", "created_at"], "idx_notifications_user_unread");
    table.index(["business_id", "notification_type"], "idx_notifications_type");
  });

  await knex.schema.createTable("system_settings", (table) => {
    table.bigIncrements("id").unsigned().primary();
    table.string("setting_key", 100).notNullable();
    table.json("setting_value").notNullable();
    table.string("description", 255).nullable();

    table.timestamp("created_at").notNullable().defaultTo(knex.fn.now());
    table.timestamp("updated_at").notNullable().defaultTo(knex.fn.now());
    table
      .bigInteger("updated_by")
      .unsigned()
      .nullable()
      .references("id")
      .inTable("system_admins")
      .onDelete("SET NULL");

    table.unique("setting_key", { indexName: "uq_system_settings_key" });
  });

  // §52's backup history. The foundation records *that* a backup happened
  // and where it went; taking one is §52's own phase, and deliberately not
  // here — a table that records backups is harmless, a half-built process
  // that writes them is not.
  await knex.schema.createTable("backups", (table) => {
    table.bigIncrements("id").unsigned().primary();

    table.string("filename", 255).notNullable();
    table.bigInteger("size_bytes").unsigned().nullable();
    table
      .enu("trigger_type", ["manual", "scheduled"], {
        useNative: true,
        enumName: "backup_trigger_enum",
      })
      .notNullable();
    table
      .enu("status", ["pending", "completed", "failed"], {
        useNative: true,
        enumName: "backup_status_enum",
      })
      .notNullable()
      .defaultTo("pending");

    table.timestamp("started_at").notNullable().defaultTo(knex.fn.now());
    table.timestamp("completed_at").nullable();
    // Plain text, never a stack trace or a path — §53's rule applies to
    // stored errors as much as to responses.
    table.string("error_message", 500).nullable();

    table
      .bigInteger("created_by")
      .unsigned()
      .nullable()
      .references("id")
      .inTable("system_admins")
      .onDelete("SET NULL");

    table.timestamp("created_at").notNullable().defaultTo(knex.fn.now());

    table.unique("filename", { indexName: "uq_backups_filename" });
    table.index(["status", "started_at"], "idx_backups_status");
  });
}

/** @param {import('knex').Knex} knex */
export async function down(knex) {
  await knex.schema.dropTableIfExists("backups");
  await knex.schema.dropTableIfExists("system_settings");
  await knex.schema.dropTableIfExists("notifications");
}
