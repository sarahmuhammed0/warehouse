// Shared login/refresh/logout/me/change-password logic — written once,
// used by both `/api/auth/*` (businessUserAdapter) and
// `/api/admin/auth/*` (systemAdminAdapter). See docs/authentication.md for
// the full flow diagrams and the reasoning behind every decision below.

import bcrypt from "bcryptjs";
import { verifyPassword, hashPassword } from "../../utils/password.js";
import { signAccessToken, generateRefreshToken, hashRefreshToken } from "../../utils/token.js";
import { normalizePhone, isValidE164 } from "../../utils/phone.js";
import { AppError } from "../../utils/AppError.js";
import { logger } from "../../utils/logger.js";
import * as repo from "./repository.js";
import { findBusinessById } from "./repository.js";
import { roleForUser } from "../rbac/repository.js";

const LOCKOUT_THRESHOLD = 5; // consecutive failures
const LOCKOUT_WINDOW_MINUTES = 15; // ...within this many minutes
const REFRESH_TOKEN_TTL_MS = 30 * 24 * 60 * 60 * 1000; // 30 days, matches env default

// A real bcrypt hash of an arbitrary constant string, generated once at
// module load (not hand-typed — a malformed hash would make bcrypt.compare
// throw instead of returning false). Compared against on an "unknown
// phone" login so the response takes roughly the same time as a real
// password check — otherwise a faster response for unknown phones would
// itself be an enumeration side-channel (architecture §7's anti-
// enumeration rule, applied to timing, not just response content).
const DUMMY_HASH = bcrypt.hashSync("no-such-account-timing-equalizer", 12);

const GENERIC_INVALID_CREDENTIALS = "Invalid phone number or password.";

function safeAccount(account) {
  return { id: account.id, name: account.name, phone: account.phone };
}

export async function login(adapter, { phone: rawPhone, password, ip, userAgent }) {
  const phone = normalizePhone(rawPhone);
  if (!isValidE164(phone)) {
    // Same generic message as a real mismatch — a malformed phone isn't
    // told apart from "wrong credentials" either.
    throw new AppError("INVALID_CREDENTIALS", GENERIC_INVALID_CREDENTIALS, 401);
  }

  const recentFailures = await repo.countRecentFailedAttempts({
    accountType: adapter.accountType,
    phone,
    sinceMinutesAgo: LOCKOUT_WINDOW_MINUTES,
  });
  if (recentFailures >= LOCKOUT_THRESHOLD) {
    // Deliberately phone-scoped, not account-scoped (§13/§58): this check
    // runs identically whether or not `phone` resolves to a real account,
    // so a lockout response never itself reveals account existence.
    throw new AppError(
      "TOO_MANY_ATTEMPTS",
      `Too many failed attempts. Try again in ${LOCKOUT_WINDOW_MINUTES} minutes.`,
      429
    );
  }

  const account = await adapter.findByPhone(phone);

  const passwordToCheck = account?.password_hash ?? DUMMY_HASH;
  const passwordOk = await verifyPassword(password, passwordToCheck);

  if (!account || !passwordOk) {
    await repo.recordLoginAttempt({ accountType: adapter.accountType, phone, success: false, ip });
    if (!account) {
      // No account row exists — nothing to attribute this to in the audit
      // trail beyond "someone tried this phone."
      await repo.writeAuditLog({
        actorType: adapter.accountType,
        action: "auth.login_failed",
        description: `Login failed for unrecognized phone (${adapter.accountType}).`,
        ip,
      });
    } else {
      await repo.writeAuditLog({
        businessId: adapter.businessIdFor(account),
        actorType: adapter.accountType,
        actorId: account.id,
        action: "auth.login_failed",
        description: "Login failed: incorrect password.",
        ip,
      });
    }
    throw new AppError("INVALID_CREDENTIALS", GENERIC_INVALID_CREDENTIALS, 401);
  }

  // Password is now proven correct — safe to reveal richer status
  // (§7's "safe to disambiguate only after proof of knowledge").
  if (account.status !== "active") {
    await repo.recordLoginAttempt({ accountType: adapter.accountType, phone, success: false, ip });
    await repo.writeAuditLog({
      businessId: adapter.businessIdFor(account),
      actorType: adapter.accountType,
      actorId: account.id,
      action: "auth.login_blocked",
      description: "Login blocked: account is disabled.",
      ip,
    });
    throw new AppError("ACCOUNT_DISABLED", "This account has been disabled. Contact your administrator.", 403);
  }

  let business = null;
  if (adapter.accountType === "business_user") {
    business = await findBusinessById(account.business_id);
    if (!business || business.status !== "active") {
      // Only `active` gets in. The status tells the owner of a
      // self-registered business something genuinely useful — whether they
      // are waiting, or were turned down — and saying "disabled" for all
      // three is both wrong and unhelpful.
      //
      // This is reached only AFTER the password has been verified above, so
      // it cannot be used to discover which phone numbers have accounts —
      // the same rule the disabled-account branch follows (§58).
      const blocked = {
        pending: {
          code: "BUSINESS_PENDING_APPROVAL",
          message: "Your registration is still awaiting approval. You will be able to sign in once it is approved.",
          audit: "Login blocked: business registration is awaiting approval.",
        },
        rejected: {
          code: "BUSINESS_REJECTED",
          message: business?.rejection_reason
            ? `Your registration was not approved: ${business.rejection_reason}`
            : "Your registration was not approved. Contact the platform administrator.",
          audit: "Login blocked: business registration was rejected.",
        },
      }[business?.status] ?? {
        code: "BUSINESS_DISABLED",
        message: "This business account has been disabled.",
        audit: "Login blocked: business is disabled.",
      };

      await repo.recordLoginAttempt({ accountType: adapter.accountType, phone, success: false, ip });
      await repo.writeAuditLog({
        businessId: account.business_id,
        actorType: adapter.accountType,
        actorId: account.id,
        action: "auth.login_blocked",
        description: blocked.audit,
        ip,
      });
      throw new AppError(blocked.code, blocked.message, 403);
    }
  }

  const businessId = adapter.businessIdFor(account);
  const accessToken = signAccessToken({
    accountType: adapter.accountType,
    userId: account.id,
    businessId,
  });

  const rawRefreshToken = generateRefreshToken();
  await adapter.createRefreshToken({
    subjectId: account.id,
    tokenHash: hashRefreshToken(rawRefreshToken),
    expiresAt: new Date(Date.now() + REFRESH_TOKEN_TTL_MS),
    ip,
    userAgent,
  });

  await adapter.updateLastLogin(account.id);
  await repo.recordLoginAttempt({ accountType: adapter.accountType, phone, success: true, ip });
  await repo.writeAuditLog({
    businessId,
    actorType: adapter.accountType,
    actorId: account.id,
    action: "auth.login_success",
    description: "Login succeeded.",
    ip,
  });

  return {
    accessToken,
    refreshToken: rawRefreshToken,
    account: safeAccount(account),
    business: business ? safeBusiness(business) : null,
    // Handed over at sign-in so the client can gate its own navigation
    // straight away, rather than having to make a second call before it can
    // draw anything. See roleForUser for why this is not a weakening of §8's
    // minimal token claims.
    role: adapter.accountType === "business_user" ? await roleForUser(account.id) : null,
  };
}

export async function refresh(adapter, { rawToken, ip, userAgent }) {
  if (!rawToken) throw new AppError("INVALID_TOKEN", "Refresh token is required.", 401);

  const tokenHash = hashRefreshToken(rawToken);
  const record = await adapter.findRefreshTokenByHash(tokenHash);

  if (!record) throw new AppError("INVALID_TOKEN", "Session is invalid or has expired.", 401);

  if (record.revoked_at) {
    // Reuse of an already-rotated (or already-logged-out) refresh token —
    // treated as a possible theft signal, not just "expired": every
    // active session for this subject is revoked defensively.
    logger.warn(
      { subjectId: record.subjectId, accountType: adapter.accountType },
      "Revoked refresh token reused — revoking all sessions for this subject"
    );
    await adapter.revokeAllRefreshTokens(record.subjectId);
    throw new AppError("INVALID_TOKEN", "Session is invalid or has expired.", 401);
  }

  if (new Date(record.expires_at).getTime() < Date.now()) {
    throw new AppError("INVALID_TOKEN", "Session is invalid or has expired.", 401);
  }

  const account = await adapter.findById(record.subjectId);
  if (!account || account.status !== "active") {
    throw new AppError("INVALID_TOKEN", "Session is invalid or has expired.", 401);
  }

  const businessId = adapter.businessIdFor(account);

  // Rotation: the presented token is revoked and replaced, never reused.
  const rawRefreshToken = generateRefreshToken();
  const newId = await adapter.createRefreshToken({
    subjectId: account.id,
    tokenHash: hashRefreshToken(rawRefreshToken),
    expiresAt: new Date(Date.now() + REFRESH_TOKEN_TTL_MS),
    ip,
    userAgent,
  });
  await adapter.revokeRefreshToken(record.id, newId);

  const accessToken = signAccessToken({ accountType: adapter.accountType, userId: account.id, businessId });

  return { accessToken, refreshToken: rawRefreshToken };
}

export async function logout(adapter, rawToken) {
  if (!rawToken) return; // idempotent — logging out with no/garbage token is a no-op, not an error
  const record = await adapter.findRefreshTokenByHash(hashRefreshToken(rawToken));
  if (record && !record.revoked_at) {
    await adapter.revokeRefreshToken(record.id);
    await repo.writeAuditLog({
      actorType: adapter.accountType,
      actorId: record.subjectId,
      action: "auth.logout",
      description: "Logout.",
    });
  }
}

export async function me(adapter, subjectId) {
  const account = await adapter.findById(subjectId);
  if (!account) throw new AppError("NOT_FOUND", "Account not found.", 404);

  let business = null;
  if (adapter.accountType === "business_user") {
    business = await findBusinessById(account.business_id);
  }

  return {
    account: safeAccount(account),
    business: business ? safeBusiness(business) : null,
    // Re-read on every /me, so a role edited while someone is signed in
    // reaches their UI on the next session restore rather than only at logout.
    role: adapter.accountType === "business_user" ? await roleForUser(account.id) : null,
  };
}

export async function changePassword(adapter, subjectId, { currentPassword, newPassword }, ip) {
  const currentHash = await adapter.findPasswordHash(subjectId);
  if (!currentHash) throw new AppError("NOT_FOUND", "Account not found.", 404);

  const currentOk = await verifyPassword(currentPassword, currentHash);
  if (!currentOk) {
    throw new AppError("INVALID_CREDENTIALS", "Current password is incorrect.", 401);
  }

  const newHash = await hashPassword(newPassword);
  await adapter.updatePasswordHash(subjectId, newHash);
  // Changing a password invalidates every other session — standard
  // practice: a compromised session shouldn't survive a password change.
  await adapter.revokeAllRefreshTokens(subjectId);

  await repo.writeAuditLog({
    actorType: adapter.accountType,
    actorId: subjectId,
    action: "auth.password_changed",
    description: "Password changed.",
    ip,
  });
}

function safeBusiness(business) {
  return {
    id: business.id,
    name: business.name,
    businessType: business.business_type,
    logoUrl: business.logo_url,
    currency: business.currency,
    language: business.language,
    timezone: business.timezone,
    status: business.status,
  };
}
