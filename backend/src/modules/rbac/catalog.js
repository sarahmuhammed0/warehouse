/**
 * The permission catalogue and the default roles — §23 and §24.
 *
 * This file is the single definition of what permissions EXIST. It is
 * deliberately code rather than rows typed into a database: a permission
 * only means something if some endpoint checks for it, so the catalogue and
 * the code that enforces it have to change together. What a *business*
 * grants to whom is data (`roles` + `role_permissions`) and is editable at
 * runtime — §24's "permissions should be configurable" is about the grants,
 * not about inventing capabilities the software does not have.
 *
 * It mirrors the Flutter client's `PermissionCatalog`
 * (`features/employees/data/employee_models.dart`) exactly. Where the two
 * disagree the backend wins, because the backend is what actually refuses a
 * request — but they must not disagree, or the UI will offer a checkbox that
 * grants nothing.
 */

/** §24's six actions, verbatim. */
export const ACTIONS = ["view", "create", "edit", "delete", "approve", "export"];

/**
 * The modules permissions are expressed over.
 *
 * `users`, `settings` and `financial` are §24's three standalone
 * permissions — "Manage Users", "Manage Settings", "View Financial
 * Information" — modelled as modules so the whole catalogue has one shape.
 * `financial` is not really a module: it is a visibility flag over monetary
 * figures other modules already display, which is why it supports only
 * `view`.
 */
export const MODULES = [
  "products",
  "categories",
  "inventory",
  "sales",
  "orders",
  "customers",
  "suppliers",
  "purchases",
  "returns",
  "production",
  "reports",
  "users",
  "settings",
  "financial",
];

/**
 * Not every module supports every action — §24's own list pairs Export only
 * with Reports and Approve only with Returns. Matches the client's
 * `PermissionCatalog.supports` decision for decision.
 */
export function supports(module, action) {
  if (module === "financial") return action === "view";
  if (action === "approve") return module === "returns" || module === "purchases";
  if (action === "export") return module === "reports";
  if (action === "delete") return module !== "reports" && module !== "settings";
  return true;
}

const LABELS = {
  view: "View",
  create: "Create",
  edit: "Edit",
  delete: "Delete",
  approve: "Approve",
  export: "Export",
};

/** `{ key, module, action, description }` for every permission that exists. */
export function buildCatalog() {
  const rows = [];
  for (const module of MODULES) {
    for (const action of ACTIONS) {
      if (!supports(module, action)) continue;
      rows.push({
        key: `${module}.${action}`,
        module,
        action,
        // §24's own phrasing: "View Products", "Export Reports".
        description: `${LABELS[action]} ${module}`,
      });
    }
  }
  return rows;
}

/** Every permission key, for validating a grant before it is written. */
export function allPermissionKeys() {
  return buildCatalog().map((p) => p.key);
}

const every = (module) => ACTIONS.filter((a) => supports(module, a)).map((a) => `${module}.${a}`);
const some = (module, actions) => actions.filter((a) => supports(module, a)).map((a) => `${module}.${a}`);

/**
 * §23's eight example roles and what each one starts with.
 *
 * These are DEFAULTS, not a ceiling: §24 requires permissions to be
 * configurable, so a business can edit any of these afterwards. `isSystem`
 * marks them as created by the platform rather than by the business —
 * it does not make them read-only.
 *
 * The reasoning behind each grant is recorded in
 * docs/roles-and-permissions.md §C/§E; the short version is that §23 gives
 * each role one line of description and this is that line expressed as
 * module/action pairs.
 */
export const DEFAULT_ROLES = [
  {
    name: "Business Owner/Admin",
    description: "Full access to their business.",
    // "Full access" (§23) — every permission that exists, including
    // financial, users and settings.
    permissions: MODULES.flatMap(every),
  },
  {
    name: "Manager",
    description: "Can manage most business operations.",
    permissions: [
      ...["products", "inventory", "sales", "orders", "customers", "suppliers", "purchases"].flatMap((m) =>
        some(m, ["view", "create", "edit"])
      ),
      ...some("categories", ["view", "create", "edit"]),
      ...some("reports", ["view"]),
    ],
  },
  {
    name: "Warehouse Manager",
    description: "Inventory, products, transfers, stock.",
    permissions: [
      ...["products", "inventory", "categories"].flatMap((m) => some(m, ["view", "create", "edit", "delete"])),
      ...some("sales", ["view"]),
      ...some("orders", ["view"]),
    ],
  },
  {
    name: "Sales Staff",
    description: "Sales and customers.",
    permissions: [
      ...["sales", "orders", "customers"].flatMap((m) => some(m, ["view", "create", "edit"])),
      ...some("products", ["view"]),
    ],
  },
  {
    name: "Inventory Staff",
    description: "Stock operations.",
    permissions: [...some("inventory", ["view", "edit"]), ...some("products", ["view"])],
  },
  {
    name: "Production Manager",
    description: "Production and materials.",
    permissions: [
      ...some("production", ["view", "create", "edit", "delete"]),
      ...some("inventory", ["view"]),
      ...some("products", ["view"]),
    ],
  },
  {
    name: "Accountant",
    description: "Financial records and reports.",
    permissions: [
      ...some("reports", ["view", "export"]),
      ...some("purchases", ["view", "approve"]),
      ...some("sales", ["view"]),
      ...some("orders", ["view"]),
      // §24's "View Financial Information" — the one role that gets it by
      // default, since financial records are the job.
      "financial.view",
    ],
  },
  {
    name: "Viewer",
    description: "Read-only access.",
    // Read-only across the operational modules. Deliberately NOT
    // financial.view: §24 names it separately, and defaulting every
    // read-only user into seeing money is a rule the specification does not
    // state either way — it is one grant away if a business wants it.
    permissions: MODULES.filter((m) => m !== "financial" && m !== "users" && m !== "settings").map(
      (m) => `${m}.view`
    ),
  },
];

/** The role a business's first user gets — §3's initial administrator. */
export const OWNER_ROLE_NAME = "Business Owner/Admin";
