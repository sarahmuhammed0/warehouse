// Phone-number normalization (Phase 2 §14 of the brief — documented
// decision, not a silent assumption).
//
// DECISION: phone numbers are stored and looked up in E.164 format
// (`+<countrycode><subscriber number>`, digits only after the leading
// `+`, 8-15 digits total per the E.164 spec). The backend does NOT guess
// a missing country code — that would mean silently assuming every
// unprefixed number is Iraqi (+964), which the specification's own
// "configurable business system" framing argues against (§14's brief:
// "avoid unnecessarily hardcoding Iraq into the backend"). Composing a
// full E.164 number — picking a country, formatting the trunk/subscriber
// part — is the Flutter client's job (its country-code picker defaults to
// Iraq, §14: "preserve it as a UI default"); this function's job is only
// to validate that what arrives is already in that shape and to strip
// incidental formatting (spaces, dashes, parentheses) a user might have
// typed. This is an honest, bounded scope: it is not a full phone-number
// library (no libphonenumber-style per-country length/prefix validation),
// which is a real limitation, documented here rather than silently
// pretended away.

const E164_PATTERN = /^\+[1-9]\d{7,14}$/;

/**
 * Strips spaces/dashes/parentheses/dots; does not add or guess a country
 * code. Returns the cleaned string unconditionally — callers validate
 * separately with `isValidE164`.
 */
export function normalizePhone(rawPhone) {
  if (typeof rawPhone !== "string") return "";
  return rawPhone.replace(/[\s\-().]/g, "");
}

export function isValidE164(phone) {
  return E164_PATTERN.test(phone);
}
