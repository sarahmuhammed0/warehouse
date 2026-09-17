/**
 * users — business-tenant accounts (login as phone+password). Deliberately
 * separate from `system_admins` (see that migration's doc comment and
 * docs/authentication.md "System Admin isolation") — a business user row
 * can never become a System Admin by data manipulation, because System
 * Admin identity isn't a flag on this table, it's a different table
 * entirely with its own auth code path.
 *
 * `phone` is UNIQUE GLOBALLY, not per-business — see docs/authentication.md
 * "Phone uniqueness" for the reasoning and the flagged alternative.
 *
 * @param {import('knex').Knex} knex
 */
export async function up(knex) {
  await knex.schema.createTable("users", (table) => {
    table.bigIncrements("id").unsigned().primary();

    table
      .bigInteger("business_id")
      .unsigned()
      .notNullable()
      .references("id")
      .inTable("businesses")
      .onDelete("RESTRICT"); // a business is archived (soft-deleted), never hard-deleted while it has users

    table.string("name", 150).notNullable();
    table.string("phone", 20).notNullable();
    table.string("password_hash", 255).notNullable();

    // Minimal elevation flag for the initial administrator created with a
    // business (Phase 2 §16/§23) — NOT a role/permission system. Full RBAC
    // (roles, permissions, role_permissions) is explicitly deferred; this
    // exists only so later phases have something to check before that
    // system exists, and so "who set up this business" stays answerable.
    table.boolean("is_owner").notNullable().defaultTo(false);

    table
      .enu("status", ["active", "disabled"], { useNative: true, enumName: "user_status_enum" })
      .notNullable()
      .defaultTo("active");
    table.timestamp("last_login_at").nullable();

    table.timestamp("created_at").notNullable().defaultTo(knex.fn.now());
    table.timestamp("updated_at").notNullable().defaultTo(knex.fn.now());
    table.timestamp("deleted_at").nullable();

    table.unique("phone", { indexName: "uq_users_phone" });
    table.index(["business_id", "status"], "idx_users_business");
  });
}

/** @param {import('knex').Knex} knex */
export async function down(knex) {
  await knex.schema.dropTableIfExists("users");
}
