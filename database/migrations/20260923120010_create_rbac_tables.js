/**
 * Role-based access control foundation (spec §23/§24).
 *
 * Three tables and one new column. The *enforcement* — middleware that
 * reads a user's permissions and refuses a request — is Phase 5 work and is
 * deliberately not here; §24's requirement that permissions be
 * "configurable" and exist "at module/action level" is a schema shape, and
 * this is that shape.
 *
 * **`permissions` has no `business_id`, on purpose.** A permission is a name
 * for a capability the *software* has ("products.create"), not a record a
 * tenant owns. Every business draws from the same catalog; what differs per
 * business is which permissions its roles hold, and that is `roles` +
 * `role_permissions`. Giving `permissions` a tenant column would mean the
 * same capability existed under N different ids, and every authorization
 * check would have to resolve a tenant before it could even name what it
 * was checking. §7's warning against handing every table a business_id
 * "just because most tables do" is exactly this case.
 *
 * **`roles` IS business-owned**, because §24 requires per-business
 * configuration: two businesses may both have a "Manager" role with
 * different grants. `is_system` marks the built-in roles §23 lists (Owner,
 * Manager, Warehouse Manager, Sales Staff, Inventory Staff, Production
 * Manager, Accountant, Viewer) once a later phase creates them per business,
 * so the UI can prevent renaming/deleting a role the app itself relies on.
 *
 * The catalog rows themselves are NOT inserted here — populating
 * `permissions` and creating each business's default roles belongs to the
 * RBAC phase, which owns the decision of what the built-in roles grant.
 *
 * @param {import('knex').Knex} knex
 */
export async function up(knex) {
  await knex.schema.createTable("permissions", (table) => {
    table.bigIncrements("id").unsigned().primary();

    // The full "{module}.{action}" key, e.g. "products.view". Stored whole
    // as well as split, because authorization checks look it up by key
    // while the settings UI groups it by module — indexing both avoids one
    // of the two doing string surgery at query time.
    table.string("permission_key", 100).notNullable();
    table.string("module", 50).notNullable();
    table.string("action", 50).notNullable();
    table.string("description", 255).nullable();

    table.timestamp("created_at").notNullable().defaultTo(knex.fn.now());
    table.timestamp("updated_at").notNullable().defaultTo(knex.fn.now());

    // §54's "invalid user permissions" must be impossible to create: the
    // key is the authoritative identifier and the database enforces it.
    table.unique("permission_key", { indexName: "uq_permissions_key" });
    table.unique(["module", "action"], { indexName: "uq_permissions_module_action" });
    table.index("module", "idx_permissions_module");
  });

  await knex.schema.createTable("roles", (table) => {
    table.bigIncrements("id").unsigned().primary();
    table
      .bigInteger("business_id")
      .unsigned()
      .notNullable()
      .references("id")
      .inTable("businesses")
      .onDelete("RESTRICT");

    table.string("name", 100).notNullable();
    table.string("description", 255).nullable();

    // A built-in role from §23's list. Later phases refuse to delete or
    // rename these; a business's own extra roles are free-form.
    table.boolean("is_system").notNullable().defaultTo(false);

    table.timestamp("created_at").notNullable().defaultTo(knex.fn.now());
    table.timestamp("updated_at").notNullable().defaultTo(knex.fn.now());
    table.timestamp("deleted_at").nullable();

    // Role names are unique *within* a business (§24's per-business
    // configuration), never globally.
    table.unique(["business_id", "name"], { indexName: "uq_roles_business_name" });
  });

  await knex.schema.createTable("role_permissions", (table) => {
    table
      .bigInteger("role_id")
      .unsigned()
      .notNullable()
      .references("id")
      .inTable("roles")
      .onDelete("CASCADE"); // deleting a role removes its grants; the grants have no meaning alone
    table
      .bigInteger("permission_id")
      .unsigned()
      .notNullable()
      .references("id")
      .inTable("permissions")
      .onDelete("RESTRICT"); // a permission still granted somewhere cannot be removed from the catalog

    table.timestamp("created_at").notNullable().defaultTo(knex.fn.now());

    // The pair IS the row — a composite primary key, so the same permission
    // cannot be granted to the same role twice.
    table.primary(["role_id", "permission_id"], { constraintName: "pk_role_permissions" });
    table.index("permission_id", "idx_role_permissions_permission");
  });

  // Links a user to their role. Nullable because Phase 2 created users
  // before roles existed, and because §23's owner is identified by
  // `users.is_owner` (kept: it is the "who set up this business" fact, and
  // an owner must stay an owner even if their role row is edited).
  await knex.schema.alterTable("users", (table) => {
    table
      .bigInteger("role_id")
      .unsigned()
      .nullable()
      .references("id")
      .inTable("roles")
      .onDelete("RESTRICT") // a role still assigned to a user cannot be deleted
      .after("is_owner");
  });
}

/** @param {import('knex').Knex} knex */
export async function down(knex) {
  await knex.schema.alterTable("users", (table) => {
    table.dropForeign("role_id");
    table.dropColumn("role_id");
  });
  await knex.schema.dropTableIfExists("role_permissions");
  await knex.schema.dropTableIfExists("roles");
  await knex.schema.dropTableIfExists("permissions");
}
