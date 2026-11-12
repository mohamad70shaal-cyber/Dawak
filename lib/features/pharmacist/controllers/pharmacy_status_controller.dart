import 'package:get/get.dart';

import '../../../app/routes/app_routes.dart';
import '../../../core/base/base_controller.dart';
import '../../../core/services/session_service.dart';
import '../../../core/widgets/app_toast.dart';
import '../../../data/models/pharmacy.dart';

/// The three "no dashboard yet" screens (P-07 pending, P-08 rejected, P-09 suspended). The session already polls
/// every 30 s while pending; [refreshNow] is the manual version.
class PharmacyStatusController extends BaseController {
  PharmacyStatusController({SessionService? session, void Function(String route)? open})
      : _session = session ?? Get.find<SessionService>(),
        _open = open ?? ((String r) => Get.toNamed<dynamic>(r));

  final SessionService _session;
  final void Function(String route) _open;

  /// Reactive pharmacy row (changes when the poll sees a decision).
  Rx<Pharmacy?> get pharmacy => _pharmacy;
  late final Rx<Pharmacy?> _pharmacy = Rx<Pharmacy?>(_session.pharmacy);

  final RxBool refreshing = false.obs;

  @override
  void onInit() {
    super.onInit();
    status.value = ViewStatus.ready;
    ever<dynamic>(_session.state, (dynamic _) => _pharmacy.value = _session.pharmacy);
  }

  String? get reason {
    final String? r = _pharmacy.value?.statusReason;
    return (r == null || r.trim().isEmpty) ? null : r.trim();
  }

  /// Re-reads the application state now. The session navigates by itself when the decision changed.
  Future<void> refreshNow() async {
    if (refreshing.value) return;
    refreshing.value = true;
    try {
      final String before = _session.homeRoute;
      await _session.refresh();
      if (_session.homeRoute == before) AppToast.info('p_status_no_change'.tr);
    } finally {
      refreshing.value = false;
    }
  }

  /// Rejected application: open the wizard prefilled with the submitted data.
  void editAndResubmit() => _open(AppRoutes.pharmacyRegister);

  Future<void> signOut() => _session.signOut();
}
