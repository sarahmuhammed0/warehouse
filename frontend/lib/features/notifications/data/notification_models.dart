/// Notifications (spec §29/§31).
enum NotificationType { lowStock, outOfStock, newOrder, returnRequest, pendingPayment, productionCompleted, transferReceived, systemAlert }

class AppNotification {
  const AppNotification({required this.id, required this.type, required this.title, required this.body, required this.createdAt, this.readAt});
  final String id;
  final NotificationType type;
  final String title;
  final String body;
  final DateTime createdAt;
  final DateTime? readAt;

  bool get isUnread => readAt == null;

  AppNotification markRead() => AppNotification(id: id, type: type, title: title, body: body, createdAt: createdAt, readAt: DateTime.now());
}
