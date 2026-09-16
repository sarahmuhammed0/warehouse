// Auth token foundation (architecture §8). Not called from anywhere yet —
// Phase 1's login/refresh endpoints are the first real callers. Kept as
// plain functions around `jsonwebtoken` so the signing/verification logic
// exists in exactly one place before any route depends on it.

import jwt from "jsonwebtoken";
import { env } from "../config/env.js";
import { AppError } from "./AppError.js";

function requireSecret() {
  if (!env.auth.jwtSecret) {
    // A deliberately loud failure — this must never be reached with an
    // empty secret outside local Phase-0 development, where no route calls
    // it yet. Production startup already refuses to boot without one
    // (see config/env.js).
    throw new AppError("AUTH_NOT_CONFIGURED", "JWT_SECRET is not configured.", 500);
  }
}

/** @param {object} payload - e.g. { userId, businessId, role } (architecture §8) */
export function signAccessToken(payload) {
  requireSecret();
  return jwt.sign(payload, env.auth.jwtSecret, { expiresIn: env.auth.accessTokenTtl });
}

export function verifyAccessToken(token) {
  requireSecret();
  try {
    return jwt.verify(token, env.auth.jwtSecret);
  } catch {
    throw new AppError("INVALID_TOKEN", "Session is invalid or has expired.", 401);
  }
}
