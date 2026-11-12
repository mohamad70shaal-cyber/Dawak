/// Every named route of the app. `test/routing/route_audit_test.dart` checks this file against
/// `docs/screen_registry.md` and `AppPages`.
///
/// Parameterised routes use `:id`-style segments; build concrete paths with the helper functions below so a
/// path is never assembled by hand in a screen.
class AppRoutes {
  const AppRoutes._();

  // ---- shared / auth -----------------------------------------------------------------------------------
  static const String splash = '/splash';
  static const String onboarding = '/onboarding';
  static const String welcome = '/welcome';
  static const String login = '/login';
  static const String register = '/register';
  static const String passwordReset = '/password-reset';
  static const String verifyEmail = '/verify-email';
  static const String accessDenied = '/access-denied';
  static const String notFound = '/not-found';
  static const String accountSuspended = '/account-suspended';
  static const String legalPrivacy = '/legal/privacy';
  static const String legalTerms = '/legal/terms';

  // ---- customer ----------------------------------------------------------------------------------------
  static const String customerHome = '/customer/home';
  static const String customerSearch = '/customer/search';
  static const String customerOrders = '/customer/orders';
  static const String customerProfile = '/customer/profile';
  static const String searchResults = '/customer/search/results';
  static const String searchFilters = '/customer/search/filters';
  static const String medicineDetails = '/customer/medicine/:id';
  static const String medicinePharmacies = '/customer/medicine/:id/pharmacies';
  static const String pharmacyDetails = '/customer/pharmacy/:id';
  static const String pharmacyContact = '/customer/pharmacy/:id/contact';
  static const String cart = '/customer/cart';
  static const String checkoutReview = '/customer/checkout/review';
  static const String checkoutResult = '/customer/checkout/result';
  static const String customerOrderDetails = '/customer/orders/:id';
  static const String customerOrderTracking = '/customer/orders/:id/tracking';
  static const String customerOrderCancel = '/customer/orders/:id/cancel';
  static const String customerProfileEdit = '/customer/profile/edit';
  static const String customerNotifications = '/customer/notifications';
  static const String customerHelp = '/customer/help';
  static const String customerRequests = '/customer/requests';
  static const String customerRequestDetails = '/customer/requests/:id';

  // ---- pharmacist --------------------------------------------------------------------------------------
  static const String pharmacistLogin = '/pharmacist/login';
  static const String pharmacistRegister = '/pharmacist/register';
  static const String pharmacyRegister = '/pharmacist/pharmacy/register';
  static const String pharmacyRegisterInfo = '/pharmacist/pharmacy/register/info';
  static const String pharmacyRegisterAddress = '/pharmacist/pharmacy/register/address';
  static const String pharmacyRegisterHours = '/pharmacist/pharmacy/register/hours';
  static const String statusPending = '/pharmacist/status/pending';
  static const String statusRejected = '/pharmacist/status/rejected';
  static const String statusSuspended = '/pharmacist/status/suspended';
  static const String pharmacistDashboard = '/pharmacist/dashboard';
  static const String pharmacistPos = '/pharmacist/pos';
  static const String pharmacistOrders = '/pharmacist/orders';
  static const String pharmacistProducts = '/pharmacist/products';
  static const String pharmacistSettings = '/pharmacist/settings';
  static const String productAdd = '/pharmacist/products/add';
  static const String productPropose = '/pharmacist/products/propose';
  static const String productImport = '/pharmacist/products/import';
  static const String productDetails = '/pharmacist/products/:id';
  static const String productEdit = '/pharmacist/products/:id/edit';
  static const String pharmacistRequests = '/pharmacist/requests';
  static const String pharmacistRequestDetails = '/pharmacist/requests/:id';
  static const String posCheckout = '/pharmacist/pos/checkout';
  static const String posCompleted = '/pharmacist/pos/completed/:saleId';
  static const String salesHistory = '/pharmacist/sales';
  static const String saleDetails = '/pharmacist/sales/:id';
  static const String ordersFind = '/pharmacist/orders/find';
  static const String pharmacistOrderDetails = '/pharmacist/orders/:id';
  static const String orderHandover = '/pharmacist/orders/:id/handover';
  static const String settingsProfile = '/pharmacist/settings/profile';
  static const String settingsContact = '/pharmacist/settings/contact';
  static const String settingsHours = '/pharmacist/settings/hours';
  static const String settingsLocation = '/pharmacist/settings/location';
  static const String settingsSecurity = '/pharmacist/settings/security';
  static const String pharmacistNotifications = '/pharmacist/notifications';

  // ---- admin -------------------------------------------------------------------------------------------
  static const String adminLogin = '/admin/login';
  static const String adminDashboard = '/admin/dashboard';
  static const String adminPharmaciesPending = '/admin/pharmacies/pending';
  static const String adminPharmacies = '/admin/pharmacies';
  static const String adminPharmacyDetails = '/admin/pharmacies/:id';
  static const String adminMedicines = '/admin/medicines';
  static const String adminMedicineNew = '/admin/medicines/new';
  static const String adminMedicineDetails = '/admin/medicines/:id';
  static const String adminCategories = '/admin/categories';
  static const String adminReports = '/admin/reports';
  static const String adminReportDetails = '/admin/reports/:id';
  static const String adminUsers = '/admin/users';
  static const String adminAuditLogs = '/admin/audit-logs';
  static const String adminMedicineImport = '/admin/medicines/import';

  // ---- builders ----------------------------------------------------------------------------------------
  static String medicine(String id) => '/customer/medicine/${_e(id)}';
  static String medicineOffers(String id) => '/customer/medicine/${_e(id)}/pharmacies';
  static String pharmacy(String id) => '/customer/pharmacy/${_e(id)}';
  static String pharmacyContactOf(String id) => '/customer/pharmacy/${_e(id)}/contact';
  static String customerOrder(String id) => '/customer/orders/${_e(id)}';
  static String customerOrderTrack(String id) => '/customer/orders/${_e(id)}/tracking';
  static String customerOrderCancelOf(String id) => '/customer/orders/${_e(id)}/cancel';
  static String customerRequest(String id) => '/customer/requests/${_e(id)}';
  static String product(String id) => '/pharmacist/products/${_e(id)}';
  static String productEditOf(String id) => '/pharmacist/products/${_e(id)}/edit';
  static String pharmacistRequest(String id) => '/pharmacist/requests/${_e(id)}';
  static String posCompletedOf(String saleId) => '/pharmacist/pos/completed/${_e(saleId)}';
  static String sale(String id) => '/pharmacist/sales/${_e(id)}';
  static String pharmacistOrder(String id) => '/pharmacist/orders/${_e(id)}';
  static String orderHandoverOf(String id) => '/pharmacist/orders/${_e(id)}/handover';
  static String adminPharmacy(String id) => '/admin/pharmacies/${_e(id)}';
  static String adminMedicine(String id) => '/admin/medicines/${_e(id)}';
  static String adminReport(String id) => '/admin/reports/${_e(id)}';

  static String _e(String s) => Uri.encodeComponent(s);

  /// All route patterns, used by the audit tests.
  static const List<String> all = <String>[
    splash, onboarding, welcome, login, register, passwordReset, verifyEmail, accessDenied, notFound,
    accountSuspended, legalPrivacy, legalTerms,
    customerHome, customerSearch, customerOrders, customerProfile, searchResults, searchFilters,
    medicineDetails, medicinePharmacies, pharmacyDetails, pharmacyContact, cart, checkoutReview,
    checkoutResult, customerOrderDetails, customerOrderTracking, customerOrderCancel, customerProfileEdit,
    customerNotifications, customerHelp, customerRequests, customerRequestDetails,
    pharmacistLogin, pharmacistRegister, pharmacyRegister, pharmacyRegisterInfo, pharmacyRegisterAddress,
    pharmacyRegisterHours, statusPending, statusRejected, statusSuspended, pharmacistDashboard, pharmacistPos,
    pharmacistOrders, pharmacistProducts, pharmacistSettings, productAdd, productPropose, productImport,
    productDetails, productEdit, pharmacistRequests, pharmacistRequestDetails, posCheckout, posCompleted,
    salesHistory, saleDetails, ordersFind, pharmacistOrderDetails, orderHandover, settingsProfile,
    settingsContact, settingsHours, settingsLocation, settingsSecurity, pharmacistNotifications,
    adminLogin, adminDashboard, adminPharmaciesPending, adminPharmacies, adminPharmacyDetails, adminMedicines,
    adminMedicineNew, adminMedicineDetails, adminCategories, adminReports, adminReportDetails, adminUsers,
    adminAuditLogs, adminMedicineImport,
  ];
}
