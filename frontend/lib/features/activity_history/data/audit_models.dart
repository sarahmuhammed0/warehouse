/// Activity history / audit log (spec §30). The backend already has a real,
/// working `audit_logs` table and writer (Phase 2's `writeAuditLog`,
/// `backend/src/modules/auth/repository.js`) for auth events — this
/// frontend model matches that shape so the eventual `GET /api/audit-logs`
/// response needs no UI changes, just a repository swap.
class AuditLogEntry {
  const AuditLogEntry({
    required this.id,
    required this.userName,
    required this.action,
    required this.module,
    required this.description,
    this.ipAddress,
    this.referenceId,
    required this.createdAt,
  });

  final String id;
  final String userName;
  final String action;
  final String module;
  final String description;
  final String? ipAddress;
  final String? referenceId;
  final DateTime createdAt;
}
