// Health check foundation (Phase 0's explicit deliverable).
//
// Two separate checks, deliberately not merged into one:
//  - GET /api/health      liveness only — "is the Node process up." Never
//                          touches the database, so it can't be dragged down
//                          by a slow/unreachable MySQL.
//  - GET /api/health/db   readiness — "can the backend actually reach MySQL."
//                          A down database is a normal, expected 503 here,
//                          not a crash and not a 500.

import { Router } from "express";
import { ok, fail } from "../utils/responseEnvelope.js";
import { checkDatabaseConnection } from "../db/pool.js";
import { env } from "../config/env.js";

export const healthRouter = Router();

healthRouter.get("/", (req, res) => {
  res.json(
    ok({
      status: "ok",
      service: "warehouse-os-backend",
      environment: env.nodeEnv,
      uptimeSeconds: Math.round(process.uptime()),
      timestamp: new Date().toISOString(),
    })
  );
});

healthRouter.get("/db", async (req, res) => {
  const result = await checkDatabaseConnection();

  if (!result.reachable) {
    return res
      .status(503)
      .json(fail("DATABASE_UNREACHABLE", "Backend cannot reach MySQL right now."));
  }

  res.json(
    ok({
      status: "ok",
      engine: "mysql",
      version: result.version,
      host: result.host,
      port: result.port,
      database: result.database,
    })
  );
});
