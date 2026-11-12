import 'package:flutter/widgets.dart';
import 'package:get/get.dart';

import '../../../core/base/base_controller.dart';
import '../../../data/repositories/auth_repository.dart';

class PasswordResetController extends BaseController {
  PasswordResetController({AuthRepository? auth}) : _auth = auth ?? Get.find<AuthRepository>();

  final AuthRepository _auth;

  final GlobalKey<FormState> form = GlobalKey<FormState>();
  final TextEditingController email = TextEditingController();
  final RxBool sent = false.obs;

  @override
  void onInit() {
    super.onInit();
    status.value = ViewStatus.ready;
  }

  /// The confirmation never reveals whether the address is registered.
  Future<void> send() async {
    if (!(form.currentState?.validate() ?? false)) return;
    final bool? ok = await submit<bool>(() async {
      await _auth.resetPassword(email.text.trim());
      return true;
    });
    if (ok == true) sent.value = true;
  }

  @override
  void onClose() {
    email.dispose();
    super.onClose();
  }
}
