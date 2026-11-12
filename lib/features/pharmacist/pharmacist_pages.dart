import 'package:get/get.dart';

import '../../app/routes/app_routes.dart';
import '../../app/routes/page_factory.dart';
import '../../core/base/shell_controller.dart';
import '../../core/services/session_service.dart';
import 'controllers/dashboard_controller.dart';
import 'controllers/availability_answer_controller.dart';
import 'controllers/availability_inbox_controller.dart';
import 'controllers/medicine_proposal_controller.dart';
import 'controllers/pharmacist_badge_controller.dart';
import 'controllers/pharmacist_notifications_controller.dart';
import 'controllers/pharmacist_orders_controller.dart';
import 'controllers/pharmacy_registration_controller.dart';
import 'controllers/pharmacy_settings_controller.dart';
import 'controllers/pharmacy_status_controller.dart';
import 'controllers/pos_controller.dart';
import 'controllers/product_add_controller.dart';
import 'controllers/product_details_controller.dart';
import 'controllers/product_edit_controller.dart';
import 'controllers/product_import_controller.dart';
import 'controllers/products_controller.dart';
import 'pharmacist_ops_pages.dart';
import 'pharmacist_tabs.dart';
import 'services/receipt_service.dart';
import 'views/availability_pages.dart';
import 'views/medicine_proposal_page.dart';
import 'views/notifications_page.dart';
import 'views/pharmacist_shell_page.dart';
import 'views/product_add_page.dart';
import 'views/product_details_page.dart';
import 'views/product_edit_page.dart';
import 'views/product_import_page.dart';
import 'views/registration_pages.dart';
import 'views/status_pages.dart';

void _ensureRegistration() {
  if (!Get.isRegistered<PharmacyRegistrationController>()) {
    Get.put<PharmacyRegistrationController>(PharmacyRegistrationController());
  }
}

void _ensureStatus() => Get.lazyPut<PharmacyStatusController>(() => PharmacyStatusController());

/// The five tab routes build the same shell; the shell controller starts on that tab, or selects it when a shell exists.
/// Everything the tabs and the screens above them share (basket, order lists, settings) lives as long as the shell.
GetPage<dynamic> _shell(String route, PharmacistTab tab) => appPage(
      route,
      () => const PharmacistShellPage(),
      binding: BindingsBuilder<dynamic>(() {
        final SessionService session = Get.find<SessionService>();
        final int index = PharmacistTabs.indexOf(tab) ?? 0;
        if (Get.isRegistered<ShellController>(tag: ShellTag.pharmacist)) {
          Get.find<ShellController>(tag: ShellTag.pharmacist).select(index);
        } else {
          Get.put<ShellController>(ShellController(PharmacistTabs.forSession(session).length, initial: index), tag: ShellTag.pharmacist);
        }
        Get.lazyPut<PharmacistBadgeController>(() => PharmacistBadgeController());
        if (session.snapshot.canManagePharmacy) Get.lazyPut<DashboardController>(() => DashboardController());
        Get.lazyPut<PosController>(() => PosController());
        Get.lazyPut<PharmacistOrdersController>(() => PharmacistOrdersController());
        Get.lazyPut<ProductsController>(() => ProductsController());
        Get.lazyPut<PharmacySettingsController>(() => PharmacySettingsController());
        Get.lazyPut<ReceiptService>(() => ReceiptService());
      }),
    );

/// All pharmacist routes (P-03 … P-73 except the ones listed in `pharmacistOpsPages`). Static paths come before
/// parameterised ones (`/products/add` before `/products/:id`).
List<GetPage<dynamic>> pharmacistPages() => <GetPage<dynamic>>[
      // registration wizard and status screens
      appPage(AppRoutes.pharmacyRegister, () => const RegistrationLicensePage(), binding: BindingsBuilder<dynamic>(_ensureRegistration)),
      appPage(AppRoutes.pharmacyRegisterInfo, () => const RegistrationInfoPage(), binding: BindingsBuilder<dynamic>(_ensureRegistration)),
      appPage(AppRoutes.pharmacyRegisterAddress, () => const RegistrationAddressPage(), binding: BindingsBuilder<dynamic>(_ensureRegistration)),
      appPage(AppRoutes.pharmacyRegisterHours, () => const RegistrationHoursPage(), binding: BindingsBuilder<dynamic>(_ensureRegistration)),
      appPage(AppRoutes.statusPending, () => const PharmacyPendingPage(), binding: BindingsBuilder<dynamic>(_ensureStatus)),
      appPage(AppRoutes.statusRejected, () => const PharmacyRejectedPage(), binding: BindingsBuilder<dynamic>(_ensureStatus)),
      appPage(AppRoutes.statusSuspended, () => const PharmacySuspendedPage(), binding: BindingsBuilder<dynamic>(_ensureStatus)),
      // shell tabs
      _shell(AppRoutes.pharmacistDashboard, PharmacistTab.dashboard),
      _shell(AppRoutes.pharmacistPos, PharmacistTab.pos),
      _shell(AppRoutes.pharmacistOrders, PharmacistTab.orders),
      _shell(AppRoutes.pharmacistProducts, PharmacistTab.products),
      _shell(AppRoutes.pharmacistSettings, PharmacistTab.settings),
      // my medicines (the list), import
      appPage(
        AppRoutes.productAdd,
        () => const ProductAddPage(),
        binding: BindingsBuilder<dynamic>(() => Get.lazyPut<ProductAddController>(() => ProductAddController())),
      ),
      appPage(
        AppRoutes.productPropose,
        () => const MedicineProposalPage(),
        binding: BindingsBuilder<dynamic>(() => Get.lazyPut<MedicineProposalController>(() => MedicineProposalController())),
      ),
      appPage(
        AppRoutes.productImport,
        () => const ProductImportPage(),
        binding: BindingsBuilder<dynamic>(() => Get.lazyPut<ProductImportController>(() => ProductImportController())),
      ),
      appPage(
        AppRoutes.productEdit,
        () => const ProductEditPage(),
        binding: BindingsBuilder<dynamic>(() => Get.lazyPut<ProductEditController>(() => ProductEditController())),
      ),
      appPage(
        AppRoutes.productDetails,
        () => const ProductDetailsPage(),
        binding: BindingsBuilder<dynamic>(() => Get.lazyPut<ProductDetailsController>(() => ProductDetailsController())),
      ),
      // notifications
      appPage(
        AppRoutes.pharmacistNotifications,
        () => const PharmacistNotificationsPage(),
        binding: BindingsBuilder<dynamic>(() {
          Get.lazyPut<PharmacistBadgeController>(() => PharmacistBadgeController());
          Get.lazyPut<PharmacistNotificationsController>(() => PharmacistNotificationsController());
        }),
      ),
      // customer requests ("is it available?")
      appPage(
        AppRoutes.pharmacistRequests,
        () => const AvailabilityInboxPage(),
        binding: BindingsBuilder<dynamic>(() {
          Get.lazyPut<PharmacistBadgeController>(() => PharmacistBadgeController());
          Get.lazyPut<AvailabilityInboxController>(() => AvailabilityInboxController());
        }),
      ),
      appPage(
        AppRoutes.pharmacistRequestDetails,
        () => const AvailabilityAnswerPage(),
        binding: BindingsBuilder<dynamic>(() {
          final String id = Get.parameters['id'] ?? '';
          Get.lazyPut<PharmacistBadgeController>(() => PharmacistBadgeController());
          Get.lazyPut<AvailabilityAnswerController>(() => AvailabilityAnswerController(requestId: id), tag: id);
        }),
      ),
      // point of sale, sales, orders, settings
      ...pharmacistOpsPages(),
    ];
