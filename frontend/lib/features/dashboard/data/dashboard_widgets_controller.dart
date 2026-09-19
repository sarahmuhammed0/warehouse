import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Which dashboard widgets a business admin has chosen to show (spec §5's
/// "customizable widgets"). In-memory only, same reasoning as
/// `theme_controller.dart`/`locale_controller.dart`: nothing here persists
/// across a restart yet — Settings doesn't have a real backend to save a
/// preference to (§48: never pretend a local toggle is durable state).
enum DashboardWidget { sales, inventory, lowStock, customers, purchases, returnsWidget, alerts }

final dashboardWidgetsProvider = NotifierProvider<DashboardWidgetsController, Set<DashboardWidget>>(
  DashboardWidgetsController.new,
);

class DashboardWidgetsController extends Notifier<Set<DashboardWidget>> {
  @override
  Set<DashboardWidget> build() => DashboardWidget.values.toSet();

  void toggle(DashboardWidget widget) {
    final next = Set<DashboardWidget>.from(state);
    next.contains(widget) ? next.remove(widget) : next.add(widget);
    state = next;
  }
}
