import { Router } from "express";
import rateLimit from "express-rate-limit";

import { env } from "../../config/env.js";

import { authenticate } from "../../middleware/authenticate.js";
import { requireAccountType } from "../../middleware/requireAccountType.js";
import { validate } from "../../middleware/validate.js";
import { createBusinessSchema, registerBusinessSchema, rejectBusinessSchema } from "./validation.js";
import {
  createBusiness,
  registerBusiness,
  listBusinesses,
  approveBusiness,
  rejectBusiness,
} from "./controller.js";

// ---- System-Admin-only (§2/§57) ------------------------------------------

export const businessesRouter = Router();

// Every route here is gated twice: authenticated, and specifically a System
// Admin. A business user's token must not reach the approval queue — see
// tests/integration/tenant-isolation.test.js.
businessesRouter.use(authenticate, requireAccountType("system_admin"));

businessesRouter.get("/", listBusinesses);
businessesRouter.post("/", validate(createBusinessSchema), createBusiness);
businessesRouter.post("/:id/approve", approveBusiness);
businessesRouter.post("/:id/reject", validate(rejectBusinessSchema), rejectBusiness);

// ---- Public self-registration --------------------------------------------

export const registrationRouter = Router();

/**
 * Stricter than the app-wide limiter and deliberately so: this endpoint is
 * unauthenticated and it WRITES, which is the combination worth protecting.
 * Without it, one script could fill the administrator's approval queue with
 * thousands of pending businesses — a denial of service against a human
 * rather than the server.
 *
 * Counted per IP over an hour. The limit comes from config (strict in
 * production, lenient in development) — see env.js's `registration` block.
 */
const registrationLimiter = rateLimit({
  windowMs: 60 * 60 * 1000,
  limit: env.registration.rateLimitPerHour,
  standardHeaders: true,
  legacyHeaders: false,
  message: {
    success: false,
    error: {
      code: "RATE_LIMITED",
      message: "Too many registration attempts. Please try again later.",
    },
  },
});

registrationRouter.post("/", registrationLimiter, validate(registerBusinessSchema), registerBusiness);
