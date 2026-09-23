/**
 * Phase 2 compatibility adjustment — the ONE change this phase makes to an
 * existing table, kept to the minimum the specification requires.
 *
 * Spec §30 lists the fields an audit record must carry: user, action,
 * **module**, description, date, time, IP, reference ID. Phase 2's
 * `audit_logs` has every one of those except `module`, because Phase 2 only
 * ever wrote authentication events, where the module was implicitly "auth".
 * From Phase 5 onward the same table receives events from every module, and
 * §30 also requires filtering by module — which needs a real column, not a
 * prefix convention inside `action`.
 *
 * Existing rows are backfilled to 'auth', which is what they actually are
 * (Phase 2 wrote login/logout/password-change events only). The column is
 * then made NOT NULL, so no later writer can omit it.
 *
 * @param {import('knex').Knex} knex
 */
export async function up(knex) {
  const hasColumn = await knex.schema.hasColumn("audit_logs", "module");
  if (hasColumn) return;

  await knex.schema.alterTable("audit_logs", (table) => {
    table.string("module", 50).nullable().after("actor_id");
  });

  // Every row that exists at this point was written by Phase 2's auth
  // service — see backend/src/modules/auth/.
  await knex("audit_logs").whereNull("module").update({ module: "auth" });

  await knex.schema.alterTable("audit_logs", (table) => {
    table.string("module", 50).notNullable().alter();
  });

  // §30 requires filtering the log by module; without this the filter is a
  // full scan of a table designed to grow without bound.
  await knex.schema.alterTable("audit_logs", (table) => {
    table.index(["business_id", "module", "created_at"], "idx_audit_logs_module");
  });
}

/** @param {import('knex').Knex} knex */
export async function down(knex) {
  const hasColumn = await knex.schema.hasColumn("audit_logs", "module");
  if (!hasColumn) return;
  await knex.schema.alterTable("audit_logs", (table) => {
    table.dropIndex(["business_id", "module", "created_at"], "idx_audit_logs_module");
    table.dropColumn("module");
  });
}
