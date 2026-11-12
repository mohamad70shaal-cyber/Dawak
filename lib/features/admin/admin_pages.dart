import 'package:get/get.dart';

import '../../app/routes/app_routes.dart';
import '../../app/routes/page_factory.dart';
import '../../core/base/shell_controller.dart';
import 'admin_tabs.dart';
import 'controllers/admin_account_controller.dart';
import 'controllers/admin_audit_logs_controller.dart';
import 'controllers/admin_categories_controller.dart';
import 'controllers/admin_dashboard_controller.dart';
import 'controllers/admin_medicine_editor_controller.dart';
import 'controllers/admin_medicine_import_controller.dart';
import 'controllers/admin_medicines_controller.dart';
import 'controllers/admin_pharmacies_controller.dart';
import 'controllers/admin_pharmacy_details_controller.dart';
import 'controllers/admin_report_details_controller.dart';
import 'controllers/admin_reports_controller.dart';
import 'controllers/admin_users_controller.dart';
import 'views/admin_audit_logs_page.dart';
import 'views/admin_categories_page.dart';
import 'views/admin_medicine_editor_page.dart';
import 'views/admin_medicine_import_page.dart';
import 'views/admin_pharmacy_details_page.dart';
import 'views/admin_report_details_page.dart';
import 'views/admin_shell_page.dart';
import 'views/admin_users_page.dart';

/// The shell and everything its four tabs share; it lives as long as the shell does.
void _bindShell(AdminTab tab, {PharmacyFilter? pharmacyFilter}) {
  if (Get.isRegistered<ShellController>(tag: ShellTag.admin)) {
    Get.find<ShellController>(tag: ShellTag.admin).select(tab.index);
  } else {
    Get.put<ShellController>(ShellController(AdminTabs.all.length, initial: tab.index), tag: ShellTag.admin);
  }
  Get.lazyPut<AdminAccountController>(() => AdminAccountController());
  Get.lazyPut<AdminDashboardController>(() => AdminDashboardController());
  Get.lazyPut<AdminPharmaciesController>(() => AdminPharmaciesController());
  Get.lazyPut<AdminMedicinesController>(() => AdminMedicinesController());
  Get.lazyPut<AdminReportsController>(() => AdminReportsController());
  if (pharmacyFilter != null && Get.isRegistered<AdminPharmaciesController>()) {
    Get.find<AdminPharmaciesController>().setFilter(pharmacyFilter);
  }
}

GetPage<dynamic> _shell(String route, AdminTab tab, {PharmacyFilter? pharmacyFilter}) => appPage(
      route,
      () => const AdminShellPage(),
      binding: BindingsBuilder<dynamic>(() => _bindShell(tab, pharmacyFilter: pharmacyFilter)),
    );

/// All admin routes (A-02 … A-13). Static paths come before parameterised ones (`/pharmacies/pending` before
/// `/pharmacies/:id`, `/medicines/new` before `/medicines/:id`). The login (A-01) and access-denied (A-14) screens belong to
/// the auth feature.
List<GetPage<dynamic>> adminPages() => <GetPage<dynamic>>[
      // shell tabs
      _shell(AppRoutes.adminDashboard, AdminTab.dashboard),
      _shell(AppRoutes.adminPharmaciesPending, AdminTab.pharmacies, pharmacyFilter: PharmacyFilter.pending),
      _shell(AppRoutes.adminPharmacies, AdminTab.pharmacies),
      _shell(AppRoutes.adminMedicines, AdminTab.medicines),
      _shell(AppRoutes.adminReports, AdminTab.reports),
      // pharmacy review
      appPage(
        AppRoutes.adminPharmacyDetails,
        () => const AdminPharmacyDetailsPage(),
        binding: BindingsBuilder<dynamic>(() {
          final String id = Get.parameters['id'] ?? '';
          Get.lazyPut<AdminPharmacyDetailsController>(() => AdminPharmacyDetailsController(pharmacyId: id), tag: id);
        }),
      ),
      // medicine catalogue
      appPage(
        AppRoutes.adminMedicineNew,
        () => const AdminMedicineEditorPage(),
        binding: BindingsBuilder<dynamic>(() => Get.lazyPut<AdminMedicineEditorController>(() => AdminMedicineEditorController(), tag: 'new')),
      ),
      appPage(
        AppRoutes.adminMedicineImport,
        () => const AdminMedicineImportPage(),
        binding: BindingsBuilder<dynamic>(() => Get.lazyPut<AdminMedicineImportController>(() => AdminMedicineImportController())),
      ),
      appPage(
        AppRoutes.adminMedicineDetails,
        () => const AdminMedicineEditorPage(),
        binding: BindingsBuilder<dynamic>(() {
          final String id = Get.parameters['id'] ?? '';
          Get.lazyPut<AdminMedicineEditorController>(() => AdminMedicineEditorController(medicineId: id), tag: id);
        }),
      ),
      appPage(
        AppRoutes.adminCategories,
        () => const AdminCategoriesPage(),
        binding: BindingsBuilder<dynamic>(() => Get.lazyPut<AdminCategoriesController>(() => AdminCategoriesController())),
      ),
      // reports
      appPage(
        AppRoutes.adminReportDetails,
        () => const AdminReportDetailsPage(),
        binding: BindingsBuilder<dynamic>(() {
          final String id = Get.parameters['id'] ?? '';
          Get.lazyPut<AdminReportDetailsController>(() => AdminReportDetailsController(reportId: id), tag: id);
        }),
      ),
      // accounts and audit log
      appPage(
        AppRoutes.adminUsers,
        () => const AdminUsersPage(),
        binding: BindingsBuilder<dynamic>(() => Get.lazyPut<AdminUsersController>(() => AdminUsersController())),
      ),
      appPage(
        AppRoutes.adminAuditLogs,
        () => const AdminAuditLogsPage(),
        binding: BindingsBuilder<dynamic>(() => Get.lazyPut<AdminAuditLogsController>(() => AdminAuditLogsController())),
      ),
    ];
