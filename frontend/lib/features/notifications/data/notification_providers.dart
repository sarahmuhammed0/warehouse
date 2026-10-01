import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/app_mode.dart';
import '../../../core/network/providers.dart';
import '../../../routing/app_routes.dart';
import '../../products/data/product_providers.dart';
import 'api_notification_repository.dart';
import 'notification_models.dart';

/// The notification centre (§29/§31).
///
/// **Backend mode:** rows raised by the server, inside the transactions that
/// caused them — a sale, a receipt, a run finishing, stock crossing its
/// threshold. Nothing here derives or invents an entry.
///
/// **Demo mode:** low/out-of-stock entries derived live from the demo product
/// list (never fabricated), plus two seeded entries for the types demo mode
/// has no trigger for.
final notificationsProvider = NotifierProvider<NotificationsController, List<AppNotification>>(NotificationsController.new);

class NotificationsController extends Notifier<List<AppNotification>> {
  // Tracked outside `state` deliberately — a Notifier must never read its
  // own `state` from within `build()` (it isn't initialized yet; doing so
  // throws "Tried to read the state of an uninitialized provider" the
  // moment this provider has a real dependency that can trigger a rebuild,
  // e.g. `productPickerOptionsProvider` resolving). Read-state survives a
  // rebuild through this plain field instead.
  final Set<String> _readIds = {};

  bool get _backend => AppModeConfig.mode == AppMode.backend;

  ApiNotificationRepository get _api => ApiNotificationRepository(ref.read(apiClientProvider));

  @override
  List<AppNotification> build() {
    if (_backend) {
      // Starts empty and fills in. `build()` cannot await, and the bell is a
      // header widget on every screen — blocking the first frame on a network
      // call to decorate it would be the wrong trade.
      Future.microtask(refresh);
      return const [];
    }

    final products = ref.watch(productPickerOptionsProvider).asData?.value ?? const [];
    final now = DateTime.now();
    // Each derived entry carries the route of the thing it is about, so
    // tapping it opens that product rather than just dismissing the menu.
    final derived = <AppNotification>[
      for (final p in products.where((p) => p.isOutOfStock))
        AppNotification(id: 'notif-out-${p.id}', type: NotificationType.outOfStock, title: 'Out of stock', body: '${p.name} is out of stock.', createdAt: now, targetRoute: AppRoutes.productDetail(p.id)),
      for (final p in products.where((p) => p.isLowStock))
        AppNotification(id: 'notif-low-${p.id}', type: NotificationType.lowStock, title: 'Low stock', body: '${p.name}: ${p.currentQuantity} ${p.unit} left.', createdAt: now, targetRoute: AppRoutes.productDetail(p.id)),
    ];
    final seeded = <AppNotification>[
      AppNotification(id: 'notif-seed-1', type: NotificationType.newOrder, title: 'New order', body: 'A new order was placed.', createdAt: now.subtract(const Duration(hours: 2)), targetRoute: AppRoutes.orders),
      // No target: a general notice isn't "about" one screen, and sending
      // the reader somewhere arbitrary would be worse than not moving.
      AppNotification(id: 'notif-seed-2', type: NotificationType.systemAlert, title: 'System alert', body: 'Demo data only — no backend connected yet.', createdAt: now.subtract(const Duration(days: 1))),
    ];
    return [
      for (final n in [...derived, ...seeded]) _readIds.contains(n.id) ? n.markRead() : n,
    ];
  }

  /// Re-reads the list from the server. Backend mode only — in demo mode the
  /// list is derived from providers that already rebuild on their own.
  Future<void> refresh() async {
    if (!_backend) return;
    try {
      state = await _api.list();
    } catch (_) {
      // The bell is decoration on every other screen. A failed fetch leaves
      // the list as it was rather than throwing out of a header widget and
      // taking the screen with it; the next refresh tries again.
    }
  }

  Future<void> markRead(String id) async {
    _readIds.add(id);
    // Moved locally first so the row responds to the tap, then confirmed. The
    // reader has already seen it — the server write records that fact, and
    // making them wait for a round trip to watch a dot disappear would be
    // worse than being briefly optimistic about it.
    state = [for (final n in state) n.id == id ? n.markRead() : n];
    if (!_backend) return;
    try {
      await _api.markRead(id);
    } catch (_) {
      await refresh();
    }
  }

  Future<void> markAllRead() async {
    _readIds.addAll(state.map((n) => n.id));
    state = [for (final n in state) n.markRead()];
    if (!_backend) return;
    try {
      await _api.markAllRead();
    } catch (_) {
      await refresh();
    }
  }
}

final unreadNotificationCountProvider = Provider<int>((ref) => ref.watch(notificationsProvider).where((n) => n.isUnread).length);
