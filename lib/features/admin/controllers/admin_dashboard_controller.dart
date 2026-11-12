import 'package:get/get.dart';

import '../../../core/base/base_controller.dart';
import '../../../data/models/platform.dart';
import '../../../data/repositories/admin_repository.dart';
import '../admin_tabs.dart';
import 'admin_medicines_controller.dart';
import 'admin_pharmacies_controller.dart';
import 'admin_reports_controller.dart';

/// Operational overview (A-02): aggregate counts only, no personal data. Tapping a figure that needs attention
/// opens the matching tab with the matching filter.
class AdminDashboardController extends BaseController {
  AdminDashboardController({
    AdminRepository? admin,
    void Function(PharmacyFilter filter)? showPharmacies,
    void Function(MedicineFilter filter)? showMedicines,
    void Function(ReportFilter filter)? showReports,
  })  : _admin = admin ?? Get.find<AdminRepository>(),
        _showPharmacies = showPharmacies ?? _defaultShowPharmacies,
        _showMedicines = showMedicines ?? _defaultShowMedicines,
        _showReports = showReports ?? _defaultShowReports;

  final AdminRepository _admin;
  final void Function(PharmacyFilter filter) _showPharmacies;
  final void Function(MedicineFilter filter) _showMedicines;
  final void Function(ReportFilter filter) _showReports;

  final Rxn<AdminMetrics> metrics = Rxn<AdminMetrics>();

  static void _defaultShowPharmacies(PharmacyFilter f) {
    if (Get.isRegistered<AdminPharmaciesController>()) Get.find<AdminPharmaciesController>().setFilter(f);
    AdminTabs.go(AdminTab.pharmacies);
  }

  static void _defaultShowMedicines(MedicineFilter f) {
    if (Get.isRegistered<AdminMedicinesController>()) Get.find<AdminMedicinesController>().setFilter(f);
    AdminTabs.go(AdminTab.medicines);
  }

  static void _defaultShowReports(ReportFilter f) {
    if (Get.isRegistered<AdminReportsController>()) Get.find<AdminReportsController>().setFilter(f);
    AdminTabs.go(AdminTab.reports);
  }

  @override
  void onReady() {
    super.onReady();
    refresh();
  }

  Future<void> refresh({bool silent = false}) => load(() async {
        metrics.value = await _admin.metrics();
      }, silent: silent);

  /// Things waiting for an administrator: applications, medicine proposals and open reports.
  int get needsAttention {
    final AdminMetrics? m = metrics.value;
    return m == null ? 0 : m.pendingPharmacies + m.pendingMedicines + m.openReports;
  }

  /// Share of the last 30 days' orders that were picked up (0 when there were no orders).
  double get completionRate {
    final AdminMetrics? m = metrics.value;
    if (m == null || m.orders30d == 0) return 0;
    return m.completedOrders30d / m.orders30d;
  }

  void openPendingPharmacies() => _showPharmacies(PharmacyFilter.pending);
  void openAllPharmacies() => _showPharmacies(PharmacyFilter.all);
  void openSuspendedPharmacies() => _showPharmacies(PharmacyFilter.suspended);
  void openPendingMedicines() => _showMedicines(MedicineFilter.pending);
  void openApprovedMedicines() => _showMedicines(MedicineFilter.approved);
  void openOpenReports() => _showReports(ReportFilter.open);
}
