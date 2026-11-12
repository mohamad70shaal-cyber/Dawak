import 'package:flutter/widgets.dart';
import 'package:get/get.dart';

import '../../../app/routes/app_routes.dart';
import '../../../core/base/shell_controller.dart';
import '../customer_tabs.dart';

/// Customer navigation shortcuts shared by controllers and screens.
class CustomerNav {
  const CustomerNav._();

  /// Back to the shell with the orders tab selected. Pops everything above the shell, so checkout screens are gone
  /// and the system back button can never submit an order again. Falls back to a fresh shell when none is open.
  static void openOrdersTab() {
    if (Get.isRegistered<ShellController>(tag: ShellTag.customer)) {
      CustomerTabs.go(CustomerTabs.orders);
    } else {
      Get.offAllNamed<dynamic>(AppRoutes.customerOrders);
    }
  }

  static void openHomeTab() {
    if (Get.isRegistered<ShellController>(tag: ShellTag.customer)) {
      CustomerTabs.go(CustomerTabs.home);
    } else {
      Get.offAllNamed<dynamic>(AppRoutes.customerHome);
    }
  }

  /// Orders tab, then the order's details on top of it (back returns to the list).
  static void openOrder(String orderId) {
    openOrdersTab();
    Get.toNamed<dynamic>(AppRoutes.customerOrder(orderId));
  }

  /// Replaces the checkout screens with the result screen; the shell stays underneath.
  static void showCheckoutResult() {
    Get.offNamedUntil<dynamic>(AppRoutes.checkoutResult, (Route<dynamic> r) => r.isFirst);
  }
}
