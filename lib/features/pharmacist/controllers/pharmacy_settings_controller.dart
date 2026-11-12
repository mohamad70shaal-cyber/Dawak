import 'package:flutter/widgets.dart';
import 'package:get/get.dart';

import '../../../core/base/base_controller.dart';
import '../../../core/services/locale_service.dart';
import '../../../core/services/session_service.dart';
import '../../../core/widgets/app_toast.dart';
import '../../../data/models/enums.dart';
import '../../../data/models/geo.dart';
import '../../../data/models/pharmacy.dart';
import '../../../data/repositories/auth_repository.dart';
import '../../../data/repositories/pharmacy_repository.dart';
import 'pharmacy_registration_controller.dart';
import 'shop_location_input.dart';

/// Settings hub (P-S0) and its screens: pharmacy profile (P-67), address and phone (P-68), opening hours (P-69), account
/// and security (P-70) and sign-out (P-72). Only the owner can change the pharmacy's data (the database enforces it);
/// managers and cashiers see the same screens read-only.
class PharmacySettingsController extends BaseController {
  PharmacySettingsController({
    PharmacyRepository? pharmacies,
    AuthRepository? auth,
    SessionService? session,
    LocaleService? locale,
    ShopLocationInput? location,
    void Function()? close,
  })  : location = location ?? ShopLocationInput(),
        _pharmacies = pharmacies ?? Get.find<PharmacyRepository>(),
        _auth = auth ?? Get.find<AuthRepository>(),
        _session = session ?? Get.find<SessionService>(),
        _locale = locale ?? Get.find<LocaleService>(),
        _close = close ?? (() => Get.back<dynamic>());

  final PharmacyRepository _pharmacies;
  final AuthRepository _auth;
  final SessionService _session;
  final LocaleService _locale;
  final void Function() _close;

  /// The shop's position (settings screen P-74). Only the owner can save a new one.
  final ShopLocationInput location;

  final GlobalKey<FormState> profileForm = GlobalKey<FormState>();
  final GlobalKey<FormState> contactForm = GlobalKey<FormState>();
  final GlobalKey<FormState> passwordForm = GlobalKey<FormState>();

  final TextEditingController name = TextEditingController();
  final TextEditingController phone = TextEditingController();
  final TextEditingController addressLine = TextEditingController();
  final TextEditingController neighborhood = TextEditingController();
  final TextEditingController city = TextEditingController();
  final TextEditingController directions = TextEditingController();
  final TextEditingController newPassword = TextEditingController();
  final TextEditingController confirmPassword = TextEditingController();

  final RxBool isListed = true.obs;
  final RxBool showPhonePublicly = true.obs;
  final Rx<OpeningHours> hours = OpeningHours.defaults().obs;
  final Rxn<Pharmacy> pharmacy = Rxn<Pharmacy>();

  /// Shown on the hours screen (closed all week, or closing before opening).
  final RxnString hoursError = RxnString();

  MemberRole? get role => _session.memberRole;

  /// Only owners may edit the pharmacy (`update_my_pharmacy`).
  bool get canEdit => role == MemberRole.owner;

  bool get canManage => _session.snapshot.canManagePharmacy;

  String get email => _session.email;

  bool get isArabic => _locale.isArabic;

  @override
  void onInit() {
    super.onInit();
    status.value = ViewStatus.ready;
    fillForms();
    ever<dynamic>(_session.state, (dynamic _) => fillForms());
  }

  @override
  void onClose() {
    for (final TextEditingController c in <TextEditingController>[name, phone, addressLine, neighborhood, city, directions, newPassword, confirmPassword]) {
      c.dispose();
    }
    location.dispose();
    super.onClose();
  }

  /// Copies the stored pharmacy into the forms (also discards unsaved edits).
  void fillForms() {
    final Pharmacy? p = _session.pharmacy;
    pharmacy.value = p;
    if (p == null) return;
    name.text = p.name;
    phone.text = p.phone;
    addressLine.text = p.addressLine;
    neighborhood.text = p.neighborhood;
    city.text = p.city;
    directions.text = p.directions;
    isListed.value = p.isListed;
    showPhonePublicly.value = p.showPhonePublicly;
    hours.value = p.hours;
    hoursError.value = null;
    location.setInitial(p.location);
  }

  Future<bool> _save(Future<Pharmacy> Function(String id) call) async {
    final Pharmacy? p = _session.pharmacy;
    if (p == null || !canEdit || submitting.value) return false;
    final Pharmacy? updated = await submit<Pharmacy>(() => call(p.id));
    if (updated == null) return false;
    await _session.refresh(navigateOnChange: false);
    AppToast.success('p_settings_saved'.tr);
    _close();
    return true;
  }

  Future<bool> saveProfile() async {
    if (!(profileForm.currentState?.validate() ?? false)) return false;
    return _save((String id) => _pharmacies.updateMine(id, name: name.text, isListed: isListed.value));
  }

  Future<bool> saveContact() async {
    if (!(contactForm.currentState?.validate() ?? false)) return false;
    return _save((String id) => _pharmacies.updateMine(
          id,
          phone: phone.text,
          showPhonePublicly: showPhonePublicly.value,
          addressLine: addressLine.text,
          neighborhood: neighborhood.text,
          city: city.text,
          directions: directions.text,
        ));
  }

  /// Saves the position chosen on the location screen. Nothing happens when no position was chosen.
  Future<bool> saveLocation() async {
    final GeoPoint? p = location.point.value;
    if (p == null) return false;
    return _save((String id) => _pharmacies.updateMine(id, location: p));
  }

  void setDayOpen(int day, bool open) => _replaceDay(day, (DayHours d) => d.copyWith(open: open));

  void setDayTime(int day, {required bool from, required String value}) =>
      _replaceDay(day, (DayHours d) => from ? d.copyWith(from: value) : d.copyWith(to: value));

  void _replaceDay(int day, DayHours Function(DayHours) change) {
    if (!canEdit) return;
    final List<DayHours> days = List<DayHours>.of(hours.value.days);
    final int i = days.indexWhere((DayHours d) => d.day == day);
    if (i < 0) return;
    days[i] = change(days[i]);
    hours.value = OpeningHours(days);
    hoursError.value = null;
  }

  Future<bool> saveHours() async {
    final List<DayHours> days = hours.value.days;
    if (!days.any((DayHours d) => d.open)) {
      hoursError.value = 'p_reg_hours_none_open'.tr;
      return false;
    }
    if (!days.every(PharmacyRegistrationController.dayIsValid)) {
      hoursError.value = 'p_reg_hours_invalid'.tr;
      return false;
    }
    hoursError.value = null;
    return _save((String id) => _pharmacies.updateMine(id, hours: hours.value));
  }

  /// Changes the sign-in password (the current session stays signed in).
  Future<bool> changePassword() async {
    if (submitting.value) return false;
    if (!(passwordForm.currentState?.validate() ?? false)) return false;
    final bool? ok = await submit<bool>(() async {
      await _auth.updatePassword(newPassword.text);
      return true;
    });
    if (ok == null) return false;
    newPassword.clear();
    confirmPassword.clear();
    AppToast.success('p_security_password_changed'.tr);
    _close();
    return true;
  }

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
