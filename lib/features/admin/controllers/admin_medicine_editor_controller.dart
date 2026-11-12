import 'package:flutter/widgets.dart';
import 'package:get/get.dart';

import '../../../core/base/base_controller.dart';
import '../../../core/errors/app_failure.dart';
import '../../../core/widgets/app_toast.dart';
import '../../../data/models/medicine.dart';
import '../../../data/repositories/medicine_repository.dart';
import '../services/admin_dialog_hooks.dart';
import '../services/admin_refresh.dart';

/// The medicine editor and proposal review (A-08). With no [medicineId] it creates a catalogue entry (approved at once);
/// with one it edits the entry and offers the review actions of its state: a pending proposal can be approved or
/// rejected, anything not archived can be archived. Edits that were typed but not saved are saved before a review
/// decision, so "fix the typo, then approve" is one tap.
class AdminMedicineEditorController extends BaseController {
  AdminMedicineEditorController({
    String? medicineId,
    MedicineRepository? medicines,
    AdminConfirmFn? confirm,
    void Function(Object? result)? close,
  })  : _medicineId = medicineId,
        _medicines = medicines ?? Get.find<MedicineRepository>(),
        _confirm = confirm ?? adminConfirm,
        _close = close ?? ((Object? r) => Get.back<Object?>(result: r));

  final String? _medicineId;
  final MedicineRepository _medicines;
  final AdminConfirmFn _confirm;
  final void Function(Object? result) _close;

  final GlobalKey<FormState> form = GlobalKey<FormState>();
  final TextEditingController nameAr = TextEditingController();
  final TextEditingController nameEn = TextEditingController();
  final TextEditingController brand = TextEditingController();
  final TextEditingController ingredient = TextEditingController();
  final TextEditingController strength = TextEditingController();
  final TextEditingController dosageForm = TextEditingController();
  final TextEditingController packageDescription = TextEditingController();

  final RxList<MedicineCategory> categories = <MedicineCategory>[].obs;
  final RxnString categoryId = RxnString();
  final Rxn<Medicine> medicine = Rxn<Medicine>();
  final RxnString notice = RxnString();

  /// True when this screen creates a new entry.
  bool get isNew => (_medicineId ?? Get.parameters['id'] ?? '').isEmpty;

  String get id => _medicineId ?? Get.parameters['id'] ?? '';

  String? get catalogStatus => medicine.value?.catalogStatus;

  bool get canApprove => !isNew && catalogStatus == 'pending';
  bool get canReject => !isNew && catalogStatus == 'pending';
  bool get canArchive => !isNew && catalogStatus != null && catalogStatus != 'archived';

  @override
  void onInit() {
    super.onInit();
    if (isNew) status.value = ViewStatus.ready;
  }

  @override
  void onReady() {
    super.onReady();
    loadCategories();
    if (!isNew) refresh();
  }

  @override
  void onClose() {
    for (final TextEditingController c in <TextEditingController>[nameAr, nameEn, brand, ingredient, strength, dosageForm, packageDescription]) {
      c.dispose();
    }
    super.onClose();
  }

  Future<void> loadCategories() async {
    try {
      categories.assignAll(await _medicines.categories(includeInactive: true));
    } catch (_) {
      // Optional field: an entry without a category is fine.
    }
  }

  /// Loads the entry. With [fill] the form takes the stored values (used on the first load and after saving);
  /// without it, what the admin has typed stays.
  Future<void> refresh({bool silent = false, bool fill = true}) => load(() async {
        final Medicine? m = await _medicines.getById(id);
        if (m == null) throw const AppFailure('not_found');
        medicine.value = m;
        if (fill) _fill(m);
      }, silent: silent);

  void _fill(Medicine m) {
    nameAr.text = m.nameAr ?? '';
    nameEn.text = m.nameEn ?? '';
    brand.text = m.brandName ?? '';
    ingredient.text = m.activeIngredient ?? '';
    strength.text = m.strength ?? '';
    dosageForm.text = m.dosageForm ?? '';
    packageDescription.text = m.packageDescription ?? '';
    categoryId.value = m.categoryId;
  }

  /// True when at least one of the two names is filled in.
  bool get hasName => nameAr.text.trim().isNotEmpty || nameEn.text.trim().isNotEmpty;

  /// At least one name is required (the database refuses an entry without any).
  String? nameRule(String? v) {
    if (nameAr.text.trim().isEmpty && nameEn.text.trim().isEmpty) return 'val_required'.tr;
    if ((v ?? '').trim().length > 160) return 'val_too_long'.trParams(<String, String>{'n': '160'});
    return null;
  }

  MedicineDraft buildDraft() => MedicineDraft(
        nameAr: nameAr.text,
        nameEn: nameEn.text,
        brandName: brand.text,
        activeIngredient: ingredient.text,
        strength: strength.text,
        dosageForm: dosageForm.text,
        packageDescription: packageDescription.text,
        categoryId: categoryId.value,
      );

  /// True when the form differs from the stored entry.
  bool get isDirty {
    final Medicine? m = medicine.value;
    if (m == null) return false;
    String t(String? s) => (s ?? '').trim();
    return t(nameAr.text) != t(m.nameAr) ||
        t(nameEn.text) != t(m.nameEn) ||
        t(brand.text) != t(m.brandName) ||
        t(ingredient.text) != t(m.activeIngredient) ||
        t(strength.text) != t(m.strength) ||
        t(dosageForm.text) != t(m.dosageForm) ||
        t(packageDescription.text) != t(m.packageDescription) ||
        categoryId.value != m.categoryId;
  }

  String _explain(AppFailure f) => f.code == 'duplicate_request' ? 'a_medicine_duplicate'.tr : failureText(f);

  /// Creates the entry, or saves the changes of an existing one, then closes the screen.
  Future<bool> save() async {
    if (submitting.value) return false;
    if (!(form.currentState?.validate() ?? false) || !hasName) return false;
    final bool? ok = await submit<bool>(() async {
      if (isNew) {
        await _medicines.adminCreate(buildDraft());
      } else {
        await _medicines.adminUpdate(id, buildDraft());
      }
      return true;
    }, toast: false);
    if (ok == null) {
      final AppFailure? f = failure.value;
      notice.value = f == null ? null : _explain(f);
      return false;
    }
    notice.value = null;
    AppToast.success((isNew ? 'a_medicine_created' : 'a_medicine_saved').tr);
    AdminRefresh.medicinesChanged();
    _close(true);
    return true;
  }

  /// Saves unsaved edits of an existing entry without closing the screen.
  Future<bool> _persistEdits() async {
    if (!isDirty) return true;
    if (!(form.currentState?.validate() ?? false) || !hasName) return false;
    final bool? ok = await submit<bool>(() async {
      await _medicines.adminUpdate(id, buildDraft());
      return true;
    }, toast: false);
    if (ok == null) {
      final AppFailure? f = failure.value;
      notice.value = f == null ? null : _explain(f);
      return false;
    }
    return true;
  }

  Future<bool> _review(String decision, String successKey) async {
    if (!await _persistEdits()) return false;
    final bool? ok = await submit<bool>(() async {
      await _medicines.adminReview(id, decision);
      return true;
    }, toast: false);
    if (ok == null) {
      final AppFailure? f = failure.value;
      notice.value = f == null ? null : (f.code == 'invalid_transition' ? 'a_medicine_notice_changed'.tr : failureText(f));
      await refresh(silent: true, fill: false);
      AdminRefresh.medicinesChanged();
      return false;
    }
    notice.value = null;
    AppToast.success(successKey.tr);
    await refresh(silent: true);
    AdminRefresh.medicinesChanged();
    return true;
  }

  Future<bool> approve() async {
    if (!canApprove || submitting.value) return false;
    return _review('approve', 'a_medicine_approved');
  }

  Future<bool> reject() async {
    if (!canReject || submitting.value) return false;
    final bool ok = await _confirm(
      title: 'a_medicine_reject_title'.tr,
      message: 'a_medicine_reject_message'.tr,
      confirmLabel: 'a_medicine_reject'.tr,
      destructive: true,
    );
    if (!ok) return false;
    return _review('reject', 'a_medicine_rejected');
  }

  Future<bool> archive() async {
    if (!canArchive || submitting.value) return false;
    final bool ok = await _confirm(
      title: 'a_medicine_archive_title'.tr,
      message: 'a_medicine_archive_message'.tr,
      confirmLabel: 'a_medicine_archive'.tr,
      destructive: true,
    );
    if (!ok) return false;
    return _review('archive', 'a_medicine_archived');
  }

  void cancel() => _close(null);
}
