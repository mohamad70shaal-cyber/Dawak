import 'dart:async';

import 'package:get/get.dart';

import '../../../core/services/session_service.dart';
import '../../../data/repositories/availability_repository.dart';
import '../../../data/repositories/notification_repository.dart';

/// Counters on the shell's app bar: unread notifications (bell) and customer requests waiting for an answer.
/// Best effort: a failed count keeps the last value. The request count is refreshed every [requestsInterval]
/// while the shell is alive (a new request also arrives as a notification).
class PharmacistBadgeController extends GetxController {
  PharmacistBadgeController({
    NotificationRepository? notifications,
    AvailabilityRepository? availability,
    SessionService? session,
    this.requestsInterval = const Duration(seconds: 60),
  })  : _notifications = notifications ?? Get.find<NotificationRepository>(),
        _availability = availability ?? (Get.isRegistered<AvailabilityRepository>() ? Get.find<AvailabilityRepository>() : null),
        _session = session ?? (Get.isRegistered<SessionService>() ? Get.find<SessionService>() : null);

  final NotificationRepository _notifications;
  final AvailabilityRepository? _availability;
  final SessionService? _session;
  final Duration requestsInterval;

  final RxInt unread = 0.obs;

  /// Requests from customers this pharmacy has not answered yet.
  final RxInt openRequests = 0.obs;

  Timer? _timer;

  @override
  void onReady() {
    super.onReady();
    refreshCount();
    refreshRequests();
    if (requestsInterval > Duration.zero) {
      _timer = Timer.periodic(requestsInterval, (Timer _) => refreshRequests());
    }
  }

  @override
  void onClose() {
    _timer?.cancel();
    _timer = null;
    super.onClose();
  }

  Future<void> refreshCount() async {
    try {
      unread.value = await _notifications.unreadCount();
    } catch (_) {
      // Non-critical: the badge is only a hint.
    }
  }

  Future<void> refreshRequests() async {
    final AvailabilityRepository? repo = _availability;
    final String? pharmacyId = _session?.pharmacy?.id;
    if (repo == null || pharmacyId == null || pharmacyId.isEmpty) return;
    try {
      openRequests.value = await repo.openCount(pharmacyId);
    } catch (_) {
      // Non-critical: the badge is only a hint.
    }
  }

  /// The inbox knows the exact number after each reload.
  void setOpenRequests(int n) => openRequests.value = n < 0 ? 0 : n;

  void decrement() {
    if (unread.value > 0) unread.value = unread.value - 1;
  }
}
