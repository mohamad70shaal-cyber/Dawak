import 'dart:async';

import 'package:get/get.dart';

import '../../../app/routes/app_routes.dart';
import '../../../core/base/base_controller.dart';
import '../../../core/base/paged.dart';
import '../../../core/services/session_service.dart';
import '../../../data/models/availability.dart';
import '../../../data/repositories/availability_repository.dart';
import 'pharmacist_badge_controller.dart';

/// Opens a route, optionally handing the tapped row to the next screen (it shows it at once and refreshes behind).
typedef OpenWithArguments = Future<Object?> Function(String route, {Object? arguments});

/// The requests inbox (P-32): customers nearby asking whether the pharmacy has a medicine. Shows the requests waiting for
/// an answer (default) or the last seven days. It never shows who asked; only the medicine and the distance.
/// While the screen is open the list refreshes by itself every [pollInterval].
class AvailabilityInboxController extends BaseController {
  AvailabilityInboxController({
    AvailabilityRepository? availability,
    SessionService? session,
    OpenWithArguments? open,
    this.pollInterval = const Duration(seconds: 20),
  })  : _availability = availability ?? Get.find<AvailabilityRepository>(),
        _session = session ?? Get.find<SessionService>(),
        _open = open ?? ((String r, {Object? arguments}) async=> Get.toNamed<Object?>(r, arguments: arguments)) {
    paged = Paged<InboxRequest>(
      fetch: (int offset, int limit) => _availability.inbox(pharmacyId, onlyOpen: onlyOpen.value, limit: limit, offset: offset),
      pageSize: 30,
    );
  }

  final AvailabilityRepository _availability;
  final SessionService _session;
  final OpenWithArguments _open;
  final Duration pollInterval;

  late final Paged<InboxRequest> paged;

  /// true = only requests still open (the ones waiting or already answered but not closed); false = last 7 days.
  final RxBool onlyOpen = true.obs;

  Timer? _timer;

  String get pharmacyId => _session.pharmacy?.id ?? '';

  bool get canManage => _session.snapshot.canManagePharmacy;

  String get currencyOrDefault => _session.pharmacy?.currency ?? 'SYP';

  /// Requests in the list that still wait for this pharmacy's answer.
  int get waitingCount => paged.items.where((InboxRequest r) => r.isWaiting).length;

  @override
  void onInit() {
    super.onInit();
    status.value = ViewStatus.ready;
  }

  @override
  void onReady() {
    super.onReady();
    paged.reload();
    if (pollInterval > Duration.zero) {
      _timer = Timer.periodic(pollInterval, (Timer _) => refreshSilently());
    }
  }

  @override
  void onClose() {
    _timer?.cancel();
    _timer = null;
    super.onClose();
  }

  /// A failed background refresh keeps the list as it is and shows a toast only when nothing is loaded.
  Future<void> refreshSilently() async {
    await paged.reload(silent: true);
    _updateBadge();
  }

  Future<void> setOnlyOpen(bool value) async {
    if (onlyOpen.value == value) return;
    onlyOpen.value = value;
    await paged.reload();
  }

  Future<void> openRequest(InboxRequest r) async {
    await _open(AppRoutes.pharmacistRequest(r.requestId), arguments: r);
    await paged.reload(silent: true);
    _updateBadge();
  }

  void _updateBadge() {
    if (Get.isRegistered<PharmacistBadgeController>() && onlyOpen.value) {
      Get.find<PharmacistBadgeController>().setOpenRequests(waitingCount);
    }
  }
}
