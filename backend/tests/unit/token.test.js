import { test } from "node:test";
import assert from "node:assert/strict";
import {
  signAccessToken,
  verifyAccessToken,
  generateRefreshToken,
  hashRefreshToken,
} from "../../src/utils/token.js";
import { AppError } from "../../src/utils/AppError.js";

test("signAccessToken/verifyAccessToken round-trip the payload", () => {
  const token = signAccessToken({ accountType: "business_user", userId: 42, businessId: 7 });
  const payload = verifyAccessToken(token);
  assert.equal(payload.accountType, "business_user");
  assert.equal(payload.userId, 42);
  assert.equal(payload.businessId, 7);
});

test("verifyAccessToken rejects a garbage token", () => {
  assert.throws(() => verifyAccessToken("not-a-real-token"), (err) => {
    assert.ok(err instanceof AppError);
    assert.equal(err.statusCode, 401);
    return true;
  });
});

test("verifyAccessToken rejects a token signed with a different secret", () => {
  // A structurally-valid JWT (three base64url segments) that this app's
  // secret never produced — must fail signature verification.
  const forged =
    "eyJhbGciOiJIUzI1NiJ9.eyJhY2NvdW50VHlwZSI6InN5c3RlbV9hZG1pbiIsInVzZXJJZCI6MX0.invalidsignature";
  assert.throws(() => verifyAccessToken(forged));
});

test("access token payload never includes the raw password or a permissions list (§8: minimal claims)", () => {
  const token = signAccessToken({ accountType: "business_user", userId: 1, businessId: 1 });
  const payload = verifyAccessToken(token);
  assert.equal(payload.password, undefined);
  assert.equal(payload.passwordHash, undefined);
  assert.equal(payload.permissions, undefined);
});

test("generateRefreshToken returns high-entropy, unique values", () => {
  const a = generateRefreshToken();
  const b = generateRefreshToken();
  assert.notEqual(a, b);
  assert.equal(a.length, 64); // 32 bytes, hex-encoded
});

test("hashRefreshToken is deterministic (needed for lookup-by-hash) but never reversible-looking like the input", () => {
  const raw = generateRefreshToken();
  const hash1 = hashRefreshToken(raw);
  const hash2 = hashRefreshToken(raw);
  assert.equal(hash1, hash2);
  assert.notEqual(hash1, raw);
  assert.equal(hash1.length, 64); // sha256 hex
});
