import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/network/providers.dart';
import '../../data/health_models.dart';
import '../../data/health_repository.dart';

/// State management (Phase 0's one real example — see
/// docs/state-management.md for why Riverpod was chosen over Bloc/Provider/
/// GetX). One `Provider` per dependency layer: the API client
/// (`core/network/providers.dart`, shared with `features/auth` since
/// Phase 2), the repository built on it, then a `FutureProvider` per
/// independent piece of data. Screens call `ref.watch(apiHealthProvider)`
/// and get an `AsyncValue` with loading/data/error states for free — no
/// manual isLoading/error booleans to keep in sync, unlike the equivalent
/// React `useState` triple that the earlier React build needed for the
/// same screen.

final healthRepositoryProvider = Provider<HealthRepository>((ref) {
  return HealthRepository(ref.watch(apiClientProvider));
});

final apiHealthProvider = FutureProvider<ApiHealth>((ref) {
  return ref.watch(healthRepositoryProvider).getApiHealth();
});

final databaseHealthProvider = FutureProvider<DatabaseHealth>((ref) {
  return ref.watch(healthRepositoryProvider).getDatabaseHealth();
});
