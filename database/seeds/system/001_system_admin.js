// Bootstraps exactly one System Admin account — necessary because there is
// no other way to create the first one (System Admin isn't self-service,
// and business creation itself requires being authenticated as one — see
// docs/authentication.md "Bootstrapping"). Reads credentials from
// environment variables rather than containing a hardcoded phone/password,
// so this file is safe to commit and safe to re-run: with no env vars set,
// it does nothing (loudly, via console.log) instead of creating a
// guessable default account.
//
// Usage:
//   SEED_ADMIN_PHONE=+9647700000000 SEED_ADMIN_PASSWORD='...' \
//     npx knex seed:run --specific=system/001_system_admin.js

import bcrypt from "bcryptjs";
// Read through the backend's own config module rather than `process.env`, so
// the cost factor here can never drift from the one the login path verifies
// against, and every env-var name in the project is declared in one file.
import { env } from "../../../backend/src/config/env.js";

/** @param {import('knex').Knex} knex */
export async function seed(knex) {
  const { adminPhone: phone, adminPassword: password, adminName: name } = env.seed;

  if (!phone || !password) {
    console.log(
      "[seed:system_admin] SEED_ADMIN_PHONE / SEED_ADMIN_PASSWORD not set — skipping. " +
        "No System Admin account was created or modified."
    );
    return;
  }

  const existing = await knex("system_admins").where({ phone }).first();
  if (existing) {
    console.log(`[seed:system_admin] ${phone} already exists — skipping.`);
    return;
  }

  const password_hash = await bcrypt.hash(password, env.auth.bcryptSaltRounds);
  await knex("system_admins").insert({ name, phone, password_hash, status: "active" });
  console.log(`[seed:system_admin] Created System Admin ${phone}.`);
}
