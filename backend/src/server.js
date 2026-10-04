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
    // Flushed before exiting, for the same reason as the crash handler below: to
    // anything that is not a terminal, pino writes asynchronously and
    // `process.exit` discards the buffer. Without this, a restart loop shows no
    // "Shutdown complete" and it is impossible to tell a clean stop from a kill.
    if (typeof logger.flush === "function") logger.flush();
    setTimeout(() => process.exit(0), 100).unref();
  });

  // Don't hang forever if something doesn't close cleanly. Logged, so a shutdown
  // that had to be forced is distinguishable from one that was not.
  setTimeout(() => {
    logger.warn("Shutdown did not complete within 5s — exiting anyway.");
    if (typeof logger.flush === "function") logger.flush();
    setTimeout(() => process.exit(1), 100).unref();
  }, 5000).unref();
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
// exit — but deliberately, after the reason has actually been written.
//
// `logger.fatal(...)` followed by `process.exit(1)` does NOT achieve that. pino
// writes asynchronously to anything that is not a TTY, and `process.exit` drops
// whatever is still buffered — so a crash logged to a file or to Docker's stdout
// produced an EMPTY log. Found exactly that way: the same EADDRINUSE crash
// printed a full stack when run in a terminal and nothing at all when redirected
// to a file, which is the one case where the reason matters most.
//
// So the exit is deferred by a tick and the code set rather than forced, giving
// the logger's stream a chance to flush first. `unref` means this timer cannot
// itself hold the process open if the flush finishes sooner.
process.on("uncaughtException", (error) => {
  logger.fatal({ err: error }, "Uncaught exception — exiting");
  process.exitCode = 1;
  if (typeof logger.flush === "function") logger.flush();
  setTimeout(() => process.exit(1), 250).unref();
});
