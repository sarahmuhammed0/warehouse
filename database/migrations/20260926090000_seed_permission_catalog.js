/**
 * Populates the permission catalogue (§24).
 *
 * A MIGRATION RATHER THAN A SEED, deliberately. Seeds are optional sample
 * data; this is reference data the application cannot function without —
 * every authorization check resolves against these rows, so an environment
 * that skipped it would authorize nothing. Running migrations must be
 * enough to get a working system.
 *
 * The source of truth is `backend/src/modules/rbac/catalog.js`, imported
 * here rather than duplicated: a permission only means something if code
 * checks for it, so the list and the checks have to change together.
 *
 * Idempotent, and safe to re-run after the catalogue grows: it inserts what
 * is missing and refreshes descriptions, and never deletes. Removing a
 * permission would silently revoke it from every role that had been granted
 * it, which is a decision for a migration of its own, written deliberately.
 */

import { buildCatalog } from "../../backend/src/modules/rbac/catalog.js";

/** @param {import('knex').Knex} knex */
export async function up(knex) {
  const rows = buildCatalog().map((p) => ({
    permission_key: p.key,
    module: p.module,
    action: p.action,
    description: p.description,
  }));

  // ON DUPLICATE KEY UPDATE rather than INSERT IGNORE: IGNORE would also
  // swallow genuine errors (a bad column, a truncated value) and leave the
  // catalogue quietly incomplete.
  await knex("permissions")
    .insert(rows)
    .onConflict("permission_key")
    .merge(["module", "action", "description"]);
}

/** @param {import('knex').Knex} knex */
export async function down(knex) {
  // Only the rows this migration created. `role_permissions` has ON DELETE
  // CASCADE from `permissions`, so any grants go with them — which is what
  // rolling this back means: the catalogue did not exist, so neither did
  // anything granted from it.
  const keys = buildCatalog().map((p) => p.key);
  await knex("permissions").whereIn("permission_key", keys).del();
}
