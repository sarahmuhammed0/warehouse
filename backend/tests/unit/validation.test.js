import { test } from "node:test";
import assert from "node:assert/strict";
import { loginSchema, changePasswordSchema, refreshSchema } from "../../src/modules/auth/validation.js";
import { createBusinessSchema } from "../../src/modules/businesses/validation.js";

test("loginSchema accepts phone + password", () => {
  const result = loginSchema.safeParse({ phone: "+9647701234567", password: "anything" });
  assert.equal(result.success, true);
});

test("loginSchema rejects a missing password", () => {
  const result = loginSchema.safeParse({ phone: "+9647701234567" });
  assert.equal(result.success, false);
});

test("loginSchema rejects an empty phone", () => {
  const result = loginSchema.safeParse({ phone: "", password: "x" });
  assert.equal(result.success, false);
});

test("changePasswordSchema requires a new password of at least 8 characters", () => {
  assert.equal(
    changePasswordSchema.safeParse({ currentPassword: "old", newPassword: "short" }).success,
    false
  );
  assert.equal(
    changePasswordSchema.safeParse({ currentPassword: "old", newPassword: "longenough1" }).success,
    true
  );
});

test("refreshSchema requires a non-empty refreshToken", () => {
  assert.equal(refreshSchema.safeParse({}).success, false);
  assert.equal(refreshSchema.safeParse({ refreshToken: "abc123" }).success, true);
});

test("createBusinessSchema rejects an unknown business type", () => {
  const result = createBusinessSchema.safeParse({
    name: "ABC Furniture",
    businessType: "not_a_real_type",
    phone: "+9647701234567",
    owner: { name: "Owner", phone: "+9647701234568", password: "longenough1" },
  });
  assert.equal(result.success, false);
});

test("createBusinessSchema accepts a minimal valid payload", () => {
  const result = createBusinessSchema.safeParse({
    name: "ABC Furniture",
    businessType: "furniture_factory",
    phone: "+9647701234567",
    owner: { name: "Owner", phone: "+9647701234568", password: "longenough1" },
  });
  assert.equal(result.success, true);
});

test("createBusinessSchema rejects a short owner password", () => {
  const result = createBusinessSchema.safeParse({
    name: "ABC Furniture",
    businessType: "furniture_factory",
    phone: "+9647701234567",
    owner: { name: "Owner", phone: "+9647701234568", password: "short" },
  });
  assert.equal(result.success, false);
});
