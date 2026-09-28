/**
 * A phone number is unique among LIVE users, not for all time.
 *
 * `uq_users_phone` covered every row including archived ones, so §45's soft
 * delete left the number permanently unusable: a business that re-hired
 * someone, or reassigned a company handset, could never create that account
 * again. The first attempt to work around it — writing a marker into the phone
 * on delete — overflowed the column, which is how this was found: `phone` is
 * VARCHAR(20) and "deleted:123:+9647701234567" is not.
 *
 * MySQL has no partial index, so the standard trick is used instead, the same
 * one `inventory` already uses for its slot key: a STORED generated column that
 * is the phone for a live row and NULL for an archived one. A unique index
 * permits any number of NULLs, so archived rows stop competing for the number
 * while keeping it on the record — which is what §45 means by archiving rather
 * than erasing, and what an audit trail needs to still name the person.
 */

export async function up(knex) {
  await knex.raw(`
    ALTER TABLE users
      ADD COLUMN active_phone VARCHAR(20)
        GENERATED ALWAYS AS (IF(deleted_at IS NULL, phone, NULL)) STORED
  `);

  // The old index goes only after the new one exists, so there is no window in
  // which two live users could take the same number.
  await knex.raw(`ALTER TABLE users ADD UNIQUE KEY uq_users_active_phone (active_phone)`);
  await knex.raw(`ALTER TABLE users DROP INDEX uq_users_phone`);
}

export async function down(knex) {
  // Reversing this can fail, and should: if two archived users share a number,
  // there is no way to restore an index that forbids it without deciding which
  // record to damage. That decision belongs to whoever is rolling back.
  await knex.raw(`ALTER TABLE users ADD UNIQUE KEY uq_users_phone (phone)`);
  await knex.raw(`ALTER TABLE users DROP INDEX uq_users_active_phone`);
  await knex.raw(`ALTER TABLE users DROP COLUMN active_phone`);
}
