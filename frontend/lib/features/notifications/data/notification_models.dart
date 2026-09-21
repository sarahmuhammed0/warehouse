/// Notifications (spec §29/§31).
enum NotificationType { lowStock, outOfStock, newOrder, returnRequest, pendingPayment, productionCompleted, transferReceived, systemAlert }

class AppNotification {
  const AppNotification({
    required this.id,
    required this.type,
    required this.title,
    required this.body,
    required this.createdAt,
    this.readAt,
    this.targetRoute,
  });

  final String id;
  final NotificationType type;
  final String title;
  final String body;
  final DateTime createdAt;
  final DateTime? readAt;

  /// Where tapping this notification should take the reader, when there is
  /// somewhere meaningful to go. "Low stock — 3-Seat Sofa" knows exactly
  /// which product it is about; opening that product is the whole point of
  /// tapping it, and previously the tap only marked it read and dismissed
  /// the menu. `null` for notifications with no single subject.
  final String? targetRoute;

  bool get isUnread => readAt == null;

  AppNotification markRead() => AppNotification(
        id: id,
        type: type,
        title: title,
        body: body,
        createdAt: createdAt,
        readAt: DateTime.now(),
        targetRoute: targetRoute,
      );
}
