import { z } from "zod";

const BUSINESS_TYPES = [
  "furniture_factory",
  "general_factory",
  "warehouse",
  "storage_store",
  "wholesale_store",
  "distribution_center",
  "custom",
];

// Minimal fields only (§16 of the Phase 2 brief: "do not invent an
// unnecessary business onboarding workflow") — enough to satisfy §2's
// required business-account fields plus one initial administrator, not
// the full business-profile form (logo upload, tax/registration details,
// etc. are all nullable columns a later Business Settings phase fills in).
/**
 * Public self-registration. Deliberately the SAME shape as the
 * System-Admin-created business below, minus nothing: a business applying
 * for an account must supply exactly what an administrator would have typed
 * on its behalf, so approving is a decision rather than a data-entry job.
 *
 * `status` is not accepted from the client — a registration is always
 * created `pending`, and the only way out of that is an administrator's
 * decision. Accepting it here would let anyone self-approve.
 */
export const registerBusinessSchema = z.object({
  name: z.string().trim().min(1, "Business name is required.").max(150),
  businessType: z.enum(BUSINESS_TYPES),
  phone: z.string().trim().min(1, "Business phone is required."),
  currency: z.string().trim().length(3).optional(),
  language: z.string().trim().min(2).max(10).optional(),
  timezone: z.string().trim().min(1).max(64).optional(),
  owner: z.object({
    name: z.string().trim().min(1, "Owner name is required.").max(150),
    phone: z.string().trim().min(1, "Owner phone is required."),
    password: z.string().min(8, "Owner password must be at least 8 characters."),
  }),
});

/** Why a registration was refused — shown to the applicant, so required. */
export const rejectBusinessSchema = z.object({
  reason: z.string().trim().min(1, "A reason is required.").max(500),
});

export const createBusinessSchema = z.object({
  name: z.string().trim().min(1, "Business name is required.").max(150),
  businessType: z.enum(BUSINESS_TYPES),
  phone: z.string().trim().min(1, "Business phone is required."),
  currency: z.string().trim().length(3).optional(),
  language: z.string().trim().min(2).max(10).optional(),
  timezone: z.string().trim().min(1).max(64).optional(),
  owner: z.object({
    name: z.string().trim().min(1, "Owner name is required.").max(150),
    phone: z.string().trim().min(1, "Owner phone is required."),
    password: z.string().min(8, "Owner password must be at least 8 characters."),
  }),
});
