// API routing foundation. Every module adds one line here when it's built —
// this file never grows business logic itself, only mounts.

import { Router } from "express";
import { healthRouter } from "./health.routes.js";
import { authRouter } from "../modules/auth/routes.js";
import { adminAuthRouter } from "../modules/admin-auth/routes.js";
import { businessesRouter, registrationRouter } from "../modules/businesses/routes.js";

export const apiRouter = Router();

apiRouter.use("/health", healthRouter);
apiRouter.use("/auth", authRouter); // business users
apiRouter.use("/admin/auth", adminAuthRouter); // System Admins — separate router, separate identity table
apiRouter.use("/admin/businesses", businessesRouter); // System-Admin-only (see modules/businesses)
apiRouter.use("/registration", registrationRouter); // PUBLIC: business self-registration, creates a pending business

// Phase 3+ modules mount here, e.g.:
//   apiRouter.use("/products", productsRouter);
