import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/config/app_mode.dart';
import '../../core/network/api_client.dart';
import '../../core/network/providers.dart';

/// "How much has arrived since I last looked", per navigation item.
///
/// One request answers the whole navigation. Asking each module's list endpoint
/// instead would be a request per item on every page load, and the client would
/// page through rows only to count and discard them.
abstract class NavActivityRepository {
  /// [since] maps an entity key the server knows (`products`, `orders`, …) to
  /// the moment that item was last opened. The answer carries only the keys
  /// that were asked for AND that the caller is allowed to see — a role without
  /// `products.view` gets no `products` key rather than a zero.
  Future<Map<String, int>> counts(Map<String, DateTime> since, {required bool asSystemAdmin});
}

class ApiNavActivityRepository implements NavActivityRepository {
  ApiNavActivityRepository(this._client);

  final ApiClient _client;

  @override
  Future<Map<String, int>> counts(Map<String, DateTime> since, {required bool asSystemAdmin}) async {
    if (since.isEmpty) return const {};
    final query = since.entries
        .map((e) => '${e.key}=${Uri.encodeQueryComponent(e.value.toUtc().toIso8601String())}')
        .join('&');
    final path = asSystemAdmin ? '/admin/activity/counts' : '/activity/counts';
    final json = await _client.getJson('$path?$query');
    return {
      for (final entry in json.entries)
        if (entry.value is num) entry.key: (entry.value as num).toInt(),
    };
  }
}

/// Demo mode has nothing to measure.
///
/// Every demo record is seeded as the app starts, so "since you last looked" is
/// either "all of it" (the first frame, which would badge every item in the
/// navigation at once) or "none of it" (every frame after). Neither is
/// information. The badge appears in demo mode only for the pending-registration
/// queue, which is a real state rather than an arrival time.
class DemoNavActivityRepository implements NavActivityRepository {
  @override
  Future<Map<String, int>> counts(Map<String, DateTime> since, {required bool asSystemAdmin}) async => const {};
}

final navActivityRepositoryProvider = Provider<NavActivityRepository>((ref) {
  return switch (AppModeConfig.mode) {
    AppMode.backend => ApiNavActivityRepository(ref.watch(apiClientProvider)),
    AppMode.demo => DemoNavActivityRepository(),
  };
});
