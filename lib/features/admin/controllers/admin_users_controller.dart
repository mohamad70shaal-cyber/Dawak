import 'package:get/get.dart';

import '../../../core/base/base_controller.dart';
import '../../../core/base/paged.dart';
import '../../../core/services/session_service.dart';
import '../../../core/widgets/app_toast.dart';
import '../../../data/models/enums.dart';
import '../../../data/models/platform.dart';
import '../../../data/repositories/admin_repository.dart';
import '../services/admin_dialog_hooks.dart';

enum AccountRoleFilter {
  all,
  pharmacist,
  admin;

  /// The `role` to ask for, or null for pharmacists and admins together.
  String? get role => this == AccountRoleFilter.all ? null : name;
}

/// Pharmacist and admin accounts (A-12): search, suspend and reactivate. Customers are not listed (privacy), an
/// administrator cannot suspend themselves or another administrator (the database refuses it too), so those rows
/// have no actions.
class AdminUsersController extends BaseController {
  AdminUsersController({AdminRepository? admin, SessionService? session, AdminConfirmFn? confirm, AdminReasonFn? askReason})
      : _admin = admin ?? Get.find<AdminRepository>(),
        _session = session ?? Get.find<SessionService>(),
        _confirm = confirm ?? adminConfirm,
        _askReason = askReason ?? adminReason {
    paged = Paged<AccountSummary>(
      fetch: (int offset, int limit) => _admin.accounts(text: _text, role: role.value.role, limit: limit, offset: offset),
      pageSize: 30,
    );
  }

  final AdminRepository _admin;
  final SessionService _session;
  final AdminConfirmFn _confirm;
  final AdminReasonFn _askReason;

  late final Paged<AccountSummary> paged;
  final Rx<AccountRoleFilter> role = AccountRoleFilter.all.obs;

  String _text = '';

  String get myId => _session.profile?.id ?? '';

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

  void search(String text) {
    final String t = text.trim();
    if (t == _text) return;
    _text = t;
    paged.reload();
  }

  void setRole(AccountRoleFilter f) {
    if (role.value == f) return;
    role.value = f;
    paged.reload();
  }

  Future<void> refreshList() => paged.reload(silent: true);

  /// Whether the admin may change this account's status.
  bool canChange(AccountSummary a) => a.role != UserRole.admin && a.id != myId;

  Future<bool> _apply(Future<void> Function() call, String successKey) async {
    final bool? ok = await submit<bool>(() async {
      await call();
      return true;
    });
    if (ok == null) {
      await paged.reload(silent: true);
      return false;
    }
    AppToast.success(successKey.tr);
    await paged.reload(silent: true);
    return true;
  }

  Future<bool> suspend(AccountSummary a) async {
    if (!canChange(a) || a.suspended || submitting.value) return false;
    final String? reason = await _askReason(
      title: 'a_user_suspend_title'.tr,
      label: 'a_user_reason'.tr,
      message: 'a_user_suspend_message'.trParams(<String, String>{'name': a.displayName}),
      confirmLabel: 'a_user_suspend'.tr,
      minLength: 3,
      destructive: true,
    );
    if (reason == null) return false;
    return _apply(() => _admin.setAccountStatus(a.id, suspended: true, reason: reason), 'a_user_suspended');
  }

  Future<bool> reactivate(AccountSummary a) async {
    if (!canChange(a) || !a.suspended || submitting.value) return false;
    final bool ok = await _confirm(
      title: 'a_user_reactivate_title'.tr,
      message: 'a_user_reactivate_message'.trParams(<String, String>{'name': a.displayName}),
      confirmLabel: 'a_user_reactivate'.tr,
    );
    if (!ok) return false;
    return _apply(() => _admin.setAccountStatus(a.id, suspended: false), 'a_user_reactivated');
  }
}
