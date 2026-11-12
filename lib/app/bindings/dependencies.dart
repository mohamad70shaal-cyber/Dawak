import 'package:get/get.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/services/locale_service.dart';
import '../../core/services/location_service.dart';
import '../../core/services/session_service.dart';
import '../../data/datasources/api_client.dart';
import '../../data/repositories/admin_repository.dart';
import '../../data/repositories/auth_repository.dart';
import '../../data/repositories/availability_repository.dart';
import '../../data/repositories/dashboard_repository.dart';
import '../../data/repositories/listing_repository.dart';
import '../../data/repositories/medicine_repository.dart';
import '../../data/repositories/notification_repository.dart';
import '../../data/repositories/order_repository.dart';
import '../../data/repositories/pharmacy_repository.dart';
import '../../data/repositories/sales_repository.dart';
import '../../data/repositories/support_repository.dart';

/// Registers everything that lives for the whole app run: data sources, repositories, locale and session.
/// `main()` passes the Supabase implementations; tests pass fakes.
void registerCoreDependencies({
  required ApiClient api,
  required AuthGateway auth,
  required FileStore files,
  required SharedPreferences prefs,
  LocationGateway location = const GeolocatorGateway(),
  void Function(String route)? navigate,
  Duration pollInterval = const Duration(seconds: 30),
}) {
  Get.put<ApiClient>(api, permanent: true);
  Get.put<AuthGateway>(auth, permanent: true);
  Get.put<FileStore>(files, permanent: true);

  final AuthRepository authRepo = Get.put<AuthRepository>(AuthRepository(auth, api), permanent: true);
  Get.put<PharmacyRepository>(PharmacyRepository(api), permanent: true);
  Get.put<MedicineRepository>(MedicineRepository(api), permanent: true);
  Get.put<ListingRepository>(ListingRepository(api), permanent: true);
  Get.put<AvailabilityRepository>(AvailabilityRepository(api), permanent: true);
  Get.put<SalesRepository>(SalesRepository(api), permanent: true);
  Get.put<OrderRepository>(OrderRepository(api), permanent: true);
  Get.put<DashboardRepository>(DashboardRepository(api), permanent: true);
  Get.put<NotificationRepository>(NotificationRepository(api), permanent: true);
  Get.put<SupportRepository>(SupportRepository(api), permanent: true);
  Get.put<AdminRepository>(AdminRepository(api), permanent: true);

  Get.put<LocaleService>(LocaleService(prefs), permanent: true);
  Get.put<LocationService>(LocationService(location), permanent: true);
  Get.put<SessionService>(
    SessionService(authRepo, navigate: navigate, pollInterval: pollInterval),
    permanent: true,
  );
}
