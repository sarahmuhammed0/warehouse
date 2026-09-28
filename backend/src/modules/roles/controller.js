import { ok } from "../../utils/responseEnvelope.js";
import { errors } from "../../utils/AppError.js";
import { toAppError } from "../../utils/databaseError.js";
import { runInTransaction } from "../../db/pool.js";
import { OWNER_ROLE_NAME } from "../rbac/catalog.js";
import * as repo from "./repository.js";

const tenant = (req) => req.auth.businessId;

const roleView = (row) => ({
  id: row.id,
  name: row.name,
  description: row.description,
  isSystemRole: Boolean(row.is_system),
  permissions: row.permissions ?? [],
  userCount: Number(row.user_count ?? 0),
  createdAt: row.created_at,
  updatedAt: row.updated_at,
});

const constraintMessages = {
  uq_roles_business_name: "A role with that name already exists.",
};

export async function list(req, res, next) {
  try {
    const roles = await repo.listRoles({ businessId: tenant(req) });
    res.json(ok(roles.map(roleView)));
  } catch (err) {
    next(err);
  }
}

/** §24's catalogue — what a permission editor can offer, and nothing more. */
export async function catalogue(req, res, next) {
  try {
    const rows = await repo.listPermissions();
    res.json(
      ok(
        rows.map((row) => ({
          key: row.permission_key,
          module: row.module,
          action: row.action,
          description: row.description,
        }))
      )
    );
  } catch (err) {
    next(err);
  }
}

export async function create(req, res, next) {
  try {
    const businessId = tenant(req);
    const { name, description, permissions = [] } = req.body;

    const unknown = await repo.unknownPermissionKeys(permissions);
    if (unknown.length) {
      throw errors.validation(`No such permission: ${unknown.join(", ")}.`);
    }

    const roleId = await runInTransaction(async (conn) => {
      const id = await repo.createRole(conn, { businessId, name, description });
      await repo.replacePermissions(conn, { roleId: id, keys: permissions });
      return id;
    });

    const roles = await repo.listRoles({ businessId });
    res.status(201).json(ok(roleView(roles.find((r) => String(r.id) === String(roleId)))));
  } catch (err) {
    next(toAppError(err, { constraintMessages }) ?? err);
  }
}

export async function rename(req, res, next) {
  try {
    const businessId = tenant(req);
    const id = req.params.id;

    const role = await repo.findRole({ businessId, id });
    if (!role) throw errors.notFound("role");

    // §23's eight roles are the vocabulary the rest of the system refers to —
    // the owner role by name, when a business is created. Renaming one would
    // leave that lookup pointing at nothing, so a system role keeps its name
    // and may only have its description changed.
    if (Boolean(role.is_system) && req.body.name !== undefined && req.body.name !== role.name) {
      throw errors.validation("A built-in role cannot be renamed.");
    }

    const affected = await runInTransaction((conn) =>
      repo.renameRole(conn, { businessId, id, name: req.body.name, description: req.body.description })
    );
    if (affected === 0) throw errors.notFound("role");

    const roles = await repo.listRoles({ businessId });
    res.json(ok(roleView(roles.find((r) => String(r.id) === String(id)))));
  } catch (err) {
    next(toAppError(err, { constraintMessages }) ?? err);
  }
}

/**
 * §24's "permissions are data, not code": what a role may do is a row set, and
 * this is the endpoint that writes it.
 */
export async function setPermissions(req, res, next) {
  try {
    const businessId = tenant(req);
    const id = req.params.id;
    const keys = [...new Set(req.body.permissions)];

    const role = await repo.findRole({ businessId, id });
    if (!role) throw errors.notFound("role");

    // The owner role is what a business falls back on to administer itself. A
    // grid saved with a box accidentally unticked would quietly remove the only
    // account that could tick it again.
    if (role.name === OWNER_ROLE_NAME) {
      throw errors.validation("The owner role always holds every permission and cannot be narrowed.");
    }

    const unknown = await repo.unknownPermissionKeys(keys);
    if (unknown.length) {
      throw errors.validation(`No such permission: ${unknown.join(", ")}.`);
    }

    await runInTransaction((conn) => repo.replacePermissions(conn, { roleId: id, keys }));

    const roles = await repo.listRoles({ businessId });
    res.json(ok(roleView(roles.find((r) => String(r.id) === String(id)))));
  } catch (err) {
    next(toAppError(err) ?? err);
  }
}

export async function remove(req, res, next) {
  try {
    const businessId = tenant(req);
    const id = req.params.id;

    const role = await repo.findRole({ businessId, id });
    if (!role) throw errors.notFound("role");
    if (Boolean(role.is_system)) {
      throw errors.validation("A built-in role cannot be deleted.");
    }

    // Deleting a role out from under its holders would leave them with no
    // permissions at all — `permissionsForUser` resolves an empty list, which
    // denies everything. Better to say so than to silently lock people out.
    const holders = await repo.usersInRole({ businessId, roleId: id });
    if (holders > 0) {
      throw errors.conflict(
        `${holders} ${holders === 1 ? "user holds" : "users hold"} this role — move them to another role first.`
      );
    }

    const affected = await runInTransaction((conn) => repo.softDeleteRole(conn, { businessId, id }));
    if (affected === 0) throw errors.notFound("role");

    res.json(ok({ id: Number(id), deleted: true }));
  } catch (err) {
    next(toAppError(err) ?? err);
  }
}
