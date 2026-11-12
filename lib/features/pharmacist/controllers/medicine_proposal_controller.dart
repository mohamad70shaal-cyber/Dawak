import 'package:flutter/widgets.dart';
import 'package:get/get.dart';

import '../../../core/base/base_controller.dart';
import '../../../core/widgets/app_toast.dart';
import '../../../data/models/medicine.dart';
import '../../../data/repositories/medicine_repository.dart';

/// Proposing a medicine the catalogue does not have (P-26). The server de-duplicates: when the catalogue already has it
/// the existing medicine comes back ([existed]) and, if approved, can be added at once. New proposals wait for an
/// administrator (the pharmacist can add the medicine once it is approved).
class MedicineProposalController extends BaseController {
  MedicineProposalController({MedicineRepository? medicines, void Function(Object? result)? close})
      : _medicines = medicines ?? Get.find<MedicineRepository>(),
        _close = close ?? ((Object? r) => Get.back<Object?>(result: r));

  final MedicineRepository _medicines;
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

  /// Shown after a proposal went to review.
  final RxBool sentForReview = false.obs;

  @override
  void onInit() {
    super.onInit();
    status.value = ViewStatus.ready;
  }

  @override
  void onReady() {
    super.onReady();
    loadCategories();
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
      categories.assignAll(await _medicines.categories());
    } catch (_) {
      // Optional field: a proposal without a category is accepted.
    }
  }

  /// At least one name is required (the server rejects a medicine without any).
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

  Future<bool> send() async {
    if (submitting.value) return false;
    if (!(form.currentState?.validate() ?? false)) return false;
    final ({String id, String status, bool existed})? r = await submit<({String id, String status, bool existed})>(
      () => _medicines.propose(buildDraft()),
    );
    if (r == null) return false;
    if (r.status == 'approved') {
      // Already in the catalogue (or approved at once): hand the medicine back so it can be added.
      final Medicine? m = await _fetch(r.id);
      AppToast.success((r.existed ? 'p_propose_existed' : 'p_propose_approved').tr);
      _close(m);
      return true;
    }
    sentForReview.value = true;
    AppToast.success('p_propose_sent'.tr);
    return true;
  }

  Future<Medicine?> _fetch(String id) async {
    try {
      return await _medicines.getById(id);
    } catch (_) {
      return null;
    }
  }

  void done() => _close(null);
}
