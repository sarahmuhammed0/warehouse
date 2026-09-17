// Auth token foundation (architecture §8, finalized in Phase 2 — see
// docs/authentication.md for the full architecture writeup).
//
// Two different token shapes, deliberately:
//  - Access token: a JWT. Short-lived (15m default), stateless, verified
//    with no DB hit on every request — exactly what an access token is
//    for. Claims are minimal on purpose (§8 of the Phase 2 brief: "never
//    put sensitive information inside JWT claims") — just enough to
//    resolve WHO is calling and WHICH tenant, nothing else. No role or
//    permission claims: RBAC doesn't exist yet, and even once it does,
//    permissions are re-checked against the database per request, never
//    trusted from a token the client could have held for minutes.
//  - Refresh token: NOT a JWT. A random opaque string, stored server-side
//    only as its SHA-256 hash (`refresh_tokens.token_hash` /
//    `system_admin_refresh_tokens.token_hash`) — never the raw value. This
//    is deliberately different from the access token because a refresh
//    token needs to be revocable (logout, rotation, compromise) — a JWT's
//    whole value proposition (stateless verification) is the wrong
//    property here; a refresh token's whole value proposition is that the
//    server can invalidate it on command, which requires a database row.

import crypto from "node:crypto";
import jwt from "jsonwebtoken";
import { env } from "../config/env.js";
import { AppError } from "./AppError.js";

function requireSecret() {
  if (!env.auth.jwtSecret) {
    throw new AppError("AUTH_NOT_CONFIGURED", "JWT_SECRET is not configured.", 500);
  }
}

/** @param {{ accountType: 'business_user'|'system_admin', userId: number, businessId: number|null }} payload */
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

/** 256 bits of randomness, hex-encoded — the raw refresh token handed to the client. */
export function generateRefreshToken() {
  return crypto.randomBytes(32).toString("hex");
}

/** SHA-256 of the raw token — the only form ever written to the database. */
export function hashRefreshToken(rawToken) {
  return crypto.createHash("sha256").update(rawToken).digest("hex");
}
