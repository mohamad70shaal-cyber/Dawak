import 'package:flutter/widgets.dart';
import 'package:get/get.dart';

import '../../../app/routes/app_routes.dart';
import '../../../core/base/base_controller.dart';
import '../../../core/base/shell_controller.dart';
import '../../../core/errors/app_failure.dart';
import '../../../core/services/session_service.dart';
import '../../../core/utils/validators.dart';
import '../../../core/widgets/app_toast.dart';
import '../../../data/datasources/api_client.dart';
import '../../../data/models/enums.dart';
import '../../../data/models/pharmacy.dart';
import '../../../data/repositories/pharmacy_repository.dart';
import '../services/license_picker.dart';
import 'shop_location_input.dart';

/// Pharmacy registration wizard (P-03 … P-06): licence → information → address → hours + review.
///
/// One controller serves the four routes. Nothing is sent before the last step: the licence file is uploaded and
/// the application submitted together, so an abandoned wizard leaves nothing behind. A rejected pharmacy opens the
/// same wizard prefilled and resubmits (`resubmit_pharmacy`); its old licence stays valid unless a new one is picked.
class PharmacyRegistrationController extends BaseController {
  PharmacyRegistrationController({
    PharmacyRepository? pharmacies,
    FileStore? files,
    SessionService? session,
    LicensePicker? picker,
    ShopLocationInput? location,
    OffAll? offAll,
    void Function(String route)? open,
  })  : _pharmacies = pharmacies ?? Get.find<PharmacyRepository>(),
        _files = files ?? Get.find<FileStore>(),
        _session = session ?? Get.find<SessionService>(),
        _pick = picker ?? LicenseFiles.pick,
        location = location ?? ShopLocationInput(),
        _offAll = offAll ?? defaultOffAll,
        _open = open ?? ((String r) => Get.toNamed<dynamic>(r));

  final PharmacyRepository _pharmacies;
  final FileStore _files;
  final SessionService _session;
  final LicensePicker _pick;

  /// The shop's position (required to continue from the address step).
  final ShopLocationInput location;

  /// Shown on the address step when no position was chosen.
  final RxnString locationError = RxnString();
  final OffAll _offAll;
  final void Function(String route) _open;

  final GlobalKey<FormState> infoForm = GlobalKey<FormState>();
  final GlobalKey<FormState> addressForm = GlobalKey<FormState>();

  final TextEditingController name = TextEditingController();
  final TextEditingController phone = TextEditingController();
  final TextEditingController addressLine = TextEditingController();
  final TextEditingController neighborhood = TextEditingController();
  final TextEditingController city = TextEditingController();
  final TextEditingController directions = TextEditingController();

  final RxBool showPhonePublicly = true.obs;
  final RxString currency = 'SYP'.obs;
  final Rx<OpeningHours> hours = OpeningHours.defaults().obs;

  /// The file chosen in this session (not uploaded yet).
  final Rxn<PickedLicense> picked = Rxn<PickedLicense>();

  /// Licence already stored for a rejected pharmacy; stays valid when no new file is picked.
  final RxnString existingLicensePath = RxnString();

  /// Shown under the licence picker (missing / wrong type / too large).
  final RxnString licenseError = RxnString();

  /// Shown on the hours step (closing before opening, or nothing open).
  final RxnString hoursError = RxnString();

  /// True when a rejected application is being corrected rather than a new one filed.
  bool get isResubmission => _existing != null;

  Pharmacy? _existing;
  String? _uploadedPath;

  @override
  void onInit() {
    super.onInit();
    status.value = ViewStatus.ready;
    final Pharmacy? p = _session.pharmacy;
    if (p != null && p.status == ApprovalStatus.rejected) {
      _existing = p;
      final PharmacyDraft d = PharmacyDraft.fromPharmacy(p);
      name.text = d.name;
      phone.text = d.phone;
      addressLine.text = d.addressLine;
      neighborhood.text = d.neighborhood;
      city.text = d.city;
      directions.text = d.directions;
      showPhonePublicly.value = d.showPhonePublicly;
      currency.value = d.currency;
      hours.value = d.hours;
      existingLicensePath.value = d.licensePath;
      location.setInitial(d.location);
    } else {
      phone.text = _session.profile?.phone ?? '';
    }
  }

  @override
  void onClose() {
    for (final TextEditingController c in <TextEditingController>[name, phone, addressLine, neighborhood, city, directions]) {
      c.dispose();
    }
    location.dispose();
    super.onClose();
  }

  Future<void> signOut() => _session.signOut();

  // ---- step 1: licence --------------------------------------------------------------------------------

  bool get hasLicense => picked.value != null || (existingLicensePath.value ?? '').isNotEmpty;

  Future<void> pickLicense() async {
    final PickedLicense? f;
    try {
      f = await _pick();
    } catch (_) {
      licenseError.value = 'p_reg_license_pick_failed'.tr;
      return;
    }
    if (f == null) return;
    if (LicenseFiles.contentTypeFor(f.name) == null) {
      licenseError.value = 'p_reg_license_bad_type'.tr;
      return;
    }
    if (f.size > LicenseFiles.maxBytes) {
      licenseError.value = 'err_file_too_large'.tr;
      return;
    }
    if (f.size == 0) {
      licenseError.value = 'p_reg_license_pick_failed'.tr;
      return;
    }
    picked.value = f;
    _uploadedPath = null;
    licenseError.value = null;
  }

  void removeLicense() {
    picked.value = null;
    _uploadedPath = null;
  }

  void continueFromLicense() {
    if (!hasLicense) {
      licenseError.value = 'p_reg_license_required'.tr;
      return;
    }
    licenseError.value = null;
    _open(AppRoutes.pharmacyRegisterInfo);
  }

  // ---- step 2 / 3: information, address --------------------------------------------------------------

  void continueFromInfo() {
    if (!(infoForm.currentState?.validate() ?? false)) return;
    _open(AppRoutes.pharmacyRegisterAddress);
  }

  void continueFromAddress() {
    final bool formOk = addressForm.currentState?.validate() ?? false;
    if (location.point.value == null) {
      locationError.value = 'p_loc_required'.tr;
      return;
    }
    locationError.value = null;
    if (!formOk) return;
    _open(AppRoutes.pharmacyRegisterHours);
  }

  void setCurrency(String c) {
    if (isResubmission) return; // the server keeps the original currency on resubmission
    if (c == 'SYP' || c == 'USD') currency.value = c;
  }

  // ---- step 4: hours ---------------------------------------------------------------------------------

  void setDayOpen(int day, bool open) {
    _replaceDay(day, (DayHours d) => d.copyWith(open: open));
  }

  /// [value] is `HH:mm`.
  void setDayTime(int day, {required bool from, required String value}) {
    _replaceDay(day, (DayHours d) => from ? d.copyWith(from: value) : d.copyWith(to: value));
  }

  void _replaceDay(int day, DayHours Function(DayHours) change) {
    final List<DayHours> days = List<DayHours>.of(hours.value.days);
    final int i = days.indexWhere((DayHours d) => d.day == day);
    if (i < 0) return;
    days[i] = change(days[i]);
    hours.value = OpeningHours(days);
    hoursError.value = null;
  }

  /// `HH:mm` strings compare correctly as text.
  static bool dayIsValid(DayHours d) => !d.open || d.from.compareTo(d.to) < 0;

  String? validateHours() {
    final List<DayHours> days = hours.value.days;
    if (!days.any((DayHours d) => d.open)) return 'p_reg_hours_none_open'.tr;
    if (!days.every(dayIsValid)) return 'p_reg_hours_invalid'.tr;
    return null;
  }

  // ---- submit ----------------------------------------------------------------------------------------

  PharmacyDraft buildDraft() => PharmacyDraft(
        name: name.text.trim(),
        phone: phone.text.trim(),
        showPhonePublicly: showPhonePublicly.value,
        addressLine: addressLine.text.trim(),
        neighborhood: neighborhood.text.trim(),
        city: city.text.trim(),
        directions: directions.text.trim(),
        hours: hours.value,
        currency: currency.value,
        licensePath: _uploadedPath ?? existingLicensePath.value,
        location: location.point.value,
      );

  /// The first earlier step whose data is missing or invalid, or null when everything is fine. Checked on the
  /// values themselves because the earlier forms are no longer mounted on the last step.
  String? firstInvalidStep() {
    if (!hasLicense) return AppRoutes.pharmacyRegister;
    final bool infoOk = Validators.length(min: 2, max: 120)(name.text) == null && Validators.phone(phone.text) == null;
    if (!infoOk) return AppRoutes.pharmacyRegisterInfo;
    final bool addressOk = Validators.length(min: 3, max: 250)(addressLine.text) == null &&
        Validators.length(min: 2, max: 100)(city.text) == null &&
        neighborhood.text.trim().length <= 100 &&
        directions.text.trim().length <= 500 &&
        location.point.value != null;
    if (!addressOk) return AppRoutes.pharmacyRegisterAddress;
    return null;
  }

  /// Uploads the licence (when a new one was picked) and files or resubmits the application.
  /// Returns true when the server accepted it; the session then moves on to the "pending" screen.
  Future<bool> submitApplication() async {
    if (submitting.value) return false;
    final String? bad = firstInvalidStep();
    if (bad != null) {
      AppToast.error('p_reg_incomplete'.tr);
      _open(bad);
      return false;
    }
    final String? hoursProblem = validateHours();
    hoursError.value = hoursProblem;
    if (hoursProblem != null) return false;

    final Pharmacy? result = await submit<Pharmacy>(() async {
      final PickedLicense? f = picked.value;
      if (f != null && _uploadedPath == null) {
        final String? userId = _session.profile?.id;
        if (userId == null) throw const AppFailure('not_authenticated');
        _uploadedPath = await _files.uploadLicense(userId: userId, fileName: f.name, bytes: f.bytes, contentType: f.contentType);
      }
      final PharmacyDraft d = buildDraft();
      final Pharmacy? old = _existing;
      return old == null ? _pharmacies.register(d) : _pharmacies.resubmit(old.id, d);
    });
    if (result == null) return false;
    await _session.refresh(navigateOnChange: false);
    _offAll(_session.homeRoute);
    return true;
  }
}
