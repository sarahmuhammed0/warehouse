/**
 * Business self-registration with System Admin approval.
 *
 * §2 gives the System Admin the power to create, disable and activate
 * business accounts. This keeps that control exactly where the
 * specification puts it while changing only who *initiates*: a business can
 * ask for an account, and nothing happens until an administrator says yes.
 * A registration that is never approved can never log in.
 *
 * MODELLED AS A STATUS, NOT A SEPARATE REQUESTS TABLE. The alternative —
 * `business_registration_requests` holding the applicant's details until
 * approval, then copying them into `businesses` — means two schemas for one
 * concept, two validation paths, and a copy step that can half-fail. Here a
 * pending business IS the request: approving it is a state change, and the
 * owner account created at signup keeps its id, so nothing is re-keyed.
 *
 * The cost, recorded honestly: `businesses` now contains rows that are not
 * yet real customers, so every query that means "actual businesses" must say
 * `status = 'active'` rather than assume it. Login already compares against
 * `'active'` exactly (see authService), which is why a pending business
 * cannot log in even before this migration's message changes land.
 */

/** @param {import('knex').Knex} knex */
export async function up(knex) {
  // MySQL cannot add ENUM members through the Knex builder, so the column is
  // redefined. Order matters for sorting: lifecycle order, not alphabetical.
  //
  // The default stays `active` deliberately. An administrator creating a
  // business directly (§2) is the approval, so that path must not have to
  // remember to pass a status; self-registration is the one that explicitly
  // asks for `pending`.
  await knex.raw(`
    ALTER TABLE businesses
      MODIFY COLUMN status ENUM('pending', 'active', 'disabled', 'rejected')
        NOT NULL DEFAULT 'active'
  `);

  await knex.schema.alterTable("businesses", (table) => {
    // Who decided, and when. Nullable because a business created directly by
    // an administrator was never in `pending` and so was never "approved" —
    // recording a decision that did not happen would be a lie in the audit
    // trail.
    table.timestamp("approved_at").nullable();
    table
      .bigInteger("approved_by")
      .unsigned()
      .nullable()
      .references("id")
      .inTable("system_admins")
      // The decision outlives the administrator who made it: archiving an
      // admin account must not erase who approved a business.
      .onDelete("SET NULL");

    table.timestamp("rejected_at").nullable();
    table
      .bigInteger("rejected_by")
      .unsigned()
      .nullable()
      .references("id")
      .inTable("system_admins")
      .onDelete("SET NULL");

    // Why it was refused. Shown to the applicant, so it is a message rather
    // than a code — the administrator writes it.
    table.string("rejection_reason", 500).nullable();

    // The admin's queue: "pending registrations, oldest first". Without this
    // the console scans every business to find the few awaiting a decision.
    table.index(["status", "created_at"], "idx_businesses_status_created");
  });
}

/** @param {import('knex').Knex} knex */
export async function down(knex) {
  await knex.schema.alterTable("businesses", (table) => {
    table.dropIndex(["status", "created_at"], "idx_businesses_status_created");
    table.dropForeign(["approved_by"]);
    table.dropForeign(["rejected_by"]);
    table.dropColumn("approved_at");
    table.dropColumn("approved_by");
    table.dropColumn("rejected_at");
    table.dropColumn("rejected_by");
    table.dropColumn("rejection_reason");
  });

  // Any row still sitting in a state the old enum cannot express would be
  // silently coerced to '' by MySQL, so it is resolved explicitly first:
  // an undecided or refused registration was never a live business, and
  // `disabled` is the old enum's term for "cannot log in".
  await knex.raw(`UPDATE businesses SET status = 'disabled' WHERE status IN ('pending', 'rejected')`);
  await knex.raw(`
    ALTER TABLE businesses
      MODIFY COLUMN status ENUM('active', 'disabled') NOT NULL DEFAULT 'active'
  `);
}
