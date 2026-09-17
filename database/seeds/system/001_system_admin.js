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

const SALT_ROUNDS = Number(process.env.BCRYPT_SALT_ROUNDS) || 12;

/** @param {import('knex').Knex} knex */
export async function seed(knex) {
  const phone = process.env.SEED_ADMIN_PHONE;
  const password = process.env.SEED_ADMIN_PASSWORD;
  const name = process.env.SEED_ADMIN_NAME || "System Administrator";

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

  const password_hash = await bcrypt.hash(password, SALT_ROUNDS);
  await knex("system_admins").insert({ name, phone, password_hash, status: "active" });
  console.log(`[seed:system_admin] Created System Admin ${phone}.`);
}
