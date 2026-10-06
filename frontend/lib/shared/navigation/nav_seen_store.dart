import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// When each navigation item was last opened, so a badge can say what has
/// arrived since.
///
/// **Per account, not per device.** The key carries the signed-in account's id:
/// two people sharing a machine, or an owner who also holds a System Admin
/// login, must not clear each other's badges. Signing out leaves the marks in
/// place — they are not secrets, and losing them on every sign-out would make
/// every item badge again on the next sign-in.
///
/// **Stored in `flutter_secure_storage`** only because it is the key/value store
/// this app already ships on every platform it targets. Nothing here is
/// sensitive; adding a second storage dependency to hold a dozen timestamps
/// would be the larger cost. (On web that package is localStorage-backed, which
/// is exactly the right strength for this.)
class NavSeenStore {
  NavSeenStore({FlutterSecureStorage? storage}) : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  static String _keyFor(String accountId) => 'warehouse_os.nav_seen.$accountId';

  Future<Map<String, DateTime>> read(String accountId) async {
    final raw = await _storage.read(key: _keyFor(accountId));
    if (raw == null || raw.isEmpty) return {};
    try {
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      return {
        for (final entry in decoded.entries)
          if (DateTime.tryParse('${entry.value}') != null) entry.key: DateTime.parse('${entry.value}'),
      };
    } catch (_) {
      // Unreadable marks are the same as no marks: every item is treated as
      // seen just now, so nobody is shouted at because a stored value went bad.
      return {};
    }
  }

  Future<void> write(String accountId, Map<String, DateTime> seen) async {
    final encoded = jsonEncode({
      for (final entry in seen.entries) entry.key: entry.value.toUtc().toIso8601String(),
    });
    await _storage.write(key: _keyFor(accountId), value: encoded);
  }
}

final navSeenStoreProvider = Provider<NavSeenStore>((ref) => NavSeenStore());
