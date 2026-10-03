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

    // How many reverse proxies sit in front of this server. 0 means none, and
    // is the only safe default.
    //
    // This is not a convenience setting. With it at 0 behind nginx, every
    // request appears to come from nginx: §7's login lockout becomes global, so
    // one attacker locks out every user in the system, and the audit trail
    // records the proxy's address for every action. Set too high, or trusted
    // blindly, a client can put whatever it likes in X-Forwarded-For and pick
    // its own identity — which defeats the lockout it is counted for.
    //
    // So it is the exact hop count for the deployment, stated deliberately.
    // One nginx in front of the API is 1. See docs/deployment.md.
    trustProxyHops: readInt("TRUST_PROXY_HOPS", 0),
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
    // How many callers may wait for a connection before the pool refuses. See
    // `db/pool.js` — the point is that it refuses at all, so an overloaded
    // server answers 503 instead of leaving requests hanging for ever.
    queueLimit: readInt("DB_QUEUE_LIMIT", 50),
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

  // The coarse, global per-IP limit in app.js — a first layer under the
  // tighter one on the login endpoints.
  //
  // Lenient outside production for the same reason as the registration limit,
  // and it was found the same way: an integration-test file that drives a
  // realistic session — sell, return, approve, complete, read it back — makes
  // well over a hundred requests in a minute, and started answering 429 to its
  // own setup. A single busy screen can do the same, so the production figure
  // is worth revisiting too, but that is a decision about real traffic rather
  // than a test's. Override with API_RATE_LIMIT.
  api: {
    rateLimitPerMinute: readInt("API_RATE_LIMIT", nodeEnv === "production" ? 100 : 5000),
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

  // §33 backups.
  //
  // Off unless a directory is configured, and that is deliberate: a backup
  // subsystem that silently writes nowhere is worse than one that says it is
  // not set up. The server logs which of the two it is at startup.
  backups: {
    // Absolute path on the machine (or mounted volume) the API runs on. Empty
    // means there is no backup target, and the endpoint reports exactly that
    // instead of pretending.
    directory: process.env.BACKUP_DIR || "",

    // mysqldump is not always on PATH — notably on Windows, where it lives
    // inside the MySQL installation directory.
    mysqldumpPath: process.env.MYSQLDUMP_PATH || "mysqldump",

    // How many completed backups to keep. Older files are removed once a new
    // one succeeds, so a disk cannot fill up silently.
    keepLast: readInt("BACKUP_KEEP_LAST", 14),

    // A daily automatic dump. Off by default: a schedule nobody asked for,
    // writing to an unconfigured path, is just a cron job that fails nightly.
    scheduleEnabled: process.env.BACKUP_SCHEDULE === "true",

    // Minutes after local midnight. 02:00 by default.
    scheduleMinuteOfDay: readInt("BACKUP_SCHEDULE_MINUTE", 120),

    // A dump that has not finished by then is recorded as failed, so a hung
    // mysqldump cannot leave a row sitting at "running" for ever.
    timeoutMs: readInt("BACKUP_TIMEOUT_MS", 10 * 60 * 1000),
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
