import '../../app/routes/app_routes.dart';
import '../../core/base/shell_controller.dart';

/// The four tabs of the admin shell. Categories, accounts and the audit log are reached from the drawer.
enum AdminTab {
  dashboard(AppRoutes.adminDashboard),
  pharmacies(AppRoutes.adminPharmacies),
  medicines(AppRoutes.adminMedicines),
  reports(AppRoutes.adminReports);

  const AdminTab(this.route);

  /// The tab-root route of this tab.
  final String route;
}

class AdminTabs {
  const AdminTabs._();

  static const List<AdminTab> all = AdminTab.values;

  /// Pops back to the shell and selects [tab].
  static void go(AdminTab tab) => Nav.toTab(ShellTag.admin, tab.index);

  /// The tab a tab-root route opens, or null when [route] is not a tab root.
  static AdminTab? forRoute(String route) {
    for (final AdminTab t in AdminTab.values) {
      if (t.route == route) return t;
    }
    return null;
  }
}
