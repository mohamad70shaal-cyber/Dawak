import 'package:get/get.dart';

import '../../../app/routes/app_routes.dart';
import '../../../core/base/base_controller.dart';
import '../../../core/errors/app_failure.dart';
import '../../../core/widgets/app_toast.dart';
import '../../../data/models/platform.dart';
import '../../../data/repositories/admin_repository.dart';
import '../services/admin_dialog_hooks.dart';
import '../services/admin_refresh.dart';

/// Reviewing one user report (A-11): start the review, resolve or dismiss it with an optional note. A report that
/// points at a pharmacy or a medicine links to it. Resolved and dismissed reports are final (read-only).
class AdminReportDetailsController extends BaseController {
  AdminReportDetailsController({
    String? reportId,
    AdminRepository? admin,
    AdminReasonFn? askNote,
    Future<Object?> Function(String route)? open,
  })  : _reportId = reportId,
        _admin = admin ?? Get.find<AdminRepository>(),
        _askNote = askNote ?? adminReason,
        _open = open ?? ((String r) async=> Get.toNamed<Object?>(r));

  final String? _reportId;
  final AdminRepository _admin;
  final AdminReasonFn _askNote;
  final Future<Object?> Function(String route) _open;

  final Rxn<UserReport> report = Rxn<UserReport>();
  final RxnString notice = RxnString();

  String get id => _reportId ?? Get.parameters['id'] ?? '';

  String? get state => report.value?.status;

  bool get canStartReview => state == 'open';
  bool get canResolve => report.value?.isOpen ?? false;
  bool get canDismiss => report.value?.isOpen ?? false;

  /// The screen the report is about, when there is one the admin can open.
  String? get targetRoute {
    final UserReport? r = report.value;
    final String? target = r?.targetId;
    if (r == null || target == null || target.isEmpty) return null;
    switch (r.targetType) {
      case 'pharmacy':
        return AppRoutes.adminPharmacy(target);
      case 'medicine':
        return AppRoutes.adminMedicine(target);
      default:
        return null;
    }
  }

  @override
  void onReady() {
    super.onReady();
    refresh();
  }

  Future<void> refresh({bool silent = false}) => load(() async {
        final UserReport? r = await _admin.report(id);
        if (r == null) throw const AppFailure('not_found');
        report.value = r;
      }, silent: silent);

  Future<void> openTarget() async {
    final String? route = targetRoute;
    if (route != null) await _open(route);
  }

  Future<bool> _set(String status, String successKey, {String? note}) async {
    final bool? ok = await submit<bool>(() async {
      await _admin.resolveReport(id, status, note: note);
      return true;
    }, toast: false);
    if (ok == null) {
      final AppFailure? f = failure.value;
      notice.value = f == null ? null : failureText(f);
      await refresh(silent: true);
      AdminRefresh.reportsChanged();
      return false;
    }
    notice.value = null;
    AppToast.success(successKey.tr);
    await refresh(silent: true);
    AdminRefresh.reportsChanged();
    return true;
  }

  Future<bool> startReview() async {
    if (!canStartReview || submitting.value) return false;
    return _set('in_review', 'a_report_in_review_done');
  }

  Future<bool> resolve() async {
    if (!canResolve || submitting.value) return false;
    final String? note = await _askNote(
      title: 'a_report_resolve_title'.tr,
      label: 'a_report_note'.tr,
      message: 'a_report_resolve_message'.tr,
      confirmLabel: 'a_report_resolve'.tr,
      minLength: 0,
      destructive: false,
    );
    if (note == null) return false;
    return _set('resolved', 'a_report_resolved_done', note: note);
  }

  Future<bool> dismiss() async {
    if (!canDismiss || submitting.value) return false;
    final String? note = await _askNote(
      title: 'a_report_dismiss_title'.tr,
      label: 'a_report_note'.tr,
      message: 'a_report_dismiss_message'.tr,
      confirmLabel: 'a_report_dismiss'.tr,
      minLength: 0,
      destructive: false,
    );
    if (note == null) return false;
    return _set('dismissed', 'a_report_dismissed_done', note: note);
  }
}
