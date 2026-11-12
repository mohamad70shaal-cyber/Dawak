import 'package:flutter/widgets.dart';
import 'package:get/get.dart';

import '../../../app/routes/app_routes.dart';
import '../../../core/base/base_controller.dart';
import '../../../core/base/shell_controller.dart';
import '../../../core/services/session_service.dart';
import '../../../core/widgets/app_toast.dart';
import '../../../data/models/enums.dart';
import '../../../data/repositories/auth_repository.dart';
import '../auth_kind.dart';

/// Sign-in for all three doors (customer, pharmacist, admin). A valid account used at the wrong door is signed
/// out again and told why, so each app section only ever sees its own role.
class LoginController extends BaseController {
  LoginController(this.kind, {AuthRepository? auth, SessionService? session, OffAll? offAll})
      : _auth = auth ?? Get.find<AuthRepository>(),
        _session = session ?? Get.find<SessionService>(),
        _offAll = offAll ?? defaultOffAll;

  final AuthKind kind;
  final AuthRepository _auth;
  final SessionService _session;
  final OffAll _offAll;

  final GlobalKey<FormState> form = GlobalKey<FormState>();
  final TextEditingController email = TextEditingController();
  final TextEditingController password = TextEditingController();

  /// Message shown above the form (wrong door, session expired).
  final RxnString notice = RxnString();

  @override
  void onInit() {
    super.onInit();
    status.value = ViewStatus.ready;
    if (_session.sessionExpired.value) {
      notice.value = 'auth_session_expired'.tr;
      _session.sessionExpired.value = false;
    }
  }

  Future<void> signIn() async {
    if (!(form.currentState?.validate() ?? false)) return;
    notice.value = null;
    final bool? ok = await submit<bool>(() async {
      await _auth.signIn(email.text.trim(), password.text);
      await _session.restore();
      final bool hasPharmacy = _session.pharmacy != null;
      final bool suspended = _session.snapshot.accountSuspended;
      if (!suspended && !kind.accepts(_session.role!, hasPharmacy: hasPharmacy)) {
        await _session.discardSession();
        notice.value = kind.wrongRoleKey.tr;
        return false;
      }
      return true;
    });
    if (ok == true) {
      password.clear();
      final bool applicant = kind == AuthKind.pharmacist && _session.role == UserRole.customer;
      _offAll(applicant ? AppRoutes.pharmacyRegister : _session.routeAfterLogin());
    }
  }

  /// From the "e-mail not confirmed" error: send the confirmation message again.
  Future<void> resendConfirmation() async {
    final String address = email.text.trim();
    if (address.isEmpty) return;
    final bool? sent = await submit<bool>(() async {
      await _auth.resendConfirmation(address);
      return true;
    });
    if (sent == true) AppToast.success('auth_confirmation_sent'.tr);
  }

  bool get needsConfirmation => failure.value?.code == 'email_not_confirmed';

  @override
  void onClose() {
    email.dispose();
    password.dispose();
    super.onClose();
  }

  String get registerRoute => kind.registerRoute;
}
