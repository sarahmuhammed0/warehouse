import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../features/system_status/presentation/system_status_screen.dart';

/// Routing foundation (architecture §27/§39's Flutter equivalent of
/// React Router). go_router was chosen over Navigator 1.0 / plain
/// MaterialApp routes because this app will eventually need deep-linkable,
/// nested routes per business module (e.g. `/products/:id/edit`) and
/// URL-based navigation on the web target — go_router supports both
/// declaratively, without hand-rolling a Navigator 2.0 delegate.
///
/// Business routes (Products, Sales, Orders, ...) get added here module by
/// module starting Phase 1 — this file never grows business logic itself,
/// only route declarations, mirroring `backend/src/routes/index.js`.
final appRouter = GoRouter(
  initialLocation: '/',
  routes: [
    GoRoute(
      path: '/',
      name: 'systemStatus',
      builder: (context, state) => const SystemStatusScreen(),
    ),
    // Phase 1+ modules register here, e.g.:
    //   GoRoute(path: '/products', builder: (context, state) => const ProductsScreen()),
  ],
  errorBuilder: (context, state) => const Scaffold(
    body: Center(
      child: Text('Page not found — Phase 0 only wires the system status page.'),
    ),
  ),
);
