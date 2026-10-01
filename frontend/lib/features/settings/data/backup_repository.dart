import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/app_mode.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/providers.dart';

/// One recorded backup request (§33).
class BackupRecord {
  const BackupRecord({
    required this.id,
    required this.status,
    required this.createdAt,
    this.fileSizeBytes,
    this.note,
  });

  final String id;

  /// `pending`, `running`, `completed` or `failed`, as the server recorded it.
  final String status;
  final DateTime createdAt;
  final int? fileSizeBytes;
  final String? note;
}

/// What a backup request did, as the server described it.
class BackupOutcome {
  const BackupOutcome({required this.accepted, required this.fileProduced, required this.message});

  final bool accepted;

  /// Whether a restorable file actually exists. It currently never does — see
  /// [ApiBackupRepository.start].
  final bool fileProduced;
  final String message;
}

abstract class BackupRepository {
  Future<List<BackupRecord>> list();
  Future<BackupOutcome> start();
}

class LocalBackupRepository implements BackupRepository {
  /// Empty, not a plausible-looking history. A demo backup history would be
  /// the most convincing lie in the application: it would say, in a screen
  /// about disaster recovery, that recoverable files exist.
  @override
  Future<List<BackupRecord>> list() async => const [];

  @override
  Future<BackupOutcome> start() async => const BackupOutcome(
    accepted: false,
    fileProduced: false,
    message: 'Backups need a connected server. Nothing was backed up.',
  );
}

class ApiBackupRepository implements BackupRepository {
  ApiBackupRepository(this._client);

  final ApiClient _client;

  /// Backups are a PLATFORM operation, not a tenant one: the endpoint dumps a
  /// database that holds every business, so it is System-Admin-only. A
  /// business owner reading this screen gets an empty history and a refusal
  /// with the server's own words, which is the truth — rather than a fake
  /// history, or a button that appears to work.
  @override
  Future<List<BackupRecord>> list() async {
    final result = await _client.getList('/admin/backups?pageSize=10&sort=createdAt&direction=desc');
    return result.data
        .cast<Map<String, dynamic>>()
        .map((row) => BackupRecord(
              id: '${row['id']}',
              status: (row['status'] as String?) ?? 'pending',
              createdAt: DateTime.tryParse('${row['createdAt']}') ?? DateTime.now(),
              fileSizeBytes: (row['sizeBytes'] as num?)?.toInt(),
              // On a `pending` row this carries the reason no dump was taken,
              // which is the single most useful thing the history can say.
              note: row['errorMessage'] as String?,
            ))
        .toList();
  }

  /// Records the request and answers 202. **No dump is taken** — the server
  /// says so itself, in `fileProduced`, and that answer is shown rather than
  /// translated into a success message. A UI reporting a completed backup over
  /// a file that does not exist is the worst outcome this screen can produce.
  @override
  Future<BackupOutcome> start() async {
    final response = await _client.postJson('/admin/backups', const {});
    return BackupOutcome(
      accepted: true,
      fileProduced: response['fileProduced'] as bool? ?? false,
      message: (response['note'] as String?) ??
          'The request was recorded. No backup file was produced.',
    );
  }
}

final backupRepositoryProvider = Provider<BackupRepository>((ref) {
  return switch (AppModeConfig.mode) {
    AppMode.backend => ApiBackupRepository(ref.watch(apiClientProvider)),
    AppMode.demo => LocalBackupRepository(),
  };
});

/// The history list. An error (a business user's 403) resolves to an empty
/// list rather than propagating — the section is one card in Settings, and the
/// button below it reports the refusal in the server's own words when pressed.
final backupHistoryProvider = FutureProvider.autoDispose<List<BackupRecord>>((ref) async {
  try {
    return await ref.watch(backupRepositoryProvider).list();
  } catch (_) {
    return const [];
  }
});
