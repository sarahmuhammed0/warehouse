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
  // Never let a password, token, or Authorization header reach a log line
  // (Phase 2 §19/§27/§33) — applied globally so this holds regardless of
  // which module logs a request/error object, not just the auth module.
  // `censor: undefined` removes the key entirely rather than printing
  // "[Redacted]", so its mere presence/length can't leak anything either.
  redact: {
    paths: [
      "req.headers.authorization",
      "req.headers.cookie",
      "*.password",
      "*.currentPassword",
      "*.newPassword",
      "*.passwordHash",
      "*.password_hash",
      "*.accessToken",
      "*.refreshToken",
      "*.token",
    ],
    censor: undefined,
    remove: true,
  },
});
