import 'package:get/get.dart';

import '../../../core/services/locale_service.dart';
import '../../../core/services/session_service.dart';
import '../../../data/repositories/auth_repository.dart';

/// The admin's own account in the drawer: who is signed in, the language and sign-out.
class AdminAccountController extends GetxController {
  AdminAccountController({SessionService? session, LocaleService? locale, AuthRepository? auth})
      : _session = session ?? Get.find<SessionService>(),
        _locale = locale ?? Get.find<LocaleService>(),
        _auth = auth ?? Get.find<AuthRepository>();

  final SessionService _session;
  final LocaleService _locale;
  final AuthRepository _auth;

  String get name => _session.profile?.displayName ?? '';

  String get email => _session.email;

  bool get isArabic => _locale.isArabic;

  Future<void> toggleLanguage() async {
    await _locale.toggle();
    try {
      await _auth.updateProfile(locale: _locale.locale.value.languageCode);
    } catch (_) {
      // Only the profile copy is missing; the device setting already applies.
    }
  }

  Future<void> signOut() => _session.signOut();
}
