import { Router } from "express";
import { z } from "zod";

import { authenticate } from "../../middleware/authenticate.js";
import { requireAccountType } from "../../middleware/requireAccountType.js";
import { authorize } from "../../middleware/authorize.js";
import { auditTrail } from "../../middleware/auditTrail.js";
import { validate } from "../../middleware/validate.js";
import { booleanSchema } from "../../validation/common.js";
import { SETTINGS } from "./catalog.js";
import { getSettings, updateSettings } from "./controller.js";

/**
 * Built from the catalogue, so a new setting needs no change here — and an
 * unknown key is rejected rather than written to a table that would happily
 * store it. `strict()` is the point: a typo'd key is a 422, not a silent no-op
 * that leaves the user certain they turned something on.
 */
const schemaForType = {
  boolean: booleanSchema,
  string: z.string().max(500),
  number: z.coerce.number(),
};

const updateSettingsSchema = z
  .object(
    Object.fromEntries(
      Object.entries(SETTINGS).map(([key, spec]) => [key, schemaForType[spec.type].optional()])
    )
  )
  .strict()
  .refine((value) => Object.keys(value).length > 0, {
    message: "Provide at least one setting to update.",
  });

export const settingsRouter = Router();
settingsRouter.use(authenticate, requireAccountType("business_user"), auditTrail("settings"));

settingsRouter.get("/", authorize("settings.view"), getSettings);
settingsRouter.patch("/", authorize("settings.edit"), validate(updateSettingsSchema), updateSettings);
