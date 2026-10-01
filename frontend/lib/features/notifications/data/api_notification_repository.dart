import '../../../core/network/api_client.dart';
import '../../../routing/app_routes.dart';
import 'notification_models.dart';

/// Notifications (§31) against the real backend.
///
/// There is no create method, and that is the design: notifications are
/// RAISED by the events that cause them, inside the transaction that causes
/// them, so a notification cannot describe something that was rolled back. A
/// client that could post one could announce a sale that never happened.
class ApiNotificationRepository {
  ApiNotificationRepository(this._client);

  final ApiClient _client;

  static const _types = <String, NotificationType>{
    'low_stock': NotificationType.lowStock,
    'out_of_stock': NotificationType.outOfStock,
    'new_order': NotificationType.newOrder,
    'return_request': NotificationType.returnRequest,
    'pending_payment': NotificationType.pendingPayment,
    'production_completed': NotificationType.productionCompleted,
    'transfer_received': NotificationType.transferReceived,
    'system_alert': NotificationType.systemAlert,
  };

  /// Where tapping this notification goes. The server says what a row is
  /// ABOUT (`referenceType` + `referenceId`); which screen shows that thing is
  /// the client's own business, so the mapping lives here.
  ///
  /// An unrecognised type yields null rather than a guess — sending a reader
  /// somewhere arbitrary is worse than not moving.
  static String? _route(String? referenceType, Object? referenceId) {
    if (referenceType == null || referenceId == null) return null;
    final id = '$referenceId';
    return switch (referenceType) {
      'products' => AppRoutes.productDetail(id),
      'orders' => AppRoutes.orderDetail(id),
      'returns' => AppRoutes.returnDetail(id),
      'production_orders' => AppRoutes.productionDetail(id),
      // §11's transfers are documents on the server but the client shows them
      // inside Inventory rather than on a page of their own.
      'stock_transfers' => AppRoutes.inventory,
      _ => null,
    };
  }

  static AppNotification _fromJson(Map<String, dynamic> json) => AppNotification(
    id: '${json['id']}',
    type: _types[json['type']] ?? NotificationType.systemAlert,
    title: (json['title'] as String?) ?? '',
    body: (json['body'] as String?) ?? '',
    createdAt: DateTime.tryParse('${json['createdAt']}') ?? DateTime.now(),
    readAt: json['readAt'] == null ? null : DateTime.tryParse('${json['readAt']}'),
    targetRoute: _route(json['referenceType'] as String?, json['referenceId']),
  );

  /// One page, newest first. The bell menu shows a recent list rather than an
  /// archive, and the count below is what the badge actually needs.
  Future<List<AppNotification>> list({int pageSize = 50}) async {
    final result = await _client.getList('/notifications?pageSize=$pageSize&sort=createdAt&direction=desc');
    return result.data.map((row) => _fromJson(row as Map<String, dynamic>)).toList();
  }

  Future<int> unreadCount() async {
    final json = await _client.getJson('/notifications/unread-count');
    return (json['unread'] as num?)?.toInt() ?? 0;
  }

  Future<void> markRead(String id) => _client.patchJson('/notifications/$id/read', const {});

  Future<void> markAllRead() => _client.patchJson('/notifications/read-all', const {});
}
