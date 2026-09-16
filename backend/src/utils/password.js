// Password hashing foundation (architecture §8/§35). Not called from
// anywhere yet — Phase 1's user-creation and login endpoints are the first
// real callers. bcryptjs (pure JS, no native build step) rather than bcrypt,
// so `npm install` never depends on a working C++ toolchain on the target
// machine; the algorithm and cost-factor semantics are identical.

import bcrypt from "bcryptjs";
import { env } from "../config/env.js";

export async function hashPassword(plainText) {
  return bcrypt.hash(plainText, env.auth.bcryptSaltRounds);
}

export async function verifyPassword(plainText, hash) {
  return bcrypt.compare(plainText, hash);
}
