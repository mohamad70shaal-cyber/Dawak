import 'package:get/get.dart';

import '../../../app/routes/app_routes.dart';
import '../../../core/base/base_controller.dart';
import '../../../core/base/paged.dart';
import '../../../core/services/session_service.dart';
import '../../../core/widgets/app_toast.dart';
import '../../../data/models/medicine.dart';
import '../../../data/repositories/listing_repository.dart';
import '../../../data/repositories/medicine_repository.dart';
import '../services/dialog_hooks.dart';

/// Names match the `filter` argument of [ListingRepository.products].
enum ProductFilter { all, available, unavailable, stale }

/// The pharmacy's own medicine list (P-21, with search P-22 and category filter P-23): name, price, available or not and
/// when it was last confirmed. There are no quantities. Cashiers see the list but not the add/edit/import controls.
class ProductsController extends BaseController {
  ProductsController({
    ListingRepository? listing,
    MedicineRepository? medicines,
    SessionService? session,
    ConfirmFn? confirm,
    Future<Object?> Function(String route)? open,
  })  : _confirm = confirm ?? defaultConfirm,
        _listing = listing ?? Get.find<ListingRepository>(),
        _medicines = medicines ?? Get.find<MedicineRepository>(),
        _session = session ?? Get.find<SessionService>(),
        _open = open ?? ((String r) async=> Get.toNamed<Object?>(r)) {
    paged = Paged<PharmacyProduct>(
      fetch: (int offset, int limit) => _listing.products(
        pharmacyId,
        text: _text,
        filter: filter.value.name,
        categoryId: categoryId.value,
        limit: limit,
        offset: offset,
      ),
      pageSize: 30,
    );
  }

  final ListingRepository _listing;
  final MedicineRepository _medicines;
  final SessionService _session;
  final ConfirmFn _confirm;
  final Future<Object?> Function(String route) _open;

  late final Paged<PharmacyProduct> paged;
  final Rx<ProductFilter> filter = ProductFilter.all.obs;
  final RxnString categoryId = RxnString();
  final RxList<MedicineCategory> categories = <MedicineCategory>[].obs;

  String _text = '';

  String get pharmacyId => _session.pharmacy?.id ?? '';

  bool get canManage => _session.snapshot.canManagePharmacy;

  String get currency => _session.pharmacy?.currency ?? 'SYP';

  @override
  void onInit() {
    super.onInit();
    status.value = ViewStatus.ready;
  }

  @override
  void onReady() {
    super.onReady();
    paged.reload();
    loadCategories();
  }

  Future<void> loadCategories() async {
    try {
      categories.assignAll(await _medicines.categories());
    } catch (_) {
      // The category chips are optional: without them the list is simply unfiltered.
    }
  }

  void search(String text) {
    final String t = text.trim();
    if (t == _text) return;
    _text = t;
    paged.reload();
  }

  void setFilter(ProductFilter f) {
    if (filter.value == f) return;
    filter.value = f;
    paged.reload();
  }

  /// Selecting the active category again clears it.
  void setCategory(String? id) {
    categoryId.value = categoryId.value == id ? null : id;
    paged.reload();
  }

  Future<void> openProduct(PharmacyProduct p) async {
    await _open(AppRoutes.product(p.id));
    await paged.reload(silent: true);
  }

  Future<void> openAdd() async {
    await _open(AppRoutes.productAdd);
    await paged.reload(silent: true);
  }

  Future<void> refreshList() => paged.reload(silent: true);

  Future<void> openImport() async {
    await _open(AppRoutes.productImport);
    await paged.reload(silent: true);
  }

  /// "My list is still correct today": refreshes the confirmation time of every available medicine, so customers stop
  /// seeing "not confirmed for a while" on items that are in fact fine. Returns how many were confirmed.
  Future<int?> confirmListing() async {
    if (submitting.value) return null;
    final bool ok = await _confirm(
      title: 'p_confirm_list_title'.tr,
      message: 'p_confirm_list_message'.tr,
      confirmLabel: 'p_confirm_list_action'.tr,
    );
    if (!ok) return null;
    final int? n = await submit<int>(() => _listing.confirmListing(pharmacyId));
    if (n == null) return null;
    AppToast.success('p_confirm_list_done'.trParams(<String, String>{'n': '$n'}));
    await paged.reload(silent: true);
    return n;
  }

  /// The quick switch on a row: marks the medicine available / unavailable (this also confirms it).
  Future<bool> setAvailable(PharmacyProduct p, bool available) async {
    if (submitting.value || p.isAvailable == available) return false;
    final bool? ok = await submit<bool>(() async {
      await _listing.updateProduct(p.id, isAvailable: available);
      return true;
    });
    if (ok == null) return false;
    AppToast.success((available ? 'p_product_marked_available' : 'p_product_marked_unavailable').tr);
    await paged.reload(silent: true);
    return true;
  }
}
