import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'core/network/auth_interceptor.dart';
import 'core/network/providers.dart';

void main() {
  // A ProviderContainer built here (rather than letting ProviderScope
  // create its own implicitly) so the auth interceptor can be attached to
  // the shared Dio instance BEFORE any widget makes its first request —
  // see core/network/auth_interceptor.dart's doc comment for why this
  // wiring happens here specifically, not inside providers.dart.
  final container = ProviderContainer();
  container.read(apiClientProvider).dio.interceptors.add(container.read(authInterceptorProvider));

  runApp(UncontrolledProviderScope(container: container, child: const WarehouseOsApp()));
}
