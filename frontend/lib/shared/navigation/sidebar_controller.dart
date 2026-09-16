import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Desktop sidebar collapsed/expanded state (§8/§24) — the mobile
/// drawer's open/closed state is handled by `Scaffold`'s own
/// `ScaffoldState` (no provider needed for that; see `AppShell`).
final sidebarCollapsedProvider = NotifierProvider<SidebarCollapsedController, bool>(
  SidebarCollapsedController.new,
);

class SidebarCollapsedController extends Notifier<bool> {
  @override
  bool build() => false;

  void toggle() => state = !state;
}
