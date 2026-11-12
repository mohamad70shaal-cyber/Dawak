import 'package:get/get.dart';

import '../controllers/customer_orders_controller.dart';
import '../controllers/home_controller.dart';
import '../controllers/my_requests_controller.dart';

/// "refreshRelated" hooks: after an order or a request was created or changed, the visible lists re-read the server.
class CustomerRefresh {
  const CustomerRefresh._();

  static void ordersChanged() {
    if (Get.isRegistered<CustomerOrdersController>()) {
      Get.find<CustomerOrdersController>().refreshList();
    }
    if (Get.isRegistered<HomeController>()) {
      Get.find<HomeController>().refreshSilently();
    }
  }

  /// A request was started, widened or closed: the history list and the home card are out of date.
  static void requestsChanged() {
    if (Get.isRegistered<MyRequestsController>()) {
      Get.find<MyRequestsController>().refreshList();
    }
    if (Get.isRegistered<HomeController>()) {
      Get.find<HomeController>().refreshSilently();
    }
  }
}
