import { hashPassword } from "../../utils/password.js";
import { normalizePhone, isValidE164 } from "../../utils/phone.js";
import { AppError } from "../../utils/AppError.js";
import { ok, paginated } from "../../utils/responseEnvelope.js";
import { parsePagination, paginationMeta } from "../../db/pagination.js";
import { getClientIp } from "../../utils/requestInfo.js";
import { writeAuditLog } from "../auth/repository.js";
import * as repo from "./repository.js";

/** One shape for a business wherever it is returned, so clients parse once. */
function toBusinessView(row) {
  return {
    id: row.id,
    name: row.name,
    businessType: row.business_type,
    phone: row.phone,
    currency: row.currency,
    status: row.status,
    rejectionReason: row.rejection_reason ?? null,
    createdAt: row.created_at,
    approvedAt: row.approved_at ?? null,
    rejectedAt: row.rejected_at ?? null,
    owner: row.owner_id ? { id: row.owner_id, name: row.owner_name, phone: row.owner_phone } : null,
  };
}

/**
 * System-Admin-only (§16/§17 of the Phase 2 brief): the minimal endpoint
 * needed to seed a real, working business + owner account — not a
 * Business Management module. No list/update/detail endpoints exist yet.
 */
export async function createBusiness(req, res, next) {
  try {
    const { name, businessType, phone, currency, language, timezone, owner } = req.body;

    const businessPhone = normalizePhone(phone);
    const ownerPhone = normalizePhone(owner.phone);
    if (!isValidE164(businessPhone) || !isValidE164(ownerPhone)) {
      throw new AppError(
        "VALIDATION_ERROR",
        "Phone numbers must be in international format, e.g. +9647701234567.",
        422
      );
    }

    if (await repo.findPhoneInUse(ownerPhone)) {
      // Safe to be specific here (§28's validation rules) — this is an
      // authenticated System-Admin-only action, not a public/anonymous
      // endpoint, so there's no account-enumeration concern the way there
      // is on the public login form.
      throw new AppError("PHONE_IN_USE", "This phone number is already registered to a user.", 409);
    }

    const passwordHash = await hashPassword(owner.password);

    const { businessId, ownerId } = await repo.createBusinessWithOwner({
      business: {
        name,
        businessType,
        phone: businessPhone,
        currency: currency ?? "USD",
        language: language ?? "en",
        timezone: timezone ?? "UTC",
      },
      owner: { name: owner.name, phone: ownerPhone, passwordHash },
    });

    await writeAuditLog({
      businessId,
      actorType: "system_admin",
      actorId: req.auth.userId,
      module: "businesses",
      action: "business.created",
      description: `Business "${name}" created with initial owner ${ownerPhone}.`,
      ip: getClientIp(req),
      referenceType: "business",
      referenceId: businessId,
    });

    res.status(201).json(ok({ businessId, ownerId }));
  } catch (err) {
    next(err);
  }
}

/**
 * PUBLIC self-registration. Creates the business as `pending` — it cannot
 * log in until a System Admin approves it, which keeps §2's "the System
 * Admin controls who has an account" intact while letting a business ask
 * rather than wait to be created.
 *
 * Anti-enumeration matters here in a way it does not on the admin's own
 * create endpoint: this is anonymous and anyone can call it, so a specific
 * "that phone is already registered" would turn it into a tool for testing
 * whether a given number has an account. The response is therefore the same
 * whether or not the phone was already in use, and the duplicate is simply
 * not created. An applicant who really does already have an account learns
 * that by signing in.
 */
export async function registerBusiness(req, res, next) {
  try {
    const { name, businessType, phone, currency, language, timezone, owner } = req.body;

    const businessPhone = normalizePhone(phone);
    const ownerPhone = normalizePhone(owner.phone);
    if (!isValidE164(businessPhone) || !isValidE164(ownerPhone)) {
      throw new AppError(
        "VALIDATION_ERROR",
        "Phone numbers must be in international format, e.g. +9647701234567.",
        422
      );
    }

    const accepted = {
      status: "pending",
      message: "Your registration has been received and is awaiting review.",
    };

    if (await repo.findPhoneInUse(ownerPhone)) {
      await writeAuditLog({
        actorType: "system", // no authenticated actor: a public submission. actor_id stays NULL.
        module: "businesses",
        action: "business.registration_duplicate_phone",
        description: "Self-registration ignored: the owner phone is already in use.",
        ip: getClientIp(req),
      });
      // Identical body and status to the success case, deliberately.
      res.status(202).json(ok(accepted));
      return;
    }

    const passwordHash = await hashPassword(owner.password);

    const { businessId, ownerId } = await repo.createBusinessWithOwner({
      business: {
        name,
        businessType,
        phone: businessPhone,
        currency: currency ?? "USD",
        language: language ?? "en",
        timezone: timezone ?? "UTC",
      },
      owner: { name: owner.name, phone: ownerPhone, passwordHash },
      status: "pending",
    });

    await writeAuditLog({
      businessId,
      actorType: "system", // no authenticated actor: a public submission. actor_id stays NULL.
      module: "businesses",
      action: "business.registration_submitted",
      description: `Self-registration submitted for "${name}", awaiting approval.`,
      ip: getClientIp(req),
      referenceType: "business",
      referenceId: businessId,
    });

    // 202, not 201: the account exists but is not usable yet, and the client
    // must not treat this as "you can now sign in".
    res.status(202).json(ok({ ...accepted, businessId, ownerId }));
  } catch (err) {
    next(err);
  }
}

/** §2/§57: the System Admin's business list, including the approval queue. */
export async function listBusinesses(req, res, next) {
  try {
    const pagination = parsePagination(req.query);
    const { rows, total } = await repo.listBusinesses(req.query, pagination);
    res.json(paginated(rows.map(toBusinessView), paginationMeta(pagination, total)));
  } catch (err) {
    next(err);
  }
}

/** §2/§57: approve or reject a pending registration. */
function decideRegistration(decision) {
  return async function decide(req, res, next) {
    try {
      const businessId = Number(req.params.id);
      if (!Number.isInteger(businessId) || businessId < 1) {
        throw new AppError("VALIDATION_ERROR", "Invalid business id.", 422);
      }

      const business = await repo.findBusinessForReview(businessId);
      if (!business) throw new AppError("NOT_FOUND", "Business not found.", 404);

      const reason = decision === "reject" ? req.body.reason : null;
      const decided = await repo.decideRegistration({
        businessId,
        decision,
        adminId: req.auth.userId,
        reason,
      });

      // The UPDATE is guarded by `status = 'pending'`, so a false here means
      // it was already decided — by someone else, or by a double-click.
      // Reporting the current state is more useful than a bare conflict.
      if (!decided) {
        throw new AppError(
          "ALREADY_DECIDED",
          `This registration is already ${business.status} and cannot be ${decision}d again.`,
          409
        );
      }

      await writeAuditLog({
        businessId,
        actorType: "system_admin",
        actorId: req.auth.userId,
        module: "businesses",
        action: decision === "approve" ? "business.registration_approved" : "business.registration_rejected",
        description:
          decision === "approve"
            ? `Registration approved for "${business.name}".`
            : `Registration rejected for "${business.name}": ${reason}`,
        ip: getClientIp(req),
        referenceType: "business",
        referenceId: businessId,
      });

      res.json(ok(toBusinessView(await repo.findBusinessForReview(businessId))));
    } catch (err) {
      next(err);
    }
  };
}

export const approveBusiness = decideRegistration("approve");
export const rejectBusiness = decideRegistration("reject");
