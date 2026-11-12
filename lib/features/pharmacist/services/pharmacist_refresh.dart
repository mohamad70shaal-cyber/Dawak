import 'package:get/get.dart';

import '../controllers/dashboard_controller.dart';
import '../controllers/pharmacist_orders_controller.dart';
import '../controllers/pos_controller.dart';
import '../controllers/products_controller.dart';

/// "refreshRelated" hooks: after the medicine list or the orders changed, the visible lists re-read the server.
class PharmacistRefresh {
  const PharmacistRefresh._();

  /// A sale, a handover or a list change moved the numbers.
  static void listChanged() {
    if (Get.isRegistered<ProductsController>()) Get.find<ProductsController>().refreshList();
    if (Get.isRegistered<PosController>()) Get.find<PosController>().reloadProducts();
    if (Get.isRegistered<DashboardController>()) Get.find<DashboardController>().refresh(silent: true);
  }

  /// An order changed state.
  static void ordersChanged() {
    if (Get.isRegistered<PharmacistOrdersController>()) Get.find<PharmacistOrdersController>().refreshAll();
    listChanged();
  }
}
