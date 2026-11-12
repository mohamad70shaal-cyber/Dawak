import 'package:get/get.dart';

import '../../../app/routes/app_routes.dart';
import '../../../core/base/base_controller.dart';
import '../../../core/base/paged.dart';
import '../../../data/models/platform.dart';
import '../../../data/repositories/notification_repository.dart';
import 'notification_badge_controller.dart';

/// Notification centre (C-26). Text comes from `notif_<kind>`; unknown kinds fall back to `notif_generic`.
class NotificationsController extends BaseController {
  NotificationsController({NotificationRepository? notifications, void Function(String route)? open})
      : _notifications = notifications ?? Get.find<NotificationRepository>(),
        _open = open ?? ((String r) => Get.toNamed<dynamic>(r)) {
    paged = Paged<AppNotification>(
      fetch: (int offset, int limit) => _notifications.list(limit: limit, offset: offset),
      pageSize: 30,
    );
  }

  final NotificationRepository _notifications;
  final void Function(String route) _open;
  late final Paged<AppNotification> paged;

  @override
  void onInit() {
    super.onInit();
    status.value = ViewStatus.ready;
  }

  @override
  void onReady() {
    super.onReady();
    paged.reload();
  }

  String textFor(AppNotification n) {
    final String key = 'notif_${n.kind}';
    final String t = key.trParams(<String, String>{'ref': n.ref, 'medicine': n.medicine, 'pharmacy': n.pharmacy});
    return t == key ? 'notif_generic'.tr : t;
  }

  /// Marks [n] read (kept unread when the server call fails) and opens the order or request it is about.
  Future<void> openNotification(AppNotification n) async {
    if (n.isUnread) await markRead(n);
    final String? id = n.entityId;
    if (n.entityType == 'order' && id != null && id.isNotEmpty) {
      _open(AppRoutes.customerOrder(id));
    } else if (n.entityType == 'availability_request' && id != null && id.isNotEmpty) {
      _open(AppRoutes.customerRequest(id));
    }
  }

  Future<void> markRead(AppNotification n) async {
    try {
      await _notifications.markRead(n.id);
    } catch (_) {
      // Stays unread and is marked again the next time it is opened.
      return;
    }
    paged.replaceWhere(
      (AppNotification x) => x.id == n.id,
      AppNotification(
        id: n.id,
        kind: n.kind,
        params: n.params,
        createdAt: n.createdAt,
        entityType: n.entityType,
        entityId: n.entityId,
        readAt: DateTime.now(),
      ),
    );
    if (Get.isRegistered<NotificationBadgeController>()) {
      Get.find<NotificationBadgeController>().decrement();
    }
  }
}
