// Logging foundation (Phase 0).
//
// One logger instance, used everywhere via import — no module reaches for
// `console.log` directly. Structured JSON in production (so it's parseable
// by whatever log pipeline is added later); pretty-printed in development.

import pino from "pino";
import { env } from "../config/env.js";

export const logger = pino({
  level: env.logging.level,
  transport: env.isDevelopment
    ? {
        target: "pino-pretty",
        options: { colorize: true, translateTime: "HH:MM:ss", ignore: "pid,hostname" },
      }
    : undefined,
});
