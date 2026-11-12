import 'package:get/get.dart';

import '../controllers/admin_dashboard_controller.dart';
import '../controllers/admin_medicines_controller.dart';
import '../controllers/admin_pharmacies_controller.dart';
import '../controllers/admin_reports_controller.dart';

/// After an action changed something, the lists and the dashboard under the details screen re-read the server.
class AdminRefresh {
  const AdminRefresh._();

  static void _metrics() {
    if (Get.isRegistered<AdminDashboardController>()) Get.find<AdminDashboardController>().refresh(silent: true);
  }

  static void pharmaciesChanged() {
    if (Get.isRegistered<AdminPharmaciesController>()) Get.find<AdminPharmaciesController>().refreshList();
    _metrics();
  }

  static void medicinesChanged() {
    if (Get.isRegistered<AdminMedicinesController>()) Get.find<AdminMedicinesController>().refreshList();
    _metrics();
  }

  static void reportsChanged() {
    if (Get.isRegistered<AdminReportsController>()) Get.find<AdminReportsController>().refreshList();
    _metrics();
  }
}
