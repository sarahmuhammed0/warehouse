import { hashPassword } from "../../utils/password.js";
import { normalizePhone, isValidE164 } from "../../utils/phone.js";
import { AppError } from "../../utils/AppError.js";
import { ok } from "../../utils/responseEnvelope.js";
import { getClientIp } from "../../utils/requestInfo.js";
import { writeAuditLog } from "../auth/repository.js";
import * as repo from "./repository.js";

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
