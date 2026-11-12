import 'package:flutter/widgets.dart';
import 'package:get/get.dart';

import '../../../app/routes/app_routes.dart';
import '../../../core/base/base_controller.dart';
import '../../../core/base/shell_controller.dart';
import '../../../core/services/session_service.dart';
import '../../../data/repositories/auth_repository.dart';
import '../auth_kind.dart';

/// Account creation for customers and pharmacists. Admin accounts are never self-registered.
class RegisterController extends BaseController {
  RegisterController(this.kind, {AuthRepository? auth, SessionService? session, OffAll? offAll})
      : assert(kind != AuthKind.admin),
        _auth = auth ?? Get.find<AuthRepository>(),
        _session = session ?? Get.find<SessionService>(),
        _offAll = offAll ?? defaultOffAll;

  final AuthKind kind;
  final AuthRepository _auth;
  final SessionService _session;
  final OffAll _offAll;

  final GlobalKey<FormState> form = GlobalKey<FormState>();
  final TextEditingController name = TextEditingController();
  final TextEditingController email = TextEditingController();
  final TextEditingController password = TextEditingController();
  final TextEditingController confirm = TextEditingController();
  final RxBool acceptedTerms = false.obs;
  final RxBool termsError = false.obs;

  @override
  void onInit() {
    super.onInit();
    status.value = ViewStatus.ready;
  }

  Future<void> register() async {
    termsError.value = !acceptedTerms.value;
    final bool valid = form.currentState?.validate() ?? false;
    if (!valid || !acceptedTerms.value) return;

    final bool? opened = await submit<bool>(() => _auth.signUp(
          email: email.text.trim(),
          password: password.text,
          displayName: name.text.trim(),
        ));
    if (opened == null) return;
    if (opened) {
      await _session.restore();
      _offAll(kind == AuthKind.pharmacist ? AppRoutes.pharmacyRegister : _session.homeRoute);
    } else {
      _offAll(AppRoutes.verifyEmail, arguments: <String, String>{'email': email.text.trim(), 'kind': kind.name});
    }
  }

  @override
  void onClose() {
    name.dispose();
    email.dispose();
    password.dispose();
    confirm.dispose();
    super.onClose();
  }
}
