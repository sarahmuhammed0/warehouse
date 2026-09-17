import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'api_client.dart';

/// The one [ApiClient] instance the whole app shares (moved here from
/// `features/system_status` in Phase 2, now that `features/auth` needs the
/// exact same instance too — the auth interceptor, added in `main.dart`,
/// must attach to this single Dio instance so every feature's requests go
/// through it, not a second, uninstrumented one).
final apiClientProvider = Provider<ApiClient>((ref) => ApiClient());
