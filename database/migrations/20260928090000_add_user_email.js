/**
 * §23's employee record carries an email address; `users` had nowhere to put it.
 *
 * Nullable, and deliberately NOT unique. Phone is the credential (§3) and the
 * unique identity; an email is contact detail, and two employees sharing a
 * family or shop address is ordinary. Making it unique would reject a real
 * business's real staff list.
 */

export async function up(knex) {
  await knex.schema.alterTable("users", (table) => {
    table.string("email", 255).nullable().after("phone");
  });
}

export async function down(knex) {
  await knex.schema.alterTable("users", (table) => {
    table.dropColumn("email");
  });
}
