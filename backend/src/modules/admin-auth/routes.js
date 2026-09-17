// System Admin authentication — a SEPARATE router from
// modules/auth/routes.js (mounted at /api/admin/auth/*, not /api/auth/*),
// reusing the same generic controller factory + shared authService, but
// bound to systemAdminAdapter so it only ever queries `system_admins`
// (never `users`). See docs/authentication.md "System Admin isolation."

import { Router } from "express";
import rateLimit from "express-rate-limit";

import { validate } from "../../middleware/validate.js";
import { authenticate } from "../../middleware/authenticate.js";
import { requireAccountType } from "../../middleware/requireAccountType.js";
import { loginSchema, changePasswordSchema, refreshSchema } from "../auth/validation.js";
import { makeAuthController } from "../auth/controller.js";
import { systemAdminAdapter } from "../auth/accountAdapters.js";

const loginLimiter = rateLimit({
  windowMs: 15 * 60 * 1000,
  limit: 20,
  standardHeaders: true,
  legacyHeaders: false,
  message: { success: false, error: { code: "RATE_LIMITED", message: "Too many requests. Please try again later." } },
});

export const adminAuthRouter = Router();
const controller = makeAuthController(systemAdminAdapter);

adminAuthRouter.post("/login", loginLimiter, validate(loginSchema), controller.login);
adminAuthRouter.post("/refresh", validate(refreshSchema), controller.refresh);
adminAuthRouter.post("/logout", controller.logout);
adminAuthRouter.get("/me", authenticate, requireAccountType("system_admin"), controller.me);
adminAuthRouter.post(
  "/change-password",
  authenticate,
  requireAccountType("system_admin"),
  validate(changePasswordSchema),
  controller.changePassword
);
