// Centralized configuration (Phase 0 foundation).
//
// Every other module reads configuration from here — nothing in the codebase
// should call `process.env` directly outside this file. That keeps env-var
// names, defaults, and validation in exactly one place as the app grows.
//
// Rule: no secret ever has a real default. Non-secret dev conveniences (port,
// log level) may default sensibly; DB_PASSWORD does not.

import "dotenv/config";

function readInt(name, fallback) {
  const raw = process.env[name];
  if (raw === undefined || raw === "") return fallback;
  const parsed = Number.parseInt(raw, 10);
  return Number.isNaN(parsed) ? fallback : parsed;
}

const nodeEnv = process.env.NODE_ENV || "development";

export const env = {
  nodeEnv,
  isProduction: nodeEnv === "production",
  isDevelopment: nodeEnv === "development",

  server: {
    port: readInt("PORT", 4000),
    corsOrigin: (process.env.CORS_ORIGIN || "http://localhost:5173")
      .split(",")
      .map((origin) => origin.trim())
      .filter(Boolean),
  },

  logging: {
    level: process.env.LOG_LEVEL || "info",
  },

  db: {
    host: process.env.DB_HOST || "127.0.0.1",
    port: readInt("DB_PORT", 3307),
    database: process.env.DB_NAME || "warehouse_os_dev",
    user: process.env.DB_USER || "warehouse_app",
    password: process.env.DB_PASSWORD || "",
    connectionLimit: readInt("DB_CONNECTION_LIMIT", 10),
    connectTimeoutMs: readInt("DB_CONNECT_TIMEOUT_MS", 3000),
  },

  // Auth foundation only (architecture §8/§10) — no /api/auth/* routes
  // exist yet in Phase 0. These are read here, once, so Phase 1's login
  // endpoint and the authenticate/authorize middleware have a value to use
  // from day one instead of each reaching into process.env separately.
  auth: {
    jwtSecret: process.env.JWT_SECRET || "",
    accessTokenTtl: process.env.JWT_ACCESS_TTL || "15m",
    refreshTokenTtl: process.env.JWT_REFRESH_TTL || "30d",
    bcryptSaltRounds: readInt("BCRYPT_SALT_ROUNDS", 12),
  },

  // Public business self-registration. The endpoint is unauthenticated AND
  // it writes, so it is rate limited per IP per hour — without that, one
  // script can fill an administrator's approval queue, which is a denial of
  // service against a person rather than a server.
  //
  // Strict in production; lenient elsewhere, because in development and in
  // the integration tests the same limit only obstructs — several
  // registrations in a row is exactly what those tests do. Override with
  // REGISTRATION_RATE_LIMIT.
  registration: {
    rateLimitPerHour: readInt("REGISTRATION_RATE_LIMIT", nodeEnv === "production" ? 5 : 200),
  },

  // One-time bootstrap of the first System Admin (`npm run seed`). Read here
  // so the seed script does not reach into `process.env` on its own. The
  // application never reads these — only the seed does, and with neither
  // value set it deliberately does nothing rather than create a guessable
  // default account.
  seed: {
    adminPhone: process.env.SEED_ADMIN_PHONE || "",
    adminPassword: process.env.SEED_ADMIN_PASSWORD || "",
    adminName: process.env.SEED_ADMIN_NAME || "System Administrator",
  },

  // Administrator-only, used exclusively by `npm run db:provision`.
  //
  // The administrator PASSWORD is deliberately absent, and must stay absent:
  // it is read from a hidden terminal prompt at the moment it is needed and
  // never stored in `.env`, in this object, in a log, or in shell history.
  // Only the two non-secret values below are configuration, so only they
  // belong here. See docs/environment.md, "The one documented exception".
  provisioning: {
    adminUser: process.env.MYSQL_ADMIN_USER || "root",
    useSsl: process.env.MYSQL_ADMIN_SSL === "true",
  },
};

// Fail fast, loudly, at startup — not three requests into production — if a
// value the app cannot safely run without is missing. Deliberately short in
// Phase 0: no DB_PASSWORD requirement yet, because the server must still be
// able to start and serve GET /api/health even before the database exists.
const missing = [];
if (!env.db.host) missing.push("DB_HOST");
if (!env.db.database) missing.push("DB_NAME");
if (!env.db.user) missing.push("DB_USER");

if (missing.length > 0) {
  // eslint-disable-next-line no-console
  console.error(
    `[config] Missing required environment variable(s): ${missing.join(", ")}. ` +
      "Copy backend/.env.example to backend/.env and fill it in."
  );
  process.exit(1);
}

if (!env.db.password && env.isProduction) {
  // eslint-disable-next-line no-console
  console.error("[config] DB_PASSWORD must be set in production.");
  process.exit(1);
}

if (!env.auth.jwtSecret && env.isProduction) {
  // eslint-disable-next-line no-console
  console.error("[config] JWT_SECRET must be set in production.");
  process.exit(1);
}
