import 'package:get/get.dart';

import '../../../core/base/base_controller.dart';
import '../../../core/base/paged.dart';
import '../../../data/models/medicine.dart';
import '../../../data/models/pharmacy.dart';
import '../../../data/repositories/medicine_repository.dart';
import '../../../data/repositories/pharmacy_repository.dart';
import 'cart_controller.dart';

/// Public pharmacy page (C-15), its contact screen (C-16) and its list of medicines with "add to cart". One instance per
/// pharmacy (registered with `tag: pharmacyId`). [highlightMedicineId] marks the medicine the customer came for.
class PharmacyDetailsController extends BaseController {
  PharmacyDetailsController(
    this.pharmacyId, {
    this.highlightMedicineId,
    PharmacyRepository? pharmacies,
    MedicineRepository? medicines,
    CartController? cart,
  })  : _pharmacies = pharmacies ?? Get.find<PharmacyRepository>(),
        _medicines = medicines ?? Get.find<MedicineRepository>(),
        cart = cart ?? Get.find<CartController>() {
    catalogue = Paged<PublicProduct>(
      fetch: (int offset, int limit) =>
          _medicines.pharmacyCatalogue(pharmacyId, query: searchText.value, limit: limit, offset: offset),
    );
  }

  final String pharmacyId;
  final String? highlightMedicineId;
  final PharmacyRepository _pharmacies;
  final MedicineRepository _medicines;
  final CartController cart;
  late final Paged<PublicProduct> catalogue;

  final Rxn<PublicPharmacy> pharmacy = Rxn<PublicPharmacy>();
  final RxString searchText = ''.obs;

  @override
  void onReady() {
    super.onReady();
    reload();
  }

  Future<void> reload() => load(() async {
        pharmacy.value = await _pharmacies.getPublic(pharmacyId);
        await catalogue.reload();
      });

  Future<void> search(String value) async {
    final String q = value.trim();
    if (q == searchText.value) return;
    searchText.value = q;
    await catalogue.reload();
  }

  CartPharmacy? get cartTarget {
    final PublicPharmacy? p = pharmacy.value;
    return p == null ? null : CartPharmacy(id: p.id, name: p.name, currency: p.currency);
  }

  /// True when the cart currently holds this pharmacy's items.
  bool get cartIsHere => !cart.isEmpty && cart.pharmacy.value?.id == pharmacyId;
}
