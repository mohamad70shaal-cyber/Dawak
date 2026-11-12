import 'package:flutter/widgets.dart';
import 'package:get/get.dart';

import '../../../core/base/base_controller.dart';
import '../../../core/base/paged.dart';
import '../../../core/errors/app_failure.dart';
import '../../../core/utils/search_normalizer.dart';
import '../../../data/models/medicine.dart';
import '../../../data/repositories/medicine_repository.dart';

/// Dosage forms offered by the filter. The value is what the catalogue stores (Arabic); the label key is `c_form_<id>`.
class DosageFormOption {
  const DosageFormOption(this.id, this.value);

  final String id;
  final String value;

  String get labelKey => 'c_form_$id';
}

/// Medicine search (C-10 tab, C-11 results, C-12 filters). Typing shows a few live suggestions; "show all"
/// (or the keyboard's search key) opens the paged results. Queries shorter than [minQueryLength] never reach the server.
class MedicineSearchController extends BaseController {
  MedicineSearchController({MedicineRepository? medicines}) : _medicines = medicines ?? Get.find<MedicineRepository>() {
    results = Paged<Medicine>(fetch: _fetchPage);
  }

  static const int minQueryLength = 2;
  static const int suggestionCount = 6;
  static const int maxRecent = 5;

  static const List<DosageFormOption> dosageForms = <DosageFormOption>[
    DosageFormOption('tablets', 'أقراص'),
    DosageFormOption('effervescent', 'أقراص فوارة'),
    DosageFormOption('capsules', 'كبسولة'),
    DosageFormOption('syrup', 'شراب'),
    DosageFormOption('injection', 'حقن'),
    DosageFormOption('cream', 'كريم'),
    DosageFormOption('ointment', 'مرهم'),
    DosageFormOption('drops', 'قطرة'),
    DosageFormOption('suppository', 'تحاميل'),
    DosageFormOption('spray', 'بخاخ'),
  ];

  final MedicineRepository _medicines;
  late final Paged<Medicine> results;

  /// Text of the search box (shared by the tab and the results screen).
  final TextEditingController text = TextEditingController();
  final RxString query = ''.obs;
  final Rxn<String> categoryId = Rxn<String>();
  final Rxn<String> dosageForm = Rxn<String>();

  /// Values being edited on the filters screen; copied to the active filters by [applyFilters].
  final Rxn<String> draftCategoryId = Rxn<String>();
  final Rxn<String> draftDosageForm = Rxn<String>();

  final RxList<MedicineCategory> categories = <MedicineCategory>[].obs;
  final RxList<Medicine> suggestions = <Medicine>[].obs;
  final RxBool suggesting = false.obs;
  final Rxn<AppFailure> suggestFailure = Rxn<AppFailure>();
  final RxList<String> recent = <String>[].obs;

  int _suggestGen = 0;
  Future<void>? _categoriesFuture;
  final RxBool categoriesLoading = false.obs;
  final RxBool categoriesLoaded = false.obs;
  final RxBool categoriesFailed = false.obs;

  bool get hasQuery => normalizeSearch(query.value).length >= minQueryLength;

  bool get hasFilters => categoryId.value != null || dosageForm.value != null;

  int get filterCount => (categoryId.value == null ? 0 : 1) + (dosageForm.value == null ? 0 : 1);

  @override
  void onInit() {
    super.onInit();
    status.value = ViewStatus.ready;
  }

  @override
  void onReady() {
    super.onReady();
    ensureCategories();
  }

  @override
  void onClose() {
    _categoriesFuture = null;
    text.dispose();
    super.onClose();
  }

  Future<List<Medicine>> _fetchPage(int offset, int limit) =>
      _medicines.search(query.value, categoryId: categoryId.value, dosageForm: dosageForm.value, limit: limit, offset: offset);

  /// Typing: refresh the suggestion list (the search box already waits for a typing pause).
  Future<void> onTyping(String value) async {
    query.value = value;
    final int gen = ++_suggestGen;
    suggestFailure.value = null;
    if (!hasQuery) {
      suggestions.clear();
      suggesting.value = false;
      return;
    }
    suggesting.value = true;
    try {
      final List<Medicine> r = await _medicines.search(
        value,
        categoryId: categoryId.value,
        dosageForm: dosageForm.value,
        limit: suggestionCount,
      );
      if (gen != _suggestGen) return;
      suggestions.assignAll(r);
    } catch (e) {
      if (gen != _suggestGen) return;
      suggestFailure.value = AppFailure.from(e);
      suggestions.clear();
    } finally {
      if (gen == _suggestGen) suggesting.value = false;
    }
  }

  /// Runs the full, paged search for [value] (submit, "show all", results-screen box, recent search).
  Future<void> runSearch(String value) async {
    final String q = value.trim();
    query.value = q;
    if (text.text != q) text.text = q;
    if (!hasQuery) {
      results.items.clear();
      results.hasMore.value = false;
      return;
    }
    _remember(q);
    await results.reload();
  }

  void _remember(String q) {
    recent.removeWhere((String r) => r == q);
    recent.insert(0, q);
    if (recent.length > maxRecent) recent.removeRange(maxRecent, recent.length);
  }

  void clearQuery() {
    query.value = '';
    text.clear();
    suggestions.clear();
    results.items.clear();
    _suggestGen++;
    suggesting.value = false;
  }

  /// A category chosen on the home screen: becomes an active filter; the user then types the medicine name.
  void applyCategory(String id) {
    categoryId.value = id;
    draftCategoryId.value = id;
    if (hasQuery) onTyping(query.value);
  }

  /// Route parameters of the results screen (`q`, `categoryId`).
  Future<void> applyParams(Map<String, String?> params) async {
    final String? cat = params['categoryId'];
    if (cat != null && cat.isNotEmpty) categoryId.value = cat;
    final String? q = params['q'];
    if (q != null && q.trim().isNotEmpty) await runSearch(q);
  }

  // ---- filters ---------------------------------------------------------------------------------------------

  Future<void> ensureCategories() async {
    if (categoriesLoaded.value) return;
    if (_categoriesFuture != null) return _categoriesFuture!;
    final Future<void> future = _loadCategories();
    _categoriesFuture = future;
    try {
      await future;
    } finally {
      if (_categoriesFuture == future) {
        _categoriesFuture = null;
      }
    }
  }

  Future<void> _loadCategories() async {
    categoriesLoading.value = true;
    categoriesFailed.value = false;
    try {
      final List<MedicineCategory> list = await _medicines.categories();
      if (isClosed) return;
      categories.assignAll(list);
      categoriesLoaded.value = true;
      categoriesFailed.value = false;
    } catch (_) {
      if (isClosed) return;
      categoriesLoaded.value = false;
      categoriesFailed.value = true;
    } finally {
      if (!isClosed) {
        categoriesLoading.value = false;
      }
    }
  }

  Future<bool> reloadCategories() async {
    categoriesLoaded.value = false;
    categoriesFailed.value = false;
    _categoriesFuture = null;
    await ensureCategories();
    return categoriesLoaded.value;
  }

  void beginFilterEdit() {
    draftCategoryId.value = categoryId.value;
    draftDosageForm.value = dosageForm.value;
  }

  void clearDraft() {
    draftCategoryId.value = null;
    draftDosageForm.value = null;
  }

  Future<void> applyFilters() async {
    categoryId.value = draftCategoryId.value;
    dosageForm.value = draftDosageForm.value;
    if (hasQuery) {
      onTyping(query.value);
      await results.reload();
    }
  }

  Future<void> removeCategoryFilter() async {
    categoryId.value = null;
    draftCategoryId.value = null;
    if (hasQuery) {
      onTyping(query.value);
      await results.reload();
    }
  }

  Future<void> removeFormFilter() async {
    dosageForm.value = null;
    draftDosageForm.value = null;
    if (hasQuery) {
      onTyping(query.value);
      await results.reload();
    }
  }

  String categoryName(String? id, bool arabic) {
    if (id == null) return '';
    for (final MedicineCategory c in categories) {
      if (c.id == id) return c.name(arabic);
    }
    return '';
  }
}
