import { app } from "./app.js";
import { env } from "./config/env.js";
import { logger } from "./utils/logger.js";
import { closePool } from "./db/pool.js";

const server = app.listen(env.server.port, () => {
  logger.info(
    `Warehouse OS backend listening on http://localhost:${env.server.port} (${env.nodeEnv})`
  );
  logger.info(`Health check:     http://localhost:${env.server.port}/api/health`);
  logger.info(`DB health check:  http://localhost:${env.server.port}/api/health/db`);
});

async function shutdown(signal) {
  logger.info(`${signal} received, shutting down gracefully...`);
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
