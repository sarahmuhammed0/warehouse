#!/usr/bin/env node
// Creates a System Admin account, typing the password at a hidden prompt.
//
// A fresh deployment has no accounts at all, and no way to make one: a System
// Admin is not self-service, and creating a business requires already being
// authenticated as one (docs/authentication.md, "Bootstrapping"). This is the
// one door in.
//
// It exists alongside the `001_system_admin` seed rather than replacing it,
// because the seed reads SEED_ADMIN_PASSWORD from the environment — fine for a
// scripted test fixture, wrong for production, where it would leave the
// platform's most privileged password sitting in a .env file for the life of the
// deployment. Here it is typed once, hashed, and never stored anywhere else.
//
// Usage, in a terminal on the server:
//   cd backend && npm run admin:create
//   npm run admin:create -- --phone +9647700000000 --name "Ops"
//
// Re-running it for an existing phone resets that admin's password, which is
// also the recovery path when the only System Admin password is lost.

import { randomBytes } from "node:crypto";

import { env } from "../src/config/env.js";
import { pool, closePool } from "../src/db/pool.js";
import { hashPassword } from "../src/utils/password.js";
import { normalizePhone, isValidE164 } from "../src/utils/phone.js";
import { readHidden } from "./lib/read-hidden.mjs";

const RESET = "\u001b[0m";
const BOLD = "\u001b[1m";
const RED = "\u001b[31m";
const GREEN = "\u001b[32m";
const YELLOW = "\u001b[33m";

const say = (m = "") => console.log(m); // eslint-disable-line no-console

async function die(message) {
  await closePool().catch(() => {});
  console.error(`${RED}✗ ${message}${RESET}`); // eslint-disable-line no-console
  process.exit(1);
}

function flag(name) {
  const index = process.argv.indexOf(`--${name}`);
  return index === -1 ? null : process.argv[index + 1] ?? null;
}

function readLine(prompt) {
  process.stdout.write(prompt);
  return new Promise((resolve) => {
    process.stdin.setEncoding("utf8");
    process.stdin.once("data", (chunk) => resolve(chunk.toString().trim()));
  });
}

say(`${BOLD}Create a System Admin${RESET}`);
say(`  database  ${env.db.database} on ${env.db.host}:${env.db.port}`);
say();

const rawPhone = flag("phone") ?? (await readLine("Phone (international format, e.g. +9647700000000): "));
const phone = normalizePhone(rawPhone);

if (!isValidE164(phone)) {
  await die(`"${rawPhone}" is not a phone number in international format. It must start with + and a country code.`);
}

const name = flag("name") ?? (await readLine("Name: ")) ?? "System Admin";

// The system floor, not a business's own policy: a System Admin belongs to no
// business, so there is no per-business minimum to read. §3's absolute floor is 8.
const MINIMUM = 8;

let password;
try {
  password = await readHidden(`Password (at least ${MINIMUM} characters, not shown): `);
  const again = await readHidden("Repeat it: ");
  if (password !== again) await die("Those did not match. Nothing was created.");
} catch (error) {
  await die(error.message);
}

if (password.length < MINIMUM) {
  await die(`That is ${password.length} characters; the minimum is ${MINIMUM}.`);
}

// A weak platform-admin password is the single worst credential in the system —
// it can read and disable every tenant. Warned about rather than refused: the
// operator knows their threat model, and a rule that blocks a long passphrase
// for lacking a digit teaches people to pick "Password1!" instead.
const weak =
  password.length < 12 ||
  !/[a-z]/.test(password) ||
  !/[A-Z0-9]/.test(password);
if (weak) {
  say();
  say(`${YELLOW}⚠ That password is short or simple. This account can read and disable every${RESET}`);
  say(`${YELLOW}  business on the platform. Consider a longer passphrase.${RESET}`);
}

try {
  const [existing] = await pool.query(
    `SELECT id, name, status FROM system_admins WHERE phone = ? LIMIT 1`,
    [phone]
  );

  const passwordHash = await hashPassword(password);

  if (existing.length > 0) {
    const admin = existing[0];
    say();
    const confirm = await readLine(
      `${YELLOW}${phone} already exists (${admin.name}). Reset its password? [y/N] ${RESET}`
    );
    if (confirm.toLowerCase() !== "y") {
      say("Nothing was changed.");
      await closePool();
      process.exit(0);
    }

    await pool.query(
      `UPDATE system_admins SET password_hash = ?, status = 'active', updated_at = NOW() WHERE id = ?`,
      [passwordHash, admin.id]
    );

    // Every existing session for this account is revoked. If the reason for the
    // reset is that someone else had the old password, leaving their session
    // alive defeats the reset entirely.
    const [revoked] = await pool.query(
      `UPDATE system_admin_refresh_tokens SET revoked_at = NOW()
        WHERE system_admin_id = ? AND revoked_at IS NULL`,
      [admin.id]
    );

    say();
    say(`${GREEN}✓ Password reset for ${phone}${RESET}`);
    if (revoked.affectedRows > 0) {
      say(`  ${revoked.affectedRows} existing session(s) revoked — sign in again.`);
    }
  } else {
    const [result] = await pool.query(
      `INSERT INTO system_admins (name, phone, password_hash, status) VALUES (?, ?, ?, 'active')`,
      [name || "System Admin", phone, passwordHash]
    );
    say();
    say(`${GREEN}✓ Created System Admin ${phone} (id ${result.insertId})${RESET}`);
    say(`  Sign in at /login, choosing System Admin.`);
  }

  // Deliberately not printed, not logged, and not written anywhere. The only
  // copy is the one the operator just typed.
  password = randomBytes(1).toString("hex");

  await closePool();
} catch (error) {
  await die(error.message);
}
