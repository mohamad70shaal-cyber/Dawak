import 'package:flutter/widgets.dart';
import 'package:get/get.dart';

import '../../../app/routes/app_routes.dart';
import '../../../core/base/base_controller.dart';
import '../../../core/errors/app_failure.dart';
import '../../../core/services/session_service.dart';
import '../../../core/utils/validators.dart';
import '../../../core/widgets/app_toast.dart';
import '../../../data/models/medicine.dart';
import '../../../data/repositories/listing_repository.dart';
import '../../../data/repositories/medicine_repository.dart';

/// Adds a medicine of the shared catalogue to the pharmacy's list (P-25): search the catalogue, pick one, set its price.
/// The new row is available and confirmed now. A medicine that is not in the catalogue is proposed first (P-26).
class ProductAddController extends BaseController {
  ProductAddController({
    ListingRepository? listing,
    MedicineRepository? medicines,
    SessionService? session,
    Future<Object?> Function(String route)? open,
    void Function(String route)? replace,
  })  : _listing = listing ?? Get.find<ListingRepository>(),
        _medicines = medicines ?? Get.find<MedicineRepository>(),
        _session = session ?? Get.find<SessionService>(),
        _open = open ?? ((String r) async=> Get.toNamed<Object?>(r)),
        _replace = replace ?? ((String r) => Get.offNamed<dynamic>(r));

  final ListingRepository _listing;
  final MedicineRepository _medicines;
  final SessionService _session;
  final Future<Object?> Function(String route) _open;
  final void Function(String route) _replace;

  final GlobalKey<FormState> form = GlobalKey<FormState>();
  final TextEditingController price = TextEditingController();

  final RxList<Medicine> results = <Medicine>[].obs;
  final Rxn<Medicine> selected = Rxn<Medicine>();
  final RxBool searching = false.obs;
  final Rxn<AppFailure> searchFailure = Rxn<AppFailure>();

  /// True once a query of at least two characters ran (so "no results" can be told apart from "nothing typed yet").
  final RxBool searched = false.obs;

  /// Set when the pharmacy already lists the chosen medicine; holds that product's id.
  final RxnString existingProductId = RxnString();

  int _generation = 0;

  String get currency => _session.pharmacy?.currency ?? 'SYP';

  @override
  void onInit() {
    super.onInit();
    status.value = ViewStatus.ready;
  }

  @override
  void onClose() {
    price.dispose();
    super.onClose();
  }

  Future<void> search(String text) async {
    final String q = text.trim();
    final int gen = ++_generation;
    searchFailure.value = null;
    if (q.length < 2) {
      results.clear();
      searched.value = false;
      searching.value = false;
      return;
    }
    searching.value = true;
    try {
      final List<Medicine> found = await _medicines.search(q, limit: 30);
      if (gen != _generation) return;
      results.assignAll(found);
      searched.value = true;
    } catch (e) {
      if (gen != _generation) return;
      searchFailure.value = AppFailure.from(e);
    } finally {
      if (gen == _generation) searching.value = false;
    }
  }

  void choose(Medicine m) {
    selected.value = m;
    existingProductId.value = null;
  }

  void clearChoice() {
    selected.value = null;
    existingProductId.value = null;
  }

  /// Opens the proposal form; a medicine that came back (already approved) is chosen right away.
  Future<void> proposeNew() async {
    final Object? r = await _open(AppRoutes.productPropose);
    if (r is Medicine) choose(r);
  }

  Future<void> openExisting() async {
    final String? id = existingProductId.value;
    if (id != null) _replace(AppRoutes.product(id));
  }

  /// Returns the new product's id, or null when validation or the server refused.
  Future<String?> save() async {
    final Medicine? m = selected.value;
    if (m == null || submitting.value) return null;
    if (!(form.currentState?.validate() ?? false)) return null;
    existingProductId.value = null;
    final String? id = await submit<String>(
      () => _listing.addProduct(
        pharmacyId: _session.pharmacy?.id ?? '',
        medicineId: m.id,
        price: Validators.parseDecimal(price.text)!,
      ),
      toast: false,
    );
    if (id == null) {
      final AppFailure? f = failure.value;
      if (f != null && f.code == 'invalid_input' && f.details['reason'] == 'already_exists') {
        existingProductId.value = (f.details['product_id'] ?? '').toString();
        AppToast.error('p_product_exists'.tr);
      } else if (f != null) {
        AppToast.error(failureText(f));
      }
      return null;
    }
    AppToast.success('p_product_added'.tr);
    _replace(AppRoutes.product(id));
    return id;
  }
}
