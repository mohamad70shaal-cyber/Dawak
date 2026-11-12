import 'package:get/get.dart';

import '../../../app/routes/app_routes.dart';
import '../../../core/widgets/app_toast.dart';
import '../../../core/widgets/dialogs.dart';
import '../../../data/models/medicine.dart';
import '../controllers/cart_controller.dart';
import '../controllers/pharmacy_details_controller.dart';

/// Puts [line] in the cart with feedback. A line of another pharmacy asks before replacing the current cart.
/// Returns true when the line is in the cart afterwards.
Future<bool> addLineWithPrompt(CartController cart, CartPharmacy target, CartLine line) async {
  final CartAddResult r = cart.add(target, line);
  switch (r) {
    case CartAddResult.added:
    case CartAddResult.increased:
      AppToast.success('c_added_to_cart'.tr);
      return true;
    case CartAddResult.maxReached:
      AppToast.info('c_max_reached'.trParams(<String, String>{'n': '${CartController.maxQtyPerLine}'}));
      return true;
    case CartAddResult.cartFull:
      AppToast.info('c_cart_full'.trParams(<String, String>{'n': '${CartController.maxLines}'}));
      return false;
    case CartAddResult.needsReplace:
      final bool ok = await confirmDialog(
        title: 'c_replace_cart_title'.tr,
        message: 'c_replace_cart_message'.trParams(<String, String>{
          'from': cart.pharmacy.value?.name ?? '',
          'to': target.name,
        }),
        confirmLabel: 'c_replace_cart_confirm'.tr,
        destructive: true,
      );
      if (!ok) return false;
      cart.replaceWith(target, line);
      AppToast.success('c_added_to_cart'.tr);
      return true;
  }
}

/// "Add to cart" on the pharmacy page.
Future<void> addProductWithPrompt(PharmacyDetailsController c, PublicProduct product) async {
  final CartPharmacy? target = c.cartTarget;
  if (target == null) return;
  await addLineWithPrompt(c.cart, target, CartLine.fromProduct(product));
}

/// "Reserve" on an offer (pharmacies list or a request's answers): puts one unit in the cart and opens it.
Future<void> reserveOffer(CartController cart, CartPharmacy target, CartLine line) async {
  final bool inCart = await addLineWithPrompt(cart, target, line);
  if (inCart) await Get.toNamed<dynamic>(AppRoutes.cart);
}
