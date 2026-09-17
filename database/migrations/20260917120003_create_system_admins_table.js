/**
 * system_admins — intentionally its OWN table, not a flag on `users`.
 *
 * DECISION (documented per the Phase 2 brief's explicit warning against a
 * weak "is_system_admin flag on a business user" model): System Admin
 * identity lives in a structurally separate table with no `business_id`
 * column at all. This makes several classes of bug/attack structurally
 * impossible rather than merely policy-forbidden:
 *   - A business user row can never carry System Admin rights, because
 *     "is System Admin" isn't a boolean that could be flipped by a bug,
 *     a mass-assignment mistake, or a SQL injection on the users table —
 *     the row simply doesn't live there.
 *   - Every query and every piece of authorization logic that deals with
 *     System Admins reads from `system_admins`, never `users` — there is
 *     no shared query path where a missing `WHERE business_id = ...`
 *     clause could accidentally treat a business user as tenant-less.
 *   - The JWT `accountType` claim ('system_admin' vs 'business_user')
 *     is corroborated by which table the token's subject id actually
 *     resolves in — see backend/src/middleware/authenticate.js.
 *
 * See docs/authentication.md "System Admin isolation" for the full
 * writeup.
 *
 * @param {import('knex').Knex} knex
 */
export async function up(knex) {
  await knex.schema.createTable("system_admins", (table) => {
    table.bigIncrements("id").unsigned().primary();

    table.string("name", 150).notNullable();
    table.string("phone", 20).notNullable();
    table.string("password_hash", 255).notNullable();

    table
      .enu("status", ["active", "disabled"], { useNative: true, enumName: "admin_status_enum" })
      .notNullable()
      .defaultTo("active");
    table.timestamp("last_login_at").nullable();

    table.timestamp("created_at").notNullable().defaultTo(knex.fn.now());
    table.timestamp("updated_at").notNullable().defaultTo(knex.fn.now());
    table.timestamp("deleted_at").nullable();

    table.unique("phone", { indexName: "uq_system_admins_phone" });
  });
}

/** @param {import('knex').Knex} knex */
export async function down(knex) {
  await knex.schema.dropTableIfExists("system_admins");
}
