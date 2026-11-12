import 'package:flutter/widgets.dart';
import 'package:get/get.dart';

import '../../../core/base/base_controller.dart';
import '../../../core/errors/app_failure.dart';
import '../../../core/utils/validators.dart';
import '../../../core/widgets/app_toast.dart';
import '../../../data/models/medicine.dart';
import '../../../data/repositories/listing_repository.dart';

/// Edit the pharmacy-specific fields of a list row (P-27): the price (P-28) and whether the medicine is available.
/// Saving always confirms the row as of now. The medicine itself (name, strength, …) belongs to the shared catalogue.
class ProductEditController extends BaseController {
  ProductEditController({String? productId, ListingRepository? listing, void Function()? close})
      : _productId = productId,
        _listing = listing ?? Get.find<ListingRepository>(),
        _close = close ?? (() => Get.back<dynamic>());

  final String? _productId;
  final ListingRepository _listing;
  final void Function() _close;

  final GlobalKey<FormState> form = GlobalKey<FormState>();
  final TextEditingController price = TextEditingController();
  final RxBool available = true.obs;
  final Rxn<PharmacyProduct> product = Rxn<PharmacyProduct>();

  String get id => _productId ?? Get.parameters['id'] ?? '';

  @override
  void onReady() {
    super.onReady();
    refresh();
  }

  @override
  void onClose() {
    price.dispose();
    super.onClose();
  }

  Future<void> refresh() => load(() async {
        final PharmacyProduct? p = await _listing.product(id);
        if (p == null) throw const AppFailure('not_found');
        product.value = p;
        price.text = _plain(p.price);
        available.value = p.isAvailable;
      });

  static String _plain(double v) => v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toString();

  /// What would be sent: null when nothing changed.
  ({double? price, bool? available})? changes() {
    final PharmacyProduct? p = product.value;
    if (p == null) return null;
    final double? newPrice = Validators.parseDecimal(price.text);
    final double? priceChange = (newPrice != null && newPrice != p.price) ? newPrice : null;
    final bool? availableChange = available.value != p.isAvailable ? available.value : null;
    if (priceChange == null && availableChange == null) return null;
    return (price: priceChange, available: availableChange);
  }

  /// Nothing changed: the row is simply confirmed ("still correct") and the screen closes.
  Future<bool> save() async {
    final PharmacyProduct? p = product.value;
    if (p == null || submitting.value) return false;
    if (!(form.currentState?.validate() ?? false)) return false;
    final ({double? price, bool? available})? c = changes();
    final bool? ok = await submit<bool>(() async {
      await _listing.updateProduct(p.id, price: c?.price, isAvailable: c?.available);
      return true;
    });
    if (ok == null) return false;
    AppToast.success('p_product_saved'.tr);
    _close();
    return true;
  }
}
