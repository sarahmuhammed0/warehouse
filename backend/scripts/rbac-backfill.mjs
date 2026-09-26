// Gives §23's default roles to businesses that predate them, and assigns
// the owner role to each business's initial administrator.
//
// Needed because roles were added after businesses already existed: those
// businesses have no roles, so every permission check for their users
// denies — which is the correct default, but leaves them unable to work.
//
// Idempotent. A business that already has roles is skipped, and a user who
// already has a role is left alone: this must never silently re-assign a
// role an administrator chose deliberately.
//
// Run: npm run rbac:backfill   (from backend/)

import { pool, closePool, runInTransaction } from "../src/db/pool.js";
import { createDefaultRoles, findOwnerRoleId, businessesWithoutRoles } from "../src/modules/rbac/repository.js";

const pending = await businessesWithoutRoles();

if (pending.length === 0) {
  console.log("Every business already has roles — nothing to do.");
} else {
  console.log(`${pending.length} business(es) without roles:`);
  for (const business of pending) {
    await runInTransaction(async (conn) => {
      await createDefaultRoles(conn, business.id);
      const ownerRoleId = await findOwnerRoleId(conn, business.id);

      // Only users who have no role at all. `WHERE role_id IS NULL` is the
      // whole safety property of this script.
      const [result] = await conn.query(
        `UPDATE users SET role_id = ?
          WHERE business_id = ? AND is_owner = TRUE AND role_id IS NULL AND deleted_at IS NULL`,
        [ownerRoleId, business.id]
      );
      console.log(`  ${business.name} (id ${business.id}) — roles created, ${result.affectedRows} owner assigned`);
    });
  }
}

// Report anyone still without a role: they can sign in but can do nothing,
// and an administrator needs to know rather than discover it from a
// confused user.
const [orphans] = await pool.query(
  `SELECT u.id, u.name, u.phone, b.name AS business
     FROM users u JOIN businesses b ON b.id = u.business_id
    WHERE u.role_id IS NULL AND u.deleted_at IS NULL`
);
if (orphans.length > 0) {
  console.log(`\n${orphans.length} user(s) still have no role and can do nothing until assigned one:`);
  for (const u of orphans) console.log(`  ${u.name} (${u.phone}) at ${u.business}`);
} else {
  console.log("\nEvery user has a role.");
}

await closePool();
