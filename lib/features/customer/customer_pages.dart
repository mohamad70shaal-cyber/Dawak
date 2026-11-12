import 'package:get/get.dart';

import '../../app/routes/app_routes.dart';
import '../../app/routes/page_factory.dart';
import '../../core/base/shell_controller.dart';
import 'controllers/availability_request_controller.dart';
import 'controllers/cart_controller.dart';
import 'controllers/checkout_controller.dart';
import 'controllers/customer_orders_controller.dart';
import 'controllers/customer_profile_controller.dart';
import 'controllers/home_controller.dart';
import 'controllers/medicine_details_controller.dart';
import 'controllers/medicine_search_controller.dart';
import 'controllers/my_requests_controller.dart';
import 'controllers/notification_badge_controller.dart';
import 'controllers/notifications_controller.dart';
import 'controllers/order_details_controller.dart';
import 'controllers/pharmacy_details_controller.dart';
import 'controllers/support_controller.dart';
import 'customer_tabs.dart';
import 'views/availability_request_page.dart';
import 'views/cart_page.dart';
import 'views/checkout_result_page.dart';
import 'views/checkout_review_page.dart';
import 'views/customer_shell_page.dart';
import 'views/help_page.dart';
import 'views/medicine_details_page.dart';
import 'views/medicine_pharmacies_page.dart';
import 'views/my_requests_page.dart';
import 'views/notifications_page.dart';
import 'views/order_cancel_page.dart';
import 'views/order_details_page.dart';
import 'views/order_tracking_page.dart';
import 'views/pharmacy_contact_page.dart';
import 'views/pharmacy_details_page.dart';
import 'views/profile_edit_page.dart';
import 'views/search_filters_page.dart';
import 'views/search_results_page.dart';

/// The cart lives for the whole app run (permanent) and every customer page may need it.
void _ensureCart() {
  if (!Get.isRegistered<CartController>()) {
    Get.put<CartController>(CartController(), permanent: true);
  }
}

void _ensureSearch() => Get.lazyPut<MedicineSearchController>(() => MedicineSearchController());

/// The four tab routes build the same shell; the shell controller starts on [tab], or selects it when a shell exists.
GetPage<dynamic> _shell(String route, int tab) => appPage(
      route,
      () => const CustomerShellPage(),
      binding: BindingsBuilder<dynamic>(() {
        _ensureCart();
        if (Get.isRegistered<ShellController>(tag: ShellTag.customer)) {
          Get.find<ShellController>(tag: ShellTag.customer).select(tab);
        } else {
          Get.put<ShellController>(ShellController(CustomerTabs.count, initial: tab), tag: ShellTag.customer);
        }
        Get.lazyPut<NotificationBadgeController>(() => NotificationBadgeController());
        Get.lazyPut<HomeController>(() => HomeController());
        _ensureSearch();
        Get.lazyPut<CustomerOrdersController>(() => CustomerOrdersController());
        Get.lazyPut<CustomerProfileController>(() => CustomerProfileController());
      }),
    );

String _id() => Get.parameters['id'] ?? '';

/// All customer routes (C-09 … C-27 and the shell X-01). Static paths come before parameterised ones.
List<GetPage<dynamic>> customerPages() => <GetPage<dynamic>>[
      _shell(AppRoutes.customerHome, CustomerTabs.home),
      _shell(AppRoutes.customerSearch, CustomerTabs.search),
      _shell(AppRoutes.customerOrders, CustomerTabs.orders),
      _shell(AppRoutes.customerProfile, CustomerTabs.profile),
      appPage(
        AppRoutes.searchResults,
        () => const SearchResultsPage(),
        binding: BindingsBuilder<dynamic>(() {
          _ensureSearch();
          final Map<String, String?> params = Map<String, String?>.from(Get.parameters);
          Get.find<MedicineSearchController>().applyParams(params);
        }),
      ),
      appPage(
        AppRoutes.searchFilters,
        () => const SearchFiltersPage(),
        binding: BindingsBuilder<dynamic>(() {
          _ensureSearch();
          Get.find<MedicineSearchController>().ensureCategories();
        }),
      ),
      appPage(
        AppRoutes.cart,
        () => const CartPage(),
        binding: BindingsBuilder<dynamic>(() {
          _ensureCart();
          Get.find<CartController>().revalidate();
        }),
      ),
      appPage(
        AppRoutes.checkoutReview,
        () => const CheckoutReviewPage(),
        binding: BindingsBuilder<dynamic>(() {
          _ensureCart();
          Get.lazyPut<CheckoutController>(() => CheckoutController());
        }),
      ),
      appPage(AppRoutes.checkoutResult, () => const CheckoutResultPage(), binding: BindingsBuilder<dynamic>(_ensureCart)),
      appPage(
        AppRoutes.customerProfileEdit,
        () => const ProfileEditPage(),
        binding: BindingsBuilder<dynamic>(() => Get.lazyPut<CustomerProfileController>(() => CustomerProfileController())),
      ),
      appPage(
        AppRoutes.customerNotifications,
        () => const NotificationsPage(),
        binding: BindingsBuilder<dynamic>(() {
          Get.lazyPut<NotificationBadgeController>(() => NotificationBadgeController());
          Get.lazyPut<NotificationsController>(() => NotificationsController());
        }),
      ),
      appPage(
        AppRoutes.customerHelp,
        () => const HelpPage(),
        binding: BindingsBuilder<dynamic>(() => Get.lazyPut<SupportController>(() => SupportController())),
      ),
      appPage(
        AppRoutes.medicineDetails,
        () => MedicineDetailsPage(id: _id()),
        binding: BindingsBuilder<dynamic>(() {
          _ensureCart();
          final String id = _id();
          Get.lazyPut<MedicineDetailsController>(() => MedicineDetailsController(id), tag: id);
        }),
      ),
      appPage(
        AppRoutes.medicinePharmacies,
        () => MedicinePharmaciesPage(id: _id()),
        binding: BindingsBuilder<dynamic>(() {
          _ensureCart();
          final String id = _id();
          Get.lazyPut<MedicineDetailsController>(() => MedicineDetailsController(id), tag: id);
        }),
      ),
      appPage(
        AppRoutes.pharmacyContact,
        () => PharmacyContactPage(id: _id()),
        binding: BindingsBuilder<dynamic>(() {
          _ensureCart();
          final String id = _id();
          Get.lazyPut<PharmacyDetailsController>(() => PharmacyDetailsController(id), tag: id);
        }),
      ),
      appPage(
        AppRoutes.pharmacyDetails,
        () => PharmacyDetailsPage(id: _id()),
        binding: BindingsBuilder<dynamic>(() {
          _ensureCart();
          final String id = _id();
          final String? medicineId = Get.parameters['medicineId'];
          Get.lazyPut<PharmacyDetailsController>(() => PharmacyDetailsController(id, highlightMedicineId: medicineId), tag: id);
        }),
      ),
      appPage(
        AppRoutes.customerRequests,
        () => const MyRequestsPage(),
        binding: BindingsBuilder<dynamic>(() => Get.lazyPut<MyRequestsController>(() => MyRequestsController())),
      ),
      appPage(
        AppRoutes.customerRequestDetails,
        () => AvailabilityRequestPage(id: _id()),
        binding: BindingsBuilder<dynamic>(() {
          _ensureCart();
          final String id = _id();
          Get.lazyPut<AvailabilityRequestController>(() => AvailabilityRequestController(id), tag: id);
        }),
      ),
      appPage(
        AppRoutes.customerOrderTracking,
        () => OrderTrackingPage(id: _id()),
        binding: BindingsBuilder<dynamic>(() {
          final String id = _id();
          Get.lazyPut<OrderDetailsController>(() => OrderDetailsController(id), tag: id);
        }),
      ),
      appPage(
        AppRoutes.customerOrderCancel,
        () => OrderCancelPage(id: _id()),
        binding: BindingsBuilder<dynamic>(() {
          final String id = _id();
          Get.lazyPut<OrderDetailsController>(() => OrderDetailsController(id), tag: id);
        }),
      ),
      appPage(
        AppRoutes.customerOrderDetails,
        () => OrderDetailsPage(id: _id()),
        binding: BindingsBuilder<dynamic>(() {
          final String id = _id();
          Get.lazyPut<OrderDetailsController>(() => OrderDetailsController(id), tag: id);
        }),
      ),
    ];
