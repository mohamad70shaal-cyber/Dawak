import 'package:flutter/widgets.dart';
import 'package:get/get.dart';

import '../../../app/routes/app_routes.dart';
import '../../../data/models/sale.dart';
import '../pharmacist_tabs.dart';

/// Navigation shortcuts of the pharmacist area.
class PharmacistNav {
  const PharmacistNav._();

  /// Replaces the checkout screen with the "sale completed" screen; the shell stays underneath.
  static void showSaleCompleted(Sale sale) {
    Get.offNamedUntil<dynamic>(AppRoutes.posCompletedOf(sale.id), (Route<dynamic> r) => r.isFirst);
  }

  /// Back to the shell on the POS tab (cashiers and managers both have it).
  static void openPos() => PharmacistTabs.go(PharmacistTab.pos);

  static void openOrdersTab() => PharmacistTabs.go(PharmacistTab.orders);
}
