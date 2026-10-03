import { app } from "./app.js";
import { env } from "./config/env.js";
import { logger } from "./utils/logger.js";
import { closePool } from "./db/pool.js";
import { startBackupScheduler, stopBackupScheduler } from "./modules/backups/scheduler.js";
import { backupsConfigured, reconcileInterruptedBackups } from "./modules/backups/service.js";

const server = app.listen(env.server.port, () => {
  logger.info(
    `Warehouse OS backend listening on http://localhost:${env.server.port} (${env.nodeEnv})`
  );
  logger.info(`Health check:     http://localhost:${env.server.port}/api/health`);
  logger.info(`DB health check:  http://localhost:${env.server.port}/api/health/db`);

  // Said at startup, every time, because "do we have backups?" must be
  // answerable from the log of a running server rather than by reading the
  // configuration and hoping.
  if (backupsConfigured()) {
    logger.info({ directory: env.backups.directory, keepLast: env.backups.keepLast }, "Backups are configured");

    // Any dump left mid-flight by a process that is no longer running. Fire and
    // forget: it must not delay the server accepting requests, and it is a
    // tidying step rather than something the API depends on.
    reconcileInterruptedBackups().catch((error) =>
      logger.error({ err: error }, "Could not reconcile interrupted backups")
    );
  } else {
    const say = env.isProduction ? logger.warn : logger.info;
    say.call(logger, "No backup target is configured (BACKUP_DIR is unset) — no backup can be taken.");
  }

  startBackupScheduler();
});

async function shutdown(signal) {
  logger.info(`${signal} received, shutting down gracefully...`);
  stopBackupScheduler();
  server.close(async () => {
    await closePool();
    logger.info("Shutdown complete.");
    process.exit(0);
  });

  // Don't hang forever if something doesn't close cleanly.
  setTimeout(() => process.exit(1), 5000).unref();
}

process.on("SIGINT", () => shutdown("SIGINT"));
process.on("SIGTERM", () => shutdown("SIGTERM"));

// A backup child process or a dropped connection can produce a rejection with
// nobody waiting on it. Logging and carrying on is right for a server: the
// default in modern Node is to terminate, which would turn one failed query
// into an outage for everyone currently using the system.
process.on("unhandledRejection", (reason) => {
  logger.error({ err: reason }, "Unhandled promise rejection");
});

// An uncaught exception leaves the process in an unknown state, so this one does
// exit — but it exits deliberately, after logging what happened, so a process
// supervisor restarts it and the reason is in the log rather than lost.
process.on("uncaughtException", (error) => {
  logger.fatal({ err: error }, "Uncaught exception — exiting");
  process.exit(1);
});
