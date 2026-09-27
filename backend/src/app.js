// Express app assembly (architecture §3's middleware chain, Phase 0 slice of
// it): security headers → CORS → rate limiting → body parsing → request
// logging → routes → 404 → centralized error handler. Nothing business-
// specific lives in this file.

import express from "express";
import cors from "cors";
import helmet from "helmet";
import rateLimit from "express-rate-limit";
import pinoHttp from "pino-http";

import { env } from "./config/env.js";
import { logger } from "./utils/logger.js";
import { apiRouter } from "./routes/index.js";
import { notFound } from "./middleware/notFound.js";
import { errorHandler } from "./middleware/errorHandler.js";

export const app = express();

app.use(helmet());
app.use(
  cors({
    origin: env.server.corsOrigin,
    credentials: true,
  })
);

// Global rate limit — a first, coarse layer. A tighter, dedicated limiter
// sits on /api/auth/*/login specifically (modules/auth/routes.js,
// modules/admin-auth/routes.js) since that's the endpoint most worth
// slowing down for credential-stuffing.
app.use(
  rateLimit({
    windowMs: 60 * 1000,
    limit: env.api.rateLimitPerMinute,
    standardHeaders: true,
    legacyHeaders: false,
  })
);

app.use(express.json({ limit: "1mb" }));
app.use(pinoHttp({ logger, autoLogging: env.isDevelopment }));

app.use("/api", apiRouter);

app.use(notFound);
app.use(errorHandler);
