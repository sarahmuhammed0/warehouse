// §23 (staff), §24 (permissions as data) and §30 (the activity log, read back).
//
// This is the module where a mistake compounds: a role that may edit users can
// grant itself everything else, and a business that disables its last owner
// cannot undo it. So most of these tests are about the refusals.

import { test, after } from "node:test";
import assert from "node:assert/strict";
import request from "supertest";

import { app } from "../../src/app.js";
import { pool, closePool, runInTransaction } from "../../src/db/pool.js";
import { createDefaultRoles, findOwnerRoleId } from "../../src/modules/rbac/repository.js";
import { OWNER_ROLE_NAME } from "../../src/modules/rbac/catalog.js";
import { signAccessToken } from "../../src/utils/token.js";
import { verifyPassword } from "../../src/utils/password.js";
import { requireDatabase, testPhone, cleanupTestData } from "./helpers.js";

async function fixture() {
  const f = await runInTransaction(async (conn) => {
    const [b] = await conn.query(
      `INSERT INTO businesses (name, business_type, phone, status) VALUES (?, 'warehouse', ?, 'active')`,
      [`Staff ${Date.now()}-${Math.random().toString(36).slice(2, 6)}`, testPhone()]
    );
    const businessId = b.insertId;
    await createDefaultRoles(conn, businessId);
    const roleId = await findOwnerRoleId(conn, businessId);

    const [u] = await conn.query(
      `INSERT INTO users (business_id, name, phone, password_hash, is_owner, role_id, status)
       VALUES (?, 'Owner', ?, 'x', TRUE, ?, 'active')`,
      [businessId, testPhone(), roleId]
    );
    return { businessId, userId: u.insertId, ownerRoleId: roleId };
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
  // The audit tests create real records in order to generate events, and the
  // business cannot be deleted while they exist — their foreign keys are
  // RESTRICT, deliberately, because a product that has been sold must not
  // vanish. Only these tests hard-delete a business, so only they unpick it.
  for (const table of [
    "audit_logs",
    "inventory_movements",
    "inventory",
    "products",
    "customers",
    "document_sequences",
    "business_settings",
  ]) {
    await pool.query(`DELETE FROM ${table} WHERE business_id = ?`, [businessId]);
  }
  const [users] = await pool.query(`SELECT id, phone FROM users WHERE business_id = ?`, [businessId]);
  if (users.length) {
    await pool.query(`DELETE FROM refresh_tokens WHERE user_id IN (?)`, [users.map((u) => u.id)]);
    await pool.query(`DELETE FROM login_attempts WHERE phone IN (?)`, [users.map((u) => u.phone)]);
    await pool.query(`DELETE FROM users WHERE business_id = ?`, [businessId]);
  }
  await pool.query(
    `DELETE rp FROM role_permissions rp JOIN roles r ON r.id = rp.role_id WHERE r.business_id = ?`,
    [businessId]
  );
  await pool.query(`DELETE FROM roles WHERE business_id = ?`, [businessId]);
  await cleanupTestData({ businessIds: [businessId] });
}

const auth = (req, token) => req.set("Authorization", `Bearer ${token}`);

const roleIdNamed = async (f, name) => {
  const [[row]] = await pool.query(`SELECT id FROM roles WHERE business_id = ? AND name = ?`, [
    f.businessId,
    name,
  ]);
  return row?.id;
};

const newUser = (f, body = {}) =>
  auth(request(app).post("/api/users"), f.token).send({
    name: "Warehouse Clerk",
    phone: testPhone(),
    roleId: f.ownerRoleId,
    ...body,
  });

// ---- §23: the staff list -------------------------------------------------

test("§23: a member of staff can be added, and gets a password to start with", async (t) => {
  if (!(await requireDatabase(t))) return;
  const f = await fixture();
  t.after(() => cleanup(f.businessId));

  const clerkRole = await roleIdNamed(f, "Warehouse Manager");
  const res = await newUser(f, { name: "Dana", email: "dana@example.com", roleId: clerkRole });

  assert.equal(res.status, 201, JSON.stringify(res.body));
  const user = res.body.data;
  assert.equal(user.name, "Dana");
  assert.equal(user.email, "dana@example.com");
  assert.equal(user.roleId, clerkRole);
  assert.equal(user.roleName, "Warehouse Manager", "the role is named, not just numbered");
  assert.equal(user.status, "active");
  assert.equal(user.isOwner, false, "only the founding account is an owner");

  // §3: the owner needs something to hand over, and it is returned exactly once.
  assert.ok(user.temporaryPassword, "a generated password must come back once");
  assert.ok(user.temporaryPassword.length >= 8);

  const [[row]] = await pool.query(`SELECT password_hash FROM users WHERE id = ?`, [user.id]);
  assert.notEqual(row.password_hash, user.temporaryPassword, "§3: never stored as plain text");
  assert.equal(
    await verifyPassword(user.temporaryPassword, row.password_hash),
    true,
    "and the hash must be of the password that was handed over"
  );

  const again = await auth(request(app).get(`/api/users/${user.id}`), f.token).send();
  assert.equal(again.status, 200);
  assert.equal(
    again.body.data.temporaryPassword,
    undefined,
    "reading the user back must never show it again"
  );
});

test("a password the caller chose is used as given", async (t) => {
  if (!(await requireDatabase(t))) return;
  const f = await fixture();
  t.after(() => cleanup(f.businessId));

  const res = await newUser(f, { password: "ChosenPassword123" });
  assert.equal(res.status, 201, JSON.stringify(res.body));
  assert.equal(res.body.data.temporaryPassword, undefined, "nothing was generated, so nothing is returned");

  const [[row]] = await pool.query(`SELECT password_hash FROM users WHERE id = ?`, [res.body.data.id]);
  assert.equal(await verifyPassword("ChosenPassword123", row.password_hash), true);
});

test("a new member of staff can actually log in with what they were given", async (t) => {
  if (!(await requireDatabase(t))) return;
  const f = await fixture();
  t.after(() => cleanup(f.businessId));

  const phone = testPhone();
  const created = await newUser(f, { phone, roleId: await roleIdNamed(f, "Sales Staff") });
  assert.equal(created.status, 201, JSON.stringify(created.body));

  // The whole point of the generated password: it has to work.
  const login = await request(app)
    .post("/api/auth/login")
    .send({ phone, password: created.body.data.temporaryPassword });
  assert.equal(login.status, 200, JSON.stringify(login.body));
  assert.ok(login.body.data.accessToken);
});

test("a duplicate phone, a bad phone, and an unknown role are each refused", async (t) => {
  if (!(await requireDatabase(t))) return;
  const f = await fixture();
  t.after(() => cleanup(f.businessId));

  const phone = testPhone();
  assert.equal((await newUser(f, { phone })).status, 201);

  const dup = await newUser(f, { phone });
  assert.equal(dup.status, 409, JSON.stringify(dup.body));
  assert.match(dup.body.error.message, /already belongs/i);
  assert.ok(!/uq_users_phone/.test(JSON.stringify(dup.body)), "§53: no constraint names in a response");

  assert.equal((await newUser(f, { phone: "07701234567" })).status, 422, "not international format");
  assert.equal((await newUser(f, { roleId: 99999999 })).status, 422, "no such role");
  assert.equal((await newUser(f, { name: "" })).status, 422);
});

test("a role from another business cannot be assigned (§36)", async (t) => {
  if (!(await requireDatabase(t))) return;
  const a = await fixture();
  const b = await fixture();
  t.after(() => Promise.all([cleanup(a.businessId), cleanup(b.businessId)]));

  const res = await newUser(b, { roleId: a.ownerRoleId });
  assert.equal(res.status, 422, JSON.stringify(res.body));
  assert.match(res.body.error.message, /does not exist/i);
});

test("staff can be edited, and their phone cannot", async (t) => {
  if (!(await requireDatabase(t))) return;
  const f = await fixture();
  t.after(() => cleanup(f.businessId));

  const created = await newUser(f, { name: "Before" });
  const id = created.body.data.id;
  const originalPhone = created.body.data.phone;

  const patched = await auth(request(app).patch(`/api/users/${id}`), f.token).send({
    name: "After",
    email: "after@example.com",
    roleId: await roleIdNamed(f, "Accountant"),
  });
  assert.equal(patched.status, 200, JSON.stringify(patched.body));
  assert.equal(patched.body.data.name, "After");
  assert.equal(patched.body.data.roleName, "Accountant");

  // The phone is the credential (§3) and the identity across every business.
  const tryPhone = await auth(request(app).patch(`/api/users/${id}`), f.token).send({
    phone: testPhone(),
  });
  assert.equal(tryPhone.status, 422, "an unknown field is not silently accepted");
  const [[row]] = await pool.query(`SELECT phone FROM users WHERE id = ?`, [id]);
  assert.equal(row.phone, originalPhone, "and the number is unchanged");

  assert.equal((await auth(request(app).patch(`/api/users/${id}`), f.token).send({})).status, 422);
});

test("disabling a user ends their sessions there and then", async (t) => {
  if (!(await requireDatabase(t))) return;
  const f = await fixture();
  t.after(() => cleanup(f.businessId));

  const phone = testPhone();
  const created = await newUser(f, { phone });
  const id = created.body.data.id;

  const login = await request(app)
    .post("/api/auth/login")
    .send({ phone, password: created.body.data.temporaryPassword });
  assert.equal(login.status, 200);
  const refreshToken = login.body.data.refreshToken;

  const [[before]] = await pool.query(`SELECT COUNT(*) AS n FROM refresh_tokens WHERE user_id = ?`, [id]);
  assert.ok(Number(before.n) >= 1, "the login left a session behind");

  const disabled = await auth(request(app).patch(`/api/users/${id}`), f.token).send({ status: "disabled" });
  assert.equal(disabled.status, 200, JSON.stringify(disabled.body));

  const [[after_]] = await pool.query(`SELECT COUNT(*) AS n FROM refresh_tokens WHERE user_id = ?`, [id]);
  assert.equal(Number(after_.n), 0, "a disabled account keeps no session");

  const reuse = await request(app).post("/api/auth/refresh").send({ refreshToken });
  assert.ok(reuse.status >= 400, "and its refresh token mints nothing further");
});

test("a business cannot lock itself out of its own account", async (t) => {
  if (!(await requireDatabase(t))) return;
  const f = await fixture();
  t.after(() => cleanup(f.businessId));

  const self = await auth(request(app).patch(`/api/users/${f.userId}`), f.token).send({
    status: "disabled",
  });
  assert.equal(self.status, 422, JSON.stringify(self.body));
  assert.match(self.body.error.message, /your own account/i);

  const selfDelete = await auth(request(app).delete(`/api/users/${f.userId}`), f.token).send();
  assert.equal(selfDelete.status, 422);

  const [[row]] = await pool.query(`SELECT status, deleted_at FROM users WHERE id = ?`, [f.userId]);
  assert.equal(row.status, "active");
  assert.equal(row.deleted_at, null);
});

test("§45: removing a member of staff archives them and frees the phone", async (t) => {
  if (!(await requireDatabase(t))) return;
  const f = await fixture();
  t.after(() => cleanup(f.businessId));

  const phone = testPhone();
  const created = await newUser(f, { phone });
  const id = created.body.data.id;

  const removed = await auth(request(app).delete(`/api/users/${id}`), f.token).send();
  assert.equal(removed.status, 200, JSON.stringify(removed.body));

  const [[row]] = await pool.query(`SELECT status, deleted_at, phone FROM users WHERE id = ?`, [id]);
  assert.ok(row.deleted_at, "§45: archived, not erased — documents still name them");
  assert.equal(row.status, "disabled");
  assert.equal(row.phone, phone, "§45: the record still says who this was");
  // Uniqueness is enforced on the generated `active_phone` column, which is NULL
  // for an archived row — so the number is free for a re-hire without the
  // record being overwritten to release it.
  const [[live]] = await pool.query(`SELECT active_phone FROM users WHERE id = ?`, [id]);
  assert.equal(live.active_phone, null, "and it stops competing for the number");

  // The list no longer shows them, and the same phone can be hired again.
  const list = await auth(request(app).get("/api/users"), f.token).send();
  assert.equal(list.body.data.some((u) => String(u.id) === String(id)), false);
  assert.equal((await newUser(f, { phone })).status, 201, "the freed number works");
});

test("users list, filter, search and tenant scope", async (t) => {
  if (!(await requireDatabase(t))) return;
  const a = await fixture();
  const b = await fixture();
  t.after(() => Promise.all([cleanup(a.businessId), cleanup(b.businessId)]));

  await newUser(a, { name: "Alpha Clerk" });
  const disabled = await newUser(a, { name: "Beta Clerk" });
  await auth(request(app).patch(`/api/users/${disabled.body.data.id}`), a.token).send({
    status: "disabled",
  });

  const all = await auth(request(app).get("/api/users?pageSize=20"), a.token).send();
  assert.equal(all.status, 200);
  assert.equal(all.body.data.length, 3, "two clerks plus the owner");
  assert.ok(Number.isInteger(all.body.meta.pagination.total));

  const active = await auth(request(app).get("/api/users?status=active"), a.token).send();
  assert.equal(active.body.data.length, 2);

  const found = await auth(request(app).get("/api/users?search=Alpha"), a.token).send();
  assert.equal(found.body.data.length, 1);
  assert.equal(found.body.data[0].name, "Alpha Clerk");

  // §36: the other business sees only its own owner.
  const other = await auth(request(app).get("/api/users"), b.token).send();
  assert.equal(other.body.data.length, 1);
  assert.equal(
    (await auth(request(app).get(`/api/users/${all.body.data[0].id}`), b.token).send()).status,
    404
  );
  assert.equal(
    (await auth(request(app).patch(`/api/users/${all.body.data[0].id}`), b.token).send({ name: "X" })).status,
    404
  );
});

test("an owner can reset a member of staff's password, ending their sessions", async (t) => {
  if (!(await requireDatabase(t))) return;
  const f = await fixture();
  t.after(() => cleanup(f.businessId));

  const phone = testPhone();
  const created = await newUser(f, { phone });
  const id = created.body.data.id;
  await request(app).post("/api/auth/login").send({ phone, password: created.body.data.temporaryPassword });

  const reset = await auth(request(app).post(`/api/users/${id}/password`), f.token).send({});
  assert.equal(reset.status, 200, JSON.stringify(reset.body));
  assert.ok(reset.body.data.temporaryPassword, "the owner needs the new one to hand over");

  const [[row]] = await pool.query(`SELECT COUNT(*) AS n FROM refresh_tokens WHERE user_id = ?`, [id]);
  assert.equal(Number(row.n), 0, "if someone else knew the old password, their session must die too");

  const old = await request(app)
    .post("/api/auth/login")
    .send({ phone, password: created.body.data.temporaryPassword });
  assert.ok(old.status >= 400, "the old password is gone");

  const fresh = await request(app)
    .post("/api/auth/login")
    .send({ phone, password: reset.body.data.temporaryPassword });
  assert.equal(fresh.status, 200, JSON.stringify(fresh.body));
});

// ---- §24: permissions as data -------------------------------------------

test("§23: a business starts with the eight roles, each with its own grants", async (t) => {
  if (!(await requireDatabase(t))) return;
  const f = await fixture();
  t.after(() => cleanup(f.businessId));

  const res = await auth(request(app).get("/api/roles"), f.token).send();
  assert.equal(res.status, 200, JSON.stringify(res.body));
  assert.equal(res.body.data.length, 8, "§23 lists eight");

  const owner = res.body.data.find((r) => r.name === OWNER_ROLE_NAME);
  assert.ok(owner.isSystemRole);
  assert.ok(owner.permissions.includes("users.edit"), "the owner administers the business");
  assert.equal(owner.userCount, 1, "and the founding account holds it");

  const viewer = res.body.data.find((r) => r.name === "Viewer");
  assert.ok(viewer.permissions.length > 0);
  assert.equal(
    viewer.permissions.every((key) => key.endsWith(".view")),
    true,
    "§23: Viewer is read-only"
  );
});

test("§24: the permission catalogue is what an editor may offer", async (t) => {
  if (!(await requireDatabase(t))) return;
  const f = await fixture();
  t.after(() => cleanup(f.businessId));

  const res = await auth(request(app).get("/api/roles/permissions"), f.token).send();
  assert.equal(res.status, 200);
  assert.ok(res.body.data.length > 20);

  const keys = res.body.data.map((p) => p.key);
  assert.ok(keys.includes("products.view"));
  assert.ok(keys.includes("financial.view"));
  assert.equal(keys.includes("reports.delete"), false, "§24: Reports has no delete");
  assert.equal(keys.includes("products.export"), false, "§24: only Reports exports");
  assert.equal(keys.includes("products.approve"), false, "§24: only Returns and Purchases approve");
  assert.ok(keys.includes("returns.approve"));

  for (const permission of res.body.data) {
    assert.match(permission.key, /^[a-z_]+\.[a-z_]+$/);
    assert.ok(permission.module && permission.action);
  }
});

test("§24: a role's permissions can be rewritten, and take effect at once", async (t) => {
  if (!(await requireDatabase(t))) return;
  const f = await fixture();
  t.after(() => cleanup(f.businessId));

  const viewerRole = await roleIdNamed(f, "Viewer");
  const phone = testPhone();
  const clerk = await newUser(f, { phone, roleId: viewerRole });
  const clerkLogin = await request(app)
    .post("/api/auth/login")
    .send({ phone, password: clerk.body.data.temporaryPassword });
  const clerkToken = clerkLogin.body.data.accessToken;

  // A Viewer may read products but not create one.
  assert.equal((await auth(request(app).get("/api/products"), clerkToken).send()).status, 200);
  assert.equal(
    (await auth(request(app).post("/api/products"), clerkToken).send({ name: "Nope" })).status,
    403
  );

  const granted = await auth(request(app).put(`/api/roles/${viewerRole}/permissions`), f.token).send({
    permissions: ["products.view", "products.create"],
  });
  assert.equal(granted.status, 200, JSON.stringify(granted.body));
  assert.deepEqual(granted.body.data.permissions.sort(), ["products.create", "products.view"]);

  // §9: permissions resolve per request, not from the token — so the same
  // token the clerk already holds now carries the new grant.
  const created = await auth(request(app).post("/api/products"), clerkToken).send({
    name: `Granted ${Math.random().toString(36).slice(2, 7)}`,
  });
  assert.equal(created.status, 201, JSON.stringify(created.body));

  // And taking it away applies just as immediately.
  await auth(request(app).put(`/api/roles/${viewerRole}/permissions`), f.token).send({
    permissions: ["products.view"],
  });
  assert.equal(
    (await auth(request(app).post("/api/products"), clerkToken).send({ name: "Nope again" })).status,
    403
  );
});

test("a permission that does not exist cannot be granted", async (t) => {
  if (!(await requireDatabase(t))) return;
  const f = await fixture();
  t.after(() => cleanup(f.businessId));

  const viewerRole = await roleIdNamed(f, "Viewer");
  const res = await auth(request(app).put(`/api/roles/${viewerRole}/permissions`), f.token).send({
    permissions: ["products.view", "products.teleport"],
  });

  assert.equal(res.status, 422, JSON.stringify(res.body));
  assert.match(res.body.error.message, /No such permission: products\.teleport/);

  // And the role is untouched — not half-written.
  const after_ = await auth(request(app).get("/api/roles"), f.token).send();
  const viewer = after_.body.data.find((r) => String(r.id) === String(viewerRole));
  assert.ok(viewer.permissions.length > 1, "the original grants survive a refused save");
});

test("the owner role cannot be narrowed, renamed or deleted", async (t) => {
  if (!(await requireDatabase(t))) return;
  const f = await fixture();
  t.after(() => cleanup(f.businessId));

  const narrowed = await auth(request(app).put(`/api/roles/${f.ownerRoleId}/permissions`), f.token).send({
    permissions: ["products.view"],
  });
  assert.equal(narrowed.status, 422, JSON.stringify(narrowed.body));

  const renamed = await auth(request(app).patch(`/api/roles/${f.ownerRoleId}`), f.token).send({
    name: "Something Else",
  });
  assert.equal(renamed.status, 422, "a built-in role keeps its name");

  const deleted = await auth(request(app).delete(`/api/roles/${f.ownerRoleId}`), f.token).send();
  assert.equal(deleted.status, 422);

  // The owner's own access is intact.
  assert.equal((await auth(request(app).get("/api/users"), f.token).send()).status, 200);
});

test("a business can add a role of its own, and describe a built-in one", async (t) => {
  if (!(await requireDatabase(t))) return;
  const f = await fixture();
  t.after(() => cleanup(f.businessId));

  const created = await auth(request(app).post("/api/roles"), f.token).send({
    name: "Night Shift",
    description: "Stock counts only",
    permissions: ["inventory.view", "inventory.edit"],
  });
  assert.equal(created.status, 201, JSON.stringify(created.body));
  assert.equal(created.body.data.isSystemRole, false);
  assert.deepEqual(created.body.data.permissions.sort(), ["inventory.edit", "inventory.view"]);

  const dup = await auth(request(app).post("/api/roles"), f.token).send({ name: "Night Shift" });
  assert.equal(dup.status, 409, JSON.stringify(dup.body));

  // A built-in role's description is editable even though its name is not.
  const described = await auth(request(app).patch(`/api/roles/${f.ownerRoleId}`), f.token).send({
    description: "Full access, as set up for us",
  });
  assert.equal(described.status, 200, JSON.stringify(described.body));
  assert.equal(described.body.data.description, "Full access, as set up for us");
});

test("a role in use cannot be deleted out from under its holders", async (t) => {
  if (!(await requireDatabase(t))) return;
  const f = await fixture();
  t.after(() => cleanup(f.businessId));

  const created = await auth(request(app).post("/api/roles"), f.token).send({
    name: "Temp Role",
    permissions: ["products.view"],
  });
  const roleId = created.body.data.id;
  const holder = await newUser(f, { roleId });

  const refused = await auth(request(app).delete(`/api/roles/${roleId}`), f.token).send();
  assert.equal(refused.status, 409, JSON.stringify(refused.body));
  assert.match(refused.body.error.message, /move them to another role/i);

  // Move the holder away, and it can go.
  await auth(request(app).patch(`/api/users/${holder.body.data.id}`), f.token).send({
    roleId: await roleIdNamed(f, "Viewer"),
  });
  assert.equal((await auth(request(app).delete(`/api/roles/${roleId}`), f.token).send()).status, 200);

  const roles = await auth(request(app).get("/api/roles"), f.token).send();
  assert.equal(roles.body.data.some((r) => String(r.id) === String(roleId)), false);
});

test("roles are tenant-scoped", async (t) => {
  if (!(await requireDatabase(t))) return;
  const a = await fixture();
  const b = await fixture();
  t.after(() => Promise.all([cleanup(a.businessId), cleanup(b.businessId)]));

  const mine = await auth(request(app).get("/api/roles"), b.token).send();
  assert.equal(mine.body.data.some((r) => String(r.id) === String(a.ownerRoleId)), false);

  assert.equal(
    (await auth(request(app).put(`/api/roles/${a.ownerRoleId}/permissions`), b.token).send({
      permissions: ["products.view"],
    })).status,
    404
  );
  assert.equal(
    (await auth(request(app).patch(`/api/roles/${a.ownerRoleId}`), b.token).send({ description: "x" })).status,
    404
  );
  assert.equal((await auth(request(app).delete(`/api/roles/${a.ownerRoleId}`), b.token).send()).status, 404);
});

test("staff management is gated on users.* — an ordinary role cannot reach it", async (t) => {
  if (!(await requireDatabase(t))) return;
  const f = await fixture();
  t.after(() => cleanup(f.businessId));

  const phone = testPhone();
  const clerk = await newUser(f, { phone, roleId: await roleIdNamed(f, "Warehouse Manager") });
  const login = await request(app)
    .post("/api/auth/login")
    .send({ phone, password: clerk.body.data.temporaryPassword });
  const clerkToken = login.body.data.accessToken;

  // §23: a Warehouse Manager runs inventory, not the staff list.
  assert.equal((await auth(request(app).get("/api/users"), clerkToken).send()).status, 403);
  assert.equal((await auth(request(app).get("/api/roles"), clerkToken).send()).status, 403);
  assert.equal(
    (await auth(request(app).put(`/api/roles/${f.ownerRoleId}/permissions`), clerkToken).send({
      permissions: [],
    })).status,
    403
  );
  assert.equal(
    (await auth(request(app).post("/api/users"), clerkToken).send({
      name: "Sneaky",
      phone: testPhone(),
      roleId: f.ownerRoleId,
    })).status,
    403
  );
  // But their own module still works.
  assert.equal((await auth(request(app).get("/api/inventory"), clerkToken).send()).status, 200);
});

// ---- §30: the activity log, read back -----------------------------------

test("§30: the activity log reads back who did what, newest first", async (t) => {
  if (!(await requireDatabase(t))) return;
  const f = await fixture();
  t.after(() => cleanup(f.businessId));

  await auth(request(app).post("/api/products"), f.token).send({
    name: `Logged ${Math.random().toString(36).slice(2, 7)}`,
  });
  await auth(request(app).post("/api/customers"), f.token).send({ name: "Logged Buyer" });

  let res;
  for (let i = 0; i < 60; i += 1) {
    res = await auth(request(app).get("/api/audit-logs"), f.token).send();
    if ((res.body.data ?? []).length >= 2) break;
    await new Promise((resolve) => setTimeout(resolve, 25));
  }

  assert.equal(res.status, 200, JSON.stringify(res.body));
  assert.ok(res.body.data.length >= 2);
  assert.ok(Number.isInteger(res.body.meta.pagination.total));

  const row = res.body.data[0];
  assert.ok(row.module, "§30 requires the module");
  assert.ok(row.action);
  assert.ok(row.description);
  assert.equal(Number(row.actorId), f.userId, "§30 requires who");
  assert.equal(row.actorName, "Owner", "and names them, not just their id");
  assert.ok(row.createdAt, "§30 requires when");

  const times = res.body.data.map((r) => new Date(r.createdAt).getTime());
  assert.deepEqual(times, [...times].sort((x, y) => y - x), "newest first");
});

test("§30: the log filters by module and by what was touched", async (t) => {
  if (!(await requireDatabase(t))) return;
  const f = await fixture();
  t.after(() => cleanup(f.businessId));

  const product = await auth(request(app).post("/api/products"), f.token).send({
    name: `Filtered ${Math.random().toString(36).slice(2, 7)}`,
  });
  await auth(request(app).post("/api/customers"), f.token).send({ name: "Filtered Buyer" });

  let products = { body: { data: [] } };
  for (let i = 0; i < 60; i += 1) {
    products = await auth(request(app).get("/api/audit-logs?module=products"), f.token).send();
    if ((products.body.data ?? []).length >= 1) break;
    await new Promise((resolve) => setTimeout(resolve, 25));
  }
  assert.ok(products.body.data.length >= 1);
  assert.equal(products.body.data.every((r) => r.module === "products"), true);

  const byRecord = await auth(
    request(app).get(`/api/audit-logs?referenceType=products&referenceId=${product.body.data.id}`),
    f.token
  ).send();
  assert.ok(byRecord.body.data.length >= 1, "a record's own history is findable");

  const actions = await auth(request(app).get("/api/audit-logs/actions"), f.token).send();
  assert.equal(actions.status, 200);
  assert.ok(actions.body.data.some((a) => a.module === "products" && a.action === "products.create"));

  const junk = await auth(request(app).get("/api/audit-logs?module=not-a-module"), f.token).send();
  assert.ok(junk.status === 200 || junk.status === 422, "junk never 500s");
});

test("§30: the log is read-only, tenant-scoped, and not for everyone", async (t) => {
  if (!(await requireDatabase(t))) return;
  const a = await fixture();
  const b = await fixture();
  t.after(() => Promise.all([cleanup(a.businessId), cleanup(b.businessId)]));

  await auth(request(app).post("/api/customers"), a.token).send({ name: "A's Buyer" });
  await new Promise((resolve) => setTimeout(resolve, 150));

  // No write path exists at all — evidence a client could add to is not evidence.
  assert.equal((await auth(request(app).post("/api/audit-logs"), a.token).send({})).status, 404);
  assert.equal((await auth(request(app).delete("/api/audit-logs/1"), a.token).send()).status, 404);

  // §36: one business never reads another's history.
  const other = await auth(request(app).get("/api/audit-logs"), b.token).send();
  assert.equal(other.status, 200);
  assert.equal(other.body.data.length, 0);

  // And an ordinary employee cannot read the whole business's activity.
  const phone = testPhone();
  const clerk = await auth(request(app).post("/api/users"), a.token).send({
    name: "Clerk",
    phone,
    roleId: (await pool.query(`SELECT id FROM roles WHERE business_id = ? AND name = 'Sales Staff'`, [a.businessId]))[0][0].id,
  });
  const login = await request(app)
    .post("/api/auth/login")
    .send({ phone, password: clerk.body.data.temporaryPassword });
  assert.equal(
    (await auth(request(app).get("/api/audit-logs"), login.body.data.accessToken).send()).status,
    403
  );
});

after(() => closePool());
