import { Router } from "express";
import rateLimit from "express-rate-limit";

import { validate } from "../../middleware/validate.js";
import { authenticate } from "../../middleware/authenticate.js";
import { requireAccountType } from "../../middleware/requireAccountType.js";
import { loginSchema, changePasswordSchema, refreshSchema } from "./validation.js";
import { makeAuthController } from "./controller.js";
import { businessUserAdapter } from "./accountAdapters.js";

// Stricter than the app-wide limiter (app.js) specifically on login — the
// endpoint most worth slowing down for credential-stuffing/brute-force
// (§13). This is IP-scoped and independent of the phone-scoped account
// lockout in authService.login; the two work together (an attacker
// rotating phones is slowed by this, one rotating IPs is slowed by that).
const loginLimiter = rateLimit({
  windowMs: 15 * 60 * 1000,
  limit: 20,
  standardHeaders: true,
  legacyHeaders: false,
  message: { success: false, error: { code: "RATE_LIMITED", message: "Too many requests. Please try again later." } },
});

export const authRouter = Router();
const controller = makeAuthController(businessUserAdapter);

authRouter.post("/login", loginLimiter, validate(loginSchema), controller.login);
authRouter.post("/refresh", validate(refreshSchema), controller.refresh);
authRouter.post("/logout", controller.logout);
authRouter.get("/me", authenticate, requireAccountType("business_user"), controller.me);
authRouter.post(
  "/change-password",
  authenticate,
  requireAccountType("business_user"),
  validate(changePasswordSchema),
  controller.changePassword
);
