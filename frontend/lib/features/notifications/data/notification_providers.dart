import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../products/data/product_providers.dart';
import 'notification_models.dart';

/// In-memory notification center (spec §29/§31) — low/out-of-stock entries
/// are *derived* live from the real product list (never fabricated), the
/// rest are seeded demo entries for notification types this frontend-only
/// phase has no live trigger for yet (new order, return request, etc. would
/// come from a real-time channel/webhook once the backend exists).
final notificationsProvider = NotifierProvider<NotificationsController, List<AppNotification>>(NotificationsController.new);

class NotificationsController extends Notifier<List<AppNotification>> {
  // Tracked outside `state` deliberately — a Notifier must never read its
  // own `state` from within `build()` (it isn't initialized yet; doing so
  // throws "Tried to read the state of an uninitialized provider" the
  // moment this provider has a real dependency that can trigger a rebuild,
  // e.g. `productPickerOptionsProvider` resolving). Read-state survives a
  // rebuild through this plain field instead.
  final Set<String> _readIds = {};

  @override
  List<AppNotification> build() {
    final products = ref.watch(productPickerOptionsProvider).asData?.value ?? const [];
    final now = DateTime.now();
    final derived = <AppNotification>[
      for (final p in products.where((p) => p.isOutOfStock))
        AppNotification(id: 'notif-out-${p.id}', type: NotificationType.outOfStock, title: 'Out of stock', body: '${p.name} is out of stock.', createdAt: now),
      for (final p in products.where((p) => p.isLowStock))
        AppNotification(id: 'notif-low-${p.id}', type: NotificationType.lowStock, title: 'Low stock', body: '${p.name}: ${p.currentQuantity} ${p.unit} left.', createdAt: now),
    ];
    final seeded = <AppNotification>[
      AppNotification(id: 'notif-seed-1', type: NotificationType.newOrder, title: 'New order', body: 'A new order was placed.', createdAt: now.subtract(const Duration(hours: 2))),
      AppNotification(id: 'notif-seed-2', type: NotificationType.systemAlert, title: 'System alert', body: 'Demo data only — no backend connected yet.', createdAt: now.subtract(const Duration(days: 1))),
    ];
    return [
      for (final n in [...derived, ...seeded]) _readIds.contains(n.id) ? n.markRead() : n,
    ];
  }

  void markRead(String id) {
    _readIds.add(id);
    state = [for (final n in state) n.id == id ? n.markRead() : n];
  }

  void markAllRead() {
    _readIds.addAll(state.map((n) => n.id));
    state = [for (final n in state) n.markRead()];
  }
}

final unreadNotificationCountProvider = Provider<int>((ref) => ref.watch(notificationsProvider).where((n) => n.isUnread).length);
