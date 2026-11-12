import 'package:get/get.dart';

import '../../app/routes/app_routes.dart';
import '../../app/routes/page_factory.dart';
import 'controllers/order_find_controller.dart';
import 'controllers/order_handover_controller.dart';
import 'controllers/pharmacist_order_details_controller.dart';
import 'controllers/pos_controller.dart';
import 'controllers/sales_controllers.dart';
import 'services/receipt_service.dart';
import 'views/order_details_page.dart';
import 'views/order_find_page.dart';
import 'views/order_handover_page.dart';
import 'views/pos_checkout_page.dart';
import 'views/sale_pages.dart';
import 'views/settings_pages.dart';

String _id() => Get.parameters['id'] ?? '';

String _saleId() => Get.parameters['saleId'] ?? '';

void _ensureReceipts() {
  if (!Get.isRegistered<ReceiptService>()) Get.lazyPut<ReceiptService>(() => ReceiptService());
}

/// POS checkout, sales, orders and settings screens. Static paths come before parameterised ones.
/// (The settings controller is created by the shell binding in `pharmacist_pages.dart`.)
List<GetPage<dynamic>> pharmacistOpsPages() => <GetPage<dynamic>>[
      appPage(
        AppRoutes.posCheckout,
        () => const PosCheckoutPage(),
        binding: BindingsBuilder<dynamic>(() {
          // The basket may be minutes old: re-read prices before the cashier confirms.
          Get.find<PosController>().revalidate();
        }),
      ),
      appPage(
        AppRoutes.posCompleted,
        () => const PosCompletedPage(),
        binding: BindingsBuilder<dynamic>(() {
          final String id = _saleId();
          Get.lazyPut<PosCompletedController>(() => PosCompletedController(saleId: id), tag: id);
        }),
      ),
      appPage(
        AppRoutes.salesHistory,
        () => const SalesHistoryPage(),
        binding: BindingsBuilder<dynamic>(() => Get.lazyPut<SalesHistoryController>(() => SalesHistoryController())),
      ),
      appPage(
        AppRoutes.saleDetails,
        () => const SaleDetailsPage(),
        binding: BindingsBuilder<dynamic>(() {
          _ensureReceipts();
          final String id = _id();
          Get.lazyPut<SaleDetailsController>(() => SaleDetailsController(saleId: id), tag: id);
        }),
      ),
      appPage(
        AppRoutes.ordersFind,
        () => const OrderFindPage(),
        binding: BindingsBuilder<dynamic>(() => Get.lazyPut<OrderFindController>(() => OrderFindController())),
      ),
      appPage(
        AppRoutes.pharmacistOrderDetails,
        () => const PharmacistOrderDetailsPage(),
        binding: BindingsBuilder<dynamic>(() {
          final String id = _id();
          Get.lazyPut<PharmacistOrderDetailsController>(() => PharmacistOrderDetailsController(orderId: id), tag: id);
        }),
      ),
      appPage(
        AppRoutes.orderHandover,
        () => const OrderHandoverPage(),
        binding: BindingsBuilder<dynamic>(() {
          final String id = _id();
          Get.lazyPut<OrderHandoverController>(() => OrderHandoverController(orderId: id), tag: id);
        }),
      ),
      appPage(AppRoutes.settingsProfile, () => const SettingsProfilePage()),
      appPage(AppRoutes.settingsContact, () => const SettingsContactPage()),
      appPage(AppRoutes.settingsHours, () => const SettingsHoursPage()),
      appPage(AppRoutes.settingsLocation, () => const SettingsLocationPage()),
      appPage(AppRoutes.settingsSecurity, () => const SettingsSecurityPage()),
    ];
