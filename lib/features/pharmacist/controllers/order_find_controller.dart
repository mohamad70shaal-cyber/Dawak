import 'package:flutter/widgets.dart';
import 'package:get/get.dart';

import '../../../app/routes/app_routes.dart';
import '../../../core/base/base_controller.dart';
import '../../../core/services/session_service.dart';
import '../../../data/models/order.dart';
import '../../../data/repositories/order_repository.dart';

/// Find an order by the code the customer shows or reads out (P-60).
class OrderFindController extends BaseController {
  OrderFindController({OrderRepository? orders, SessionService? session, void Function(String route)? open})
      : _orders = orders ?? Get.find<OrderRepository>(),
        _session = session ?? Get.find<SessionService>(),
        _open = open ?? ((String r) => Get.toNamed<dynamic>(r));

  final OrderRepository _orders;
  final SessionService _session;
  final void Function(String route) _open;

  final GlobalKey<FormState> form = GlobalKey<FormState>();
  final TextEditingController reference = TextEditingController();
  final RxnString notice = RxnString();

  @override
  void onInit() {
    super.onInit();
    status.value = ViewStatus.ready;
  }

  @override
  void onClose() {
    reference.dispose();
    super.onClose();
  }

  /// Upper case, no spaces or stray characters around the code.
  static String normalize(String raw) => raw.trim().toUpperCase().replaceAll(RegExp(r'\s+'), '');

  String? referenceRule(String? v) {
    final String s = normalize(v ?? '');
    if (s.isEmpty) return 'val_required'.tr;
    if (s.length < 4) return 'val_too_short'.trParams(<String, String>{'n': '4'});
    if (s.length > 30) return 'val_too_long'.trParams(<String, String>{'n': '30'});
    return null;
  }

  /// Returns the order when found (and opens it).
  Future<Order?> find() async {
    if (submitting.value) return null;
    if (!(form.currentState?.validate() ?? false)) return null;
    notice.value = null;
    final String ref = normalize(reference.text);
    final Order? o = await submit<Order?>(() => _orders.findByRef(_session.pharmacy?.id ?? '', ref), toast: false);
    if (o == null) {
      final f = failure.value;
      notice.value = f != null ? failureText(f) : 'p_find_not_found'.tr;
      return null;
    }
    _open(AppRoutes.pharmacistOrder(o.id));
    return o;
  }
}
