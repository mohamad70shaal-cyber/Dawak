import 'package:flutter/widgets.dart';
import 'package:get/get.dart';

import '../../../core/base/base_controller.dart';
import '../../../core/services/locale_service.dart';
import '../../../core/services/session_service.dart';
import '../../../core/utils/phone_utils.dart';
import '../../../core/widgets/app_toast.dart';
import '../../../data/models/profile.dart';
import '../../../data/repositories/auth_repository.dart';

/// Profile tab (C-24) and edit profile (C-25).
class CustomerProfileController extends BaseController {
  CustomerProfileController({
    AuthRepository? auth,
    SessionService? session,
    LocaleService? locale,
    VoidCallback? onSaved,
  })  : _auth = auth ?? Get.find<AuthRepository>(),
        _session = session ?? Get.find<SessionService>(),
        _locale = locale ?? Get.find<LocaleService>(),
        _onSaved = onSaved ?? Get.back<dynamic>;

  final AuthRepository _auth;
  final SessionService _session;
  final LocaleService _locale;
  final VoidCallback _onSaved;

  final GlobalKey<FormState> form = GlobalKey<FormState>();
  final TextEditingController name = TextEditingController();
  final TextEditingController phone = TextEditingController();

  Profile? get profile => _session.profile;
  String get email => _session.email;
  bool get isArabic => _locale.isArabic;

  @override
  void onInit() {
    super.onInit();
    status.value = ViewStatus.ready;
    fillForm();
  }

  @override
  void onClose() {
    name.dispose();
    phone.dispose();
    super.onClose();
  }

  /// Copies the current profile into the edit form (also used to discard edits).
  void fillForm() {
    final Profile? p = profile;
    name.text = p?.displayName ?? '';
    phone.text = p?.phone ?? '';
  }

  Future<bool> save() async {
    if (submitting.value) return false;
    if (!(form.currentState?.validate() ?? false)) return false;
    final String rawPhone = phone.text.trim();
    final Profile? saved = await submit<Profile>(
      () => _auth.updateProfile(displayName: name.text.trim(), phone: rawPhone.isEmpty ? '' : (cleanPhone(rawPhone) ?? rawPhone)),
    );
    if (saved == null) return false;
    await _session.refresh(navigateOnChange: false);
    AppToast.success('c_profile_saved'.tr);
    _onSaved();
    return true;
  }

  /// Switches Arabic/English. The choice is stored on the device and, best effort, on the profile.
  Future<void> toggleLanguage() async {
    await _locale.toggle();
    try {
      await _auth.updateProfile(locale: _locale.locale.value.languageCode);
    } catch (_) {
      // Only the profile copy is missing; the device setting already applies.
    }
  }

  Future<void> signOut() async {
    await submit<bool>(() async {
      await _session.signOut();
      return true;
    });
  }
}
