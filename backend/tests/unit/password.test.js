import { test } from "node:test";
import assert from "node:assert/strict";
import { hashPassword, verifyPassword } from "../../src/utils/password.js";

test("hashPassword never returns the plaintext", async () => {
  const hash = await hashPassword("correct horse battery staple");
  assert.notEqual(hash, "correct horse battery staple");
  assert.match(hash, /^\$2[aby]\$/); // bcrypt hash shape
});

test("hashPassword is salted — same input produces different hashes", async () => {
  const a = await hashPassword("same-password");
  const b = await hashPassword("same-password");
  assert.notEqual(a, b);
});

test("verifyPassword accepts the correct password against its own hash", async () => {
  const hash = await hashPassword("my-real-password-123");
  assert.equal(await verifyPassword("my-real-password-123", hash), true);
});

test("verifyPassword rejects an incorrect password", async () => {
  const hash = await hashPassword("my-real-password-123");
  assert.equal(await verifyPassword("wrong-password", hash), false);
});
