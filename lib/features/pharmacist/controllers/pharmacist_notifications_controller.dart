import 'package:get/get.dart';

import '../../../app/routes/app_routes.dart';
import '../../../core/base/base_controller.dart';
import '../../../core/base/paged.dart';
import '../../../data/models/platform.dart';
import '../../../data/repositories/notification_repository.dart';
import 'pharmacist_badge_controller.dart';

/// Notification centre of the pharmacy (P-73). Order notifications open the order, request notifications the request; text comes from `notif_<kind>`.
class PharmacistNotificationsController extends BaseController {
  PharmacistNotificationsController({NotificationRepository? notifications, void Function(String route)? open})
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

  Future<void> openNotification(AppNotification n) async {
    if (n.isUnread) await markRead(n);
    final String? id = n.entityId;
    if (n.entityType == 'order' && id != null && id.isNotEmpty) {
      _open(AppRoutes.pharmacistOrder(id));
    } else if (n.entityType == 'availability_request' && id != null && id.isNotEmpty) {
      _open(AppRoutes.pharmacistRequest(id));
    }
  }

  Future<void> markRead(AppNotification n) async {
    try {
      await _notifications.markRead(n.id);
    } catch (_) {
      return; // stays unread; marked again the next time it is opened
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
    if (Get.isRegistered<PharmacistBadgeController>()) {
      Get.find<PharmacistBadgeController>().decrement();
    }
  }
}
