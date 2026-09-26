import { test } from "node:test";
import assert from "node:assert/strict";
import {
  ACTIONS,
  MODULES,
  supports,
  buildCatalog,
  allPermissionKeys,
  DEFAULT_ROLES,
  OWNER_ROLE_NAME,
} from "../../src/modules/rbac/catalog.js";

test("the catalogue offers §24's six actions and no others", () => {
  assert.deepEqual(ACTIONS, ["view", "create", "edit", "delete", "approve", "export"]);
});

test("§24's action restrictions are honoured", () => {
  // The specification pairs Export only with Reports and Approve only with
  // the two modules that have an approval step. Granting products.export
  // would be offering a capability the software does not have.
  assert.deepEqual(
    buildCatalog().filter((p) => p.action === "export").map((p) => p.key),
    ["reports.export"]
  );
  assert.deepEqual(
    buildCatalog().filter((p) => p.action === "approve").map((p) => p.key).sort(),
    ["purchases.approve", "returns.approve"]
  );

  // Reports and Settings have nothing to delete.
  assert.ok(!supports("reports", "delete"));
  assert.ok(!supports("settings", "delete"));

  // "View Financial Information" (§24) is a visibility flag, not a module.
  assert.deepEqual(
    buildCatalog().filter((p) => p.module === "financial").map((p) => p.key),
    ["financial.view"]
  );
});

test("every module supports view, so nothing is invisible to every role", () => {
  for (const module of MODULES) {
    assert.ok(supports(module, "view"), `${module} cannot be viewed by anyone`);
  }
});

test("permission keys are unique and shaped {module}.{action}", () => {
  const keys = allPermissionKeys();
  assert.equal(new Set(keys).size, keys.length, "duplicate permission key");
  for (const key of keys) {
    assert.match(key, /^[a-z]+\.[a-z]+$/, `malformed key: ${key}`);
  }
});

test("every default role grants only permissions that exist", () => {
  // A grant for a key not in the catalogue is a permission nobody can ever
  // hold: it fails closed, but silently, and the UI would show a checkbox
  // that does nothing.
  const known = new Set(allPermissionKeys());
  for (const role of DEFAULT_ROLES) {
    const unknown = role.permissions.filter((p) => !known.has(p));
    assert.deepEqual(unknown, [], `${role.name} grants unknown permission(s): ${unknown.join(", ")}`);
  }
});

test("§23's eight roles exist, each with a distinct name", () => {
  const names = DEFAULT_ROLES.map((r) => r.name);
  assert.equal(names.length, 8);
  assert.equal(new Set(names).size, 8, "duplicate role name");
  for (const expected of [
    "Business Owner/Admin",
    "Manager",
    "Warehouse Manager",
    "Sales Staff",
    "Inventory Staff",
    "Production Manager",
    "Accountant",
    "Viewer",
  ]) {
    assert.ok(names.includes(expected), `§23 lists "${expected}" but the catalogue does not`);
  }
});

test("the owner role has full access — §23's 'Full access to their business'", () => {
  const owner = DEFAULT_ROLES.find((r) => r.name === OWNER_ROLE_NAME);
  assert.ok(owner);
  assert.equal(
    owner.permissions.length,
    allPermissionKeys().length,
    "the owner role must hold every permission that exists"
  );
});

test("no role except the owner gets settings or users management by default", () => {
  // §23: "Do NOT give every user full access." Manage Users and Manage
  // Settings (§24) are the two that hand over control of the business
  // itself, so they are not handed out casually.
  for (const role of DEFAULT_ROLES) {
    if (role.name === OWNER_ROLE_NAME) continue;
    const elevated = role.permissions.filter((p) => p.startsWith("users.") || p.startsWith("settings."));
    assert.deepEqual(elevated, [], `${role.name} should not manage users or settings by default`);
  }
});

test("Viewer is read-only — it holds no action other than view", () => {
  const viewer = DEFAULT_ROLES.find((r) => r.name === "Viewer");
  const writes = viewer.permissions.filter((p) => !p.endsWith(".view"));
  assert.deepEqual(writes, [], "a read-only role must not be able to change anything");
});

test("only the Accountant sees financial information by default", () => {
  const withFinancial = DEFAULT_ROLES.filter((r) => r.permissions.includes("financial.view")).map((r) => r.name);
  assert.deepEqual(withFinancial.sort(), ["Accountant", OWNER_ROLE_NAME].sort());
});
