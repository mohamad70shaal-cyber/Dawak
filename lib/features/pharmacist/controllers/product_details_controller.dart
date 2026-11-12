import 'package:get/get.dart';

import '../../../app/routes/app_routes.dart';
import '../../../core/base/base_controller.dart';
import '../../../core/errors/app_failure.dart';
import '../../../core/services/session_service.dart';
import '../../../core/widgets/app_toast.dart';
import '../../../data/models/medicine.dart';
import '../../../data/repositories/listing_repository.dart';
import '../services/dialog_hooks.dart';

/// One medicine of the pharmacy's list (P-24): price, available or not, when it was last confirmed, and the actions
/// (edit the price, mark available / unavailable, confirm that the row is still correct).
class ProductDetailsController extends BaseController {
  ProductDetailsController({
    String? productId,
    ListingRepository? listing,
    SessionService? session,
    ConfirmFn? confirm,
    Future<Object?> Function(String route)? open,
  })  : _productId = productId,
        _listing = listing ?? Get.find<ListingRepository>(),
        _session = session ?? Get.find<SessionService>(),
        _confirm = confirm ?? defaultConfirm,
        _open = open ?? ((String r)async => Get.toNamed<Object?>(r));

  final String? _productId;
  final ListingRepository _listing;
  final SessionService _session;
  final ConfirmFn _confirm;
  final Future<Object?> Function(String route) _open;

  final Rxn<PharmacyProduct> product = Rxn<PharmacyProduct>();

  String get id => _productId ?? Get.parameters['id'] ?? '';

  bool get canManage => _session.snapshot.canManagePharmacy;

  /// The pharmacy's own currency (a product row carries none).
  String get currency => _session.pharmacy?.currency ?? 'SYP';

  @override
  void onReady() {
    super.onReady();
    refresh();
  }

  Future<void> refresh({bool silent = false}) => load(() async {
        final PharmacyProduct? p = await _listing.product(id);
        if (p == null) throw const AppFailure('not_found');
        product.value = p;
      }, silent: silent);

  Future<void> openEdit() async {
    await _open(AppRoutes.productEditOf(id));
    await refresh(silent: true);
  }

  /// "Unavailable" keeps the row (and its price) but customers stop seeing the pharmacy for this medicine.
  /// Both directions confirm the row as of now.
  Future<void> setAvailable(bool available) async {
    final PharmacyProduct? p = product.value;
    if (p == null || submitting.value) return;
    if (!available) {
      final bool ok = await _confirm(
        title: 'p_product_unavailable_title'.tr,
        message: 'p_product_unavailable_message'.tr,
        confirmLabel: 'p_product_mark_unavailable'.tr,
        destructive: true,
      );
      if (!ok) return;
    }
    final bool? done = await submit<bool>(() async {
      await _listing.updateProduct(p.id, isAvailable: available);
      return true;
    });
    if (done == null) return;
    AppToast.success((available ? 'p_product_marked_available' : 'p_product_marked_unavailable').tr);
    await refresh(silent: true);
  }

  /// "Still correct today": re-stamps the confirmation time without changing anything else.
  Future<void> confirmStillCorrect() async {
    final PharmacyProduct? p = product.value;
    if (p == null || submitting.value) return;
    final bool? done = await submit<bool>(() async {
      await _listing.updateProduct(p.id);
      return true;
    });
    if (done == null) return;
    AppToast.success('p_product_confirmed'.tr);
    await refresh(silent: true);
  }
}
