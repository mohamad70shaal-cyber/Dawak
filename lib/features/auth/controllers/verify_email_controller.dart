import 'package:get/get.dart';

import '../../../core/base/base_controller.dart';
import '../../../core/widgets/app_toast.dart';
import '../../../data/repositories/auth_repository.dart';
import '../auth_kind.dart';

/// "Check your inbox" screen after sign-up when the project requires e-mail confirmation.
class VerifyEmailController extends BaseController {
  VerifyEmailController({AuthRepository? auth, Map<String, dynamic>? arguments})
      : this._(auth ?? Get.find<AuthRepository>(), arguments ?? _routeArguments());

  VerifyEmailController._(this._auth, Map<String, dynamic> args)
      : email = (args['email'] ?? '').toString(),
        kind = AuthKind.values.firstWhere(
          (AuthKind k) => k.name == (args['kind'] ?? '').toString(),
          orElse: () => AuthKind.customer,
        );

  static Map<String, dynamic> _routeArguments() {
    final Object? a = Get.arguments;
    return a is Map ? Map<String, dynamic>.from(a) : <String, dynamic>{};
  }

  final AuthRepository _auth;
  final String email;
  final AuthKind kind;

  @override
  void onInit() {
    super.onInit();
    status.value = ViewStatus.ready;
  }

  Future<void> resend() async {
    if (email.isEmpty) return;
    final bool? ok = await submit<bool>(() async {
      await _auth.resendConfirmation(email);
      return true;
    });
    if (ok == true) AppToast.success('auth_confirmation_sent'.tr);
  }
}
