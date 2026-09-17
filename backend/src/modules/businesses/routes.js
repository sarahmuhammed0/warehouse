import { Router } from "express";

import { authenticate } from "../../middleware/authenticate.js";
import { requireAccountType } from "../../middleware/requireAccountType.js";
import { validate } from "../../middleware/validate.js";
import { createBusinessSchema } from "./validation.js";
import { createBusiness } from "./controller.js";

export const businessesRouter = Router();

businessesRouter.post(
  "/",
  authenticate,
  requireAccountType("system_admin"),
  validate(createBusinessSchema),
  createBusiness
);
