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
