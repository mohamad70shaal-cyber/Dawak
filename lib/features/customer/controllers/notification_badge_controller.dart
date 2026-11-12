import 'package:get/get.dart';

import '../../../data/repositories/notification_repository.dart';

/// Unread-notification count shown on the bell (shell app bar) and the profile entry. Best effort: a failed
/// count simply keeps the last value.
class NotificationBadgeController extends GetxController {
  NotificationBadgeController({NotificationRepository? notifications})
      : _notifications = notifications ?? Get.find<NotificationRepository>();

  final NotificationRepository _notifications;
  final RxInt unread = 0.obs;

  @override
  void onReady() {
    super.onReady();
    refreshCount();
  }

  Future<void> refreshCount() async {
    try {
      unread.value = await _notifications.unreadCount();
    } catch (_) {
      // Non-critical: the badge is only a hint.
    }
  }

  void decrement() {
    if (unread.value > 0) unread.value = unread.value - 1;
  }
}
