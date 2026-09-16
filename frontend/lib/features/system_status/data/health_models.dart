/// Models foundation, feature-scoped (architecture §4: models live beside
/// the feature that owns them, not in one giant shared file). These two
/// mirror the backend's `/api/health` and `/api/health/db` response shapes
/// exactly — see `backend/src/routes/health.routes.js`.
library;

class ApiHealth {
  final String status;
  final String environment;
  final int uptimeSeconds;

  const ApiHealth({
    required this.status,
    required this.environment,
    required this.uptimeSeconds,
  });

  factory ApiHealth.fromJson(Map<String, dynamic> json) => ApiHealth(
    status: json['status'] as String,
    environment: json['environment'] as String,
    uptimeSeconds: json['uptimeSeconds'] as int,
  );
}

class DatabaseHealth {
  final String engine;
  final String version;
  final String host;
  final int port;
  final String database;

  const DatabaseHealth({
    required this.engine,
    required this.version,
    required this.host,
    required this.port,
    required this.database,
  });

  factory DatabaseHealth.fromJson(Map<String, dynamic> json) => DatabaseHealth(
    engine: json['engine'] as String,
    version: json['version'] as String,
    host: json['host'] as String,
    port: json['port'] as int,
    database: json['database'] as String,
  );
}
