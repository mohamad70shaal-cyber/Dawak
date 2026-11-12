import 'package:flutter/widgets.dart';
import 'package:get/get.dart';

import '../../../app/routes/app_routes.dart';
import '../../../core/base/base_controller.dart';
import '../../../core/errors/app_failure.dart';
import '../../../data/models/enums.dart';
import '../../../data/models/order.dart';
import '../../../data/models/sale.dart';
import '../../../data/repositories/order_repository.dart';
import '../services/pharmacist_refresh.dart';

/// Hand the goods over and take the cash (P-61, P-62). The person at the counter confirms the code the customer shows;
/// the server compares it with the order's reference, turns the reservation into a sale and answers with the invoice.
/// Repeating the call for an order that is already completed returns the same sale, so a double tap is harmless.
class OrderHandoverController extends BaseController {
  OrderHandoverController({String? orderId, OrderRepository? orders, void Function(String route)? replace})
      : _orderId = orderId,
        _orders = orders ?? Get.find<OrderRepository>(),
        _replace = replace ?? ((String r) => Get.offNamed<dynamic>(r));

  final String? _orderId;
  final OrderRepository _orders;
  final void Function(String route) _replace;

  final GlobalKey<FormState> form = GlobalKey<FormState>();
  final TextEditingController reference = TextEditingController();
  final Rxn<Order> order = Rxn<Order>();
  final RxnString notice = RxnString();

  String get id => _orderId ?? Get.parameters['id'] ?? '';

  @override
  void onReady() {
    super.onReady();
    refresh();
  }

  @override
  void onClose() {
    reference.dispose();
    super.onClose();
  }

  Future<void> refresh({bool silent = false}) => load(() async {
        final Order? o = await _orders.getOrder(id);
        if (o == null) throw const AppFailure('not_found');
        order.value = o;
      }, silent: silent);

  /// Handover is only possible while the order is "ready for pickup".
  bool get canComplete => order.value?.status == OrderStatus.readyForPickup;

  String normalize(String raw) => raw.trim().toUpperCase().replaceAll(RegExp(r'\s+'), '');

  String? referenceRule(String? v) {
    final String s = normalize(v ?? '');
    if (s.isEmpty) return 'val_required'.tr;
    return null;
  }

  /// Returns the sale on success (and opens its receipt in place of this screen).
  Future<Sale?> complete() async {
    final Order? o = order.value;
    if (o == null || submitting.value || !canComplete) return null;
    if (!(form.currentState?.validate() ?? false)) return null;
    notice.value = null;
    final Sale? sale = await submit<Sale>(() => _orders.complete(o.id, normalize(reference.text)), toast: false);
    if (sale == null) {
      final AppFailure? f = failure.value;
      if (f != null) {
        notice.value = f.code == 'reference_mismatch'
            ? 'p_handover_mismatch'.tr
            : f.code == 'reservation_expired'
                ? 'p_order_notice_expired'.tr
                : f.code == 'invalid_transition'
                    ? 'p_order_notice_changed'.tr
                    : failureText(f);
        if (f.code != 'reference_mismatch') await refresh(silent: true);
      }
      return null;
    }
    PharmacistRefresh.ordersChanged();
    _replace(AppRoutes.sale(sale.id));
    return sale;
  }
}
