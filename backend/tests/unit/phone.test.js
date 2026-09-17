import { test } from "node:test";
import assert from "node:assert/strict";
import { normalizePhone, isValidE164 } from "../../src/utils/phone.js";

test("normalizePhone strips spaces, dashes, parens, dots", () => {
  assert.equal(normalizePhone("+964 770 123 4567"), "+9647701234567");
  assert.equal(normalizePhone("+964-770-123-4567"), "+9647701234567");
  assert.equal(normalizePhone("(+964) 770.123.4567"), "+9647701234567");
});

test("normalizePhone returns empty string for non-string input", () => {
  assert.equal(normalizePhone(null), "");
  assert.equal(normalizePhone(undefined), "");
  assert.equal(normalizePhone(12345), "");
});

test("isValidE164 accepts well-formed international numbers", () => {
  assert.equal(isValidE164("+9647701234567"), true);
  assert.equal(isValidE164("+12025550123"), true);
});

test("isValidE164 rejects numbers without a country code, with formatting, or too short/long", () => {
  assert.equal(isValidE164("07701234567"), false); // no country code, i.e. no leading +
  assert.equal(isValidE164("+964 770 123 4567"), false); // not normalized first
  assert.equal(isValidE164("+1"), false); // too short
  assert.equal(isValidE164("+" + "1".repeat(20)), false); // too long
  assert.equal(isValidE164(""), false);
});
