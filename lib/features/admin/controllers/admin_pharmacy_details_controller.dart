import 'package:get/get.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/base/base_controller.dart';
import '../../../core/errors/app_failure.dart';
import '../../../core/widgets/app_toast.dart';
import '../../../data/datasources/api_client.dart';
import '../../../data/models/enums.dart';
import '../../../data/models/pharmacy.dart';
import '../../../data/models/platform.dart';
import '../../../data/repositories/pharmacy_repository.dart';
import '../services/admin_dialog_hooks.dart';
import '../services/admin_refresh.dart';

Future<bool> _launchExternal(String url) => launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);

/// One pharmacy application or pharmacy as an administrator sees it (A-04, A-05, A-06): the data, the owner, the licence
/// document (a short-lived signed link) and the review actions that fit the current state.
///
/// Approve and reject are for pending applications, suspend for approved pharmacies, reinstate for suspended ones.
/// Reject and suspend need a reason, which the pharmacy owner is shown. After a refusal the record is re-read so the
/// buttons always match the server's state (another administrator may have decided in the meantime).
class AdminPharmacyDetailsController extends BaseController {
  AdminPharmacyDetailsController({
    String? pharmacyId,
    PharmacyRepository? pharmacies,
    FileStore? files,
    AdminConfirmFn? confirm,
    AdminReasonFn? askReason,
    Future<bool> Function(String url)? openUrl,
  })  : _pharmacyId = pharmacyId,
        _pharmacies = pharmacies ?? Get.find<PharmacyRepository>(),
        _files = files ?? Get.find<FileStore>(),
        _confirm = confirm ?? adminConfirm,
        _askReason = askReason ?? adminReason,
        _openUrl = openUrl ?? _launchExternal;

  final String? _pharmacyId;
  final PharmacyRepository _pharmacies;
  final FileStore _files;
  final AdminConfirmFn _confirm;
  final AdminReasonFn _askReason;
  final Future<bool> Function(String url) _openUrl;

  final Rxn<PharmacyApplication> application = Rxn<PharmacyApplication>();
  final RxnString notice = RxnString();

  String get id => _pharmacyId ?? Get.parameters['id'] ?? '';

  Pharmacy? get pharmacy => application.value?.pharmacy;

  ApprovalStatus? get state => pharmacy?.status;

  bool get canApprove => state == ApprovalStatus.pending;
  bool get canReject => state == ApprovalStatus.pending;
  bool get canSuspend => state == ApprovalStatus.approved;
  bool get canReinstate => state == ApprovalStatus.suspended;

  bool get hasLicense => (pharmacy?.licensePath ?? '').isNotEmpty;

  @override
  void onReady() {
    super.onReady();
    refresh();
  }

  Future<void> refresh({bool silent = false}) => load(() async {
        final PharmacyApplication? a = await _pharmacies.adminGet(id);
        if (a == null) throw const AppFailure('not_found');
        application.value = a;
      }, silent: silent);

  /// Opens the licence document outside the app through a link that stops working after a few minutes.
  Future<bool> viewLicense() async {
    final String path = pharmacy?.licensePath ?? '';
    if (path.isEmpty || submitting.value) return false;
    final bool? opened = await submit<bool>(() async {
      final String url = await _files.signedLicenseUrl(path);
      return _openUrl(url);
    });
    if (opened == null) return false;
    if (!opened) AppToast.error('a_license_open_failed'.tr);
    return opened;
  }

  String _explain(AppFailure f) => f.code == 'invalid_transition' ? 'a_pharmacy_notice_changed'.tr : failureText(f);

  Future<bool> _review(String decision, String successKey, {String? reason}) async {
    final bool? ok = await submit<bool>(() async {
      await _pharmacies.adminReview(id, decision, reason: reason);
      return true;
    }, toast: false);
    if (ok == null) {
      final AppFailure? f = failure.value;
      notice.value = f == null ? null : _explain(f);
      await refresh(silent: true);
      AdminRefresh.pharmaciesChanged();
      return false;
    }
    notice.value = null;
    AppToast.success(successKey.tr);
    await refresh(silent: true);
    AdminRefresh.pharmaciesChanged();
    return true;
  }

  Future<bool> approve() async {
    if (!canApprove || submitting.value) return false;
    final bool ok = await _confirm(
      title: 'a_pharmacy_approve_title'.tr,
      message: 'a_pharmacy_approve_message'.tr,
      confirmLabel: 'a_pharmacy_approve'.tr,
    );
    if (!ok) return false;
    return _review('approve', 'a_pharmacy_approved');
  }

  Future<bool> reject() async {
    if (!canReject || submitting.value) return false;
    final String? reason = await _askReason(
      title: 'a_pharmacy_reject_title'.tr,
      label: 'a_pharmacy_reason'.tr,
      message: 'a_pharmacy_reject_message'.tr,
      confirmLabel: 'a_pharmacy_reject'.tr,
      minLength: 3,
      destructive: true,
    );
    if (reason == null) return false;
    return _review('reject', 'a_pharmacy_rejected', reason: reason);
  }

  Future<bool> suspend() async {
    if (!canSuspend || submitting.value) return false;
    final String? reason = await _askReason(
      title: 'a_pharmacy_suspend_title'.tr,
      label: 'a_pharmacy_reason'.tr,
      message: 'a_pharmacy_suspend_message'.tr,
      confirmLabel: 'a_pharmacy_suspend'.tr,
      minLength: 3,
      destructive: true,
    );
    if (reason == null) return false;
    return _review('suspend', 'a_pharmacy_suspended', reason: reason);
  }

  Future<bool> reinstate() async {
    if (!canReinstate || submitting.value) return false;
    final bool ok = await _confirm(
      title: 'a_pharmacy_reinstate_title'.tr,
      message: 'a_pharmacy_reinstate_message'.tr,
      confirmLabel: 'a_pharmacy_reinstate'.tr,
    );
    if (!ok) return false;
    return _review('reinstate', 'a_pharmacy_reinstated');
  }
}
