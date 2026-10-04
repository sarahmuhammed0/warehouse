#!/usr/bin/env node
// Removes rows left behind by the integration tests.
//
// Tests clean up after themselves, but a test that throws part-way through its
// own teardown does not finish — and over many runs that leaves a database full
// of businesses named "Applicant Co 1790430679237", "Tenant A", "RBAC Test", and
// in one case a working System Admin account nobody knows exists. None of it is
// real data, all of it is confusing, and the stray admin is a live credential.
//
// WHAT IT WILL AND WILL NOT TOUCH
//
// Only the reserved test phone namespace, `+1555…`, which
// `tests/integration/helpers.js` documents as "never used by real seed/dev
// data". A business created through the UI, with a real phone number, is not in
// that namespace and is never considered — which is the whole reason the
// namespace exists.
//
// It is a DRY RUN unless `--yes` is passed. Deleting business records is not
// something to do on the strength of a flag nobody read.
//
// Usage:
//   node scripts/purge-test-data.mjs          # show what would go
//   node scripts/purge-test-data.mjs --yes    # actually delete it

import { pool, closePool } from "../src/db/pool.js";

const RESET = "\u001b[0m";
const BOLD = "\u001b[1m";
const RED = "\u001b[31m";
const GREEN = "\u001b[32m";
const YELLOW = "\u001b[33m";
const DIM = "\u001b[2m";

const say = (m = "") => console.log(m); // eslint-disable-line no-console
const execute = process.argv.includes("--yes");

/** The reserved namespace, and nothing else. */
const TEST_PHONE = "+1555%";

const [businesses] = await pool.query(
  `SELECT id, name, phone FROM businesses WHERE phone LIKE ? ORDER BY id`,
  [TEST_PHONE]
);
const [users] = await pool.query(
  `SELECT id, name, phone, business_id FROM users WHERE phone LIKE ? ORDER BY id`,
  [TEST_PHONE]
);
const [admins] = await pool.query(
  `SELECT id, name, phone FROM system_admins WHERE phone LIKE ? ORDER BY id`,
  [TEST_PHONE]
);

// Users of a doomed business, even where their own phone is not a test phone —
// a business cannot be deleted while they reference its roles.
const businessIds = businesses.map((b) => b.id);
const [usersOfBusinesses] = businessIds.length
  ? await pool.query(`SELECT id, name, phone FROM users WHERE business_id IN (?)`, [businessIds])
  : [[]];

const userIds = [...new Set([...users.map((u) => u.id), ...usersOfBusinesses.map((u) => u.id)])];
const adminIds = admins.map((a) => a.id);

say(`${BOLD}Test data left behind by the integration suite${RESET}`);
say(`${DIM}  matching the reserved ${TEST_PHONE} namespace only${RESET}`);
say();

say(`businesses     ${businesses.length}`);
for (const b of businesses.slice(0, 8)) say(`  ${String(b.id).padEnd(7)} ${b.name}`);
if (businesses.length > 8) say(`  ${DIM}… and ${businesses.length - 8} more${RESET}`);

say(`users          ${userIds.length}`);
say(`system admins  ${adminIds.length}`);
for (const a of admins) {
  // Called out on its own line: this is a credential that can still sign in and
  // administer the platform.
  say(`  ${RED}${String(a.id).padEnd(7)} ${a.name} ${a.phone} — a working System Admin${RESET}`);
}

if (businesses.length === 0 && userIds.length === 0 && adminIds.length === 0) {
  say();
  say(`${GREEN}✓ Nothing to purge.${RESET}`);
  await closePool();
  process.exit(0);
}

if (!execute) {
  say();
  say(`${YELLOW}Dry run — nothing was deleted. Re-run with --yes to remove the above.${RESET}`);
  await closePool();
  process.exit(0);
}

// The order below is the one tests/integration/helpers.js uses, for the reasons
// documented there: roles before businesses because roles.business_id is
// RESTRICT, and users before roles because a user references a role.
try {
  if (userIds.length) {
    await pool.query(`DELETE FROM refresh_tokens WHERE user_id IN (?)`, [userIds]);
    await pool.query(
      `DELETE FROM login_attempts WHERE phone IN (SELECT phone FROM users WHERE id IN (?))`,
      [userIds]
    );
    await pool.query(`DELETE FROM audit_logs WHERE actor_id IN (?) AND actor_type = 'business_user'`, [userIds]);
    await pool.query(`DELETE FROM users WHERE id IN (?)`, [userIds]);
  }

  if (adminIds.length) {
    await pool.query(`DELETE FROM system_admin_refresh_tokens WHERE system_admin_id IN (?)`, [adminIds]);
    await pool.query(`DELETE FROM audit_logs WHERE actor_id IN (?) AND actor_type = 'system_admin'`, [adminIds]);
    await pool.query(`DELETE FROM system_admins WHERE id IN (?)`, [adminIds]);
  }

  if (businessIds.length) {
    await pool.query(
      `DELETE rp FROM role_permissions rp JOIN roles r ON r.id = rp.role_id WHERE r.business_id IN (?)`,
      [businessIds]
    );

    // Every table that belongs to a business, emptied of these businesses' rows
    // in whatever order the foreign keys permit.
    //
    // Self-ordering rather than a hand-written sequence, because the first
    // version was a hand-written sequence and it was wrong: it missed `products`
    // and `customers`, so the purge failed on a constraint after deleting the
    // users. The dependency graph here is 47 foreign keys deep and will grow;
    // a list maintained by hand is a list that goes stale silently.
    //
    // Each pass deletes what it can and ignores foreign-key refusals, so
    // children go before parents without anyone having to know which is which.
    // It stops when a pass achieves nothing, and what is left is then reported
    // rather than forced.
    const [owned] = await pool.query(
      `SELECT TABLE_NAME AS t FROM information_schema.COLUMNS
        WHERE TABLE_SCHEMA = DATABASE() AND COLUMN_NAME = 'business_id' AND TABLE_NAME <> 'businesses'`
    );
    let remaining = owned.map((row) => row.t);

    for (let pass = 0; pass < 12 && remaining.length > 0; pass += 1) {
      const stillBlocked = [];
      for (const table of remaining) {
        try {
          await pool.query(`DELETE FROM \`${table}\` WHERE business_id IN (?)`, [businessIds]);
        } catch (error) {
          if (error.code === "ER_ROW_IS_REFERENCED_2" || error.code === "ER_ROW_IS_REFERENCED") {
            stillBlocked.push(table);
          } else {
            throw error;
          }
        }
      }
      if (stillBlocked.length === remaining.length) break; // no progress
      remaining = stillBlocked;
    }

    if (remaining.length > 0) {
      throw new Error(
        `these tables still hold rows for the test businesses and could not be emptied: ${remaining.join(", ")}`
      );
    }

    await pool.query(`DELETE FROM businesses WHERE id IN (?)`, [businessIds]);
  }

  // Login attempts for phones that never became a user — an "unknown phone" a
  // login test tried. Invisible to the user-based delete above, and they
  // accumulate until five of them inside the lockout window make an unrelated
  // request answer 429.
  const [attempts] = await pool.query(`DELETE FROM login_attempts WHERE phone LIKE ?`, [TEST_PHONE]);

  say();
  say(`${GREEN}✓ Purged${RESET}`);
  say(`  ${businessIds.length} businesses, ${userIds.length} users, ${adminIds.length} system admins`);
  say(`  ${attempts.affectedRows} stray login attempts`);
} catch (error) {
  say();
  say(`${RED}✗ Purge failed: ${error.message}${RESET}`);
  say(`  Nothing further was deleted. A foreign key may reference one of these rows`);
  say(`  from a table this script does not know about — that is worth reading before`);
  say(`  forcing it.`);
  await closePool();
  process.exit(1);
}

await closePool();
