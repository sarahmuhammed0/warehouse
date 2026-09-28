import { randomBytes } from "node:crypto";

import { ok, paginated } from "../../utils/responseEnvelope.js";
import { parsePagination, paginationMeta } from "../../db/pagination.js";
import { errors } from "../../utils/AppError.js";
import { toAppError } from "../../utils/databaseError.js";
import { runInTransaction } from "../../db/pool.js";
import { hashPassword } from "../../utils/password.js";
import { normalizePhone, isValidE164 } from "../../utils/phone.js";
import * as repo from "./repository.js";

const tenant = (req) => req.auth.businessId;

const userView = (row) => ({
  id: row.id,
  businessId: row.business_id,
  name: row.name,
  phone: row.phone,
  email: row.email,
  roleId: row.role_id,
  roleName: row.role_name ?? null,
  isOwner: Boolean(row.is_owner),
  status: row.status,
  lastLoginAt: row.last_login_at,
  createdAt: row.created_at,
  updatedAt: row.updated_at,
});

const constraintMessages = {
  // Uniqueness moved to the generated `active_phone` column so an archived user
  // stops blocking their old number (§45). Both names are mapped: the old index
  // may still exist in an environment that has not run the migration, and an
  // unmapped constraint would surface as a bare 409 with no useful message.
  uq_users_active_phone: "That phone number already belongs to a user.",
  uq_users_phone: "That phone number already belongs to a user.",
};

/**
 * A first password for an account someone else is creating.
 *
 * §23's staff list is built by an owner, who has no way to know what password
 * the employee will want — so one is generated, returned ONCE in the create
 * response for the owner to pass on, and stored only as a hash (§3). It is
 * deliberately not emailed or logged: there is no mail transport in this
 * system, and a password in a log is a password in a backup.
 */
function temporaryPassword() {
  // 9 bytes of base64url ≈ 12 characters, comfortably over the 8-character
  // minimum, with no ambiguous-looking padding.
  return randomBytes(9).toString("base64url");
}

export async function list(req, res, next) {
  try {
    const pagination = parsePagination(req.query);
    const { rows, total } = await repo.listUsers({
      businessId: tenant(req),
      query: req.query,
      pagination,
    });
    res.json(paginated(rows.map(userView), paginationMeta(pagination, total)));
  } catch (err) {
    next(err);
  }
}

export async function get(req, res, next) {
  try {
    const row = await repo.findUser({ businessId: tenant(req), id: req.params.id });
    if (!row) throw errors.notFound("user");
    res.json(ok(userView(row)));
  } catch (err) {
    next(err);
  }
}

export async function create(req, res, next) {
  try {
    const businessId = tenant(req);
    const { name, email, roleId, status } = req.body;

    const phone = normalizePhone(req.body.phone);
    if (!isValidE164(phone)) {
      throw errors.validation("The phone number must be in international format, e.g. +9647701234567.");
    }
    if (!(await repo.roleBelongsToBusiness({ businessId, roleId }))) {
      throw errors.validation("That role does not exist.");
    }

    // Sent, or generated for the owner to hand over.
    const generated = req.body.password ? null : temporaryPassword();
    const password = req.body.password ?? generated;

    const userId = await runInTransaction(async (conn) =>
      repo.createUser(conn, {
        businessId,
        name,
        phone,
        email,
        passwordHash: await hashPassword(password),
        roleId,
        status,
      })
    );

    const view = userView(await repo.findUser({ businessId, id: userId }));
    // The only moment this value exists in a response. It is not stored, and
    // re-reading the user will never return it again.
    if (generated) view.temporaryPassword = generated;
    res.status(201).json(ok(view));
  } catch (err) {
    next(toAppError(err, { constraintMessages }) ?? err);
  }
}

export async function update(req, res, next) {
  try {
    const businessId = tenant(req);
    const id = req.params.id;
    const { name, email, roleId, status } = req.body;

    const target = await repo.findUser({ businessId, id });
    if (!target) throw errors.notFound("user");

    if (roleId !== undefined && !(await repo.roleBelongsToBusiness({ businessId, roleId }))) {
      throw errors.validation("That role does not exist.");
    }

    const disabling = status === "disabled" && target.status !== "disabled";
    if (disabling) {
      // Two ways a business can lock itself out of its own account, both worth
      // refusing rather than explaining afterwards.
      if (String(target.id) === String(req.auth.userId)) {
        throw errors.validation("You cannot disable your own account.");
      }
      if (
        Boolean(target.is_owner) &&
        !(await repo.hasAnotherActiveOwner({ businessId, exceptId: target.id }))
      ) {
        throw errors.validation("This is the only active owner — promote someone else first.");
      }
    }

    await runInTransaction(async (conn) => {
      const affected = await repo.updateUser(conn, {
        businessId,
        id,
        fields: { name, email, roleId, status },
      });
      if (affected === 0) throw errors.notFound("user");

      // A disabled account must lose the sessions it already holds. Without
      // this, the access token in its browser keeps working until it expires,
      // and its refresh token keeps minting new ones for a month.
      if (disabling) await repo.revokeRefreshTokens(conn, { userId: id });
    });

    res.json(ok(userView(await repo.findUser({ businessId, id }))));
  } catch (err) {
    next(toAppError(err, { constraintMessages }) ?? err);
  }
}

/**
 * §45: archived, never erased. Every document the user created still names
 * them, and history that forgets who did something is not an audit trail.
 */
export async function remove(req, res, next) {
  try {
    const businessId = tenant(req);
    const id = req.params.id;

    const target = await repo.findUser({ businessId, id });
    if (!target) throw errors.notFound("user");
    if (String(target.id) === String(req.auth.userId)) {
      throw errors.validation("You cannot remove your own account.");
    }
    if (
      Boolean(target.is_owner) &&
      !(await repo.hasAnotherActiveOwner({ businessId, exceptId: target.id }))
    ) {
      throw errors.validation("This is the only active owner — promote someone else first.");
    }

    await runInTransaction(async (conn) => {
      const affected = await repo.softDeleteUser(conn, { businessId, id });
      if (affected === 0) throw errors.notFound("user");
      await repo.revokeRefreshTokens(conn, { userId: id });
    });

    res.json(ok({ id: Number(id), deleted: true }));
  } catch (err) {
    next(toAppError(err) ?? err);
  }
}

/**
 * An owner resetting a member of staff's password — the case §3's self-service
 * change-password endpoint cannot serve, because the person who forgot it
 * cannot sign in to change it.
 *
 * Every session is revoked: if the reason for the reset is that someone else
 * had the old password, leaving their session alive defeats the reset.
 */
export async function resetPassword(req, res, next) {
  try {
    const businessId = tenant(req);
    const id = req.params.id;

    const target = await repo.findUser({ businessId, id });
    if (!target) throw errors.notFound("user");

    const generated = req.body.password ? null : temporaryPassword();
    const password = req.body.password ?? generated;
    const passwordHash = await hashPassword(password);

    await runInTransaction(async (conn) => {
      const affected = await repo.updateUser(conn, { businessId, id, fields: { passwordHash } });
      if (affected === 0) throw errors.notFound("user");
      await repo.revokeRefreshTokens(conn, { userId: id });
    });

    res.json(ok({ id: Number(id), ...(generated ? { temporaryPassword: generated } : {}) }));
  } catch (err) {
    next(toAppError(err) ?? err);
  }
}
