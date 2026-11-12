import 'package:get/get.dart';

import '../../app/routes/app_routes.dart';
import '../../core/base/shell_controller.dart';
import '../../core/services/session_service.dart';

enum PharmacistTab {
  dashboard(AppRoutes.pharmacistDashboard),
  pos(AppRoutes.pharmacistPos),
  orders(AppRoutes.pharmacistOrders),
  products(AppRoutes.pharmacistProducts),
  settings(AppRoutes.pharmacistSettings);

  const PharmacistTab(this.route);

  /// The tab-root route of this tab.
  final String route;
}

/// Tabs of the pharmacist shell for the signed-in member. Owners and managers get all five; cashiers have no
/// dashboard (money figures are owner/manager only), so their list is shorter and indices shift.
class PharmacistTabs {
  const PharmacistTabs._();

  static List<PharmacistTab> forSession(SessionService s) => s.snapshot.canManagePharmacy
      ? PharmacistTab.values
      : PharmacistTab.values.where((PharmacistTab t) => t != PharmacistTab.dashboard).toList();

  static List<PharmacistTab> current() => forSession(Get.find<SessionService>());

  /// Index of [tab] in the current member's shell, or null when that member does not have it.
  static int? indexOf(PharmacistTab tab) {
    final int i = current().indexOf(tab);
    return i < 0 ? null : i;
  }

  /// Pops back to the shell and selects [tab] (no-op when the member does not have that tab).
  static void go(PharmacistTab tab) {
    final int? i = indexOf(tab);
    if (i != null) Nav.toTab(ShellTag.pharmacist, i);
  }

  /// The tab a tab-root route opens, or null when [route] is not a tab root.
  static PharmacistTab? forRoute(String route) {
    for (final PharmacistTab t in PharmacistTab.values) {
      if (t.route == route) return t;
    }
    return null;
  }
}
