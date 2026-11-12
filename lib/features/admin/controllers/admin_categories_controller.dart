import 'package:flutter/widgets.dart';
import 'package:get/get.dart';

import '../../../core/base/base_controller.dart';
import '../../../core/errors/app_failure.dart';
import '../../../core/utils/validators.dart';
import '../../../core/widgets/app_toast.dart';
import '../../../data/models/medicine.dart';
import '../../../data/repositories/medicine_repository.dart';

/// Medicine categories (A-09): add, rename, reorder and switch on or off. A switched-off category disappears from the pickers
/// of pharmacists and customers but stays on the medicines that already use it. The add/edit form lives in a bottom
/// sheet that shares this controller's fields.
class AdminCategoriesController extends BaseController {
  AdminCategoriesController({MedicineRepository? medicines}) : _medicines = medicines ?? Get.find<MedicineRepository>();

  final MedicineRepository _medicines;

  final RxList<MedicineCategory> categories = <MedicineCategory>[].obs;

  final GlobalKey<FormState> form = GlobalKey<FormState>();
  final TextEditingController nameAr = TextEditingController();
  final TextEditingController nameEn = TextEditingController();
  final TextEditingController sortOrder = TextEditingController();
  final RxBool isActive = true.obs;

  /// The category being edited, or null when the form adds a new one.
  final Rxn<MedicineCategory> editing = Rxn<MedicineCategory>();
  final RxnString notice = RxnString();

  @override
  void onReady() {
    super.onReady();
    refresh();
  }

  @override
  void onClose() {
    nameAr.dispose();
    nameEn.dispose();
    sortOrder.dispose();
    super.onClose();
  }

  Future<void> refresh({bool silent = false}) => load(() async {
        categories.assignAll(await _medicines.categories(includeInactive: true));
      }, isEmpty: () => categories.isEmpty, silent: silent);

  /// Prepares the form for a new category; its position defaults to the end of the list.
  void startNew() {
    editing.value = null;
    notice.value = null;
    nameAr.clear();
    nameEn.clear();
    final int last = categories.isEmpty ? 0 : categories.map((MedicineCategory c) => c.sortOrder).reduce((int a, int b) => a > b ? a : b);
    sortOrder.text = '${categories.isEmpty ? 0 : last + 1}';
    isActive.value = true;
  }

  void startEdit(MedicineCategory c) {
    editing.value = c;
    notice.value = null;
    nameAr.text = c.nameAr;
    nameEn.text = c.nameEn ?? '';
    sortOrder.text = '${c.sortOrder}';
    isActive.value = c.isActive;
  }

  String? nameArRule(String? v) => Validators.length(min: 1, max: 80)(v);

  String? nameEnRule(String? v) => Validators.length(max: 80)(v);

  String? sortRule(String? v) => Validators.integer(min: 0, max: 9999)(v);

  String _explain(AppFailure f) => f.code == 'duplicate_request' ? 'a_category_duplicate'.tr : failureText(f);

  /// Saves the form. The view closes the sheet when this returns true.
  Future<bool> save() async {
    if (submitting.value) return false;
    if (!(form.currentState?.validate() ?? false) || nameAr.text.trim().isEmpty) return false;
    final MedicineCategory? current = editing.value;
    final bool? ok = await submit<bool>(() async {
      await _medicines.saveCategory(
        id: current?.id,
        nameAr: nameAr.text,
        nameEn: nameEn.text,
        sortOrder: Validators.parseInt(sortOrder.text) ?? 0,
        isActive: isActive.value,
      );
      return true;
    }, toast: false);
    if (ok == null) {
      final AppFailure? f = failure.value;
      notice.value = f == null ? null : _explain(f);
      return false;
    }
    notice.value = null;
    AppToast.success((current == null ? 'a_category_added' : 'a_category_saved').tr);
    await refresh(silent: true);
    return true;
  }

  /// Switches a category on or off from the list.
  Future<bool> toggleActive(MedicineCategory c) async {
    if (submitting.value) return false;
    final bool? ok = await submit<bool>(() async {
      await _medicines.saveCategory(id: c.id, nameAr: c.nameAr, nameEn: c.nameEn, sortOrder: c.sortOrder, isActive: !c.isActive);
      return true;
    });
    if (ok == null) return false;
    AppToast.success((c.isActive ? 'a_category_switched_off' : 'a_category_switched_on').tr);
    await refresh(silent: true);
    return true;
  }
}
