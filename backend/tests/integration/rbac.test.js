// §23/§24 against the real database: a business gets its roles, a user's
// permissions resolve through them, and a user without a role can do
// nothing.
//
// The "can do nothing" case is the one worth proving. It is the safe
// default, but only if it is actually what happens — a resolution bug that
// returned every permission for a roleless user would be invisible until
// someone exploited it.

import { test, after } from "node:test";
import assert from "node:assert/strict";

import { pool, closePool, runInTransaction } from "../../src/db/pool.js";
import { createDefaultRoles, findOwnerRoleId, permissionsForUser } from "../../src/modules/rbac/repository.js";
import { DEFAULT_ROLES, allPermissionKeys, OWNER_ROLE_NAME } from "../../src/modules/rbac/catalog.js";
import * as businesses from "../../src/modules/businesses/repository.js";
import { requireDatabase, testPhone, cleanupTestData } from "./helpers.js";

async function dropBusiness(businessId) {
  if (!businessId) return;
  const [users] = await pool.query(`SELECT id FROM users WHERE business_id = ?`, [businessId]);
  // role_permissions and roles cascade from businesses; users must go first.
  await cleanupTestData({ businessIds: [businessId], userIds: users.map((u) => u.id) });
}

test("the permission catalogue is in the database, complete", async (t) => {
  if (!(await requireDatabase(t))) return;

  const [rows] = await pool.query(`SELECT permission_key FROM permissions`);
  const inDatabase = new Set(rows.map((r) => r.permission_key));

  const missing = allPermissionKeys().filter((key) => !inDatabase.has(key));
  assert.deepEqual(missing, [], `the catalogue migration did not seed: ${missing.join(", ")}`);
});

test("creating a business creates its roles, in the same transaction", async (t) => {
  if (!(await requireDatabase(t))) return;

  const { businessId, ownerId } = await businesses.createBusinessWithOwner({
    business: {
      name: `RBAC Test ${Date.now()}`,
      businessType: "warehouse",
      phone: testPhone(),
      currency: "IQD",
      language: "en",
      timezone: "UTC",
    },
    owner: { name: "RBAC Owner", phone: testPhone(), passwordHash: "x" },
  });
  t.after(() => dropBusiness(businessId));

  const [roles] = await pool.query(`SELECT name, is_system FROM roles WHERE business_id = ?`, [businessId]);
  assert.equal(roles.length, DEFAULT_ROLES.length, "§23's roles should all exist");
  assert.ok(roles.every((r) => r.is_system === 1), "platform-created roles are marked is_system");

  // The initial administrator (§3) must be able to work immediately.
  const [[owner]] = await pool.query(
    `SELECT r.name AS role FROM users u JOIN roles r ON r.id = u.role_id WHERE u.id = ?`,
    [ownerId]
  );
  assert.equal(owner?.role, OWNER_ROLE_NAME, "the first user must get the owner role");

  const permissions = await permissionsForUser(ownerId);
  assert.equal(permissions.length, allPermissionKeys().length, "§23: the owner has full access");
});

test("a user with no role resolves to no permissions, never to all of them", async (t) => {
  if (!(await requireDatabase(t))) return;

  const businessId = await runInTransaction(async (conn) => {
    const [r] = await conn.query(
      `INSERT INTO businesses (name, business_type, phone, status) VALUES (?, 'custom', ?, 'active')`,
      [`NoRole ${Date.now()}`, testPhone()]
    );
    return r.insertId;
  });
  t.after(() => dropBusiness(businessId));

  const [user] = await pool.query(
    `INSERT INTO users (business_id, name, phone, password_hash, is_owner, status)
     VALUES (?, 'Roleless', ?, 'x', FALSE, 'active')`,
    [businessId, testPhone()]
  );

  const permissions = await permissionsForUser(user.insertId);
  assert.deepEqual(permissions, [], "no role must mean no permissions");
});

test("a soft-deleted role stops granting its permissions", async (t) => {
  if (!(await requireDatabase(t))) return;

  // Archiving a role must revoke it. If the resolution query ignored
  // deleted_at, a role an administrator had removed would keep working.
  const businessId = await runInTransaction(async (conn) => {
    const [r] = await conn.query(
      `INSERT INTO businesses (name, business_type, phone, status) VALUES (?, 'custom', ?, 'active')`,
      [`RoleDel ${Date.now()}`, testPhone()]
    );
    await createDefaultRoles(conn, r.insertId);
    return r.insertId;
  });
  t.after(() => dropBusiness(businessId));

  const roleId = await runInTransaction((conn) => findOwnerRoleId(conn, businessId));
  const [user] = await pool.query(
    `INSERT INTO users (business_id, name, phone, password_hash, is_owner, role_id, status)
     VALUES (?, 'Owner', ?, 'x', TRUE, ?, 'active')`,
    [businessId, testPhone(), roleId]
  );

  assert.ok((await permissionsForUser(user.insertId)).length > 0, "should start with permissions");

  await pool.query(`UPDATE roles SET deleted_at = NOW() WHERE id = ?`, [roleId]);
  assert.deepEqual(await permissionsForUser(user.insertId), [], "an archived role must grant nothing");
});

test("roles are per business — one tenant's role never reaches another", async (t) => {
  if (!(await requireDatabase(t))) return;

  // §36. Roles are business-owned, so the same role NAME in two businesses
  // must be two different rows granting independently.
  const made = [];
  for (const label of ["A", "B"]) {
    const { businessId } = await businesses.createBusinessWithOwner({
      business: {
        name: `Tenant ${label} ${Date.now()}`,
        businessType: "warehouse",
        phone: testPhone(),
        currency: "USD",
        language: "en",
        timezone: "UTC",
      },
      owner: { name: `Owner ${label}`, phone: testPhone(), passwordHash: "x" },
    });
    made.push(businessId);
  }
  t.after(async () => {
    for (const id of made) await dropBusiness(id);
  });

  const [rows] = await pool.query(
    `SELECT business_id, id FROM roles WHERE business_id IN (?) AND name = ?`,
    [made, OWNER_ROLE_NAME]
  );
  assert.equal(rows.length, 2, "each business gets its own owner role");
  assert.notEqual(rows[0].id, rows[1].id, "they must not be the same row");
});

test("creating roles twice for one business is a no-op, not a duplicate", async (t) => {
  if (!(await requireDatabase(t))) return;

  // The backfill has to be safe to re-run.
  const businessId = await runInTransaction(async (conn) => {
    const [r] = await conn.query(
      `INSERT INTO businesses (name, business_type, phone, status) VALUES (?, 'custom', ?, 'active')`,
      [`Idem ${Date.now()}`, testPhone()]
    );
    await createDefaultRoles(conn, r.insertId);
    await createDefaultRoles(conn, r.insertId);
    return r.insertId;
  });
  t.after(() => dropBusiness(businessId));

  const count = (await pool.query(`SELECT COUNT(*) AS n FROM roles WHERE business_id = ?`, [businessId]))[0][0].n;
  assert.equal(Number(count), DEFAULT_ROLES.length, "roles must not be duplicated");

  const [[grants]] = await pool.query(
    `SELECT COUNT(*) AS n FROM role_permissions rp JOIN roles r ON r.id = rp.role_id WHERE r.business_id = ?`,
    [businessId]
  );
  const expected = DEFAULT_ROLES.reduce((sum, r) => sum + r.permissions.length, 0);
  assert.equal(Number(grants.n), expected, "grants must not be duplicated either");
});

after(async () => {
  await closePool();
});
