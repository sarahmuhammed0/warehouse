/**
 * login_attempts — powers account-level lockout + gives the rate limiter
 * something to check beyond raw IP throttling (Phase 2 §13). Records
 * EVERY attempt, including ones against a phone number that doesn't
 * resolve to any account — necessary so a lockout check never has to
 * first reveal "does this phone exist" (§7's anti-enumeration rule) by
 * behaving differently for real vs. fake phone numbers.
 *
 * @param {import('knex').Knex} knex
 */
export async function up(knex) {
  await knex.schema.createTable("login_attempts", (table) => {
    table.bigIncrements("id").unsigned().primary();
    table
      .enu("account_type", ["business_user", "system_admin"], {
        useNative: true,
        enumName: "login_attempt_account_type_enum",
      })
      .notNullable();
    table.string("phone", 20).notNullable();
    table.boolean("success").notNullable();
    table.string("ip_address", 45).nullable();
    table.timestamp("created_at").notNullable().defaultTo(knex.fn.now());

    table.index(["phone", "account_type", "created_at"], "idx_login_attempts_phone");
    table.index(["ip_address", "created_at"], "idx_login_attempts_ip");
  });
}

/** @param {import('knex').Knex} knex */
export async function down(knex) {
  await knex.schema.dropTableIfExists("login_attempts");
}
