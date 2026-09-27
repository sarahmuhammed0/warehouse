// The shared schemas in src/validation/common.js — §54's building blocks.
//
// Most of these tests exist because the behaviour they pin down was WRONG at
// some point and the failure was silent: a message that never reached the
// client, a "false" that arrived as true, a null that became 0. None of those
// throw, so only an assertion catches them.

import { test } from "node:test";
import assert from "node:assert/strict";

import {
  requiredString,
  optionalString,
  enumSchema,
  booleanSchema,
  idSchema,
  moneySchema,
  quantitySchema,
  optionalMoneySchema,
  optionalQuantitySchema,
  optionalDateSchema,
} from "../../src/validation/common.js";

const messageOf = (schema, value) => schema.safeParse(value).error?.issues[0]?.message;

// ---- custom messages actually reach the client ---------------------------
//
// zod 4 renamed the option that carries these. Under the old `required_error`
// /`invalid_type_error`/`errorMap` spelling every message here was silently
// discarded and the API answered "Invalid input: expected string, received
// undefined" instead. The library accepts the dead keys without complaint, so
// nothing but an assertion on the text notices.

test("requiredString's message survives — a missing value says what is missing", () => {
  const schema = requiredString(50, "Name");
  assert.equal(messageOf(schema, undefined), "Name is required.");
  assert.equal(messageOf(schema, ""), "Name is required.");
  assert.equal(messageOf(schema, 42), "Name is required.");
  assert.equal(messageOf(schema, "x".repeat(51)), "Name must be 50 characters or fewer.");
});

test("enumSchema's message lists the options", () => {
  const schema = enumSchema(["active", "inactive"], "Status");
  assert.equal(messageOf(schema, "nope"), "Status must be one of: active, inactive.");
});

test("idSchema's and moneySchema's messages survive", () => {
  assert.equal(messageOf(idSchema, "abc"), "Must be a number.");
  assert.equal(messageOf(idSchema, 0), "Must be greater than zero.");
  assert.equal(messageOf(moneySchema, "abc"), "Must be an amount.");
  assert.equal(messageOf(moneySchema, -1), "Cannot be negative.");
  assert.equal(messageOf(quantitySchema, -0.5), "Cannot be negative.");
});

// ---- booleanSchema -------------------------------------------------------

test('booleanSchema reads "false" as false, not as a non-empty string', () => {
  // z.coerce.boolean() runs Boolean("false"), which is true — so a client
  // sending isDefault: "false" used to promote the warehouse it was trying
  // not to promote.
  assert.equal(booleanSchema.parse("false"), false);
  assert.equal(booleanSchema.parse("FALSE"), false);
  assert.equal(booleanSchema.parse("0"), false);
  assert.equal(booleanSchema.parse("off"), false);
  assert.equal(booleanSchema.parse(0), false);
  assert.equal(booleanSchema.parse(false), false);
});

test("booleanSchema reads the truthy spellings as true", () => {
  for (const value of ["true", "TRUE", "1", "yes", "on", 1, true]) {
    assert.equal(booleanSchema.parse(value), true, `${JSON.stringify(value)} should be true`);
  }
});

test("booleanSchema rejects something that is not a boolean at all", () => {
  assert.equal(booleanSchema.safeParse("maybe").success, false);
  assert.equal(booleanSchema.safeParse({}).success, false);
});

// ---- absent vs null ------------------------------------------------------

test("null clears a numeric field; it is not read as zero", () => {
  // Number(null) === 0, so the naive coercion stored 0 — and max_stock 0
  // makes every product with any stock at all look overstocked.
  assert.equal(optionalQuantitySchema.parse(null), null);
  assert.equal(optionalMoneySchema.parse(null), null);
  assert.equal(optionalMoneySchema.parse(""), null);
});

test("a real zero is still a real zero", () => {
  assert.equal(optionalQuantitySchema.parse(0), 0);
  assert.equal(optionalMoneySchema.parse("0"), 0);
});

test("an absent numeric field stays undefined, so a PATCH leaves the column alone", () => {
  assert.equal(optionalMoneySchema.parse(undefined), undefined);
  assert.equal("value" in { value: optionalMoneySchema.parse(undefined) }, true);
});

test("optionalString distinguishes absent (leave it) from null (clear it)", () => {
  const schema = optionalString(100);
  assert.equal(schema.parse(undefined), undefined);
  assert.equal(schema.parse(null), null);
  // An emptied text input means the user wants the value gone.
  assert.equal(schema.parse(""), null);
  assert.equal(schema.parse("  kept  "), "kept");
});

test("optionalString still enforces its maximum", () => {
  assert.equal(optionalString(3).safeParse("abcd").success, false);
});

test("optionalDateSchema follows the same absent/null rule", () => {
  assert.equal(optionalDateSchema.parse(undefined), undefined);
  assert.equal(optionalDateSchema.parse(null), null);
  assert.equal(optionalDateSchema.parse(""), null);
  assert.equal(optionalDateSchema.parse("2026-09-26"), "2026-09-26");
  assert.equal(optionalDateSchema.safeParse("26/09/2026").success, false);
});
