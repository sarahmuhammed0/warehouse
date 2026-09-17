/**
 * audit_logs — append-only (architecture §19). Phase 2 writes only
 * authentication-related events (login success/failure, logout, password
 * change — see backend/src/modules/auth/service.js); the table itself is
 * general-purpose so every later module reuses it without a schema change.
 *
 * `business_id` is nullable: a System Admin action (or a failed login
 * against an unrecognized phone, before any tenant is known) has no
 * business context. `actor_id` is nullable for the same reason a failed
 * login against a non-existent phone has no real actor.
 *
 * @param {import('knex').Knex} knex
 */
export async function up(knex) {
  await knex.schema.createTable("audit_logs", (table) => {
    table.bigIncrements("id").unsigned().primary();
    table
      .bigInteger("business_id")
      .unsigned()
      .nullable()
      .references("id")
      .inTable("businesses")
      .onDelete("SET NULL");
    table
      .enu("actor_type", ["business_user", "system_admin", "system"], {
        useNative: true,
        enumName: "audit_actor_type_enum",
      })
      .notNullable();
    table.bigInteger("actor_id").unsigned().nullable();
    table.string("action", 100).notNullable();
    table.string("description", 500).notNullable();
    table.string("ip_address", 45).nullable();
    table.string("reference_type", 50).nullable();
    table.bigInteger("reference_id").unsigned().nullable();
    table.timestamp("created_at").notNullable().defaultTo(knex.fn.now());

    table.index(["business_id", "created_at"], "idx_audit_logs_business");
    table.index(["actor_type", "actor_id"], "idx_audit_logs_actor");
    table.index(["action", "created_at"], "idx_audit_logs_action");
  });
}

/** @param {import('knex').Knex} knex */
export async function down(knex) {
  await knex.schema.dropTableIfExists("audit_logs");
}
