// The role and permissions handed to a session (§24), so the CLIENT can stop
// offering what the server will refuse.
//
// This is UX, not authorization: `middleware/authorize.js` still re-reads a
// user's grants on every request, which is what makes a revoked permission
// take effect immediately. These tests exist because the two could drift —
// a sidebar built from a stale or wrong list would offer screens that 403, or
// hide ones that would have worked.

import { test, after } from "node:test";
import assert from "node:assert/strict";
import request from "supertest";

import { app } from "../../src/app.js";
import { pool, closePool, runInTransaction } from "../../src/db/pool.js";
import { createDefaultRoles, findOwnerRoleId, roleForUser } from "../../src/modules/rbac/repository.js";
import { signAccessToken } from "../../src/utils/token.js";
import { hashPassword } from "../../src/utils/password.js";
import { requireDatabase, testPhone, cleanupTestData } from "./helpers.js";

const PASSWORD = "RolePayload123";

async function fixture({ roleName } = {}) {
  const f = await runInTransaction(async (conn) => {
    const [b] = await conn.query(
      `INSERT INTO businesses (name, business_type, phone, status) VALUES (?, 'warehouse', ?, 'active')`,
      [`RolePayload ${Date.now()}-${Math.random().toString(36).slice(2, 6)}`, testPhone()]
    );
    const businessId = b.insertId;
    await createDefaultRoles(conn, businessId);

    let roleId = await findOwnerRoleId(conn, businessId);
    if (roleName) {
      const [rows] = await conn.query(
        `SELECT id FROM roles WHERE business_id = ? AND name = ? LIMIT 1`,
        [businessId, roleName]
      );
      assert.ok(rows.length, `the seeded role "${roleName}" should exist`);
      roleId = rows[0].id;
    }

    const phone = testPhone();
    const [u] = await conn.query(
      `INSERT INTO users (business_id, name, phone, password_hash, is_owner, role_id, status)
       VALUES (?, 'Member', ?, ?, ?, ?, 'active')`,
      [businessId, phone, await hashPassword(PASSWORD), roleName ? false : true, roleId]
    );
    return { businessId, userId: u.insertId, roleId, phone };
  });

  f.token = signAccessToken({
    accountType: "business_user",
    userId: f.userId,
    businessId: f.businessId,
  });
  return f;
}

async function cleanup(businessId) {
  if (!businessId) return;
  const [users] = await pool.query(`SELECT id, phone FROM users WHERE business_id = ?`, [businessId]);
  if (users.length) {
    await pool.query(`DELETE FROM refresh_tokens WHERE user_id IN (?)`, [users.map((u) => u.id)]);
    await pool.query(`DELETE FROM login_attempts WHERE phone IN (?)`, [users.map((u) => u.phone)]);
  }
  await pool.query(`DELETE FROM audit_logs WHERE business_id = ?`, [businessId]);
  await pool.query(`DELETE FROM users WHERE business_id = ?`, [businessId]);
  await pool.query(
    `DELETE rp FROM role_permissions rp JOIN roles r ON r.id = rp.role_id WHERE r.business_id = ?`,
    [businessId]
  );
  await pool.query(`DELETE FROM roles WHERE business_id = ?`, [businessId]);
  await cleanupTestData({ businessIds: [businessId] });
}

test("login and /me both carry the role, so the UI can gate before its first request", async (t) => {
  if (!(await requireDatabase(t))) return;
  const f = await fixture();
  try {
    const login = await request(app)
      .post("/api/auth/login")
      .send({ phone: f.phone, password: PASSWORD })
      .expect(200);

    assert.ok(login.body.data.role, "login should carry the role");
    assert.equal(login.body.data.role.id, f.roleId);
    assert.ok(
      login.body.data.role.permissions.includes("users.view"),
      "an owner holds users.view"
    );

    const me = await request(app)
      .get("/api/auth/me")
      .set("Authorization", `Bearer ${login.body.data.accessToken}`)
      .expect(200);

    assert.deepEqual(
      me.body.data.role.permissions.sort(),
      login.body.data.role.permissions.sort(),
      "a session restore must resolve the same grants as the sign-in did"
    );
  } finally {
    await cleanup(f.businessId);
  }
});

test("the access token still carries no permissions — this is a lookup, not a claim", async (t) => {
  if (!(await requireDatabase(t))) return;
  const f = await fixture();
  try {
    const login = await request(app)
      .post("/api/auth/login")
      .send({ phone: f.phone, password: PASSWORD })
      .expect(200);

    const payload = JSON.parse(
      Buffer.from(login.body.data.accessToken.split(".")[1], "base64url").toString("utf8")
    );

    // §8's minimal claims. A token that carried its grants would keep them
    // until it expired — up to fifteen minutes of access after an
    // administrator revoked them.
    assert.equal(payload.permissions, undefined);
    assert.equal(payload.role, undefined);
    assert.equal(payload.roleId, undefined);
  } finally {
    await cleanup(f.businessId);
  }
});

test("a revoked permission is gone from the next /me, not held until logout", async (t) => {
  if (!(await requireDatabase(t))) return;
  const f = await fixture();
  try {
    const before = await request(app)
      .get("/api/auth/me")
      .set("Authorization", `Bearer ${f.token}`)
      .expect(200);
    assert.ok(before.body.data.role.permissions.includes("products.delete"));

    await pool.query(
      `DELETE rp FROM role_permissions rp
         JOIN permissions p ON p.id = rp.permission_id
        WHERE rp.role_id = ? AND p.permission_key = 'products.delete'`,
      [f.roleId]
    );

    const after = await request(app)
      .get("/api/auth/me")
      .set("Authorization", `Bearer ${f.token}`)
      .expect(200);
    assert.ok(!after.body.data.role.permissions.includes("products.delete"));
  } finally {
    await cleanup(f.businessId);
  }
});

test("the three navigation-only keys are derived from what the server enforces", async (t) => {
  if (!(await requireDatabase(t))) return;

  // The client's sidebar gates Dashboard, Documents and Activity History on
  // keys no endpoint checks, because they are screens assembled from other
  // modules. Granting them to everyone would offer Activity History to a role
  // whose /api/audit-logs request then 403s.
  const owner = await fixture();
  const sales = await fixture({ roleName: "Sales Staff" });
  try {
    const ownerRole = await roleForUser(owner.userId);
    const salesRole = await roleForUser(sales.userId);

    // Dashboard composes from whatever its reader may already see.
    assert.ok(ownerRole.permissions.includes("dashboard.view"));
    assert.ok(salesRole.permissions.includes("dashboard.view"));

    // Documents lists orders.
    assert.ok(salesRole.permissions.includes("orders.view"), "Sales Staff reads orders");
    assert.ok(salesRole.permissions.includes("documents.view"));

    // Activity History IS /api/audit-logs, which is gated on settings.view.
    assert.ok(ownerRole.permissions.includes("settings.view"));
    assert.ok(ownerRole.permissions.includes("audit.view"));
    assert.ok(!salesRole.permissions.includes("settings.view"), "Sales Staff holds no settings");
    assert.ok(
      !salesRole.permissions.includes("audit.view"),
      "so the sidebar must not offer them Activity History"
    );
  } finally {
    await cleanup(owner.businessId);
    await cleanup(sales.businessId);
  }
});

test("a role that grants nothing returns an empty list, not null and not one null key", async (t) => {
  if (!(await requireDatabase(t))) return;
  const f = await fixture();
  try {
    // roleForUser LEFT JOINs the grants so that a role with none still resolves
    // — an inner join would return no rows and read as "this user has no role
    // at all", which the client treats as unrestricted. That is the one way
    // this lookup could hand a stripped role the whole application.
    await pool.query(`DELETE FROM role_permissions WHERE role_id = ?`, [f.roleId]);

    const role = await roleForUser(f.userId);

    assert.ok(role, "the role itself still resolves");
    assert.equal(role.id, f.roleId);
    assert.deepEqual(
      role.permissions,
      ["dashboard.view"],
      "only the key derived for everyone — and no null among them"
    );
    assert.ok(!role.permissions.includes(null));
  } finally {
    await cleanup(f.businessId);
  }
});

test("GET /api/roles does not leak the derived keys into the permission editor", async (t) => {
  if (!(await requireDatabase(t))) return;
  const f = await fixture();
  try {
    const response = await request(app)
      .get("/api/roles")
      .set("Authorization", `Bearer ${f.token}`)
      .expect(200);

    const keys = response.body.data.flatMap((role) => role.permissions);
    // A checkbox for a key the server does not store would be unsaveable —
    // PUT /roles/:id/permissions refuses a key that is not in the catalogue.
    for (const derived of ["dashboard.view", "documents.view", "audit.view"]) {
      assert.ok(!keys.includes(derived), `${derived} must not appear in the editor's list`);
    }
  } finally {
    await cleanup(f.businessId);
  }
});

test("a System Admin has no business-scoped role, and is told so explicitly", async (t) => {
  if (!(await requireDatabase(t))) return;

  const phone = testPhone();
  const [admin] = await pool.query(
    `INSERT INTO system_admins (name, phone, password_hash, status) VALUES ('Ops', ?, ?, 'active')`,
    [phone, await hashPassword(PASSWORD)]
  );
  try {
    const login = await request(app)
      .post("/api/admin/auth/login")
      .send({ phone, password: PASSWORD })
      .expect(200);

    // Null, not an empty list: an empty list would read as "a role that grants
    // nothing", and the client restricts against that.
    assert.equal(login.body.data.role, null);
  } finally {
    await pool.query(`DELETE FROM system_admin_refresh_tokens WHERE system_admin_id = ?`, [admin.insertId]);
    await pool.query(`DELETE FROM login_attempts WHERE phone = ?`, [phone]);
    await pool.query(`DELETE FROM audit_logs WHERE actor_id = ? AND actor_type = 'system_admin'`, [
      admin.insertId,
    ]);
    await pool.query(`DELETE FROM system_admins WHERE id = ?`, [admin.insertId]);
  }
});

after(() => closePool());
