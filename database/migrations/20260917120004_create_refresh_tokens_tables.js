/**
 * refresh_tokens (business users) + system_admin_refresh_tokens (System
 * Admins) — two separate tables, mirroring the two separate identity
 * tables, each with a real FK (a polymorphic single table with a
 * `subject_type` discriminator would lose FK-enforced referential
 * integrity — see docs/authentication.md "Token architecture").
 *
 * Only `token_hash` (SHA-256 of the raw refresh token) is ever stored —
 * never the raw token itself (src/utils/token.js). `replaced_by_id` tracks
 * rotation chains (issuing a new refresh token on use revokes the old one
 * and links forward), which is what lets a reused/stolen old token be
 * detected as a reuse-after-rotation the moment it's presented.
 *
 * @param {import('knex').Knex} knex
 */
export async function up(knex) {
  await knex.schema.createTable("refresh_tokens", (table) => {
    table.bigIncrements("id").unsigned().primary();
    table.bigInteger("user_id").unsigned().notNullable().references("id").inTable("users").onDelete("CASCADE");
    table.specificType("token_hash", "CHAR(64)").notNullable();
    table.timestamp("expires_at").notNullable();
    table.timestamp("revoked_at").nullable();
    table
      .bigInteger("replaced_by_id")
      .unsigned()
      .nullable()
      .references("id")
      .inTable("refresh_tokens")
      .onDelete("SET NULL");
    table.string("ip_address", 45).nullable();
    table.string("user_agent", 255).nullable();
    table.timestamp("created_at").notNullable().defaultTo(knex.fn.now());

    table.unique("token_hash", { indexName: "uq_refresh_tokens_hash" });
    table.index(["user_id", "revoked_at", "expires_at"], "idx_refresh_tokens_user");
  });

  await knex.schema.createTable("system_admin_refresh_tokens", (table) => {
    table.bigIncrements("id").unsigned().primary();
    table
      .bigInteger("system_admin_id")
      .unsigned()
      .notNullable()
      .references("id")
      .inTable("system_admins")
      .onDelete("CASCADE");
    table.specificType("token_hash", "CHAR(64)").notNullable();
    table.timestamp("expires_at").notNullable();
    table.timestamp("revoked_at").nullable();
    table
      .bigInteger("replaced_by_id")
      .unsigned()
      .nullable()
      .references("id")
      .inTable("system_admin_refresh_tokens")
      .onDelete("SET NULL");
    table.string("ip_address", 45).nullable();
    table.string("user_agent", 255).nullable();
    table.timestamp("created_at").notNullable().defaultTo(knex.fn.now());

    table.unique("token_hash", { indexName: "uq_admin_refresh_tokens_hash" });
    table.index(["system_admin_id", "revoked_at", "expires_at"], "idx_admin_refresh_tokens_admin");
  });
}

/** @param {import('knex').Knex} knex */
export async function down(knex) {
  await knex.schema.dropTableIfExists("system_admin_refresh_tokens");
  await knex.schema.dropTableIfExists("refresh_tokens");
}
