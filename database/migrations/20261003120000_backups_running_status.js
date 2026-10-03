/**
 * A backup that is being taken right now needs a status of its own.
 *
 * The column was `enum('pending','completed','failed')`, written when the
 * endpoint recorded an intention and took no dump — `pending` meant "asked for,
 * nothing done", and nothing ever moved it.
 *
 * Now a dump really runs, and the two states are genuinely different:
 *
 *   pending    recorded, not started
 *   running    mysqldump is writing the file at this moment
 *   completed  the file exists, with its real size
 *   failed     it did not, and `error_message` says why
 *
 * The distinction is not cosmetic. The download endpoint refuses anything that
 * is not `completed`, because a running backup's file is half-written and
 * handing it over is how someone restores a truncated database. Collapsing
 * "being written" into `pending` would make that check unable to tell the
 * difference.
 *
 * `error_message` grows to 1000 characters at the same time. mysqldump's
 * complaints are the only evidence of why a backup failed, and 500 characters
 * cut them off mid-sentence — which matters precisely when someone is reading
 * them in a hurry.
 */

export async function up(knex) {
  await knex.raw(
    `ALTER TABLE backups
       MODIFY COLUMN status ENUM('pending','running','completed','failed') NOT NULL DEFAULT 'pending'`
  );
  await knex.raw(`ALTER TABLE backups MODIFY COLUMN error_message VARCHAR(1000) NULL DEFAULT NULL`);
}

export async function down(knex) {
  // A row left mid-dump has no pre-migration equivalent. It is recorded as
  // failed rather than pending, because that is what an interrupted backup is:
  // there is no file, and nothing is going to finish writing one.
  await knex.raw(
    `UPDATE backups
        SET status = 'failed',
            error_message = COALESCE(error_message, 'Interrupted — recorded while a dump was running.')
      WHERE status = 'running'`
  );
  await knex.raw(`UPDATE backups SET error_message = LEFT(error_message, 500) WHERE error_message IS NOT NULL`);
  await knex.raw(`ALTER TABLE backups MODIFY COLUMN error_message VARCHAR(500) NULL DEFAULT NULL`);
  await knex.raw(
    `ALTER TABLE backups
       MODIFY COLUMN status ENUM('pending','completed','failed') NOT NULL DEFAULT 'pending'`
  );
}
