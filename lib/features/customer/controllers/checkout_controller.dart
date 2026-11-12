import 'package:flutter/widgets.dart';
import 'package:get/get.dart';

import '../../../core/base/base_controller.dart';
import '../../../core/errors/app_failure.dart';
import '../../../core/services/session_service.dart';
import '../../../core/utils/idempotency.dart';
import '../../../data/models/order.dart';
import '../../../data/repositories/order_repository.dart';
import '../services/customer_nav.dart';
import '../services/customer_refresh.dart';
import 'cart_controller.dart';

/// Order review and submission (C-18). The cart is cleared only after the server returned the order.
///
/// Retrying the same payload (network error, double tap) reuses the idempotency key, so the server answers with the
/// first order instead of creating a second one. A changed payload (new prices, other quantities or notes) gets a new key.
class CheckoutController extends BaseController {
  CheckoutController({
    OrderRepository? orders,
    CartController? cart,
    SessionService? session,
    VoidCallback? showResult,
  })  : _orders = orders ?? Get.find<OrderRepository>(),
        cart = cart ?? Get.find<CartController>(),
        _session = session ?? Get.find<SessionService>(),
        _showResult = showResult ?? CustomerNav.showCheckoutResult;

  static const int notesMax = 300;

  final OrderRepository _orders;
  final CartController cart;
  final SessionService _session;
  final VoidCallback _showResult;
  final IdempotencyKeeper _keeper = IdempotencyKeeper();

  final GlobalKey<FormState> form = GlobalKey<FormState>();
  final TextEditingController notes = TextEditingController();
  final TextEditingController phone = TextEditingController();

  /// Explanation shown above the form after a server rejection or a price refresh.
  final RxnString notice = RxnString();

  @override
  void onInit() {
    super.onInit();
    status.value = ViewStatus.ready;
    phone.text = _session.profile?.phone ?? '';
  }

  @override
  void onReady() {
    super.onReady();
    refreshPrices();
  }

  @override
  void onClose() {
    notes.dispose();
    phone.dispose();
    super.onClose();
  }

  /// Re-reads prices and availability from the pharmacy's list and explains what changed.
  Future<void> refreshPrices() async {
    final CartSyncResult? r = await cart.revalidate();
    if (r == null) {
      notice.value = 'c_notice_sync_failed'.tr;
    } else {
      _explain(r);
    }
  }

  void _explain(CartSyncResult r) {
    if (r.unavailable > 0) {
      notice.value = 'c_notice_unavailable'.tr;
    } else if (r.priceChanged > 0) {
      notice.value = 'c_notice_price_changed'.tr;
    }
  }

  String _signature() {
    final String lines = cart.lines.map((CartLine l) => '${l.productId}:${l.quantity}:${l.unitPrice}').join(',');
    return '${cart.pharmacy.value?.id}|$lines|${notes.text.trim()}|${phone.text.trim()}';
  }

  /// Sends the order. Returns true when the server confirmed it.
  Future<bool> submitOrder() async {
    if (submitting.value) return false;
    final CartPharmacy? ph = cart.pharmacy.value;
    if (ph == null || cart.isEmpty) return false;
    if (!(form.currentState?.validate() ?? false)) return false;
    if (!cart.canCheckout) {
      notice.value = 'c_notice_unavailable'.tr;
      return false;
    }
    notice.value = null;
    final String key = _keeper.keyFor(_signature(), 'ord');
    final Order? order = await submit<Order>(
      () => _orders.create(
        pharmacyId: ph.id,
        items: cart.toInputs(),
        idempotencyKey: key,
        notes: notes.text,
        contactPhone: phone.text,
      ),
      toast: false,
    );
    if (order == null) {
      await _onFailure(failure.value);
      return false;
    }
    _keeper.clear();
    cart.completeOrder(order);
    notes.clear();
    CustomerRefresh.ordersChanged();
    _showResult();
    return true;
  }

  Future<void> _onFailure(AppFailure? f) async {
    if (f == null) return;
    switch (f.code) {
      case 'price_changed':
        final CartSyncResult? r = await cart.revalidate();
        notice.value = r != null && r.unavailable > 0 ? 'c_notice_unavailable'.tr : 'c_notice_price_changed'.tr;
      case 'product_unavailable':
        await cart.revalidate();
        notice.value = 'c_notice_unavailable'.tr;
      default:
        notice.value = failureText(f);
    }
  }

  bool get tooManyPending => failure.value?.code == 'too_many_pending';
  bool get pharmacyInactive => failure.value?.code == 'pharmacy_not_active';

  /// The pharmacy is gone: drop the cart and return to the shell.
  void abandonCart() {
    cart.clear();
    _keeper.clear();
    CustomerNav.openHomeTab();
  }
}
