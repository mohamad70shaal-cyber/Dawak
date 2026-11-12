import 'package:get/get.dart';

import '../../features/admin/admin_pages.dart';
import '../../features/auth/auth_pages.dart';
import '../../features/auth/views/status_pages.dart';
import '../../features/customer/customer_pages.dart';
import '../../features/pharmacist/pharmacist_pages.dart';
import 'app_routes.dart';
import 'page_factory.dart';

/// All pages of the app. `test/routing/route_audit_test.dart` checks this list against `AppRoutes` and the
/// screen registry.
class AppPages {
  const AppPages._();

  static List<GetPage<dynamic>> get pages => <GetPage<dynamic>>[
        ...authPages(),
        ...customerPages(),
        ...pharmacistPages(),
        ...adminPages(),
      ];

  static GetPage<dynamic> get unknown => appPage(AppRoutes.notFound, () => const NotFoundPage());
}
