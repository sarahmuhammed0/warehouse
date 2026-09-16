// API routing foundation. Every module adds one line here when it's built —
// this file never grows business logic itself, only mounts.

import { Router } from "express";
import { healthRouter } from "./health.routes.js";

export const apiRouter = Router();

apiRouter.use("/health", healthRouter);

// Phase 1+ modules mount here, e.g.:
//   apiRouter.use("/auth", authRouter);
//   apiRouter.use("/products", productsRouter);
